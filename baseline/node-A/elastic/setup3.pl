#!/bin/perl
use strict;
use warnings;
use File::Copy;
use IO::Handle;
use YAML::PP;

# =====================================
# ノード A : elastic 設定
# =====================================

# 引数 : elastic クラスター名
my $SETUP_ELASTIC_CLUSTER_NAME = "my-elastic-cluster";
# 引数 : elastic コンテナの FQDN
my $SETUP_ELASTIC_FQDN = "elastic.lan";
# 引数 : Elasticsearch が待ち受けるポート番号
my $SETUP_ELASTIC_PORT = 9200;
# 引数 : Elasticsearch が利用できるメモリサイズ ( GB )
my $SETUP_ELASTIC_JVM_HEAP_SIZE_GB = 6;

# 引数 : Elastic 側 SSL 証明書の保存先パス
my $SETUP_ELASTIC_SSL_CERT_PATH = "/etc/elasticsearch/certs/fullchain.pem";
# 引数 : Elastic 側 SSL 鍵ファイルの保存先パス
my $SETUP_ELASTIC_SSL_KEY_PATH = "/etc/elasticsearch/certs/privkey.pem";

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
# 設定変更
# =====================================

sub backup_etc_elasticsearch_elasticsearch_yml {
    my $target = "/etc/elasticsearch/elasticsearch.yml";
    my $backup = "$target.org";
    copy($target, $backup) or die "Failed to backup $target to $backup: $!\n";
}

sub regexp_edit_etc_elasticsearch_elasticsearch_yml {
    my $target = "/etc/elasticsearch/elasticsearch.yml";
    my $content = "$target.edit";
    open(my $input, '<', $target) or die $!;
    open(my $output, '>', $content) or die $!;
    while (my $line = <$input>) {
        # #cluster.name: my-application
        # ↓
        # cluster.name: <elastic クラスター名>
        $line =~ s/^#\s*(cluster\.name:)\s*.*/$1 $SETUP_ELASTIC_CLUSTER_NAME/;
        # #network.host: 192.168.0.1
        # ↓
        # network.host: <elastic コンテナの FQDN>
        $line =~ s/^#\s*(network\.host:)\s*.*/$1 $SETUP_ELASTIC_FQDN/;
        # #http.port: 9200
        # ↓
        # http.port: <Elasticsearch が待ち受けるポート番号>
        $line =~ s/^#\s*(http\.port:)\s*.*/$1 $SETUP_ELASTIC_PORT/;
        # http.host: 0.0.0.0
        # ↓
        # http.host: <elastic コンテナの FQDN>
        $line =~ s/^\s*(http\.host:)\s*.*/$1 $SETUP_ELASTIC_FQDN/;
        $output->print($line);
    }
    close($output);
    close($input);
    rename($content, $target) or die $!;
}

sub yaml_pp_edit_etc_elasticsearch_elasticsearch_yml {
    my $target = "/etc/elasticsearch/elasticsearch.yml";
    my $yaml = YAML::PP->new;
    my ($data) = $yaml->load_file($target);
    # xpack.security.http.ssl セクションに certificate と key を追記, keystore.path を削除
    my $http_ssl = $data->{'xpack.security.http.ssl'} //= {};
    $http_ssl->{'certificate'} = $SETUP_ELASTIC_SSL_CERT_PATH;
    $http_ssl->{'key'} = $SETUP_ELASTIC_SSL_KEY_PATH;
    delete $http_ssl->{'keystore.path'};
    # xpack.security.transport.ssl セクションに certificate と key を追記, keystore.path と truststore.path を削除
    my $transport_ssl = $data->{'xpack.security.transport.ssl'} //= {};
    $transport_ssl->{'certificate'} = $SETUP_ELASTIC_SSL_CERT_PATH;
    $transport_ssl->{'key'} = $SETUP_ELASTIC_SSL_KEY_PATH;
    delete $transport_ssl->{'keystore.path'};
    delete $transport_ssl->{'truststore.path'};
    $yaml->dump_file($target, $data);
}

sub backup_etc_elasticsearch_jvm_options {
    my $target = "/etc/elasticsearch/jvm.options";
    my $backup = "$target.org";
    copy($target, $backup) or die "Failed to backup $target to $backup: $!\n";
}

sub regexp_edit_etc_elasticsearch_jvm_options {
    my $target = "/etc/elasticsearch/jvm.options";
    my $content = "$target.ssl";
    open(my $input, '<', $target) or die $!;
    open(my $output, '>', $content) or die $!;
    while (my $line = <$input>) {
        # ## -Xms4g
        # ↓
        # -Xms<Elasticsearch が利用できるメモリサイズ ( GB )>g
        $line =~ s/^#+\s*(-Xms).*/$1${SETUP_ELASTIC_JVM_HEAP_SIZE_GB}g/;
        # ## -Xmx4g
        # ↓
        # -Xmx<Elasticsearch が利用できるメモリサイズ ( GB )>g
        $line =~ s/^#+\s*(-Xmx).*/$1${SETUP_ELASTIC_JVM_HEAP_SIZE_GB}g/;
        $output->print($line);
    }
    close($output);
    close($input);
    rename($content, $target) or die $!;
}

# =====================================
# Elasticsearch 起動
# =====================================

sub start_elastic {
    run_cmd_or_die("systemctl", "daemon-reload");
    run_cmd_or_die("systemctl", "enable", "elasticsearch");
    run_cmd_or_die("systemctl", "start", "elasticsearch");
}

sub setup_main {
    backup_etc_elasticsearch_elasticsearch_yml();
    regexp_edit_etc_elasticsearch_elasticsearch_yml();
    yaml_pp_edit_etc_elasticsearch_elasticsearch_yml();
    backup_etc_elasticsearch_jvm_options();
    regexp_edit_etc_elasticsearch_jvm_options();
    start_elastic();
}

setup_main();
