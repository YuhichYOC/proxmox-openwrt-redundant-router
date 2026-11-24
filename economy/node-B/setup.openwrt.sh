#!/bin/bash
set -euo pipefail

# =====================================
# ノード B : test1wrt2 設定
# =====================================

# 引数 : 使用する OpenWrt のバージョン
SETUP_OPENWRT_VERSION="24.10.5"
# セットアップ実行日付 ( YYYYMMDD )
SETUP_DATE=$(date +%Y%m%d)

# 引数 : OpenWrt VM ID
SETUP_VM_ID="102"
# 引数 : OpenWrt VM の名前
SETUP_VM_NAME="test1wrt2"
# 引数 : OpenWrt フックスクリプトの配置場所
SETUP_SNIPPET="local:snippets/openwrt-hook.sh"
# 引数 : OpenWrt VM が WAN 側と接続する NIC の MAC アドレスと接続する仮想ブリッジの名前
SETUP_OPENWRT_NET_WAN="virtio=02:50:58:00:00:02,bridge=br0_wan"
# 引数 : OpenWrt VM が VRRP で利用する NIC の MAC アドレスと接続する仮想ブリッジの名前
SETUP_OPENWRT_NET_VRRP="virtio=02:50:58:00:04:02,bridge=br4_vrrp"
# 引数 : OpenWrt VM がインターネットアクセス提供用に使用する NIC の MAC アドレスと接続する仮想ブリッジの名前
SETUP_OPENWRT_NET_INET="virtio=02:50:58:00:05:02,bridge=br5_inet"
# 引数 : OpenWrt VM のディスクを配置するストレージ ID
SETUP_DISK_STORAGE_ID="local-lvm"

# =====================================
# 最新ディスクイメージの取得
# =====================================

fetch_latest_diskimage () {
	shopt -s nullglob
	candidates=("/var/lib/vz/template/iso/openwrt.${SETUP_OPENWRT_VERSION}."*-ext4-combined-efi.img)
	echo "$(printf '%s\n' "${candidates[@]}" | sort | tail -n 1)"
}

fetch_temp_diskimage () {
	echo "/var/lib/vz/template/iso/openwrt.${SETUP_OPENWRT_VERSION}.${SETUP_DATE}.latest-ext4-combined-efi.img"
}

calc_start_offset () {
	# fdisk の出力から一番サイズの大きい Linux filesystem ( = xxx-efi.img2 ) の Start ... 33280 を 512 倍した値 = 17039360 を取得
	# 以下は fdisk -l <OpenWrt ディスクイメージファイルパス> の出力例
	# Device                                                                           Start    End Sectors  Size Type
	# /var/lib/vz/template/iso/openwrt-24.10.5-x86-64-generic-ext4-combined-efi.img1     512  33279   32768   16M Linux filesystem
	# /var/lib/vz/template/iso/openwrt-24.10.5-x86-64-generic-ext4-combined-efi.img2   33280 246271  212992  104M Linux filesystem
	# /var/lib/vz/template/iso/openwrt-24.10.5-x86-64-generic-ext4-combined-efi.img128    34    511     478  239K BIOS boot
	local pos=$(fdisk -l $(fetch_temp_diskimage) 2>/dev/null \
		| grep "Linux filesystem" \
		| awk '
			$4 > max_size {
				max_size=$4;
				start_val=$2
			}
			END {print start_val}
		')
	echo $((pos * 512))
}

# =====================================
# ディスクイメージの編集
# =====================================

copy_openwrt_diskimage () {
	# 一日に複数回実施することを考えてディスクイメージのコピーを行う。仮想マシン作成にはコピー先を使用する
	# /etc/rc.local に /root/script.sh キックが複数行書き込まれることを防ぐ
	cp $(fetch_latest_diskimage) $(fetch_temp_diskimage)
}

expand_openwrt_diskimage () {
	# ディスクイメージのサイズを 8 GiB まで拡張する。OpenWrt 側から見えるディスク容量を拡張するには以下の手順を参照
	# https://openwrt.org/docs/guide-user/advanced/expand_root
	qemu-img resize -f raw $(fetch_temp_diskimage) 8G
}

mount_openwrt_diskimage () {
	mkdir /mnt/openwrt
	mount -o loop,offset=$(calc_start_offset) $(fetch_temp_diskimage) /mnt/openwrt
}

put_setup_script_into_diskimage () {
	cp openwrt/init_interfaces /mnt/openwrt/etc/init.d/
	chmod +x /mnt/openwrt/etc/init.d/init_interfaces
	cp openwrt/setup.sh /mnt/openwrt/root/
	chmod +x /mnt/openwrt/root/setup.sh
	sed -i '/exit 0/i /root/setup.sh > /root/setup.log 2>&1' /mnt/openwrt/etc/rc.local
}

unmount_openwrt_diskimage () {
	umount /mnt/openwrt
	rm -r /mnt/openwrt
}

# =====================================
# VM 作成
# =====================================

create_vm () {
	qm create $SETUP_VM_ID \
		--name $SETUP_VM_NAME \
		--cpu host \
		--sockets 1 \
		--cores 4 \
		--memory 1024 \
		--net0 $SETUP_OPENWRT_NET_WAN \
		--net1 $SETUP_OPENWRT_NET_VRRP \
		--net2 $SETUP_OPENWRT_NET_INET \
		--ostype l26 \
		--hookscript $SETUP_SNIPPET

	qm importdisk $SETUP_VM_ID $(fetch_temp_diskimage) $SETUP_DISK_STORAGE_ID
	qm set $SETUP_VM_ID --bios ovmf
	qm set $SETUP_VM_ID --efidisk0 $SETUP_DISK_STORAGE_ID:0
	qm set $SETUP_VM_ID --sata0 $(qm config $SETUP_VM_ID | grep '^unused0:' | awk '{print $2}')
	qm set $SETUP_VM_ID --boot order=sata0
	qm set $SETUP_VM_ID --tablet 0
	qm set $SETUP_VM_ID --serial0 socket
}

start_vm () {
	qm start $SETUP_VM_ID
}

cleanup () {
	rm $(fetch_temp_diskimage)
}

setup_main () {
	echo "Creating OpenWrt container..."
	copy_openwrt_diskimage
	expand_openwrt_diskimage
	mount_openwrt_diskimage
	put_setup_script_into_diskimage
	unmount_openwrt_diskimage
	create_vm
	start_vm
	cleanup
	echo "Setup completed."
}

setup_main "$@"
