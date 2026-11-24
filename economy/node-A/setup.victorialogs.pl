#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use FindBin;
use lib "$FindBin::Bin/lib";
use IO::Handle;
use File::Glob ':glob';
use File::Temp qw(tempfile);
use SetupConfig qw(load_config cfg dump_toml);

STDOUT->autoflush(1);

# 前提条件 1. victorialogs コンテナの固定 IP 設定と名前解決が DNS サーバーで済んでいること
#
# 例 ... OpenWrt
#   victorialogs コンテナの作成前でも MAC アドレスに対して割り当てる IP アドレスを設定できる
#   IP アドレスが決まっていれば、DNS レコードも作成できる
# 当スクリプトでは victorialogs コンテナの NIC が持つ MAC アドレスを引数として指定する・引数の MAC アドレスをルーターでの固定 IP 設定に使用する
#
# Debian 13 コンテナイメージがダウンロードされていない場合は pveam で最新の debian-13-standard をダウンロードする

# =====================================
# 設定の読み込み ( 値は config.toml の [victorialogs] / [victorialogs.guest] へ記入する )
# =====================================

my $CONFIG_PATH = $ARGV[0] // "$FindBin::Bin/config.toml";
my $C = load_config($CONFIG_PATH);

my $SETUP_IMAGE_STORAGE_ID = cfg($C, "victorialogs.image_storage_id");
my $SETUP_IMAGE_DIRECTORY = cfg($C, "victorialogs.image_directory");
my $SETUP_DEBIAN_VERSION = cfg($C, "victorialogs.debian_version");
my $SETUP_MEMORY_SIZE = cfg($C, "victorialogs.memory_size");
my $SETUP_SWAP_SIZE = cfg($C, "victorialogs.swap_size");
my $SETUP_CPU_CORES = cfg($C, "victorialogs.cpu_cores");

my $SETUP_CONTAINER_ID = cfg($C, "victorialogs.container_id");
my $SETUP_CONTAINER_NAME = cfg($C, "victorialogs.container_name");
my $SETUP_DISK_STORAGE_ID = cfg($C, "victorialogs.disk_storage_id");
my $SETUP_DISK_SIZE = cfg($C, "victorialogs.disk_size");
my $SETUP_BR_INET = cfg($C, "pve.br_inet");
my $SETUP_NIC_MACADDR = cfg($C, "victorialogs.nic_macaddr");

# コンテナへ送り込むファイルの配置先 ( セットアップ完了後に削除する )
my $GUEST_WORK_DIR = "/root/setup";

# =====================================
# ユーティリティ
# =====================================

sub run_cmd {
    my @cmd = @_;
    return system(@cmd); # system() の戻り値をそのまま返す
}

sub run_cmd_or_die {
    my @cmd = @_;
    run_cmd(@cmd) == 0
        or die "Command failed (@cmd): $?\n";
}

sub push_or_die {
    my ($local_path, $remote_path, $owner, $permission) = @_;
    run_cmd_or_die("pct", "push", $SETUP_CONTAINER_ID, $local_path, $remote_path);
    run_cmd_or_die("pct", "exec", $SETUP_CONTAINER_ID, "--", "chown", $owner, $remote_path);
    run_cmd_or_die("pct", "exec", $SETUP_CONTAINER_ID, "--", "chmod", $permission, $remote_path);
}

# =====================================
# イメージダウンロード
# =====================================

sub find_debian_image {
    my @candidates = sort(bsd_glob("$SETUP_IMAGE_DIRECTORY/debian-$SETUP_DEBIAN_VERSION-standard_*_amd64.tar.*"));
    return $candidates[-1];
}

sub download_image {
    return if defined(find_debian_image());
    run_cmd_or_die("pveam", "update");
    open(my $command_h, '-|', 'pveam', 'available', '--section', 'system') or die "Failed to run pveam available: $!\n";
    # 出力例 : system          debian-13-standard_13.1-2_amd64.tar.zst
    my @templates = sort map { /\s(debian-$SETUP_DEBIAN_VERSION-standard_\S+_amd64\.tar\.\S+)/ ? $1 : () } <$command_h>;
    close($command_h);
    die "Error: No Debian $SETUP_DEBIAN_VERSION template found by pveam\n" unless @templates;
    run_cmd_or_die("pveam", "download", $SETUP_IMAGE_STORAGE_ID, $templates[-1]);
}

