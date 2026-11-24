#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use FindBin;
use lib "$FindBin::Bin/lib";
use IO::Handle;
use File::Glob ':glob';
use File::Temp qw(tempfile);
use POSIX qw(strftime);
use SetupConfig qw(load_config cfg dump_toml);

STDOUT->autoflush(1);

# =====================================
# 設定の読み込み ( 値は config.toml の [suricata] / [suricata.guest] へ記入する )
# =====================================

my $CONFIG_PATH = $ARGV[0] // "$FindBin::Bin/config.toml";
my $C = load_config($CONFIG_PATH);

my $SETUP_UBUNTU_IMAGE_URL = cfg($C, "suricata.ubuntu_image_url");
my $SETUP_IMAGE_DIRECTORY = cfg($C, "suricata.image_directory");
my $SETUP_UBUNTU_VERSION = cfg($C, "suricata.ubuntu_version");
# セットアップ実行日付 ( YYYYMMDD )
my $SETUP_DATE = strftime("%Y%m%d", localtime);

my $SETUP_CONTAINER_ID = cfg($C, "suricata.container_id");
my $SETUP_CONTAINER_NAME = cfg($C, "suricata.container_name");
my $SETUP_SNIPPET = cfg($C, "suricata.snippet");
my $SETUP_SNIPPET_DIRECTORY = cfg($C, "pve.snippet_directory");

my $SETUP_PHYSICAL_WAN_PORT = cfg($C, "pve.physical_wan_port");
my $SETUP_WAN_MACADDR = cfg($C, "suricata.wan_macaddr");
my $SETUP_BR_WAN = cfg($C, "pve.br_wan");
my $SETUP_LAN_MACADDR = cfg($C, "suricata.lan_macaddr");
my $SETUP_BR_INET = cfg($C, "pve.br_inet");
my $SETUP_MIRROR_NAME = cfg($C, "suricata.mirror_name");

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

sub read_cmd_or_die {
    my @cmd = @_;
    open(my $command_h, '-|', @cmd) or die "Failed to run (@cmd): $!\n";
    my @output = <$command_h>;
    close($command_h) or die "Command failed (@cmd): $?\n";
    return @output;
}

sub push_or_die {
    my ($local_path, $remote_path, $permission) = @_;
    run_cmd_or_die("pct", "push", $SETUP_CONTAINER_ID, $local_path, $remote_path);
    run_cmd_or_die("pct", "exec", $SETUP_CONTAINER_ID, "--", "chmod", $permission, $remote_path);
}

# =====================================
# イメージダウンロード
# =====================================

sub download_image {
    my $image = "$SETUP_IMAGE_DIRECTORY/ubuntu.${SETUP_UBUNTU_VERSION}.${SETUP_DATE}.tar.xz";
    return if -f $image;
    run_cmd_or_die("wget", "-O", $image, $SETUP_UBUNTU_IMAGE_URL);
}

# =====================================
# コンテナ作成
# =====================================

sub create_container {
    my @candidates = sort(bsd_glob("$SETUP_IMAGE_DIRECTORY/ubuntu.$SETUP_UBUNTU_VERSION.*.tar.xz"));
    die "Error: No Ubuntu image found in $SETUP_IMAGE_DIRECTORY for version $SETUP_UBUNTU_VERSION\n" unless @candidates;
    my $container_image = $candidates[-1];

    # Ubuntu 24.04 などの新しい OS のコンテナを作成する場合、ネスト設定「--features nesting=1」が必要になる
    run_cmd_or_die(
        "pct", "create", $SETUP_CONTAINER_ID, $container_image,
        "--arch", "amd64",
        "--hostname", $SETUP_CONTAINER_NAME,
        "--rootfs", "local-lvm:60",
        "--memory", "2048",
        "--swap", "2048",
        "--cores", "4",
        "--net0", "name=eth0,bridge=$SETUP_BR_WAN,hwaddr=$SETUP_WAN_MACADDR,firewall=0",
        "--net1", "name=lan0,bridge=$SETUP_BR_INET,hwaddr=$SETUP_LAN_MACADDR,firewall=0,ip=dhcp",
        "--ostype", "ubuntu",
        "--unprivileged", "1",
        "--features", "nesting=1",
    );
}

