#!/usr/bin/perl
use strict;
use warnings;
use File::Glob ':glob';

# 前提条件 1. victorialogs コンテナの固定 IP 設定と名前解決が DNS サーバーで済んでいること
#
# 例 ... OpenWrt
#   victorialogs コンテナの作成前でも MAC アドレスに対して割り当てる IP アドレスを設定できる
#   IP アドレスが決まっていれば、DNS レコードも作成できる
# 当スクリプトでは victorialogs コンテナの NIC が持つ MAC アドレスを引数として指定する・引数の MAC アドレスをルーターでの固定 IP 設定に使用する
#
# Debian 13 コンテナイメージがダウンロードされていない場合は pveam で最新の debian-13-standard をダウンロードする

# =====================================
# ノード A : victorialogs 設定
# =====================================

# 引数 : コンテナイメージを保存する Proxmox ストレージ ID
my $SETUP_IMAGE_STORAGE_ID = "local";
# 引数 : コンテナイメージの保存先ディレクトリ
my $SETUP_IMAGE_DIRECTORY = "/var/lib/vz/template/cache";
# 引数 : 使用する Debian のバージョン
my $SETUP_DEBIAN_VERSION = "13";
# 引数 : メモリサイズ
my $SETUP_MEMORY_SIZE = "2048"; # MiB
# 引数 : スワップサイズ
my $SETUP_SWAP_SIZE = "1024"; # MiB
# 引数 : CPU コア数
my $SETUP_CPU_CORES = "2";

# 引数 : VictoriaLogs コンテナの ID
my $SETUP_CONTAINER_ID = "141";
# 引数 : VictoriaLogs コンテナの名前
my $SETUP_CONTAINER_NAME = "victorialogs";
# 引数 : VictoriaLogs コンテナのディスクを配置するストレージ ID
my $SETUP_DISK_STORAGE_ID = "local-lvm";
# 引数 : VictoriaLogs コンテナのディスクサイズ ( GiB ) , Elasticsearch の 10 分の 1 から運用開始
my $SETUP_DISK_SIZE = "30";
# 引数 : VictoriaLogs コンテナが LAN と接続する OVS 仮想ブリッジの名前
my $SETUP_BR_INET = "br5_inet";
# 引数 : VictoriaLogs コンテナの NIC が持つ MAC アドレス
my $SETUP_NIC_MACADDR = "02:50:58:00:05:05";

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

sub push_environment_edit_script {
    push_or_die("victorialogs/setup1.pl", "/root/setup1.pl", "root:root", "744");
}

sub run_environment_edit_script {
    run_cmd_or_die("pct exec $SETUP_CONTAINER_ID -- /usr/bin/perl /root/setup1.pl > /root/setup.victorialogs-$SETUP_CONTAINER_ID-setup1.log 2>&1");
}

sub push_victorialogs_install_script {
    push_or_die("victorialogs/setup2.pl", "/root/setup2.pl", "root:root", "744");
}

sub run_victorialogs_install_script {
    run_cmd_or_die("pct exec $SETUP_CONTAINER_ID -- /usr/bin/perl /root/setup2.pl > /root/setup.victorialogs-$SETUP_CONTAINER_ID-setup2.log 2>&1");
}

sub setup_main {
    download_image();
    create_container();
    start_victorialogs_container();
    wait_for_nic_up();
    push_environment_edit_script();
    run_environment_edit_script();
    push_victorialogs_install_script();
    run_victorialogs_install_script();
}

setup_main();
