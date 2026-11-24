#!/usr/bin/perl
use strict;
use warnings;
use IO::Handle;

# =====================================
# ノード A : victorialogs 設定
# =====================================

# 引数 : タイムゾーン
my $SETUP_TIMEZONE = "Asia/Tokyo";
# 引数 : Debian リポジトリミラー URL
my $SETUP_DEBIAN_MIRROR_URL = "http://ftp.jp.debian.org/debian";

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
