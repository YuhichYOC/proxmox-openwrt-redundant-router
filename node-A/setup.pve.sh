#!/bin/bash
set -euo pipefail

# =====================================
# ノード A : test1pve1 設定
# =====================================

# 引数 : この Proxmox ノードを識別する番号
SETUP_NODE_NUMBER=1
# 引数 : この Proxmox ノードの名前
SETUP_NODENAME="test1pve1"
# 引数 : 使用するドメインの名前
SETUP_DOMAIN="lan"

# 引数 : このノードで稼働する OpenWrt VM が WAN 側の NIC として利用する物理 NIC
SETUP_PHYSICAL_WAN_PORT="ens33"
# 引数 : このノードで稼働する OpenWrt VM が LAN 側の NIC として利用する物理 NIC
SETUP_PHYSICAL_LAN_PORTS=("ens34" "ens35")

# 引数 : Enterprise Repository を無効化するか
SETUP_DISABLE_ENTERPRISE_REPOSITORY=false
# 引数 : Debian ミラーリポジトリの指定を変更するか
SETUP_CHANGE_DEBIAN_MIRROR=false
# 引数 : Debian ミラーリポジトリの URL
SETUP_DEBIAN_MIRROR_URL="http://ftp.jp.debian.org/debian/"

# 引数 : Proxmox ノードセットアップ中に一時的に利用するルーターの IP アドレス
SETUP_TEMPORARY_GATEWAY="192.168.200.1"
# 引数 : Proxmox ノード管理 & クラスターネットワークの先頭 3 オクテット
SETUP_MGMT_NET_PREFIX="192.168.82"
# Proxmox ノード管理 & クラスターネットワーク
SETUP_MGMT_NET="${SETUP_MGMT_NET_PREFIX}.0/24"
# 引数 : OpenWrt が VRRP で利用するネットワーク
SETUP_VRRP_NET="192.168.92.0/24"
# 引数 : OpenWrt がインターネットアクセスを提供する LAN ネットワーク
SETUP_INET_NET="192.168.101.0/24"

# 引数 : この Proxmox ノードが管理 & クラスターで使用する IP アドレス ( CIDR )
SETUP_PVE_MGMT_CIDR="192.168.82.1/24"
# 引数 : この Proxmox ノードが管理 & クラスターで使用する IP アドレス ( IPv4 )
SETUP_PVE_MGMT_IPV4="192.168.82.1"
# 引数 : この Proxmox ノードがインターネットアクセスにアクセスする IP アドレス ( CIDR )
SETUP_PVE_INET_CIDR="192.168.101.251/24"
# 引数 : OpenWrt のセットアップ完了時点でこのノードがインターネットアクセスするときのルーター IP アドレス = このノードのデフォルトゲートウェイ = クラスターネットワークセグメント, VRRP ネットワークセグメント, インターネットアクセスセグメント以外へアクセスする際どちらへパケットを送信するか？
SETUP_PVE_DEFAULT_GATEWAY="192.168.101.1"
# 引数 : Proxmox クラスターに存在するノードの IP アドレス ( IPv4 )
SETUP_CLUSTER_NODES=("192.168.82.1" "192.168.82.2" "192.168.82.3") # ノード 1, 2, QDevice

# 引数 : WAN 側ブリッジ ( WAN ⇔ OpenWrt ) の名前
SETUP_BR_WAN="br0_wan"
# 引数 : LAN 側 L2 ブリッジの名前
SETUP_BR_L2="br1_lanl2"
# 引数 : LAN 側 L3 ブリッジの名前
SETUP_BR_L3="br2_lanl3"
# 引数 : Proxmox 管理用 L2 ブリッジの名前
SETUP_BR_MGMT="br3_mgmt"
# 引数 : VRRP 用 L2 ブリッジの名前
SETUP_BR_VRRP="br4_vrrp"
# 引数 : インターネットアクセス提供用 L2 ブリッジの名前
SETUP_BR_INET="br5_inet"
# 引数 : Proxmox 専用 L3 ブリッジの名前
SETUP_BR_PVEL3="br6_pvel3"

# 引数 : Proxmox 管理用 OVS 内部インターフェースの名前
SETUP_PVEL3_MGMT_PORT="mgmt0"
# 引数 : Proxmox がインターネットへアクセスするための内部インターフェースの名前
SETUP_PVEL3_INET_PORT="inet0"
# 引数 : LAN 側 L2 ブリッジ から LAN 側 L3 ブリッジ への OVS ピアポートの名前
SETUP_PATCH_TO_LANL3="p-to-lanl3"
# 引数 : LAN 側 L3 ブリッジ から LAN 側 L2 ブリッジ への OVS ピアポートの名前
SETUP_PATCH_FROM_LANL3="p-from-lanl3"
# 引数 : LAN 側 L3 ブリッジ から Proxmox 管理用 L2 ブリッジ への OVS ピアポートの名前
SETUP_PATCH_TO_MGMT="p-to-mgmt"
# 引数 : Proxmox 管理用 L2 ブリッジ から LAN 側 L3 ブリッジ への OVS ピアポートの名前
SETUP_PATCH_FROM_MGMT="p-from-mgmt"
# 引数 : LAN 側 L3 ブリッジ から VRRP 用 L2 ブリッジ への OVS ピアポートの名前
SETUP_PATCH_TO_VRRP="p-to-vrrp"
# 引数 : VRRP 用 L2 ブリッジ から LAN 側 L3 ブリッジ への OVS ピアポートの名前
SETUP_PATCH_FROM_VRRP="p-from-vrrp"
# 引数 : LAN 側 L3 ブリッジ から インターネットアクセス提供用 L2 ブリッジ への OVS ピアポートの名前
SETUP_PATCH_TO_INET="p-to-inet"
# 引数 : インターネットアクセス提供用 L2 ブリッジ から LAN 側 L3 ブリッジ への OVS ピアポートの名前
SETUP_PATCH_FROM_INET="p-from-inet"
# 引数 : Proxmox 管理用 L2 ブリッジ から Proxmox 専用 L3 ブリッジ への OVS ピアポートの名前
SETUP_PATCH_TO_PVEL3_MGMT="p-to-pvel3m"
# 引数 : Proxmox 専用 L3 ブリッジ から Proxmox 管理用 L2 ブリッジ への OVS ピアポートの名前
SETUP_PATCH_FROM_PVEL3_MGMT="p-from-pvel3m"
# 引数 : インターネットアクセス提供用 L2 ブリッジ から Proxmox 専用 L3 ブリッジ への OVS ピアポートの名前
SETUP_PATCH_TO_PVEL3_INET="p-to-pvel3i"
# 引数 : Proxmox 専用 L3 ブリッジ から インターネットアクセス提供用 L2 ブリッジ への OVS ピアポートの名前
SETUP_PATCH_FROM_PVEL3_INET="p-from-pvel3i"

