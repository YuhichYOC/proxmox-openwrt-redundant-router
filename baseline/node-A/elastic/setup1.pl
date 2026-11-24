#!/bin/perl
use strict;
use warnings;
use IO::Handle;

# =====================================
# ノード A : elastic 設定
# =====================================

# 引数 : タイムゾーン
my $SETUP_TIMEZONE = "Asia/Tokyo";
# 引数 : Ubuntu リポジトリミラー URL
my $SETUP_UBUNTU_MIRROR_URL = "jp.archive.ubuntu.com";

# 引数 : Elastic コンテナの名前
my $SETUP_CONTAINER_NAME = "elastic";

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
    # http://archive.ubuntu.com/ubuntu に日本からアクセスすると非常に遅いのでミラーの指定を行う
    # ファイル /etc/apt/sources.list.d/ubuntu.sources が存在する場合は /etc/apt/sources.list.d/ubuntu.sources, 存在しない場合は /etc/apt/sources.list を更新
    my $target = -f "/etc/apt/sources.list.d/ubuntu.sources" ? "/etc/apt/sources.list.d/ubuntu.sources" : "/etc/apt/sources.list";
    # archive.ubuntu.com もしくは us.archive.ubuntu.com を jp.archive.ubuntu.com へ置換する
    my $content = "$target.edit";
    open(my $input, '<', $target) or die $!;
    open(my $output, '>', $content) or die $!;
    while (my $line = <$input>) {
        $line =~ s/(archive|us\.archive)\.ubuntu\.com/$SETUP_UBUNTU_MIRROR_URL/;
        # print($output, $line); は $output, $line をリストと見做して全部標準出力へ出力する。print $output $line とは全然違うらしい
        # 急にシェルスクリプトぽい挙動すんなし。それでも bash で書くよりは全然マシ。python 使いてェ
        $output->print($line); # IO::Handle::print を使う
    }
    close($output);
    close($input);
    rename($content, $target) or die $!;
}

sub install_packages {
    run_cmd_or_die("apt-get", "update");
    run_cmd_or_die("apt-get", "install", "-y", "cpanminus");
    run_cmd_or_die("cpanm", "File::Copy", "YAML::PP");
}

sub backup_etc_hosts {
    my $target = "/etc/hosts";
    my $backup = "$target.org";
    require File::Copy;
    File::Copy::copy($target, $backup) or die "Failed to backup $target to $backup: $!\n";
}

sub regexp_edit_etc_hosts {
    my $target = "/etc/hosts";
    my $content = "$target.edit";
    open(my $input, '<', $target) or die $!;
    open(my $output, '>', $content) or die $!;
    while (my $line = <$input>) {
        # 127.0.1.1 <FQDN ( Proxmox が自動で設定 )> <ホスト名 ( Proxmox が自動で設定 )> をコメントアウト
        $line =~ s/^(.+\s+$SETUP_CONTAINER_NAME.*)/#$1/;
        $output->print($line);
    }
    close($output);
    close($input);
    rename($content, $target) or die $!;
}

sub stop_auto_edit_etc_hosts_by_proxmox {
    # /etc/.pve-ignore.hosts を空のファイルで配置することにより、Proxmox が自動で /etc/hosts を編集することを抑制する
    run_cmd_or_die("touch", "/etc/.pve-ignore.hosts");
}

sub setup_main {
    change_timezone();
    change_mirror();
    install_packages();
    backup_etc_hosts();
    regexp_edit_etc_hosts();
    stop_auto_edit_etc_hosts_by_proxmox();
}

setup_main();
