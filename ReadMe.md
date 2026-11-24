### proxmox-openwrt-redundant-router by Yuichi Yoshii is licensed under the Apache License, Version2.0

Proxmox 上の OpenWrt で冗長構成ルーターを構築するスクリプト集  
構成の異なるバージョンをディレクトリごとに同居させている

| ディレクトリ | 内容 |
| --- | --- |
| [baseline](baseline/ReadMe.md) | 基本構成 ( OpenWrt 冗長化 + Suricata + Elasticsearch & Kibana ) |
| [economy](economy/ReadMe.md) | baseline の Elasticsearch & Kibana を VictoriaLogs へ置き換えた省リソース構成 |

各バージョンのセットアップ手順は、それぞれのディレクトリの ReadMe.md を参照