# =====================================
# コンテナ作成
# =====================================

sub create_container {
    my $container_image = find_debian_image()
        or die "Error: No Debian image found in $SETUP_IMAGE_DIRECTORY for version $SETUP_DEBIAN_VERSION\n";

    # Debian 13 などの新しい OS のコンテナを作成する場合、ネスト設定「--features nesting=1」が必要になる
    run_cmd_or_die(
        "pct", "create", $SETUP_CONTAINER_ID, $container_image,
        "--arch", "amd64",
        "--hostname", $SETUP_CONTAINER_NAME,
        "--rootfs", "$SETUP_DISK_STORAGE_ID:$SETUP_DISK_SIZE",
        "--memory", $SETUP_MEMORY_SIZE,
        "--swap", $SETUP_SWAP_SIZE,
        "--cores", $SETUP_CPU_CORES,
        "--net0", "name=eth0,bridge=$SETUP_BR_INET,hwaddr=$SETUP_NIC_MACADDR,firewall=0,ip=dhcp",
        "--ostype", "debian",
        "--unprivileged", "1",
        "--features", "nesting=1",
    );
}

sub start_victorialogs_container {
    run_cmd_or_die("pct", "start", $SETUP_CONTAINER_ID);
}

sub wait_for_nic_up {
    my $polling_wait_max = 30;
    my $wait_count = 0;

    while (1) {
        my $ret = run_cmd(
            "pct", "exec", $SETUP_CONTAINER_ID, "--",
            "ping", "-c", "1", "-W", "2", "8.8.8.8"
        );
        last if $ret == 0;
        if ($wait_count >= $polling_wait_max) {
            die "Error: Internet connection timeout\n";
        }
        sleep 2;
        $wait_count++;
    }
}

sub push_setup_files {
    # [victorialogs.guest] だけを切り出して渡す ( VRRP パスワードなど他の設定をコンテナへ持ち込まない )
    my ($fh, $guest_config) = tempfile(UNLINK => 1);
    binmode($fh, ':encoding(UTF-8)');
    $fh->print(dump_toml(cfg($C, "victorialogs.guest")));
    close($fh);

    run_cmd_or_die("pct", "exec", $SETUP_CONTAINER_ID, "--", "mkdir", "-p", "$GUEST_WORK_DIR/lib");
    push_or_die("$FindBin::Bin/victorialogs/setup1.pl", "$GUEST_WORK_DIR/setup1.pl", "root:root", "744");
    push_or_die("$FindBin::Bin/victorialogs/setup2.pl", "$GUEST_WORK_DIR/setup2.pl", "root:root", "744");
    push_or_die("$FindBin::Bin/lib/SetupConfig.pm", "$GUEST_WORK_DIR/lib/SetupConfig.pm", "root:root", "644");
    push_or_die($guest_config, "$GUEST_WORK_DIR/config.toml", "root:root", "600");
}

sub run_environment_edit_script {
    run_cmd_or_die("pct exec $SETUP_CONTAINER_ID -- /usr/bin/perl $GUEST_WORK_DIR/setup1.pl $GUEST_WORK_DIR/config.toml > /root/setup.victorialogs-$SETUP_CONTAINER_ID-setup1.log 2>&1");
}

sub run_victorialogs_install_script {
    run_cmd_or_die("pct exec $SETUP_CONTAINER_ID -- /usr/bin/perl $GUEST_WORK_DIR/setup2.pl $GUEST_WORK_DIR/config.toml > /root/setup.victorialogs-$SETUP_CONTAINER_ID-setup2.log 2>&1");
}

sub remove_setup_files {
    run_cmd_or_die("pct", "exec", $SETUP_CONTAINER_ID, "--", "rm", "-rf", $GUEST_WORK_DIR);
}

sub setup_main {
    download_image();
    create_container();
    start_victorialogs_container();
    wait_for_nic_up();
    push_setup_files();
    run_environment_edit_script();
    run_victorialogs_install_script();
    remove_setup_files();
}

setup_main();
