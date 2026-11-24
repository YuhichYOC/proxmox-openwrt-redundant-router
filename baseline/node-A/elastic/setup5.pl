#!/bin/perl
use strict;
use warnings;
use File::Copy;
use IO::Handle;

# =====================================
# ノード A : kibana 設定
# =====================================

# 引数 : elastic コンテナの FQDN
my $SETUP_ELASTIC_FQDN = "elastic.lan";
# 引数 : Elasticsearch が待ち受けるポート番号
my $SETUP_ELASTIC_PORT = 9200;
# 引数 : Kibana が待ち受けるポート番号
my $SETUP_KIBANA_PORT = 5601;

# 引数 : Kibana 側 SSL 証明書の保存先パス
my $SETUP_KIBANA_SSL_CERT_PATH = "/etc/kibana/certs/fullchain.pem";
# 引数 : Kibana 側 SSL 鍵ファイルの保存先パス
my $SETUP_KIBANA_SSL_KEY_PATH = "/etc/kibana/certs/privkey.pem";

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
# kibana_system ユーザーのパスワード生成
# =====================================

sub create_kibana_system_password {
    open(my $command_h, '-|', '/usr/share/elasticsearch/bin/elasticsearch-reset-password', '-u', 'kibana_system', '-b', '--url', "https://$SETUP_ELASTIC_FQDN:$SETUP_ELASTIC_PORT") or die "Failed to create kibana_system password: $!\n";
    my @output = <$command_h>;
    close($command_h);

    # elasticsearch-reset-password の出力を切り出して kibana_system_password.output に保存する
    # パスワードが記載されている行の行頭は "New value:" であることが前提
    # Elastic が API を変更した場合は修正が必要, 多分めっちゃ変えてくる
    # 例
    # コマンドの出力
    #   Password for the [kibana_system] user successfully reset.
    #   New value: ot4G1f+P*2ODP=K_40qc
    #   ↓
    # ファイルへの書き込み
    #   ot4G1f+P*2ODP=K_40qc
    print(@output); # セットアップログへコマンドの出力を記録, API 変更に気づく手がかりとする
    open(my $file_h, '>', 'kibana_system_password.output') or die "Cannot open kibana_system_password.output: $!\n";
    $file_h->print(map { /New value:\s+(\S+)/ ? $1 : () } @output);
    close($file_h);
}

# =====================================
# 設定変更
# =====================================

sub backup_etc_kibana_kibana_yml {
    my $target = "/etc/kibana/kibana.yml";
    my $backup = "$target.org";
    copy($target, $backup) or die "Failed to backup $target to $backup: $!\n";
}

