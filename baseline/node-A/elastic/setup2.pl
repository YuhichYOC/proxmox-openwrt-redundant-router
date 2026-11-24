#!/bin/perl
use strict;
use warnings;
use IO::Handle;

# =====================================
# ノード A : elastic 設定
# =====================================

# 引数 : Elasticsearch 公開署名鍵の URL
my $SETUP_ELASTICSEARCH_PUBKEY_URL = "https://artifacts.elastic.co/GPG-KEY-elasticsearch";
# 引数 : Elasticsearch 外部リポジトリの GPG 公開鍵保存先フルパス
my $SETUP_ELASTICSEARCH_PUBKEY_GPG_PATH = "/usr/share/keyrings/elasticsearch-keyring.gpg";
# 引数 : Elasticsearch の APT リポジトリ URL
my $SETUP_ELASTIC_REPO_URL = "https://artifacts.elastic.co/packages/9.x/apt";
# 引数 : Elasticsearch の APT リポジトリファイルパス
my $SETUP_ELASTIC_REPO_FILE = "/etc/apt/sources.list.d/elastic-9.x.list";

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

sub install_elastic {
    run_cmd_or_die("apt-get", "update");
    run_cmd_or_die("apt-get", "install", "-y", "apt-transport-https", "curl", "gpg", "wget", "libnss3", "libfontconfig1", "libgbm1", "libasound2t64", "cpanminus");
    #                                                                                                            libasound2 の代わりに ^^^^^^^^^^^^^ を使用する
    run_cmd_or_die("wget", "-qO", "elastic.gpg.key", $SETUP_ELASTICSEARCH_PUBKEY_URL);
    run_cmd_or_die("gpg", "--dearmor", "-o", $SETUP_ELASTICSEARCH_PUBKEY_GPG_PATH, "elastic.gpg.key");
    my $repo_line = "deb [signed-by=$SETUP_ELASTICSEARCH_PUBKEY_GPG_PATH] $SETUP_ELASTIC_REPO_URL stable main\n";
    my $repo_file = "$SETUP_ELASTIC_REPO_FILE";
    open(my $fh, '>', $repo_file) or die "Cannot open $repo_file: $!\n";
    $fh->print($repo_line);
    close($fh);
    run_cmd_or_die("apt-get", "update");
    open(my $command_h, '-|', 'bash', '-c', 'apt-get install -y elasticsearch 2>&1') or die "Failed to install elasticsearch: $!\n";
    open(my $log_fh, '>', 'elastic_install.log') or die "Cannot open elastic_install.log: $!\n";
    while (my $line = <$command_h>) {
        $log_fh->print($line);
    }
    close($log_fh);
    close($command_h);
}

sub setup_main {
    install_elastic();
}

setup_main();