# 引数 : OpenWrt VM ディスクイメージのダウンロード URL
SETUP_OPENWRT_IMAGE_URL="https://downloads.openwrt.org/releases/24.10.5/targets/x86/64/openwrt-24.10.5-x86-64-generic-ext4-combined-efi.img.gz"
# 引数 : 使用する OpenWrt のバージョン
SETUP_OPENWRT_VERSION="24.10.5"
# セットアップ実行日付 ( YYYYMMDD )
SETUP_DATE=$(date +%Y%m%d)
# 引数 : スニペットディレクトリのパス
SETUP_SNIPPET_DIRECTORY="/var/lib/vz/snippets"

# 引数 : OpenWrt VM の VM ID
SETUP_OPENWRTS=("101" "102")

# 引数 : Proxmox クラスターを作成するか
SETUP_CREATE_CLUSTER=false
# 引数 : クラスター作成時のクラスター名
SETUP_CLUSTER_NAME="pve-cluster"
# 引数 : Proxmox クラスターに参加するか
# 注意 : クラスター参加の自動化を Proxmox 公式は推奨していない
SETUP_JOIN_CLUSTER=false
# 引数 : クラスターのマスターノード IP アドレス
SETUP_CLUSTER_MASTER_IPV4="192.168.82.1"
# 引数 : クラスターのマスターノード名
SETUP_CLUSTER_MASTER_NODENAME="test1pve1"
# 引数 : クラスターのマスターノード root ユーザーパスワード
SETUP_CLUSTER_MASTER_PASSWORD="cluster_root_password"

# =====================================
# 一時的に WAN へ接続できるようにする
# 前提
# 1. ノードは管理用 NIC へ接続中
# 2. WAN 用 NIC は接続中・設定なし
# =====================================