sub start_suricata_container {
    run_cmd_or_die("pct", "start", $SETUP_CONTAINER_ID);
}

sub push_suricata_setup_script {
    # [suricata.guest] だけを切り出して渡す ( VRRP パスワードなど他の設定をコンテナへ持ち込まない )
    my ($fh, $guest_config) = tempfile(UNLINK => 1);
    binmode($fh, ':encoding(UTF-8)');
    $fh->print(dump_toml(cfg($C, "suricata.guest")));
    close($fh);

    run_cmd_or_die("pct", "exec", $SETUP_CONTAINER_ID, "--", "mkdir", "-p", "$GUEST_WORK_DIR/lib");
    push_or_die("$FindBin::Bin/suricata/setup.pl", "$GUEST_WORK_DIR/setup.pl", "744");
    push_or_die("$FindBin::Bin/suricata/suricata.yaml.tmpl", "$GUEST_WORK_DIR/suricata.yaml.tmpl", "644");
    push_or_die("$FindBin::Bin/lib/SetupConfig.pm", "$GUEST_WORK_DIR/lib/SetupConfig.pm", "644");
    push_or_die($guest_config, "$GUEST_WORK_DIR/config.toml", "600");
}

sub wait_for_nic_up {
    my $polling_wait_max = 30;
    my $wait_count = 0;
    while (run_cmd("pct exec $SETUP_CONTAINER_ID -- ping -c 1 -W 2 8.8.8.8 > /dev/null 2>&1") != 0) {
        die "Error: Internet connection timeout\n" if $wait_count >= $polling_wait_max;
        sleep 2;
        $wait_count++;
    }
}

sub run_suricata_setup_script {
    run_cmd_or_die("pct", "exec", $SETUP_CONTAINER_ID, "--", "/bin/bash", "-c",
        "/usr/bin/perl $GUEST_WORK_DIR/setup.pl $GUEST_WORK_DIR/config.toml $GUEST_WORK_DIR/suricata.yaml.tmpl > /root/setup.log 2>&1");
    # セットアップ用ファイルを削除
    run_cmd_or_die("pct", "exec", $SETUP_CONTAINER_ID, "--", "rm", "-rf", $GUEST_WORK_DIR);
}

sub write_var_lib_vz_snippets_snippets_suricata_hook_sh {
    my ($suricata_port) = grep { /^veth[0-9]{3}[io][0-9]+$/ } map { chomp; $_ } read_cmd_or_die("ovs-vsctl", "list-ports", $SETUP_BR_WAN);
    die "Error: Suricata container port not found on $SETUP_BR_WAN\n" unless defined $suricata_port;

    my $path = "$SETUP_SNIPPET_DIRECTORY/suricata-hook.sh";
    open(my $fh, '>', $path) or die "Cannot open $path: $!\n";
    $fh->print(<<~"EOF");
    #!/bin/bash

    if [ "\$2" == "post-start" ]; then
        sleep 10
        ovs-vsctl -- --id=\@src get port $SETUP_PHYSICAL_WAN_PORT \\
            -- --id=\@out get port $suricata_port \\
            -- --id=\@mirror create mirror name=$SETUP_MIRROR_NAME select-src-port=\@src select-dst-port=\@src output-port=\@out \\
            -- set bridge $SETUP_BR_WAN mirrors=\@mirror
    fi
    EOF
    close($fh);

    chmod(0755, $path) or die "Cannot chmod $path: $!\n";
}

sub add_hookscript_into_container {
    run_cmd_or_die("pct", "set", $SETUP_CONTAINER_ID, "-hookscript", $SETUP_SNIPPET);
}

sub reboot_container {
    run_cmd_or_die("pct", "reboot", $SETUP_CONTAINER_ID);
}

sub setup_main {
    print "Downloding Ubuntu container image...\n";
    download_image();
    print "Creating Suricata container...\n";
    create_container();
    start_suricata_container();
    push_suricata_setup_script();
    wait_for_nic_up();
    run_suricata_setup_script();
    write_var_lib_vz_snippets_snippets_suricata_hook_sh();
    add_hookscript_into_container();
    reboot_container();
    print "Setup completed.\n";
}

setup_main();
