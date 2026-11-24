#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use FindBin;
use lib "$FindBin::Bin/lib";
use IO::Handle;
use File::Copy;
use File::Glob ':glob';
use POSIX qw(strftime);
use SetupConfig qw(load_config cfg shell_quote);

STDOUT->autoflush(1);

# =====================================
# 設定の読み込み ( 値は config.toml の [openwrt] / [openwrt.guest] へ記入する )
# =====================================

my $CONFIG_PATH = $ARGV[0] // "$FindBin::Bin/config.toml";
my $C = load_config($CONFIG_PATH);

my $SETUP_OPENWRT_VERSION = cfg($C, "openwrt.version");
# セットアップ実行日付 ( YYYYMMDD )
my $SETUP_DATE = strftime("%Y%m%d", localtime);

my $SETUP_VM_ID = cfg($C, "openwrt.vm_id");
my $SETUP_VM_NAME = cfg($C, "openwrt.vm_name");

my $SETUP_SNIPPET = cfg($C, "openwrt.snippet");
my $SETUP_OPENWRT_NET_WAN = "virtio=" . cfg($C, "openwrt.wan_macaddr") . ",bridge=" . cfg($C, "pve.br_wan");
my $SETUP_OPENWRT_NET_VRRP = "virtio=" . cfg($C, "openwrt.vrrp_macaddr") . ",bridge=" . cfg($C, "pve.br_vrrp");
my $SETUP_OPENWRT_NET_INET = "virtio=" . cfg($C, "openwrt.inet_macaddr") . ",bridge=" . cfg($C, "pve.br_inet");
my $SETUP_DISK_STORAGE_ID = cfg($C, "openwrt.disk_storage_id");

my $IMAGE_DIRECTORY = "/var/lib/vz/template/iso";
my $MOUNT_POINT = "/mnt/openwrt";
# OpenWrt VM 内のスクリプト ( openwrt/setup.sh, openwrt/init_interfaces ) が読み込むシェル変数ファイル
my $GUEST_CONFIG_PATH = "/etc/openwrt-setup.conf";

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

# =====================================
# 最新ディスクイメージの取得
# =====================================

sub fetch_latest_diskimage {
    my @candidates = sort(bsd_glob("$IMAGE_DIRECTORY/openwrt.${SETUP_OPENWRT_VERSION}.*-ext4-combined-efi.img"));
    die "Error: No OpenWrt image found in $IMAGE_DIRECTORY for version $SETUP_OPENWRT_VERSION\n" unless @candidates;
    return $candidates[-1];
}

sub fetch_temp_diskimage {
    return "$IMAGE_DIRECTORY/openwrt.${SETUP_OPENWRT_VERSION}.${SETUP_DATE}.latest-ext4-combined-efi.img";
}

sub calc_start_offset {
    # fdisk の出力から一番サイズの大きい Linux filesystem ( = xxx-efi.img2 ) の Start ... 33280 を 512 倍した値 = 17039360 を取得
    # 以下は fdisk -l <OpenWrt ディスクイメージファイルパス> の出力例
    # Device                                                                           Start    End Sectors  Size Type
    # /var/lib/vz/template/iso/openwrt-24.10.5-x86-64-generic-ext4-combined-efi.img1     512  33279   32768   16M Linux filesystem
    # /var/lib/vz/template/iso/openwrt-24.10.5-x86-64-generic-ext4-combined-efi.img2   33280 246271  212992  104M Linux filesystem
    # /var/lib/vz/template/iso/openwrt-24.10.5-x86-64-generic-ext4-combined-efi.img128    34    511     478  239K BIOS boot
    my ($max_sectors, $start) = (0, undef);
    for my $line (read_cmd_or_die("fdisk", "-l", fetch_temp_diskimage())) {
        next unless $line =~ /Linux filesystem/;
        my @fields = split(' ', $line);
        if ($fields[3] > $max_sectors) {
            $max_sectors = $fields[3];
            $start = $fields[1];
        }
    }
    die "Error: Linux filesystem partition not found in " . fetch_temp_diskimage() . "\n" unless defined $start;
    return $start * 512;
}

# =====================================
# ディスクイメージの編集
# =====================================

sub copy_openwrt_diskimage {
    # 一日に複数回実施することを考えてディスクイメージのコピーを行う。仮想マシン作成にはコピー先を使用する
    # /etc/rc.local に /root/script.sh キックが複数行書き込まれることを防ぐ
    copy(fetch_latest_diskimage(), fetch_temp_diskimage()) or die "Failed to copy disk image: $!\n";
}

sub expand_openwrt_diskimage {
    # ディスクイメージのサイズを 8 GiB まで拡張する。OpenWrt 側から見えるディスク容量を拡張するには以下の手順を参照
    # https://openwrt.org/docs/guide-user/advanced/expand_root
    run_cmd_or_die("qemu-img", "resize", "-f", "raw", fetch_temp_diskimage(), "8G");
}

sub mount_openwrt_diskimage {
    mkdir($MOUNT_POINT) or die "Cannot create $MOUNT_POINT: $!\n";
    run_cmd_or_die("mount", "-o", "loop,offset=" . calc_start_offset(), fetch_temp_diskimage(), $MOUNT_POINT);
}