write_temp_network_configuration () {
	cp /etc/network/interfaces /etc/network/interfaces.org

	cat <<-EOF > /etc/network/interfaces
		auto lo
		iface lo inet loopback

		iface $SETUP_PHYSICAL_WAN_PORT inet manual

		auto vmbr_wan
		iface vmbr_wan inet dhcp
		    gateway $SETUP_TEMPORARY_GATEWAY
		    bridge-ports $SETUP_PHYSICAL_WAN_PORT
		    bridge-stp off
		    bridge-fd 0

	EOF

	for port in "${SETUP_PHYSICAL_LAN_PORTS[@]}"; do
		cat <<-EOF >> /etc/network/interfaces
			iface $port inet manual

		EOF
	done

	cat <<-EOF >> /etc/network/interfaces
		auto vmbr_lan
		iface vmbr_lan inet static
		    address $SETUP_PVE_MGMT_CIDR
		    bridge-ports ${SETUP_PHYSICAL_LAN_PORTS[@]}
		    bridge-stp on
		    bridge-fd 0

		source /etc/network/interfaces.d/*
	EOF
}

restart_network () {
	ifreload -a || true
}

# =====================================
# パッケージのインストール
# =====================================

disable_enterprise_repository () {
	if [ "${SETUP_DISABLE_ENTERPRISE_REPOSITORY}" != "true" ]; then
		return 0
	fi
	# Proxmox Enterprise Repository ( CEPH ) の無効化
	cat <<-EOF >> /etc/apt/sources.list.d/ceph.sources
		Enabled: false
	EOF
	# Proxmox Enterprise Repository ( PVE ) の無効化
	cat <<-EOF >> /etc/apt/sources.list.d/pve-enterprise.sources
		Enabled: false
	EOF
	# Proxmox No-Subscription Repository の追加
	cat <<-EOF > /etc/apt/sources.list.d/proxmox.sources
		Types: deb
		URIs: http://download.proxmox.com/debian/pve
		Suites: trixie
		Components: pve-no-subscription
		Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
	EOF
}

install_packages () {
	if [ "${SETUP_CHANGE_DEBIAN_MIRROR}" = "true" ]; then
		sed -i.org 's@http://deb.debian.org/debian/@'"${SETUP_DEBIAN_MIRROR_URL}"'@' /etc/apt/sources.list.d/debian.sources
	fi
	apt-get update
	apt-get install openvswitch-switch iputils-arping corosync-qdevice -y

	#if [ "${SETUP_JOIN_CLUSTER}" = "true" ]; then
	#	apt-get install expect -y
	#fi
}

# =====================================
# イメージダウンロード
# =====================================

download_image () {
	wget -O "/var/lib/vz/template/iso/openwrt.${SETUP_OPENWRT_VERSION}.${SETUP_DATE}-ext4-combined-efi.img.gz" "${SETUP_OPENWRT_IMAGE_URL}"
	gunzip /var/lib/vz/template/iso/openwrt.${SETUP_OPENWRT_VERSION}.${SETUP_DATE}-ext4-combined-efi.img.gz || true
}

# =====================================
# ネットワーク設定用スクリプトの配置
# =====================================

write_etc_systemd_system_apply_openflow_service() {
	cat <<-EOF > /etc/systemd/system/apply-openflow.service
		[Unit]
		Description=Apply OpenFlow rules after boot or OVS restart
		After=network-online.target openvswitch.service
		Wants=network-online.target

		[Service]
		Type=oneshot
		ExecStartPre=/usr/local/bin/wait_for_ovs_intport.sh
		ExecStart=/usr/local/bin/apply-openflow.sh
		RemainAfterExit=true

		[Install]
		WantedBy=multi-user.target
	EOF
}

write_usr_local_bin_get_ofport_sh () {
	cat <<-EOF > /usr/local/bin/get_ofport.sh
		#!/bin/bash
		set -e
		PORT="\$1"

		if [ -z "\$PORT" ]; then
		    echo "Usage: \$0 <port-name>" >&2
		    exit 2
		fi

		for i in \$(seq 1 10); do
		    OFP=\$(ovs-vsctl --if-exists get Interface "\$PORT" ofport 2>/dev/null)
		    if [[ -n "\$OFP" && "\$OFP" != "[]" && "\$OFP" != "-1" ]]; then
		        echo "\$OFP"
		        exit 0
		    fi
		    sleep 0.5
		done

		echo "ERROR: cannot get ofport for \$PORT" >&2
		exit 1
	EOF

	chmod +x /usr/local/bin/get_ofport.sh
}

write_usr_local_bin_wait_for_ovs_intport_sh () {
	cat <<-EOF > /usr/local/bin/wait_for_ovs_intport.sh
		#!/bin/bash
		set -e

		MAX_WAIT=60
		INTERVAL=2
		elapsed=0

		echo "Waiting for inet0 to acquire IP address..."

		while [ \$elapsed -lt \$MAX_WAIT ]; do
		    if ip addr show inet0 | grep -q "inet "; then
		        IP=\$(ip -4 addr show inet0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}/\d+' | head -1)
		        echo "inet0 has IP address: \$IP"
		        exit 0
		    fi

		    sleep \$INTERVAL
		    elapsed=\$((elapsed + INTERVAL))
		    echo "Still waiting... (\${elapsed}s / \${MAX_WAIT}s)"
		done

		echo "WARNING: inet0 did not acquire IP address within \${MAX_WAIT} seconds"
		echo "Proceeding anyway..."
		exit 0  # 警告だけでサービスは続行
	EOF

	chmod +x /usr/local/bin/wait_for_ovs_intport.sh
}

write_usr_local_bin_apply_openflow_sh () {
	cat <<-EOF > /usr/local/bin/apply-openflow.sh
		#!/bin/bash
		set -euo pipefail

		CONFIG_FILE="/etc/openvswitch/networks.conf"

		if [ ! -f "\$CONFIG_FILE" ]; then
		    echo "ERROR: Configuration file \$CONFIG_FILE not found" >&2
		    exit 1
		fi

		source "\$CONFIG_FILE"

		get_ofport () { /usr/local/bin/get_ofport.sh "\$1"; }

		# フローエントリ用ポート番号取得
		PMGMT0=\$(get_ofport "\$PVEL3_MGMT_PORT")
		PINET0=\$(get_ofport "\$PVEL3_INET_PORT")
		PMGMT=\$(get_ofport "\$PATCH_TO_MGMT")
		PVRRP=\$(get_ofport "\$PATCH_TO_VRRP")
		PINET=\$(get_ofport "\$PATCH_TO_INET")
		PMGMTPVEL3=\$(get_ofport "\$PATCH_FROM_PVEL3M")
		PINETPVEL3=\$(get_ofport "\$PATCH_FROM_PVEL3I")
		PL3=\$(get_ofport "\$PATCH_FROM_L3")

		delete_flows_from_br_l3 () {
		    ovs-ofctl --protocols=OpenFlow13 del-flows "\$BR_L3" 2>/dev/null || true
		}

		add_corosync_flows_into_br_l3 () {
		    local cluster_node="\$1"

		    # TCP/UDP 5404-5405 ( Corosync )
		    ovs-ofctl --protocols=OpenFlow13 add-flow "\$BR_L3" \\
		        "priority=500,in_port=\${PL3},ip,nw_dst=\${cluster_node},tp_dst=5404,actions=output:\${PMGMT}"
		    ovs-ofctl --protocols=OpenFlow13 add-flow "\$BR_L3" \\
		        "priority=500,in_port=\${PL3},ip,nw_dst=\${cluster_node},tp_dst=5405,actions=output:\${PMGMT}"

		    # SSH ( クラスター管理用 )
		    ovs-ofctl --protocols=OpenFlow13 add-flow "\$BR_L3" \\
		        "priority=500,in_port=\${PL3},tcp,nw_dst=\${cluster_node},tp_dst=22,actions=output:\${PMGMT}"
		}

		add_mgmt_flows_into_br_l3 () {
		    # 管理ネットワーク宛て
		    ovs-ofctl --protocols=OpenFlow13 add-flow "\$BR_L3" \\
		        "priority=400,in_port=\${PL3},arp,arp_tpa=\${MGMT_NET},actions=output:\${PMGMT}"
		    ovs-ofctl --protocols=OpenFlow13 add-flow "\$BR_L3" \\
		        "priority=400,in_port=\${PL3},ip,nw_dst=\${MGMT_NET},actions=output:\${PMGMT}"
		}

		add_vrrp_flows_into_br_l3 () {
		    # VRRP マルチキャストの処理
		    ovs-ofctl --protocols=OpenFlow13 add-flow "\$BR_L3" \\
		        "priority=300,in_port=\${PL3},ip,nw_dst=224.0.0.18,actions=output:\${PVRRP}"

		    # VRRP ネットワーク宛て
		    ovs-ofctl --protocols=OpenFlow13 add-flow "\$BR_L3" \\
		        "priority=300,in_port=\${PL3},arp,arp_tpa=\${VRRP_NET},actions=output:\${PVRRP}"
		    ovs-ofctl --protocols=OpenFlow13 add-flow "\$BR_L3" \\
		        "priority=300,in_port=\${PL3},ip,nw_dst=\${VRRP_NET},actions=output:\${PVRRP}"
		}

		add_vrrp_flood_flows_into_br_l3 () {
		    # VRRP ネットワークからのマルチキャストを全物理ポートへ転送（フラッド）
		    ovs-ofctl --protocols=OpenFlow13 add-flow "\$BR_L3" \\
		        "priority=300,in_port=\${PVRRP},ip,nw_dst=224.0.0.18,actions=output:\${PL3}"
		}

		add_inet_flows_into_br_l3 () {
		    # その他すべて ( インターネット向け )
		    ovs-ofctl --protocols=OpenFlow13 add-flow "\$BR_L3" \\
		        "priority=200,in_port=\${PL3},actions=output:\${PINET}"
		}

		add_return_flows_into_br_l3 () {
		    # 戻りトラフィック（全物理ポートにフラッド - スイッチが適切なポートを選択）
		    ovs-ofctl --protocols=OpenFlow13 add-flow "\$BR_L3" \\
		        "priority=100,in_port=\${PMGMT},actions=output:\${PL3}"
		    ovs-ofctl --protocols=OpenFlow13 add-flow "\$BR_L3" \\
		        "priority=100,in_port=\${PVRRP},actions=output:\${PL3}"
		    ovs-ofctl --protocols=OpenFlow13 add-flow "\$BR_L3" \\
		        "priority=100,in_port=\${PINET},actions=output:\${PL3}"
		}

		add_default_drop_flow_into_br_l3 () {
		    # デフォルト : ドロップ
		    ovs-ofctl --protocols=OpenFlow13 add-flow "\$BR_L3" \\
		        "priority=0,actions=drop"
		}

		init_flows_into_br_l2 () {
		    local bridge="\$1"

		    ovs-ofctl --protocols=OpenFlow13 del-flows "\$bridge" 2>/dev/null || true
		    ovs-ofctl --protocols=OpenFlow13 add-flow "\$bridge" "priority=0,actions=normal"
		}

		delete_flows_from_br_pvel3 () {
		    ovs-ofctl --protocols=OpenFlow13 del-flows "\$BR_PVEL3" 2>/dev/null || true
		}

		add_mgmt_flows_into_br_pvel3 () {
		    # 管理 NW 内部通信
		    ovs-ofctl --protocols=OpenFlow13 add-flow "\$BR_PVEL3" \\
		        "priority=500,in_port=\${PMGMT0},ip,nw_dst=\${MGMT_NET},actions=output:\${PMGMTPVEL3}"
		    ovs-ofctl --protocols=OpenFlow13 add-flow "\$BR_PVEL3" \\
		        "priority=500,in_port=\${PMGMTPVEL3},ip,nw_dst=\${MGMT_NET},actions=output:\${PMGMT0}"
		}

		add_inet_flows_into_br_pvel3 () {
		    # 家庭 LAN 内部通信
		    ovs-ofctl --protocols=OpenFlow13 add-flow "\$BR_PVEL3" \\
		        "priority=500,in_port=\${PINET0},ip,actions=output:\${PINETPVEL3}"
		    ovs-ofctl --protocols=OpenFlow13 add-flow "\$BR_PVEL3" \\
		        "priority=500,in_port=\${PINETPVEL3},ip,nw_dst=\${INET_NET},actions=output:\${PINET0}"
		}

		add_security_drop_flows_into_br_pvel3 () {
		    # 管理 NW から家庭 LAN への直接アクセスを拒否
		    ovs-ofctl --protocols=OpenFlow13 add-flow "\$BR_PVEL3" \\
		        "priority=450,in_port=\${PMGMT0},ip,nw_dst=\${INET_NET},actions=drop"

		    # 家庭 LAN から管理 NW へのアクセスを拒否
		    ovs-ofctl --protocols=OpenFlow13 add-flow "\$BR_PVEL3" \\
		        "priority=450,in_port=\${PINET0},ip,nw_dst=\${MGMT_NET},actions=drop"
		    ovs-ofctl --protocols=OpenFlow13 add-flow "\$BR_PVEL3" \\
		        "priority=450,in_port=\${PINETPVEL3},ip,nw_dst=\${MGMT_NET},actions=drop"
		}

		add_arp_flows_into_br_pvel3 () {
		    # ARP は制限付きで許可
		    ovs-ofctl --protocols=OpenFlow13 add-flow "\$BR_PVEL3" \\
		        "priority=200,arp,arp_tpa=\${MGMT_NET},actions=output:\${PMGMTPVEL3},\${PMGMT0}"
		    ovs-ofctl --protocols=OpenFlow13 add-flow "\$BR_PVEL3" \\
		        "priority=200,arp,arp_tpa=\${INET_NET},actions=output:\${PINETPVEL3},\${PINET0}"
		}

		add_default_drop_flow_into_br_pvel3 () {
		    # デフォルト : ドロップ
		    ovs-ofctl --protocols=OpenFlow13 add-flow "\$BR_PVEL3" \\
		        "priority=0,actions=drop"
		}

		# ===== L3 振り分け用ブリッジ =====
		delete_flows_from_br_l3

		# ===== 【重要】クラスター通信の優先ルール =====
		for node_ip in "\${CLUSTER_NODES[@]}"; do
		    add_corosync_flows_into_br_l3 "\${node_ip}"
		done

		# 管理ネットワーク宛て
		add_mgmt_flows_into_br_l3

		# VRRP マルチキャストの処理
		# VRRP ネットワーク宛て
		add_vrrp_flows_into_br_l3

		# VRRP ネットワークからのマルチキャストを全物理ポートへ転送（フラッド）
		add_vrrp_flood_flows_into_br_l3

		# WAN への通信用ルール
		# その他すべて
		add_inet_flows_into_br_l3

		# 戻りトラフィック（全物理ポートにフラッド - スイッチが適切なポートを選択）
		add_return_flows_into_br_l3

		# デフォルト : ドロップ
		add_default_drop_flow_into_br_l3

		# L2 ブリッジとして動作する仮想ブリッジのフローエントリ設定
		# Proxmox ノードに作成した OVS 仮想ブリッジはデフォルトで L2 ブリッジとして動作するため、このステップは今のところ不要。何がしたいのかを示すためコメントアウトで残す
		#for br in "\${L2_BRIDGES[@]}"; do
		#    init_flows_into_br_l2 "\${br}"
		#done

		# ===== ここから下 L3 ブリッジ : PVE <-> 管理ネットワーク / 家庭 LAN 振り分け用の設定 =====
		delete_flows_from_br_pvel3

		# 管理 NW 内部通信 ( br2_mgmt 経由 )
		add_mgmt_flows_into_br_pvel3

		# 家庭 LAN 内部通信 ( br4_inet 経由 )
		add_inet_flows_into_br_pvel3

		# 管理 NW から家庭 LAN への直接アクセスを拒否
		# 家庭 LAN から管理 NW へのアクセスを拒否
		add_security_drop_flows_into_br_pvel3

		# ARP は制限付きで許可
		add_arp_flows_into_br_pvel3

		# デフォルト : ドロップ
		add_default_drop_flow_into_br_pvel3

		echo "OpenFlow rules applied (no VLAN tags needed)"
	EOF

	chmod +x /usr/local/bin/apply-openflow.sh
}

write_var_lib_vz_snippets_snippets_openflow_hook_sh () {
	mkdir -p $SETUP_SNIPPET_DIRECTORY

	cp /etc/pve/storage.cfg /etc/pve/storage.cfg.org

	cat <<-EOF > /etc/pve/storage.cfg
		dir: local
		        path /var/lib/vz
		        content vztmpl,iso,import,backup,snippets

		lvmthin: local-lvm
		        thinpool data
		        vgname pve
		        content rootdir,images
	EOF

	cat <<-EOF > $SETUP_SNIPPET_DIRECTORY/openwrt-hook.sh
		#!/bin/bash
		VMID="\$1"
		PHASE="\$2"

		OPENWRTS=(${SETUP_OPENWRTS[@]@Q})
		CONFIG_FILE="/etc/openvswitch/networks.conf"

		log_message () {
		    echo "\$(date '+%Y-%m-%d %H:%M:%S') [\$HOSTNAME] \$1" >> /var/log/openwrt-hook.log
		}

		if [ ! -f "\$CONFIG_FILE" ]; then
		    log_message "ERROR: Configuration file \$CONFIG_FILE not found"
		    exit 1
		fi

		source "\$CONFIG_FILE"

		detect_openwrt_port () {
		    local bridge="\$1"
		    local vmid="\$2"

		    if ! ovs-vsctl br-exists "\$bridge" 2>/dev/null; then
		        log_message "ERROR: Bridge \$bridge does not exist"
		        return 1
		    fi

		    local all_ports=\$(ovs-vsctl list-ports "\$bridge" 2>/dev/null) || return 1

		    # パターン 1 : ファイアウォール有効 ( VM / LXC 共通 )
		    local ports=\$(echo "\$all_ports" | grep -E "^fwln\${vmid}[io][0-9]+\$")
		    if [ -n "\$ports" ]; then
		        [ \$(echo "\$ports" | grep -c .) -gt 1 ] && log_message "WARNING: Multiple fwln ports found for VMID \$vmid on \$bridge"
		        echo "\$ports" | head -1
		        return 0
		    fi

		    # パターン 2 : VM, ファイアウォール無効
		    ports=\$(echo "\$all_ports" | grep -E "^tap\${vmid}[io][0-9]+\$")
		    if [ -n "\$ports" ]; then
		        [ \$(echo "\$ports" | grep -c .) -gt 1 ] && log_message "WARNING: Multiple tap ports found for VMID \$vmid on \$bridge"
		        echo "\$ports" | head -1
		        return 0
		    fi

		    # パターン 3 : LXC, ファイアウォール無効
		    ports=\$(echo "\$all_ports" | grep -E "^veth\${vmid}[io][0-9]+\$")
		    if [ -n "\$ports" ]; then
		        [ \$(echo "\$ports" | grep -c .) -gt 1 ] && log_message "WARNING: Multiple veth ports found for VMID \$vmid on \$bridge"
		        echo "\$ports" | head -1
		        return 0
		    fi

		    return 1
		}

		post_start () {
		    log_message "Container \$VMID started, waiting for veth interfaces..."

		    # LXC の場合、veth インターフェースが作成されるまで少し待つ
		    for i in {1..30}; do
		        VRRP_PORT=\$(detect_openwrt_port "\$BR_VRRP" "\$VMID")
		        INET_PORT=\$(detect_openwrt_port "\$BR_INET" "\$VMID")

		        [ \$i -eq 1 ] || [ \$((i % 5)) -eq 0 ] && \\
		            log_message "Retry \$i/30: VRRP=\${VRRP_PORT:-waiting}, INET=\${INET_PORT:-waiting}"

		        if [ -n "\$VRRP_PORT" ] && [ -n "\$INET_PORT" ]; then
		            log_message "\${VRRP_PORT} and \${INET_PORT} detected"
		            break
		        fi

		        sleep 1
		    done

		    if [ -z "\$VRRP_PORT" ] || [ -z "\$INET_PORT" ]; then
		        log_message "ERROR: Timeout waiting for all ports. VRRP=\${VRRP_PORT:-none}, INET=\${INET_PORT:-none}"
		        exit 1
		    fi

		    # OpenFlow ルール適用
		    if /usr/local/bin/apply-openflow.sh >> /var/log/openflow-apply.log 2>&1; then
		        log_message "OpenFlow rules applied successfully for CT \$VMID"
		    else
		        log_message "ERROR: Failed to apply OpenFlow rules for CT \$VMID"
		    fi
		}

		if [[ "\$PHASE" == "post-start" ]]; then
		    for id in "\${OPENWRTS[@]}"; do
		        if [[ "\$VMID" == "\$id" ]]; then
		            post_start
		            break
		        fi
		    done
		fi
	EOF

	chmod +x $SETUP_SNIPPET_DIRECTORY/openwrt-hook.sh
}

# =====================================
# ネットワーク変更
# =====================================

write_network_configuration () {
	cat <<-EOF > /etc/network/interfaces
		auto lo
		iface lo inet loopback

		# ===== WAN 側設定 =====
		auto $SETUP_PHYSICAL_WAN_PORT
		iface $SETUP_PHYSICAL_WAN_PORT inet manual
		    ovs_type OVSPort
		    ovs_bridge $SETUP_BR_WAN

		auto $SETUP_BR_WAN
		iface $SETUP_BR_WAN inet manual
		    ovs_type OVSBridge
		    ovs_ports $SETUP_PHYSICAL_WAN_PORT

		# ===== LAN 側設定 =====
	EOF

	for port in "${SETUP_PHYSICAL_LAN_PORTS[@]}"; do
		cat <<-EOF >> /etc/network/interfaces
			auto $port
			iface $port inet manual
			    ovs_type OVSPort
			    ovs_bridge $SETUP_BR_L2

		EOF
	done

	cat <<-EOF >> /etc/network/interfaces
		# ===== 1 段目 : L2 ブリッジ =====
		auto $SETUP_BR_L2
		iface $SETUP_BR_L2 inet manual
		    ovs_type OVSBridge
		    ovs_ports ${SETUP_PHYSICAL_LAN_PORTS[@]} $SETUP_PATCH_TO_LANL3
		    up ovs-vsctl set Bridge \${IFACE} rstp_enable=true
		    up ovs-vsctl set Bridge \${IFACE} other_config:rstp-forward-delay=3
		    up ovs-vsctl set Bridge \${IFACE} other_config:rstp-max-age=10
		    up ovs-vsctl set Bridge \${IFACE} other_config:rstp-hello-time=2

		# ===== 2 段目 : L3 振り分け用ブリッジ =====
		auto $SETUP_BR_L3
		iface $SETUP_BR_L3 inet manual
		    ovs_type OVSBridge
		    ovs_ports $SETUP_PATCH_FROM_LANL3 $SETUP_PATCH_TO_MGMT $SETUP_PATCH_TO_VRRP $SETUP_PATCH_TO_INET

		# ===== 3 段目 : 管理用ブリッジ =====
		auto $SETUP_BR_MGMT
		iface $SETUP_BR_MGMT inet manual
		    ovs_type OVSBridge
		    ovs_ports $SETUP_PATCH_FROM_MGMT $SETUP_PATCH_TO_PVEL3_MGMT

		# ===== 3 段目 : VRRP ブリッジ =====
		auto $SETUP_BR_VRRP
		iface $SETUP_BR_VRRP inet manual
		    ovs_type OVSBridge
		    ovs_ports $SETUP_PATCH_FROM_VRRP

		# ===== 3 段目 : 家庭用ブリッジ =====
		auto $SETUP_BR_INET
		iface $SETUP_BR_INET inet manual
		    ovs_type OVSBridge
		    ovs_ports $SETUP_PATCH_FROM_INET $SETUP_PATCH_TO_PVEL3_INET

		# ===== 4 段目 : PVE <-> 管理ネットワーク / 家庭 LAN 振り分け用ブリッジ =====
		auto $SETUP_BR_PVEL3
		iface $SETUP_BR_PVEL3 inet manual
		    ovs_type OVSBridge
		    ovs_ports $SETUP_PATCH_FROM_PVEL3_MGMT $SETUP_PATCH_FROM_PVEL3_INET $SETUP_PVEL3_MGMT_PORT $SETUP_PVEL3_INET_PORT

		# 管理ネットワーク用内部ポート
		auto $SETUP_PVEL3_MGMT_PORT
		iface $SETUP_PVEL3_MGMT_PORT inet static
		    ovs_type OVSIntPort
		    ovs_bridge $SETUP_BR_PVEL3
		    address $SETUP_PVE_MGMT_CIDR
			up arping -U -I \${IFACE} -c 3 $SETUP_PVE_MGMT_IPV4

		# 家庭 LAN 用内部ポート
		auto $SETUP_PVEL3_INET_PORT
		iface $SETUP_PVEL3_INET_PORT inet static
		    ovs_type OVSIntPort
		    ovs_bridge $SETUP_BR_PVEL3
		    address $SETUP_PVE_INET_CIDR
		    gateway $SETUP_PVE_DEFAULT_GATEWAY

		# ===== パッチポート定義 =====

		# $SETUP_BR_L2 <-> $SETUP_BR_L3
		auto $SETUP_PATCH_TO_LANL3
		iface $SETUP_PATCH_TO_LANL3 inet manual
		    ovs_type OVSPatchPort
		    ovs_bridge $SETUP_BR_L2
		    ovs_patch_peer $SETUP_PATCH_FROM_LANL3

		auto $SETUP_PATCH_FROM_LANL3
		iface $SETUP_PATCH_FROM_LANL3 inet manual
		    ovs_type OVSPatchPort
		    ovs_bridge $SETUP_BR_L3
		    ovs_patch_peer $SETUP_PATCH_TO_LANL3

		# $SETUP_BR_L3 <-> $SETUP_BR_MGMT
		auto $SETUP_PATCH_TO_MGMT
		iface $SETUP_PATCH_TO_MGMT inet manual
		    ovs_type OVSPatchPort
		    ovs_bridge $SETUP_BR_L3
		    ovs_patch_peer $SETUP_PATCH_FROM_MGMT

		auto $SETUP_PATCH_FROM_MGMT
		iface $SETUP_PATCH_FROM_MGMT inet manual
		    ovs_type OVSPatchPort
		    ovs_bridge $SETUP_BR_MGMT
		    ovs_patch_peer $SETUP_PATCH_TO_MGMT

		# $SETUP_BR_L3 <-> $SETUP_BR_VRRP
		auto $SETUP_PATCH_TO_VRRP
		iface $SETUP_PATCH_TO_VRRP inet manual
		    ovs_type OVSPatchPort
		    ovs_bridge $SETUP_BR_L3
		    ovs_patch_peer $SETUP_PATCH_FROM_VRRP

		auto $SETUP_PATCH_FROM_VRRP
		iface $SETUP_PATCH_FROM_VRRP inet manual
		    ovs_type OVSPatchPort
		    ovs_bridge $SETUP_BR_VRRP
		    ovs_patch_peer $SETUP_PATCH_TO_VRRP

		# $SETUP_BR_L3 <-> $SETUP_BR_INET
		auto $SETUP_PATCH_TO_INET
		iface $SETUP_PATCH_TO_INET inet manual
		    ovs_type OVSPatchPort
		    ovs_bridge $SETUP_BR_L3
		    ovs_patch_peer $SETUP_PATCH_FROM_INET

		auto $SETUP_PATCH_FROM_INET
		iface $SETUP_PATCH_FROM_INET inet manual
		    ovs_type OVSPatchPort
		    ovs_bridge $SETUP_BR_INET
		    ovs_patch_peer $SETUP_PATCH_TO_INET

		# $SETUP_BR_MGMT <-> $SETUP_BR_PVEL3
		auto $SETUP_PATCH_TO_PVEL3_MGMT
		iface $SETUP_PATCH_TO_PVEL3_MGMT inet manual
		    ovs_type OVSPatchPort
		    ovs_bridge $SETUP_BR_MGMT
		    ovs_patch_peer $SETUP_PATCH_FROM_PVEL3_MGMT

		auto $SETUP_PATCH_FROM_PVEL3_MGMT
		iface $SETUP_PATCH_FROM_PVEL3_MGMT inet manual
		    ovs_type OVSPatchPort
		    ovs_bridge $SETUP_BR_PVEL3
		    ovs_patch_peer $SETUP_PATCH_TO_PVEL3_MGMT

		# $SETUP_BR_INET <-> $SETUP_BR_PVEL3
		auto $SETUP_PATCH_TO_PVEL3_INET
		iface $SETUP_PATCH_TO_PVEL3_INET inet manual
		    ovs_type OVSPatchPort
		    ovs_bridge $SETUP_BR_INET
		    ovs_patch_peer $SETUP_PATCH_FROM_PVEL3_INET

		auto $SETUP_PATCH_FROM_PVEL3_INET
		iface $SETUP_PATCH_FROM_PVEL3_INET inet manual
		    ovs_type OVSPatchPort
		    ovs_bridge $SETUP_BR_PVEL3
		    ovs_patch_peer $SETUP_PATCH_TO_PVEL3_INET

		source /etc/network/interfaces.d/*
	EOF
}

write_etc_openvswitch_networks_conf () {
	cat <<-EOF > /etc/openvswitch/networks.conf
		# 管理ネットワーク
		MGMT_NET=$SETUP_MGMT_NET
		# VRRP ネットワーク
		VRRP_NET=$SETUP_VRRP_NET
		# LAN ネットワーク
		INET_NET=$SETUP_INET_NET

		# 仮想ブリッジ名
		BR_L2=$SETUP_BR_L2
		BR_L3=$SETUP_BR_L3
		BR_MGMT=$SETUP_BR_MGMT
		BR_VRRP=$SETUP_BR_VRRP
		BR_INET=$SETUP_BR_INET
		BR_PVEL3=$SETUP_BR_PVEL3
		#L2_BRIDGES=(\$BR_L2 \$BR_MGMT \$BR_VRRP \$BR_INET)

		# ポート名
		PHYSICAL_PORTS=(${SETUP_PHYSICAL_LAN_PORTS[@]})
		PATCH_FROM_L3=$SETUP_PATCH_FROM_LANL3
		PVEL3_MGMT_PORT=$SETUP_PVEL3_MGMT_PORT
		PVEL3_INET_PORT=$SETUP_PVEL3_INET_PORT
		PATCH_TO_MGMT=$SETUP_PATCH_TO_MGMT
		PATCH_TO_VRRP=$SETUP_PATCH_TO_VRRP
		PATCH_TO_INET=$SETUP_PATCH_TO_INET
		PATCH_FROM_PVEL3M=$SETUP_PATCH_FROM_PVEL3_MGMT
		PATCH_FROM_PVEL3I=$SETUP_PATCH_FROM_PVEL3_INET

		# ノード番号
		NODE_NUMBER=$SETUP_NODE_NUMBER
		# 管理ネットワーク上の IP アドレス
		MGMT_ADDRESS=${SETUP_MGMT_NET_PREFIX}.\${NODE_NUMBER}/24
		# クラスター上のノード
		CLUSTER_NODES=(${SETUP_CLUSTER_NODES[@]@Q})

		# LAN の設定
		INET_MODE=dhcp # または "static"
		# Static モードの場合の設定例
		# INET_ADDRESS=192.168.200.\${NODE_NUMBER}/24
		# INET_GATEWAY=192.168.200.1
		# INET_DNS=192.168.200.1
	EOF
}

write_etc_hosts () {
	cp /etc/hosts /etc/hosts.org

	cat <<-EOF > /etc/hosts
		127.0.0.1 localhost.localdomain localhost
		$SETUP_PVE_MGMT_IPV4 $SETUP_NODENAME.$SETUP_DOMAIN $SETUP_NODENAME
	EOF
	if [ "${SETUP_JOIN_CLUSTER}" = "true" ]; then
		cat <<-EOF >> /etc/hosts
			$SETUP_CLUSTER_MASTER_IPV4 $SETUP_CLUSTER_MASTER_NODENAME.$SETUP_DOMAIN $SETUP_CLUSTER_MASTER_NODENAME
		EOF
	fi
	cat <<-EOF >> /etc/hosts

		# The following lines are desirable for IPv6 capable hosts

		::1     ip6-localhost ip6-loopback
		fe00::0 ip6-localnet
		ff00::0 ip6-mcastprefix
		ff02::1 ip6-allnodes
		ff02::2 ip6-allrouters
		ff02::3 ip6-allhosts
	EOF
}

enable_openflow_restore_service () {
	systemctl daemon-reload
	systemctl enable apply-openflow.service
}

# =====================================
# クラスターの作成 / 参加
# =====================================

create_cluster () {
	if [ "${SETUP_CREATE_CLUSTER}" != "true" ]; then
		return 0
	fi
	pvecm create "${SETUP_CLUSTER_NAME}" -link0 "${SETUP_PVE_MGMT_IPV4}"
}

join_cluster () {
	if [ "${SETUP_JOIN_CLUSTER}" != "true" ]; then
		return 0
	fi
	# クラスターのマスター側が応答するまでしばらく待つ
	for i in {1..30}; do
		echo "Waiting for cluster master ${SETUP_CLUSTER_MASTER_IPV4} to respond... ($i/30)"
		if ping -c 1 -W 2 "${SETUP_CLUSTER_MASTER_IPV4}" > /dev/null 2>&1; then
			break
		fi
	done
	# 注意 : クラスター参加の自動化を Proxmox 公式は推奨していない。以下の処理を利用する場合、セキュリティ面でのリスクを理解した上で行うこと
	# マスター側からの応答が無くてもクラスター参加を続行する。pvecm add コマンドの応答がない場合は手動でクラスターへ参加する必要がある
	# 以下はクラスター参加コマンドの実行例, パスワードと yes の入力を自動化
	# $ pvecm add 192.168.82.1 -link0 192.168.82.2
	# Please enter superuser (root) password for '192.168.82.1': ************
	# Establishing API connection with host '192.168.82.1'
	# The authenticity of host '192.168.82.1' can't be established.
	# X509 SHA256 key fingerprint is xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx.
	# Are you sure you want to continue connecting (yes/no)? yes
	# Login succeeded.
	#expect <<-EOF
	#	set timeout 10
	#	spawn pvecm add "${SETUP_CLUSTER_MASTER_IPV4}" -link0 "${SETUP_PVE_MGMT_IPV4}"
	#	expect "password for '${SETUP_CLUSTER_MASTER_IPV4}':"
	#	send "${SETUP_CLUSTER_MASTER_PASSWORD}\r"
	#	expect "Are you sure you want to continue connecting (yes/no)?"
	#	send "yes\r"
	#	expect eof
	#EOF
	pvecm add "${SETUP_CLUSTER_MASTER_IPV4}" -link0 "${SETUP_PVE_MGMT_IPV4}" <<-EOF
		"${SETUP_CLUSTER_MASTER_PASSWORD}"
		yes
	EOF
}

setup_main() {
	write_temp_network_configuration
	restart_network
	echo "Installing packages..."
	disable_enterprise_repository
	install_packages
	echo "Downloding OpenWrt container image..."
	download_image
	echo "Creating script files..."
	write_etc_systemd_system_apply_openflow_service
	write_usr_local_bin_get_ofport_sh
	write_usr_local_bin_wait_for_ovs_intport_sh
	write_usr_local_bin_apply_openflow_sh
	write_var_lib_vz_snippets_snippets_openflow_hook_sh
	echo "Writing network configuration..."
	write_network_configuration
	write_etc_openvswitch_networks_conf
	write_etc_hosts
	enable_openflow_restore_service
	restart_network
	create_cluster
	join_cluster
	echo "Setup completed."
	shutdown -r now
}

setup_main "$@"
