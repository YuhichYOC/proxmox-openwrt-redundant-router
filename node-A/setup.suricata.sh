#!/bin/bash
set -euo pipefail

# =====================================
# ノード A : suricata1 設定
# =====================================

# 引数 : Ubuntu コンテナイメージのダウンロード URL
SETUP_UBUNTU_IMAGE_URL="https://images.linuxcontainers.org/images/ubuntu/noble/amd64/default/20260220_07:42/rootfs.tar.xz"
# 引数 : コンテナイメージの保存先ディレクトリ
SETUP_IMAGE_DIRECTORY="/var/lib/vz/template/cache"
# 引数 : 使用する Ubuntu のバージョン
SETUP_UBUNTU_VERSION="24.04"
# セットアップ実行日付 ( YYYYMMDD )
SETUP_DATE=$(date +%Y%m%d)

# 引数 : Suricata コンテナの ID
SETUP_CONTAINER_ID="121"
# 引数 : Suricata コンテナの名前
SETUP_CONTAINER_NAME="suricata1"
# 引数 : Suricata コンテナフックスクリプトの配置場所 ( Proxmox ストレージ形式 )
SETUP_SNIPPET="local:snippets/suricata-hook.sh"
# 引数 : Suricata コンテナフックスクリプトの配置ディレクトリ ( 実際のディレクトリパス )
SETUP_SNIPPET_DIRECTORY="/var/lib/vz/snippets"

# 引数 : 監視対象 WAN 側物理 NIC の名前
SETUP_PHYSICAL_WAN_PORT="ens33"
# 引数 : 監視対象 WAN 側物理 NIC が接続している OVS 仮想ブリッジの名前
SETUP_BR_WAN="br0_wan"
# 引数 : Suricata コンテナが LAN と接続する OVS 仮想ブリッジの名前
SETUP_BR_INET="br5_inet"
# 引数 : パケットスニッフィングのために作成する OVS ミラーの名前
SETUP_MIRROR_NAME="br0_m0"

# =====================================
# イメージダウンロード
# =====================================

download_image () {
	if [ -f /var/lib/vz/template/cache/ubuntu.${SETUP_UBUNTU_VERSION}.${SETUP_DATE}.tar.xz ]; then
		return 0
	fi
	wget -O "/var/lib/vz/template/cache/ubuntu.${SETUP_UBUNTU_VERSION}.${SETUP_DATE}.tar.xz" "${SETUP_UBUNTU_IMAGE_URL}"
}

# =====================================
# コンテナ作成
# =====================================

create_container () {
	shopt -s nullglob
	candidates=("${SETUP_IMAGE_DIRECTORY}/ubuntu.${SETUP_UBUNTU_VERSION}."*.tar.xz)
	local container_image="$(printf '%s\n' "${candidates[@]}" | sort | tail -n 1)"

	# Ubuntu 24.04 などの新しい OS のコンテナを作成する場合、ネスト設定「--features nesting=1」が必要になる
	pct create $SETUP_CONTAINER_ID $container_image --arch amd64 --hostname $SETUP_CONTAINER_NAME \
		--rootfs local-lvm:60 \
		--memory 2048 \
		--swap 2048 \
		--cores 4 \
		--net0 name=eth0,bridge=$SETUP_BR_WAN,firewall=0 \
		--net1 name=lan0,bridge=$SETUP_BR_INET,firewall=0,ip=dhcp \
		--ostype ubuntu \
		--unprivileged 1 \
		--features nesting=1
}

start_suricata_container () {
	pct start $SETUP_CONTAINER_ID
}

push_suricata_setup_script () {
	pct push $SETUP_CONTAINER_ID suricata/setup.sh /root/setup.sh
	pct exec $SETUP_CONTAINER_ID -- chmod 744 /root/setup.sh
}

wait_for_nic_up () {
	local polling_wait_max=30
	local wait_count=0
	while [ ! pct exec ${SETUP_CONTAINER_ID} -- ping -c 1 -W 2 8.8.8.8 > /dev/null 2>&1 ]; do
		if [ $wait_count -ge $polling_wait_max ]; then
			echo "Error: Internet connection timeout"
			exit 1
		fi
		sleep 2
		wait_count=$((wait_count + 1))
	done
}

run_suricata_setup_script () {
	pct exec $SETUP_CONTAINER_ID -- /bin/bash -c "/bin/bash /root/setup.sh > /root/setup.log 2>&1"
}

write_var_lib_vz_snippets_snippets_suricata_hook_sh () {
	local br_wan_port=$(ovs-vsctl list-ports $SETUP_BR_WAN 2>/dev/null) || return 1
	local suricata_port=$(echo "${br_wan_port}" | grep -E "^veth[0-9]{3}[io][0-9]+\$")

	cat <<-EOF > $SETUP_SNIPPET_DIRECTORY/suricata-hook.sh
		#!/bin/bash

		if [ "\$2" == "post-start" ]; then
		    sleep 10
		    ovs-vsctl -- --id=@src get port $SETUP_PHYSICAL_WAN_PORT \\
		        -- --id=@out get port $suricata_port \\
		        -- --id=@mirror create mirror name=$SETUP_MIRROR_NAME select-src-port=@src select-dst-port=@src output-port=@out \\
		        -- set bridge $SETUP_BR_WAN mirrors=@mirror
		fi
	EOF

	chmod +x $SETUP_SNIPPET_DIRECTORY/suricata-hook.sh
}

add_hookscript_into_container () {
	pct set $SETUP_CONTAINER_ID -hookscript $SETUP_SNIPPET
}

reboot_container () {
	pct reboot $SETUP_CONTAINER_ID
}

setup_main () {
	echo "Downloding Ubuntu container image..."
	download_image
	echo "Creating Suricata container..."
	create_container
	start_suricata_container
	push_suricata_setup_script
	wait_for_nic_up
	run_suricata_setup_script
	write_var_lib_vz_snippets_snippets_suricata_hook_sh
	add_hookscript_into_container
	reboot_container
	echo "Setup completed."
}

setup_main "$@"
