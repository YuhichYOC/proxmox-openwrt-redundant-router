#!/usr/bin/perl
use strict;
use warnings;
use File::Glob ':glob';

# 前提条件 1. Ubuntu コンテナイメージのダウンロードが済んでいること
# 前提条件 2. SSL 証明書と SSL 鍵ファイルがホスト側のファイルシステム上に存在していること
# 前提条件 3. elastic コンテナの固定 IP 設定と名前解決が DNS サーバーで済んでいること
#
# 例 ... OpenWrt
#   elastic コンテナの作成前でも MAC アドレスに対して割り当てる IP アドレスを設定できる
#   IP アドレスが決まっていれば、DNS レコードも作成できる
# 当スクリプトでは elastic コンテナの NIC が持つ MAC アドレスを引数として指定する・引数の MAC アドレスをルーターでの固定 IP 設定に使用する

# =====================================
# ノード A : elastic 設定
# =====================================

# Ubuntu コンテナイメージはダウンロード済みである前提

# 引数 : コンテナイメージの保存先ディレクトリ
my $SETUP_IMAGE_DIRECTORY = "/var/lib/vz/template/cache";
# 引数 : 使用する Ubuntu のバージョン
my $SETUP_UBUNTU_VERSION = "24.04";
# 引数 : メモリサイズ
my $SETUP_MEMORY_SIZE = "10240"; # MiB
# 引数 : スワップサイズ
my $SETUP_SWAP_SIZE = "10240"; # MiB
# 引数 : CPU コア数
my $SETUP_CPU_CORES = "6";

# 引数 : Elastic コンテナの ID
my $SETUP_CONTAINER_ID = "141";
# 引数 : Elastic コンテナの名前
my $SETUP_CONTAINER_NAME = "elastic";
# 引数 : Elastic コンテナのディスクを配置するストレージ ID
my $SETUP_DISK_STORAGE_ID = "local-lvm";
# 引数 : Elastic コンテナのディスクサイズ ( GiB )
my $SETUP_DISK_SIZE = "300";
# 引数 : Elastic コンテナが LAN と接続する OVS 仮想ブリッジの名前
my $SETUP_BR_INET = "br5_inet";
# 引数 : Elastic コンテナの NIC が持つ MAC アドレス
my $SETUP_NIC_MACADDR = "02:50:58:00:05:05";

# 引数 : ホスト側 SSL 証明書フルパス
my $SETUP_SSL_CERT_PATH = "/root/ssl_certs/elastic.crt";
# 引数 : ホスト側 SSL 鍵ファイルフルパス
my $SETUP_SSL_KEY_PATH = "/root/ssl_certs/elastic.key";
# 引数 : Elastic 側 SSL 証明書の保存先パス
my $SETUP_ELASTIC_SSL_CERT_PATH = "/etc/elasticsearch/certs/fullchain.pem";
# 引数 : Elastic 側 SSL 鍵ファイルの保存先パス
my $SETUP_ELASTIC_SSL_KEY_PATH = "/etc/elasticsearch/certs/privkey.pem";
# 引数 : Kibana 側 SSL 証明書の保存先パス
my $SETUP_KIBANA_SSL_CERT_PATH = "/etc/kibana/certs/fullchain.pem";
# 引数 : Kibana 側 SSL 鍵ファイルの保存先パス
my $SETUP_KIBANA_SSL_KEY_PATH = "/etc/kibana/certs/privkey.pem";

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
# コンテナ作成
# =====================================

