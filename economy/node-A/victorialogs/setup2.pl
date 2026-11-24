#!/usr/bin/perl
use strict;
use warnings;
use IO::Handle;

# =====================================
# ノード A : victorialogs 設定
# =====================================

# 引数 : VictoriaLogs のバージョン
my $SETUP_VICTORIALOGS_VERSION = "v1.51.0";
# 引数 : VictoriaLogs の実行ユーザー名
my $SETUP_VICTORIALOGS_USER = "victorialogs";
# 引数 : VictoriaLogs のバイナリ配置ディレクトリ
my $SETUP_VICTORIALOGS_BIN_DIR = "/opt/victorialogs";
# 引数 : VictoriaLogs のデータ保存ディレクトリ
my $SETUP_VICTORIALOGS_DATA_DIR = "/var/lib/victorialogs";
# 引数 : ログの保存期間
my $SETUP_VICTORIALOGS_RETENTION_PERIOD = "30d";
# 引数 : VictoriaLogs の HTTP API ( 取り込み・検索・Web UI ) が待ち受けるポート番号
my $SETUP_VICTORIALOGS_HTTP_PORT = 9428;
# 引数 : VictoriaLogs の syslog リスナー ( TCP ) が待ち受けるポート番号
# 非特権コンテナでは 1024 番未満のポートを一般ユーザーが利用できないため、syslog で使うポートを 5140 番にする
my $SETUP_VICTORIALOGS_SYSLOG_TCP_PORT = 5140;

my $SETUP_VICTORIALOGS_ARCHIVE = "victoria-logs-linux-amd64-$SETUP_VICTORIALOGS_VERSION.tar.gz";
my $SETUP_VICTORIALOGS_URL = "https://github.com/VictoriaMetrics/VictoriaLogs/releases/download/$SETUP_VICTORIALOGS_VERSION/$SETUP_VICTORIALOGS_ARCHIVE";
my $SETUP_VICTORIALOGS_UNIT_FILE = "/etc/systemd/system/victorialogs.service";

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
# ユーザー作成
# =====================================

sub create_victorialogs_user {
    run_cmd_or_die("useradd", "--system", "--no-create-home", "--shell", "/usr/sbin/nologin", $SETUP_VICTORIALOGS_USER);
    run_cmd_or_die("mkdir", "-p", $SETUP_VICTORIALOGS_BIN_DIR, $SETUP_VICTORIALOGS_DATA_DIR);
    run_cmd_or_die("chown", "-R", "$SETUP_VICTORIALOGS_USER:$SETUP_VICTORIALOGS_USER", $SETUP_VICTORIALOGS_BIN_DIR, $SETUP_VICTORIALOGS_DATA_DIR);
}

# =====================================
# バイナリの取得
# =====================================

sub install_victorialogs {
    my $work_dir = "/tmp/victorialogs-install";
    run_cmd_or_die("mkdir", "-p", $work_dir);
    run_cmd_or_die("curl", "-fL", "-o", "$work_dir/$SETUP_VICTORIALOGS_ARCHIVE", $SETUP_VICTORIALOGS_URL);
    run_cmd_or_die("tar", "xzf", "$work_dir/$SETUP_VICTORIALOGS_ARCHIVE", "-C", $work_dir);
    run_cmd_or_die("install", "-o", $SETUP_VICTORIALOGS_USER, "-g", $SETUP_VICTORIALOGS_USER, "-m", "755",
        "$work_dir/victoria-logs-prod", "$SETUP_VICTORIALOGS_BIN_DIR/victoria-logs-prod");
    run_cmd_or_die("rm", "-rf", $work_dir);
}

# =====================================
# ユニットファイル作成
# =====================================

sub create_unit_file {
    open(my $fh, '>', $SETUP_VICTORIALOGS_UNIT_FILE) or die "Cannot open $SETUP_VICTORIALOGS_UNIT_FILE: $!\n";
    $fh->print(<<"EOF");
[Unit]
Description=VictoriaLogs
After=network.target

[Service]
User=$SETUP_VICTORIALOGS_USER
Group=$SETUP_VICTORIALOGS_USER
ExecStart=$SETUP_VICTORIALOGS_BIN_DIR/victoria-logs-prod \\
  -storageDataPath=$SETUP_VICTORIALOGS_DATA_DIR \\
  -retentionPeriod=$SETUP_VICTORIALOGS_RETENTION_PERIOD \\
  -httpListenAddr=:$SETUP_VICTORIALOGS_HTTP_PORT \\
  -syslog.listenAddr.tcp=:$SETUP_VICTORIALOGS_SYSLOG_TCP_PORT \\
  -loggerFormat=json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    close($fh);
}

# =====================================
# VictoriaLogs 起動
# =====================================

sub start_victorialogs {
    run_cmd_or_die("systemctl", "daemon-reload");
    run_cmd_or_die("systemctl", "enable", "--now", "victorialogs");
    run_cmd("systemctl", "status", "--no-pager", "victorialogs"); # セットアップログへ起動状態を記録
}

sub setup_main {
    create_victorialogs_user();
    install_victorialogs();
    create_unit_file();
    start_victorialogs();
}

setup_main();
