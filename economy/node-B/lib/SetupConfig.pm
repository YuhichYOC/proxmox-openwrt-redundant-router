package SetupConfig;
use strict;
use warnings;
use Exporter 'import';

# =====================================
# 設定ファイル ( TOML ) 読み込み用モジュール
# =====================================
#
# Proxmox クリーンインストール直後でも動くよう、CPAN モジュールを使わずに TOML のサブセットを解釈する
# 対応している書式
#   - コメント            : # 以降 ( 文字列中の # は除く )
#   - テーブル            : [table] / [table.sub]
#   - キー                : bare_key = 値 ( 英数字・_・- )
#   - 文字列              : "basic" ( \" \\ \n \t エスケープ対応 ) / 'literal'
#   - 整数                : 123 / -1
#   - 真偽値              : true / false
#   - 配列                : [ "a", "b" ] / [ 1, 2 ] ( 複数行・末尾カンマ可 )
# 未対応 : インラインテーブル, テーブル配列 [[x]], 日付, 浮動小数点, 複数行文字列

our @EXPORT_OK = qw(load_config dump_toml shell_quote cfg);

sub _strip_comment {
    my ($line) = @_;
    my $out = "";
    my $quote = "";
    my @chars = split(//, $line);
    for (my $i = 0; $i < @chars; $i++) {
        my $c = $chars[$i];
        if ($quote eq '"' && $c eq '\\') {
            $out .= $c . ($chars[$i + 1] // "");
            $i++;
            next;
        }
        if ($quote) {
            $quote = "" if $c eq $quote;
        } elsif ($c eq '"' || $c eq "'") {
            $quote = $c;
        } elsif ($c eq '#') {
            last;
        }
        $out .= $c;
    }
    return $out;
}

sub _parse_value {
    my ($text, $where) = @_;
    my $pos = 0;
    my $value = _parse_value_at(\$text, \$pos, $where);
    my $rest = substr($text, $pos);
    die "$where: unexpected text after value: $rest\n" if $rest =~ /\S/;
    return $value;
}

sub _skip_ws {
    my ($text_ref, $pos_ref) = @_;
    $$pos_ref++ while $$pos_ref < length($$text_ref) && substr($$text_ref, $$pos_ref, 1) =~ /\s/;
}

sub _parse_value_at {
    my ($text_ref, $pos_ref, $where) = @_;
    _skip_ws($text_ref, $pos_ref);
    my $rest = substr($$text_ref, $$pos_ref);
    if ($rest =~ /^"((?:[^"\\]|\\.)*)"/) {
        $$pos_ref += length($&);
        my $s = $1;
        my %esc = ('"' => '"', '\\' => '\\', 'n' => "\n", 't' => "\t", 'r' => "\r");
        $s =~ s/\\(.)/exists $esc{$1} ? $esc{$1} : die "$where: unsupported escape \\$1\n"/ge;
        return $s;
    }
    if ($rest =~ /^'([^']*)'/) {
        $$pos_ref += length($&);
        return $1;
    }
    if ($rest =~ /^(true|false)\b/) {
        $$pos_ref += length($&);
        return $1 eq 'true' ? 1 : 0;
    }
    if ($rest =~ /^([+-]?\d[\d_]*)\b/) {
        $$pos_ref += length($&);
        (my $n = $1) =~ s/_//g;
        return $n + 0;
    }
    if ($rest =~ /^\[/) {
        $$pos_ref++;
        my @array;
        while (1) {
            _skip_ws($text_ref, $pos_ref);
            die "$where: unterminated array\n" if $$pos_ref >= length($$text_ref);
            if (substr($$text_ref, $$pos_ref, 1) eq ']') {
                $$pos_ref++;
                last;
            }
            push @array, _parse_value_at($text_ref, $pos_ref, $where);
            _skip_ws($text_ref, $pos_ref);
            my $c = substr($$text_ref, $$pos_ref, 1);
            if ($c eq ',') {
                $$pos_ref++;
            } elsif ($c ne ']') {
                die "$where: expected ',' or ']' in array\n";
            }
        }
        return \@array;
    }
    die "$where: cannot parse value: $rest\n";
}

