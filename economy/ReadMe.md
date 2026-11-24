### proxmox-openwrt-redundant-router by Yuichi Yoshii is licensed under the Apache License, Version2.0

### economy 構成
baseline の Elasticsearch & Kibana を VictoriaLogs へ置き換えた構成  
VictoriaLogs コンテナは CPU 2 コア・メモリ 2 GiB・ディスク 30 GiB ( Elasticsearch の 10 分の 1 ) から運用を開始する

| 項目 | baseline ( Elasticsearch & Kibana ) | economy ( VictoriaLogs ) |
| --- | --- | --- |
| OS | Ubuntu 24.04 | Debian 13 |
| CPU | 6 コア | 2 コア |
| メモリ | 10 GiB | 2 GiB |
| ディスク | 300 GiB | 30 GiB |
| 待ち受けポート | 9200 ( Elasticsearch ) / 5601 ( Kibana ) | 9428 ( HTTP API・Web UI ) / 5140 ( syslog TCP ) |
| SSL | あり | なし |

### 前提
このリポジトリのスクリプトは Proxmox クリーンインストール直後のノードで実行することを前提にしている  
それ以外の状態で実行する場合の動作確認はしていない

### このスクリプトでセットアップする Proxmox と OpenWrt の関係図
![](../baseline/images/network-image.png)

### セットアップ手順

#### ノード A
1. node-A/setup.pve.sh へ引数を記入
1. node-A/setup.openwrt.sh へ引数を記入
1. node-A/openwrt/setup.sh へ引数を記入
1. VRRP 用パスワードを生成
1. node-A/openwrt/init_interfaces へ引数を記入
1. node-A/setup.suricata.sh へ引数を記入 ( Suricata が必要な場合のみ )
1. node-A/suricata/setup.sh へ引数を記入 ( Suricata が必要な場合のみ )
1. ノード A へ SSH ログイン
1. ノード A へスクリプトを配置
1. setup.pve.sh を実行
    - 自動でログアウトする
1. setup.openwrt.sh を実行
1. Suricata が必要な場合
    - setup.suricata.sh を実行
1. VictoriaLogs が必要な場合
    1. node-A/setup.victorialogs.pl へ引数を記入
    1. node-A/victorialogs/setup1.pl, node-A/victorialogs/setup2.pl へ引数を記入
    1. OpenWrt で VictoriaLogs コンテナ NIC の固定 IP 設定・DNS レコード登録を済ませる
    1. setup.victorialogs.pl を実行
        - Debian 13 コンテナイメージが無い場合は pveam で自動ダウンロードする
        - 実行後 http://<VictoriaLogs コンテナの IP>:9428/select/vmui で Web UI を確認できる

#### ノード B
1. node-B/setup.pve.sh へ引数を記入
1. node-B/setup.openwrt.sh へ引数を記入
1. node-B/openwrt/setup.sh へ引数を記入
1. node-B/openwrt/init_interfaces へ引数を記入
1. node-B/setup.suricata.sh へ引数を記入 ( Suricata が必要な場合のみ )
1. node-B/suricata/setup.sh へ引数を記入 ( Suricata が必要な場合のみ )
1. ノード B へ SSH ログイン
1. ノード B へスクリプトを配置
1. setup.pve.sh を実行
    - 自動でログアウトする
1. setup.openwrt.sh を実行
1. Suricata が必要な場合
    - setup.suricata.sh を実行

#### QDevice ノード
1. qdev/setup.pl へ引数を記入
1. QDevice ノードへ SSH ログイン
1. QDevice ノードへスクリプトを配置
1. setup.pl を実行