sub guest_config_content {
    # [openwrt.guest] の各キーを SETUP_<キーの大文字> というシェル変数にする
    my %vars = (
        NODENAME => $SETUP_VM_NAME,
        MGMT_NET => cfg($C, "pve.mgmt_net_prefix") . ".0/24",
        PHYSICAL_WAN_PORT_MACADDR => cfg($C, "openwrt.wan_macaddr"),
        PHYSICAL_VRRP_PORT_MACADDR => cfg($C, "openwrt.vrrp_macaddr"),
        PHYSICAL_INET_PORT_MACADDR => cfg($C, "openwrt.inet_macaddr"),
    );
    my $guest = cfg($C, "openwrt.guest");
    for my $key (keys %$guest) {
        die "Config error: openwrt.guest.$key must be a scalar\n" if ref($guest->{$key});
        $vars{uc($key)} = $guest->{$key};
    }
    my $content = "# setup.openwrt.pl が config.toml から生成したファイル\n";
    $content .= "SETUP_$_=" . shell_quote($vars{$_}) . "\n" for sort keys %vars;
    return $content;
}

sub put_setup_script_into_diskimage {
    copy("$FindBin::Bin/openwrt/init_interfaces", "$MOUNT_POINT/etc/init.d/init_interfaces") or die "Failed to copy init_interfaces: $!\n";
    chmod(0755, "$MOUNT_POINT/etc/init.d/init_interfaces") or die $!;
    copy("$FindBin::Bin/openwrt/setup.sh", "$MOUNT_POINT/root/setup.sh") or die "Failed to copy setup.sh: $!\n";
    chmod(0755, "$MOUNT_POINT/root/setup.sh") or die $!;

    open(my $conf_h, '>:encoding(UTF-8)', "$MOUNT_POINT$GUEST_CONFIG_PATH") or die "Cannot open $MOUNT_POINT$GUEST_CONFIG_PATH: $!\n";
    $conf_h->print(guest_config_content());
    close($conf_h);
    chmod(0600, "$MOUNT_POINT$GUEST_CONFIG_PATH") or die $!; # VRRP パスワードを含むため root のみ読み取り可

    # /etc/rc.local の exit 0 の前に /root/setup.sh のキックを挿入する
    my $rc_local = "$MOUNT_POINT/etc/rc.local";
    open(my $input, '<', $rc_local) or die "Cannot open $rc_local: $!\n";
    my @lines = <$input>;
    close($input);
    open(my $output, '>', $rc_local) or die "Cannot open $rc_local: $!\n";
    for my $line (@lines) {
        $output->print("/root/setup.sh > /root/setup.log 2>&1\n") if $line =~ /exit 0/;
        $output->print($line);
    }
    close($output);
}

sub unmount_openwrt_diskimage {
    run_cmd_or_die("umount", $MOUNT_POINT);
    rmdir($MOUNT_POINT) or die "Cannot remove $MOUNT_POINT: $!\n";
}

# =====================================
# VM 作成
# =====================================

sub create_vm {
    run_cmd_or_die(
        "qm", "create", $SETUP_VM_ID,
        "--name", $SETUP_VM_NAME,
        "--cpu", "host",
        "--sockets", "1",
        "--cores", "4",
        "--memory", "1024",
        "--net0", $SETUP_OPENWRT_NET_WAN,
        "--net1", $SETUP_OPENWRT_NET_VRRP,
        "--net2", $SETUP_OPENWRT_NET_INET,
        "--ostype", "l26",
        "--hookscript", $SETUP_SNIPPET,
    );

    run_cmd_or_die("qm", "importdisk", $SETUP_VM_ID, fetch_temp_diskimage(), $SETUP_DISK_STORAGE_ID);
    run_cmd_or_die("qm", "set", $SETUP_VM_ID, "--bios", "ovmf");
    run_cmd_or_die("qm", "set", $SETUP_VM_ID, "--efidisk0", "$SETUP_DISK_STORAGE_ID:0");
    my ($unused0) = map { /^unused0:\s+(\S+)/ ? $1 : () } read_cmd_or_die("qm", "config", $SETUP_VM_ID);
    die "Error: imported disk (unused0) not found in VM $SETUP_VM_ID\n" unless defined $unused0;
    run_cmd_or_die("qm", "set", $SETUP_VM_ID, "--sata0", $unused0);
    run_cmd_or_die("qm", "set", $SETUP_VM_ID, "--boot", "order=sata0");
    run_cmd_or_die("qm", "set", $SETUP_VM_ID, "--tablet", "0");
    run_cmd_or_die("qm", "set", $SETUP_VM_ID, "--serial0", "socket");
}

sub start_vm {
    run_cmd_or_die("qm", "start", $SETUP_VM_ID);
}

sub cleanup {
    unlink(fetch_temp_diskimage()) or die "Cannot remove " . fetch_temp_diskimage() . ": $!\n";
}

sub setup_main {
    print "Creating OpenWrt container...\n";
    copy_openwrt_diskimage();
    expand_openwrt_diskimage();
    mount_openwrt_diskimage();
    put_setup_script_into_diskimage();
    unmount_openwrt_diskimage();
    create_vm();
    start_vm();
    cleanup();
    print "Setup completed.\n";
}

setup_main();
