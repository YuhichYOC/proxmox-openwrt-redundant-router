#!/bin/bash
set -euo pipefail

# =====================================
# 設定
# =====================================

# 引数 : LAN 側 L2 ブリッジの名前
SETUP_BR_L2="br1_lanl2"
# 引数 : Proxmox 管理用 L2 ブリッジの名前
SETUP_BR_MGMT="br2_mgmt"
# 引数 : インターネットアクセス用 L2 ブリッジの名前
SETUP_BR_INET="br3_inet"

# 引数 : この QDevice ノードが利用できる物理 NIC の名前
SETUP_PHYSICAL_PORT="ens37"
# 引数 : LAN 側 L2 ブリッジ から Proxmox 管理用 L2 ブリッジ への OVS ピアポートの名前
SETUP_PATCH_TO_MGMT="p-to-mgmt"
# 引数 : Proxmox 管理用 L2 ブリッジ から LAN 側 L2 ブリッジ への OVS ピアポートの名前
SETUP_PATCH_FROM_MGMT="p-from-mgmt"
# 引数 : LAN 側 L2 ブリッジ から インターネットアクセス用 L2 ブリッジ への OVS ピアポートの名前
SETUP_PATCH_TO_INET="p-to-inet"
# 引数 : インターネットアクセス用 L2 ブリッジ から LAN 側 L2 ブリッジ への OVS ピアポートの名前
SETUP_PATCH_FROM_INET="p-from-inet"

# 引数 : Proxmox 管理用 OVS 内部インターフェースの名前
SETUP_MGMT_PORT="mgmt0"
# 引数 : この QDevice ノードがインターネットへアクセスするための内部インターフェースの名前
SETUP_INET_PORT="inet0"
# 引数 : この QDevice ノードが管理 & クラスターで使用する IP アドレス ( CIDR )
SETUP_MGMT_CIDR="192.168.82.3/24"
# 引数 : Proxmox ノード管理 & クラスターネットワーク
SETUP_MGMT_NET="192.168.82.0/24"
# 引数 : Proxmox 管理用 OVS 内部インターフェースへ IP アドレスを設定するまでの待ち時間・このノードが起動したときからインターフェース up まで最大何秒待つか
SETUP_MAX_WAIT=10

# =====================================
# パッケージのインストール
# =====================================

install_packages () {
	apt-get update
	apt-get install openvswitch-switch corosync-qnetd -y
}

# =====================================
# 初回セットアップ 仮想スイッチ作成
# =====================================

add_virtual_switches () {
	ovs-vsctl add-br $SETUP_BR_L2
	ovs-vsctl add-br $SETUP_BR_MGMT
	ovs-vsctl add-br $SETUP_BR_INET
}

# =====================================
# ネットワークインターフェース設定
# =====================================

