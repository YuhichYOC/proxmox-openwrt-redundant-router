#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use FindBin;
use lib "$FindBin::Bin/lib", "$FindBin::Bin/../lib";
use IO::Handle;
use SetupConfig qw(load_config cfg);

# =====================================
# VictoriaLogs コンテナ内部の設定
# =====================================
# setup.victorialogs.pl が config.toml の [victorialogs.guest] だけを切り出した TOML を作成し、引数として渡す
# 使い方 : perl setup2.pl <設定ファイル>

my $CONFIG_PATH = $ARGV[0] // die "Usage: $0 <config.toml>\n";
my $C = load_config($CONFIG_PATH);

my $SETUP_VICTORIALOGS_VERSION = cfg($C, "version");
my $SETUP_VICTORIALOGS_USER = cfg($C, "user");
my $SETUP_VICTORIALOGS_BIN_DIR = cfg($C, "bin_dir");
my $SETUP_VICTORIALOGS_DATA_DIR = cfg($C, "data_dir");
my $SETUP_VICTORIALOGS_RETENTION_PERIOD = cfg($C, "retention_period");
my $SETUP_VICTORIALOGS_HTTP_PORT = cfg($C, "http_port");
my $SETUP_VICTORIALOGS_SYSLOG_TCP_PORT = cfg($C, "syslog_tcp_port");

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
