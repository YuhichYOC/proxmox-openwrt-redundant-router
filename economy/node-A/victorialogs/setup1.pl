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
# 使い方 : perl setup1.pl <設定ファイル>

my $CONFIG_PATH = $ARGV[0] // die "Usage: $0 <config.toml>\n";
my $C = load_config($CONFIG_PATH);

my $SETUP_TIMEZONE = cfg($C, "timezone");
my $SETUP_DEBIAN_MIRROR_URL = cfg($C, "debian_mirror_url");

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
# セットアップ前の環境設定
# =====================================

sub change_timezone {
    run_cmd_or_die("timedatectl", "set-timezone", $SETUP_TIMEZONE);
}

sub change_mirror {
    # ファイル /etc/apt/sources.list.d/debian.sources が存在する場合は /etc/apt/sources.list.d/debian.sources, 存在しない場合は /etc/apt/sources.list を更新
    my $target = -f "/etc/apt/sources.list.d/debian.sources" ? "/etc/apt/sources.list.d/debian.sources" : "/etc/apt/sources.list";
    return unless -f $target;
    my $content = "$target.edit";
    open(my $input, '<', $target) or die $!;
    open(my $output, '>', $content) or die $!;
    while (my $line = <$input>) {
        # http://deb.debian.org/debian を <Debian リポジトリミラー URL> へ置換する
        # http://deb.debian.org/debian-security は置換しない
        $line =~ s@https?://deb\.debian\.org/debian(?=/|\s|$)@$SETUP_DEBIAN_MIRROR_URL@;
        $output->print($line);
    }
    close($output);
    close($input);
    rename($content, $target) or die $!;
}

sub install_packages {
    run_cmd_or_die("apt-get", "update");
    run_cmd_or_die("apt-get", "install", "-y", "curl", "ca-certificates", "tar");
}

sub setup_main {
    change_timezone();
    change_mirror();
    install_packages();
}

setup_main();
