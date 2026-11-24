#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use FindBin;
use lib "$FindBin::Bin/lib", "$FindBin::Bin/../lib";
use IO::Handle;
use File::Copy;
use SetupConfig qw(load_config cfg);

STDOUT->autoflush(1);

# =====================================
# Suricata コンテナ内部の設定
# =====================================
# setup.suricata.pl が config.toml の [suricata.guest] だけを切り出した TOML を作成し、引数として渡す
# 使い方 : perl setup.pl <設定ファイル> <suricata.yaml テンプレート>

my ($CONFIG_PATH, $TEMPLATE_PATH) = @ARGV;
die "Usage: $0 <config.toml> <suricata.yaml.tmpl>\n" unless defined $CONFIG_PATH && defined $TEMPLATE_PATH;
my $C = load_config($CONFIG_PATH);

my $SETUP_TIMEZONE = cfg($C, "timezone");
my $SETUP_UBUNTU_MIRROR_URL = cfg($C, "ubuntu_mirror_url");
my $SETUP_WAN_NET = cfg($C, "wan_net");
my $SETUP_ENABLE_SURICATA_RULE_NAME = cfg($C, "enable_suricata_rule_name");

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

# =====================================
# 設定
# =====================================

sub change_timezone {
    run_cmd_or_die("timedatectl", "set-timezone", $SETUP_TIMEZONE);
}

sub change_mirror {
    # http://archive.ubuntu.com/ubuntu に日本からアクセスすると非常に遅いのでミラーの指定を行う
    # ファイル /etc/apt/sources.list.d/ubuntu.sources が存在する場合は /etc/apt/sources.list.d/ubuntu.sources, 存在しない場合は /etc/apt/sources.list を更新
    my $target = -f "/etc/apt/sources.list.d/ubuntu.sources" ? "/etc/apt/sources.list.d/ubuntu.sources" : "/etc/apt/sources.list";
    copy($target, "$target.org") or die "Failed to backup $target: $!\n";
    open(my $input, '<', "$target.org") or die $!;
    open(my $output, '>', $target) or die $!;
    while (my $line = <$input>) {
        # archive.ubuntu.com もしくは us.archive.ubuntu.com を <Ubuntu リポジトリミラー> へ置換する
        $line =~ s/(archive|us\.archive)\.ubuntu\.com/$SETUP_UBUNTU_MIRROR_URL/g;
        $output->print($line);
    }
    close($output);
    close($input);
}

sub install_suricata {
    change_mirror();
    run_cmd_or_die("apt-get", "update");
    run_cmd_or_die("apt-get", "install", "suricata", "-y");
}

sub write_etc_suricata_suricata_yaml {
    my $target = "/etc/suricata/suricata.yaml";
    copy($target, "$target.org") or die "Failed to backup $target: $!\n";

    open(my $input, '<:encoding(UTF-8)', $TEMPLATE_PATH) or die "Cannot open $TEMPLATE_PATH: $!\n";
    my $content = do { local $/; <$input> };
    close($input);
    # テンプレート中の @@SETUP_WAN_NET@@ を WAN 側ネットワークへ置換する
    $content =~ s/\@\@SETUP_WAN_NET\@\@/$SETUP_WAN_NET/g;

    open(my $output, '>:encoding(UTF-8)', $target) or die "Cannot open $target: $!\n";
    $output->print($content);
    close($output);
}

sub run_suricata_update {
    run_cmd_or_die("suricata-update");
    run_cmd_or_die("suricata-update", "list-sources");
    run_cmd_or_die("suricata-update", "enable-source", $SETUP_ENABLE_SURICATA_RULE_NAME);
    run_cmd_or_die("suricata-update", "update-sources");
    run_cmd_or_die("suricata-update");
}

sub setup_main {
    change_timezone();
    print "Installing package...\n";
    install_suricata();
    print "Creating config file...\n";
    write_etc_suricata_suricata_yaml();
    run_suricata_update();
    print "Setup completed.\n";
}

setup_main();