write_usr_local_bin_add_ovs_switch_sh () {
	cat <<-EOF > /usr/local/bin/add-ovs-switch.sh
		#!/bin/bash
		set -euo pipefail

		BR_L2=$SETUP_BR_L2
		BR_MGMT=$SETUP_BR_MGMT
		BR_INET=$SETUP_BR_INET

		PATCH_TO_MGMT=$SETUP_PATCH_TO_MGMT
		PATCH_FROM_MGMT=$SETUP_PATCH_FROM_MGMT
		PATCH_TO_INET=$SETUP_PATCH_TO_INET
		PATCH_FROM_INET=$SETUP_PATCH_FROM_INET
		MGMT_PORT=$SETUP_MGMT_PORT
		INET_PORT=$SETUP_INET_PORT
		MGMT_CIDR=$SETUP_MGMT_CIDR

		MAX_WAIT=$SETUP_MAX_WAIT

		# OVS データベースのソケット準備を待機（最大 10 秒）
		COUNTER=0
		while [ ! -S /var/run/openvswitch/db.sock ]; do
		    if [ \$COUNTER -ge \$MAX_WAIT ]; then
		        echo "Error: OVS database socket not found after \${MAX_WAIT} seconds."
		        exit 1
		    fi
		    sleep 1
		    let COUNTER=COUNTER+1
		done

		# OVS Patch Ports設定
		ovs-vsctl --if-exists del-port \$BR_L2 \$PATCH_TO_MGMT
		ovs-vsctl --if-exists del-port \$BR_MGMT \$PATCH_FROM_MGMT
		ovs-vsctl --if-exists del-port \$BR_L2 \$PATCH_TO_INET
		ovs-vsctl --if-exists del-port \$BR_INET \$PATCH_FROM_INET

		ovs-vsctl add-port \$BR_L2 \$PATCH_TO_MGMT \\
		    -- set interface \$PATCH_TO_MGMT type=patch options:peer=\$PATCH_FROM_MGMT
		ovs-vsctl add-port \$BR_MGMT \$PATCH_FROM_MGMT \\
		    -- set interface \$PATCH_FROM_MGMT type=patch options:peer=\$PATCH_TO_MGMT

		if [ \$? -ne 0 ]; then
		    echo "Abort creating peer ports between L2 and MGMT"
		    exit 1
		fi

		ovs-vsctl add-port \$BR_L2 \$PATCH_TO_INET \\
		    -- set interface \$PATCH_TO_INET type=patch options:peer=\$PATCH_FROM_INET
		ovs-vsctl add-port \$BR_INET \$PATCH_FROM_INET \\
		    -- set interface \$PATCH_FROM_INET type=patch options:peer=\$PATCH_TO_INET

		if [ \$? -ne 0 ]; then
		    echo "Abort creating peer ports between L2 and INET"
		    exit 1
		fi

		# mgmt0 インターフェース設定
		echo "Configuring \$MGMT_PORT..."
		ovs-vsctl --if-exists del-port \$BR_MGMT \$MGMT_PORT
		ovs-vsctl add-port \$BR_MGMT \$MGMT_PORT -- set interface \$MGMT_PORT type=internal
		for i in {1..\$MAX_WAIT}; do
		    if ip link show \$MGMT_PORT > /dev/null 2>&1; then
		        break
		    fi
		    sleep 1
		done
		ip link set \$MGMT_PORT up
		ip addr add \$MGMT_CIDR dev \$MGMT_PORT

		# inet0 インターフェース設定
		echo "Configuring \$INET_PORT..."
		ovs-vsctl --if-exists del-port \$BR_INET \$INET_PORT
		ovs-vsctl add-port \$BR_INET \$INET_PORT -- set interface \$INET_PORT type=internal
		ip link set \$INET_PORT up

		exit 0
	EOF

	chmod +x /usr/local/bin/add-ovs-switch.sh
}

write_etc_systemd_system_add_ovs_switch_service () {
	cat <<-EOF > /etc/systemd/system/add-ovs-switch.service
		[Unit]
		Description=OVS QDevice Configuration
		After=openvswitch-switch.service network-pre.target
		Before=network.target
		Wants=network-pre.target

		[Service]
		Type=oneshot
		ExecStart=/usr/local/bin/add-ovs-switch.sh
		RemainAfterExit=yes

		[Install]
		WantedBy=multi-user.target
	EOF
}

write_etc_netplan_99_custom_yaml () {
	cat <<-EOF > /etc/netplan/99-custom.yaml
		network:
		  version: 2
		  renderer: networkd
		  ethernets:
		    $SETUP_PHYSICAL_PORT:
		      dhcp4: false
		      # 物理リンクを強制的にUPにするための設定
		      critical: true
		    $SETUP_MGMT_PORT:
		      dhcp4: false
		    $SETUP_INET_PORT:
		      dhcp4: true
		      dhcp4-overrides:
		        route-metric: 100  # デフォルトゲートウェイの優先度
		  openvswitch: {}
		  bridges:
		    $SETUP_BR_L2:
		      interfaces: [$SETUP_PHYSICAL_PORT]
		      openvswitch: {}
		    $SETUP_BR_MGMT:
		      interfaces: [$SETUP_MGMT_PORT]
		      openvswitch: {}
		    $SETUP_BR_INET:
		      interfaces: [$SETUP_INET_PORT]
		      openvswitch: {}
	EOF
}

enable_add_ovs_switch_service () {
	systemctl daemon-reload
	systemctl enable add-ovs-switch.service
}

setup_main () {
	echo "Installing packages..."
	install_packages
	echo "Creating virtual switches..."
	add_virtual_switches
	echo "Writing network configuration..."
	write_usr_local_bin_add_ovs_switch_sh
	write_etc_systemd_system_add_ovs_switch_service
	write_etc_netplan_99_custom_yaml
	enable_add_ovs_switch_service
	echo "Setup completed."
	shutdown -r now
}

setup_main "$@"