sub _bracket_depth {
    my ($text) = @_;
    my $depth = 0;
    my $quote = "";
    my @chars = split(//, $text);
    for (my $i = 0; $i < @chars; $i++) {
        my $c = $chars[$i];
        if ($quote eq '"' && $c eq '\\') { $i++; next; }
        if ($quote) { $quote = "" if $c eq $quote; next; }
        if ($c eq '"' || $c eq "'") { $quote = $c; next; }
        $depth++ if $c eq '[';
        $depth-- if $c eq ']';
    }
    return $depth;
}

# TOML ファイルを読み込み、ハッシュリファレンスを返す
sub load_config {
    my ($path) = @_;
    open(my $fh, '<:encoding(UTF-8)', $path) or die "Cannot open config file $path: $!\n";
    my %root;
    my $table = \%root;
    my $lineno = 0;
    my ($pending_key, $pending_value, $pending_line);
    while (my $raw = <$fh>) {
        $lineno++;
        my $line = _strip_comment($raw);
        if (defined $pending_key) {
            # 複数行配列の続き
            $pending_value .= " $line";
            next if _bracket_depth($pending_value) > 0;
            $table->{$pending_key} = _parse_value($pending_value, "$path:$pending_line");
            undef $pending_key;
            next;
        }
        next if $line =~ /^\s*$/;
        if ($line =~ /^\s*\[\s*([A-Za-z0-9_.-]+)\s*\]\s*$/) {
            $table = \%root;
            for my $part (split(/\./, $1)) {
                $table->{$part} //= {};
                die "$path:$lineno: $part is not a table\n" unless ref($table->{$part}) eq 'HASH';
                $table = $table->{$part};
            }
            next;
        }
        if ($line =~ /^\s*([A-Za-z0-9_-]+)\s*=\s*(.*?)\s*$/) {
            my ($key, $value) = ($1, $2);
            die "$path:$lineno: duplicate key $key\n" if exists $table->{$key};
            if (_bracket_depth($value) > 0) {
                ($pending_key, $pending_value, $pending_line) = ($key, $value, $lineno);
                next;
            }
            $table->{$key} = _parse_value($value, "$path:$lineno");
            next;
        }
        die "$path:$lineno: cannot parse line: $raw";
    }
    die "$path:$pending_line: unterminated array\n" if defined $pending_key;
    close($fh);
    return \%root;
}

# "table.sub.key" 形式で値を取り出す・存在しない場合は die
sub cfg {
    my ($config, $path) = @_;
    my $node = $config;
    for my $part (split(/\./, $path)) {
        die "Config error: '$path' is not defined\n" unless ref($node) eq 'HASH' && exists $node->{$part};
        $node = $node->{$part};
    }
    return $node;
}

sub _toml_scalar {
    my ($v) = @_;
    return $v if defined($v) && $v =~ /^-?\d+$/;
    (my $s = $v // "") =~ s/(["\\])/\\$1/g;
    $s =~ s/\n/\\n/g;
    $s =~ s/\t/\\t/g;
    return "\"$s\"";
}

# フラットなハッシュ ( 値はスカラーか配列 ) を TOML 文字列にする
# コンテナへ必要な設定だけを渡すときに使う
sub dump_toml {
    my ($hash) = @_;
    my $out = "";
    for my $key (sort keys %$hash) {
        my $v = $hash->{$key};
        if (ref($v) eq 'ARRAY') {
            $out .= "$key = [" . join(", ", map { _toml_scalar($_) } @$v) . "]\n";
        } else {
            $out .= "$key = " . _toml_scalar($v) . "\n";
        }
    }
    return $out;
}

# sh 向けにシングルクォートで囲む
sub shell_quote {
    my ($s) = @_;
    $s =~ s/'/'\\''/g;
    return "'$s'";
}

1;
