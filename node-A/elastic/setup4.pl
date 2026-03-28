#!/bin/perl
use strict;
use warnings;
use IO::Handle;

# =====================================
# ノード A : kibana 設定
# =====================================

# 引数 : Kibana 側 SSL 証明書の保存ディレクトリ
my $SETUP_KIBANA_SSL_CERT_DIR = "/etc/kibana/certs";

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

sub install_kibana {
    open(my $out_fh, '-|', 'bash', '-c', 'apt-get install -y kibana 2>&1') or die "Failed to install kibana: $!\n";
    open(my $log_fh, '>', 'kibana_install.log') or die "Cannot open kibana_install.log: $!\n";
    while (my $line = <$out_fh>) {
        $log_fh->print($line);
    }
    close($log_fh);
    close($out_fh);
}

# =====================================
# SSL 証明書配置ディレクトリの作成
# =====================================

sub mkdir_etc_kibana_certs {
    run_cmd_or_die("mkdir", $SETUP_KIBANA_SSL_CERT_DIR);
    run_cmd_or_die("chown", "root:kibana", $SETUP_KIBANA_SSL_CERT_DIR);
}

sub setup_main {
    install_kibana();
    mkdir_etc_kibana_certs();
}

setup_main();
