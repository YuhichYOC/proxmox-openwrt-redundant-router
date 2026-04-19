#!/usr/bin/perl
use strict;
use warnings;
use IO::Handle;

STDOUT->autoflush(1);

# =====================================
# 設定
# =====================================

# 引数 : Ubuntu リポジトリミラー URL
my $SETUP_UBUNTU_MIRROR_URL = "jp.archive.ubuntu.com";

# 引数 : LAN 側 L2 ブリッジの名前
my $SETUP_BR_L2 = "br1_lanl2";
# 引数 : Proxmox 管理用 L2 ブリッジの名前
my $SETUP_BR_MGMT = "br2_mgmt";
# 引数 : インターネットアクセス用 L2 ブリッジの名前
my $SETUP_BR_INET = "br3_inet";

# 引数 : この QDevice ノードが利用できる物理 NIC の名前
my $SETUP_PHYSICAL_PORT = "ens33";
# 引数 : LAN 側 L2 ブリッジ から Proxmox 管理用 L2 ブリッジ への OVS ピアポートの名前
my $SETUP_PATCH_TO_MGMT = "p-to-mgmt";
# 引数 : Proxmox 管理用 L2 ブリッジ から LAN 側 L2 ブリッジ への OVS ピアポートの名前
my $SETUP_PATCH_FROM_MGMT = "p-from-mgmt";
# 引数 : LAN 側 L2 ブリッジ から インターネットアクセス用 L2 ブリッジ への OVS ピアポートの名前
my $SETUP_PATCH_TO_INET = "p-to-inet";
# 引数 : インターネットアクセス用 L2 ブリッジ から LAN 側 L2 ブリッジ への OVS ピアポートの名前
my $SETUP_PATCH_FROM_INET = "p-from-inet";

# 引数 : Proxmox 管理用 OVS 内部インターフェースの名前
my $SETUP_MGMT_PORT = "mgmt0";
# 引数 : この QDevice ノードが管理 & クラスターで使用する IP アドレス ( CIDR )
my $SETUP_MGMT_CIDR = "192.168.82.3/24";
# 引数 : この QDevice ノードがインターネットへアクセスするための内部インターフェースの名前
my $SETUP_INET_PORT = "inet0";
# 引数 : この QDevice ノードがインターネットへアクセスするための IP アドレス ( CIDR )
my $SETUP_INET_CIDR = "192.168.101.253/24";
# 引数 : この QDevice ノードがインターネットへアクセスするためのデフォルトゲートウェイ
my $SETUP_INET_GATEWAY = "192.168.101.1";
# 引数 : DNS サーバーの IP アドレス
my $SETUP_DNS_SERVER_IPV4 = "192.168.101.1";

# 引数 : Proxmox 管理用 OVS 内部インターフェースへ IP アドレスを設定するまでの待ち時間・このノードが起動したときからインターフェース up まで最大何秒待つか
my $SETUP_MAX_WAIT = 10;

# =====================================
# ユーティリティ
# =====================================

sub run_cmd {
    my @cmd = @_;
    return system(@cmd);  # system() の戻り値をそのまま返す
}

sub run_cmd_or_die {
    my @cmd = @_;
    run_cmd(@cmd) == 0
        or die "Command failed (@cmd): $?\n";
}

# =====================================
# パッケージのインストール
# =====================================

sub change_mirror {
    my $target = -f "/etc/apt/sources.list.d/ubuntu.sources" ? "/etc/apt/sources.list.d/ubuntu.sources" : "/etc/apt/sources.list";
    my $content = "$target.edit";
    open(my $input, '<', $target) or die $!;
    open(my $output, '>', $content) or die $!;
    while (my $line = <$input>) {
        $line =~ s/(archive|us\.archive)\.ubuntu\.com/$SETUP_UBUNTU_MIRROR_URL/;
        $output->print($line);
    }
    close($output);
    close($input);
    rename($content, $target) or die $!;
}

sub install_packages {
    run_cmd_or_die("apt-get", "update");
    run_cmd_or_die("apt-get", "install", "-y", "openvswitch-switch", "corosync-qnetd");
}

# =====================================
# 仮想ブリッジ・インターフェース設定の記入
# =====================================