sub regexp_edit_etc_kibana_kibana_yml {
    open(my $kibana_system_password_fh, '<', "kibana_system_password.output") or die "Cannot open: $!";
    chomp(my $kibana_system_password = <$kibana_system_password_fh>);
    close($kibana_system_password_fh);

    my $target = "/etc/kibana/kibana.yml";
    my $content = "$target.edit";
    open(my $input, '<', $target) or die $!;
    open(my $output, '>', $content) or die $!;
    while (my $line = <$input>) {
        # #server.host: "localhost"
        # ↓
        # server.host: "<elastic コンテナの FQDN>"
        $line =~ s/^#\s*(server\.host:)\s*.*/$1 "$SETUP_ELASTIC_FQDN"/;
        # #server.publicBaseUrl: ""
        # ↓
        # server.publicBaseUrl: "https://<elastic コンテナの FQDN>:<Kibana が待ち受けるポート番号>"
        $line =~ s@^#\s*(server\.publicBaseUrl:)\s*.*@$1 "https://$SETUP_ELASTIC_FQDN:$SETUP_KIBANA_PORT"@;
        # #server.ssl.enabled: false
        # ↓
        # server.ssl.enabled: true
        $line =~ s/^#\s*(server\.ssl\.enabled:)\s*.*/$1 true/;
        # #server.ssl.certificate: /path/to/your/server.crt
        # ↓
        # server.ssl.certificate: <Kibana 側 SSL 証明書の保存先パス>
        $line =~ s/^#\s*(server\.ssl\.certificate:)\s*.*/$1 $SETUP_KIBANA_SSL_CERT_PATH/;
        # #server.ssl.key: /path/to/your/server.key
        # ↓
        # server.ssl.key: <Kibana 側 SSL 鍵ファイルの保存先パス>
        $line =~ s/^#\s*(server\.ssl\.key:)\s*.*/$1 $SETUP_KIBANA_SSL_KEY_PATH/;
        # #elasticsearch.hosts: ["http://localhost:9200"]
        # ↓
        # elasticsearch.hosts: ["https://<elastic コンテナの FQDN>:<Elasticsearch が待ち受けるポート番号>"]
        $line =~ s@^#\s*(elasticsearch\.hosts:)\s*(\[").+("\])@$1 $2https://$SETUP_ELASTIC_FQDN:$SETUP_ELASTIC_PORT$3@;
        # #elasticsearch.username: "kibana_system"
        # ↓
        # elasticsearch.username: "kibana_system"
        $line =~ s/^#\s*(elasticsearch\.username:\s*.*)/$1/;
        # #elasticsearch.password: "pass"
        # ↓
        # elasticsearch.password: "<create_kibana_system_password で再生成したパスワード>"
        $line =~ s/^#\s*(elasticsearch\.password:)\s+(")\w+(")/$1 $2$kibana_system_password$3/;
        # #elasticsearch.ssl.verificationMode: full
        # ↓
        # elasticsearch.ssl.verificationMode: full
        $line =~ s/^#\s*(elasticsearch\.ssl\.verificationMode:)\s*.*/$1 full/;
        $output->print($line);
    }
    close($output);
    close($input);
    rename($content, $target) or die $!;
}

sub create_encryptedSavedObjects_encryptionKey {
    my $key = `openssl rand -base64 32`;
    chomp $key;
    open(my $file_h, '>', 'encryptedSavedObjects.encryptionKey.output') or die "Cannot open encryptedSavedObjects.encryptionKey.output: $!\n";
    $file_h->print($key);
    close($file_h);
    open(my $pipe, '|-', '/usr/share/kibana/bin/kibana-keystore add xpack.encryptedSavedObjects.encryptionKey --stdin') or die;
    $pipe->print("$key\n");
    close($pipe);
}

sub create_reporting_encryptionKey {
    my $key = `openssl rand -base64 32`;
    chomp $key;
    open(my $file_h, '>', 'reporting.encryptionKey.output') or die "Cannot open reporting.encryptionKey.output: $!\n";
    $file_h->print($key);
    close($file_h);
    open(my $pipe, '|-', '/usr/share/kibana/bin/kibana-keystore add xpack.reporting.encryptionKey --stdin') or die;
    $pipe->print("$key\n");
    close($pipe);
}

sub create_security_encryptionKey {
    my $key = `openssl rand -base64 32`;
    chomp $key;
    open(my $file_h, '>', 'security.encryptionKey.output') or die "Cannot open security.encryptionKey.output: $!\n";
    $file_h->print($key);
    close($file_h);
    open(my $pipe, '|-', '/usr/share/kibana/bin/kibana-keystore add xpack.security.encryptionKey --stdin') or die;
    $pipe->print("$key\n");
    close($pipe);
}

sub start_kibana {
    run_cmd_or_die("systemctl", "daemon-reload");
    run_cmd_or_die("systemctl", "enable", "kibana");
    run_cmd_or_die("systemctl", "start", "kibana");
}

sub setup_main {
    create_kibana_system_password();
    backup_etc_kibana_kibana_yml();
    regexp_edit_etc_kibana_kibana_yml();
    create_encryptedSavedObjects_encryptionKey();
    create_reporting_encryptionKey();
    create_security_encryptionKey();
    start_kibana();
}

setup_main();