sub create_container {
    my @candidates = sort(bsd_glob("$SETUP_IMAGE_DIRECTORY/ubuntu.$SETUP_UBUNTU_VERSION.*.tar.xz"));
    die "Error: No Ubuntu image found in $SETUP_IMAGE_DIRECTORY for version $SETUP_UBUNTU_VERSION\n" unless @candidates;
    my $container_image = $candidates[-1]
        or die "Error: No Ubuntu image found in $SETUP_IMAGE_DIRECTORY\n";

    # Ubuntu 24.04 などの新しい OS のコンテナを作成する場合、ネスト設定「--features nesting=1」が必要になる
    run_cmd_or_die(
        "pct", "create", $SETUP_CONTAINER_ID, $container_image,
        "--arch", "amd64",
        "--hostname", $SETUP_CONTAINER_NAME,
        "--rootfs", "$SETUP_DISK_STORAGE_ID:$SETUP_DISK_SIZE",
        "--memory", $SETUP_MEMORY_SIZE,
        "--swap", $SETUP_SWAP_SIZE,
        "--cores", $SETUP_CPU_CORES,
        "--net0", "name=lan0,bridge=$SETUP_BR_INET,hwaddr=$SETUP_NIC_MACADDR,firewall=0,ip=dhcp",
        "--ostype", "ubuntu",
        "--unprivileged","1",
        "--features", "nesting=1",
    );
}

sub start_elastic_container {
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
    push_or_die("elastic/setup1.pl", "/root/setup1.pl", "root:root", "744");
}

sub run_environment_edit_script {
    run_cmd_or_die("pct exec $SETUP_CONTAINER_ID -- /bin/perl /root/setup1.pl > /root/setup.elasticsearch-$SETUP_CONTAINER_ID-setup1.log 2>&1");
}

sub push_elastic_install_script {
    push_or_die("elastic/setup2.pl", "/root/setup2.pl", "root:root", "744");
}

sub run_elastic_install_script {
    run_cmd_or_die("pct exec $SETUP_CONTAINER_ID -- /bin/perl /root/setup2.pl > /root/setup.elasticsearch-$SETUP_CONTAINER_ID-setup2.log 2>&1");
}

sub push_elastic_ssl_certs {
    push_or_die($SETUP_SSL_CERT_PATH, $SETUP_ELASTIC_SSL_CERT_PATH, "root:elasticsearch", "660");
    push_or_die($SETUP_SSL_KEY_PATH, $SETUP_ELASTIC_SSL_KEY_PATH, "root:elasticsearch", "660");
}

sub push_elastic_config_edit_script {
    push_or_die("elastic/setup3.pl", "/root/setup3.pl", "root:root", "744");
}

sub run_elastic_config_edit_script {
    run_cmd_or_die("pct exec $SETUP_CONTAINER_ID -- /bin/perl /root/setup3.pl > /root/setup.elasticsearch-$SETUP_CONTAINER_ID-setup3.log 2>&1");
}

sub push_kibana_install_script {
    push_or_die("elastic/setup4.pl", "/root/setup4.pl", "root:root", "744");
}

sub run_kibana_install_script {
    run_cmd_or_die("pct exec $SETUP_CONTAINER_ID -- /bin/perl /root/setup4.pl > /root/setup.elasticsearch-$SETUP_CONTAINER_ID-setup4.log 2>&1");
}

sub push_kibana_ssl_certs {
    push_or_die($SETUP_SSL_CERT_PATH, $SETUP_KIBANA_SSL_CERT_PATH, "root:kibana", "660");
    push_or_die($SETUP_SSL_KEY_PATH, $SETUP_KIBANA_SSL_KEY_PATH, "root:kibana", "660");
}

sub push_kibana_config_edit_script {
    push_or_die("elastic/setup5.pl", "/root/setup5.pl", "root:root", "744");
}

sub run_kibana_config_edit_script {
    run_cmd_or_die("pct exec $SETUP_CONTAINER_ID -- /bin/perl /root/setup5.pl > /root/setup.elasticsearch-$SETUP_CONTAINER_ID-setup5.log 2>&1");
}

sub setup_main {
    create_container();
    start_elastic_container();
    wait_for_nic_up();
    push_environment_edit_script();
    run_environment_edit_script();
    push_elastic_install_script();
    run_elastic_install_script();
    push_elastic_ssl_certs();
    push_elastic_config_edit_script();
    run_elastic_config_edit_script();
    push_kibana_install_script();
    run_kibana_install_script();
    push_kibana_ssl_certs();
    push_kibana_config_edit_script();
    run_kibana_config_edit_script();
}

setup_main();