sub write_usr_local_bin_add_ovs_switch_pl {
    open(my $fh, '>', "/usr/local/bin/add-ovs-switch.pl") or die $!;
    $fh->print(get_usr_local_bin_add_ovs_switch_pl());
    close($fh);
    chmod(0755, "/usr/local/bin/add-ovs-switch.pl") or die $!;
}

sub write_etc_systemd_system_add_ovs_switch_service {
    open(my $fh, '>', "/etc/systemd/system/add-ovs-switch.service") or die $!;
    $fh->print(get_etc_systemd_system_add_ovs_switch_service());
    close($fh);
}

sub write_etc_netplan_99_custom_yaml {
    open(my $fh, '>', "/etc/netplan/99-custom.yaml") or die $!;
    $fh->print(get_etc_netplan_99_custom_yaml());
    close($fh);
}

sub enable_add_ovs_switch_service {
    run_cmd_or_die("systemctl", "daemon-reload");
    run_cmd_or_die("systemctl", "enable", "add-ovs-switch.service");
}

sub setup_main {
    STDOUT->print("Installing packages...\n");
    change_mirror();
    install_packages();
    STDOUT->print("Writing network configuration...\n");
    write_usr_local_bin_add_ovs_switch_pl();
    write_etc_systemd_system_add_ovs_switch_service();
    write_etc_netplan_99_custom_yaml();
    enable_add_ovs_switch_service();
    STDOUT->print("Setup completed.\n");
    STDOUT->sync();
    run_cmd_or_die("shutdown", "-r", "now");
}

setup_main();

# =====================================
# このスクリプトで出力するファイルの内容
# =====================================

sub get_usr_local_bin_add_ovs_switch_pl {
    return <<~"EOS";
    #!/usr/bin/perl
    use strict;
    use warnings;

    my \$BR_L2 = "$SETUP_BR_L2";
    my \$BR_MGMT = "$SETUP_BR_MGMT";
    my \$BR_INET = "$SETUP_BR_INET";
    my \$PATCH_TO_MGMT = "$SETUP_PATCH_TO_MGMT";
    my \$PATCH_FROM_MGMT = "$SETUP_PATCH_FROM_MGMT";
    my \$PATCH_TO_INET = "$SETUP_PATCH_TO_INET";
    my \$PATCH_FROM_INET = "$SETUP_PATCH_FROM_INET";
    my \$MGMT_PORT = "$SETUP_MGMT_PORT";
    my \$MGMT_CIDR = "$SETUP_MGMT_CIDR";
    my \$INET_PORT = "$SETUP_INET_PORT";
    my \$INET_CIDR = "$SETUP_INET_CIDR";
    my \$INET_GATEWAY = "$SETUP_INET_GATEWAY";
    my \$DNS_SERVER_IPV4 = "$SETUP_DNS_SERVER_IPV4";
    my \$MAX_WAIT = $SETUP_MAX_WAIT;

    sub run_cmd {
        my \@cmd = \@_;
        return system(\@cmd);
    }

    sub run_cmd_or_die {
        my \@cmd = \@_;
        run_cmd(\@cmd) == 0
            or die "Command failed (\@cmd): \$?\\n";
    }

    # OVS データベースのソケット準備を待機 ( 最大 10 秒 )
    for my \$i (1 .. \$MAX_WAIT) {
        if (-S "/var/run/openvswitch/db.sock") {
            last;
        }
        if (\$i == \$MAX_WAIT) {
            die "OVS database socket not found after waiting for \$MAX_WAIT seconds\\n";
        }
        sleep(1);
    }

    # OVS パッチポートの設定
    run_cmd_or_die("ovs-vsctl", "--if-exists", "del-port", "\$BR_L2", "\$PATCH_TO_MGMT");
    run_cmd_or_die("ovs-vsctl", "--if-exists", "del-port", "\$BR_MGMT", "\$PATCH_FROM_MGMT");
    run_cmd_or_die("ovs-vsctl", "--if-exists", "del-port", "\$BR_L2", "\$PATCH_TO_INET");
    run_cmd_or_die("ovs-vsctl", "--if-exists", "del-port", "\$BR_INET", "\$PATCH_FROM_INET");

    run_cmd_or_die("ovs-vsctl", "add-port", "\$BR_L2", "\$PATCH_TO_MGMT",
        "--", "set", "interface", "\$PATCH_TO_MGMT", "type=patch", "options:peer=\$PATCH_FROM_MGMT");
    run_cmd_or_die("ovs-vsctl", "add-port", "\$BR_MGMT", "\$PATCH_FROM_MGMT",
        "--", "set", "interface", "\$PATCH_FROM_MGMT", "type=patch", "options:peer=\$PATCH_TO_MGMT");
    run_cmd_or_die("ovs-vsctl", "add-port", "\$BR_L2", "\$PATCH_TO_INET",
        "--", "set", "interface", "\$PATCH_TO_INET", "type=patch", "options:peer=\$PATCH_FROM_INET");
    run_cmd_or_die("ovs-vsctl", "add-port", "\$BR_INET", "\$PATCH_FROM_INET",
        "--", "set", "interface", "\$PATCH_FROM_INET", "type=patch", "options:peer=\$PATCH_TO_INET");

    # mgmt0 インターフェース設定
    run_cmd_or_die("ovs-vsctl", "--if-exists", "del-port", "\$BR_MGMT", "\$MGMT_PORT");
    run_cmd_or_die("ovs-vsctl", "add-port", "\$BR_MGMT", "\$MGMT_PORT", "--", "set", "interface", "\$MGMT_PORT", "type=internal");
    run_cmd_or_die("ip", "link", "set", "\$MGMT_PORT", "up");
    # mgmt0 UP まで待機 ( 最大 10 秒 )
    for my \$i (1 .. \$MAX_WAIT) {
        if (run_cmd("ip", "link", "show", "\$MGMT_PORT") == 0) {
            last;
        }
        sleep(1);
    }
    run_cmd_or_die("ip", "addr", "add", "\$MGMT_CIDR", "dev", "\$MGMT_PORT");

    # inet0 インターフェース設定
    run_cmd_or_die("ovs-vsctl", "--if-exists", "del-port", "\$BR_INET", "\$INET_PORT");
    run_cmd_or_die("ovs-vsctl", "add-port", "\$BR_INET", "\$INET_PORT", "--", "set", "interface", "\$INET_PORT", "type=internal");
    run_cmd_or_die("ip", "link", "set", "\$INET_PORT", "up");
    # inet0 UP まで待機 ( 最大 10 秒 )
    for my \$i (1 .. \$MAX_WAIT) {
        if (run_cmd("ip", "link", "show", "\$INET_PORT") == 0) {
            last;
        }
        sleep(1);
    }
    run_cmd_or_die("ip", "addr", "add", "\$INET_CIDR", "dev", "\$INET_PORT");

    run_cmd_or_die("ip", "route", "add", "default", "via", "\$INET_GATEWAY", "dev", "\$INET_PORT");
    run_cmd_or_die("resolvectl", "dns", "\$INET_PORT", "\$DNS_SERVER_IPV4");
    run_cmd_or_die("resolvectl", "domain", "\$INET_PORT", "~.");
    EOS
}

sub get_etc_systemd_system_add_ovs_switch_service {
    return <<~"EOS";
    [Unit]
    Description=OVS QDevice Configuration
    After=ovsdb-server.service ovs-vswitchd.service systemd-networkd.service network-online.target
    Wants=network-online.target

    [Service]
    Type=oneshot
    ExecStart=/usr/local/bin/add-ovs-switch.pl
    RemainAfterExit=yes

    [Install]
    WantedBy=multi-user.target
    EOS
}

sub get_etc_netplan_99_custom_yaml {
    return <<~"EOS";
    network:
      version: 2
      renderer: networkd
      ethernets:
        $SETUP_PHYSICAL_PORT:
          dhcp4: false
          critical: true
      openvswitch: {}
      bridges:
        $SETUP_BR_L2:
          interfaces: [$SETUP_PHYSICAL_PORT]
          openvswitch: {}
        $SETUP_BR_MGMT:
          openvswitch: {}
        $SETUP_BR_INET:
          openvswitch: {}
    EOS
}
