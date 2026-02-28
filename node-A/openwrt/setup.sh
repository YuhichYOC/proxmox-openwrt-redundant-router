#!/bin/sh
set -e

# =====================================
# ノード A : test1wrt1 設定
# =====================================

# 引数 : OpenWrt VM の名前
SETUP_NODENAME="test1wrt1"

# 引数 : Proxmox ノード管理 & クラスターネットワーク
SETUP_MGMT_NET="192.168.82.0/24"
# 引数 : 使用するドメインの名前
SETUP_LAN_DOMAIN_NAME="lan"

# 引数 : VRRP で死活監視を行う宛先の OpenWrt VM の IP アドレス
SETUP_VRRP_PEER_IPV4="192.168.92.3"
# 引数 : VRRP で死活監視を行う宛先の OpenWrt VM の名前
SETUP_VRRP_PEER_HOSTNAME="test1wrt2"

# 引数 : ファイアウォールで VRRP 用として通信を許可するルールの名前
SETUP_VRRP_ALLOW_PEER_RULE_NAME="Allow-VRRP-from-peer"
# 引数 : ファイアウォールで VRRP ネットワーク外から VRRP ネットワークに侵入するパケットを拒否するルールの名前
SETUP_VRRP_DENY_OTHER_RULE_NAME="Drop-other-VRRP"
# 引数 : ファイアウォールで Proxmox 管理ネットワーク外から Proxmox 管理 & クラスターネットワークに侵入するパケットを拒否するルールの名前
SETUP_MGMT_BLOCK_RULE_NAME="Block-to-Proxmox-Management"

. "/etc/init.d/init_interfaces"

# =====================================
# 各種ファイルの配置
# =====================================

wait_for_config_files () {
	local polling_wait_max=60
	local wait_count=0
	until [ -f /etc/config/network -a -f /etc/config/dhcp -a -f /etc/config/firewall ]; do
		[ $wait_count -eq $polling_wait_max ] && { echo "wait_for_config_files::Timeout: Config files not found."; exit 1; }
		sleep 1
		wait_count=$((wait_count + 1))
	done
}

write_etc_config_network () {
	cp /etc/config/network /etc/config/network.org

	init_etc_config_network
}

write_etc_config_dhcp () {
	cp /etc/config/dhcp /etc/config/dhcp.org

	cat <<-EOF > /etc/config/dhcp
		config dnsmasq
		    option domainneeded '1'
		    option boguspriv '1'
		    option filterwin2k '0'
		    option localise_queries '1'
		    option rebind_protection '1'
		    option rebind_localhost '1'
		    option local '/${SETUP_LAN_DOMAIN_NAME}/'
		    option domain '${SETUP_LAN_DOMAIN_NAME}'
		    option expandhosts '1'
		    option nonegcache '0'
		    option cachesize '1000'
		    option authoritative '1'
		    option readethers '1'
		    option leasefile '/tmp/dhcp.leases'
		    option resolvfile '/tmp/resolv.conf.d/resolv.conf.auto'
		    option nonwildcard '1'
		    # 「ローカルサブネットからの問い合わせのみ許可する」設定を OFF
		    option localservice '0'
		    option ednspacket_max '1232'
		    option filter_aaaa '0'
		    option filter_a '0'
		    list interface 'lan'
		    list notinterface 'vrrp'
		    list notinterface 'wan'
		    list notinterface 'wan6'

		config dhcp 'lan'
		    option interface 'lan'
		    option start '100'
		    option limit '150'
		    option leasetime '12h'
		    option dhcpv4 'server'
		    option dhcpv6 'server'
		    option ra 'server'
		    option ra_slaac '1'
		    list ra_flags 'managed-config'
		    list ra_flags 'other-config'
		    list dhcp_option '3,${SETUP_VIRTUAL_ROUTER_IPV4}'
		    list dhcp_option '6,${SETUP_VIRTUAL_ROUTER_IPV4}'

		config dhcp 'wan'
		    option interface 'wan'
		    option ignore '1'

		config odhcpd 'odhcpd'
		    option maindhcp '0'
		    option leasefile '/tmp/hosts/odhcpd'
		    option leasetrigger '/usr/sbin/odhcpd-update'
		    option loglevel '4'
		    option piofolder '/tmp/odhcpd-piofolder'

		config dhcp 'vrrp'
		    option interface 'vrrp'
		    option ignore '1'
	EOF
}

write_etc_config_firewall () {
	cp /etc/config/firewall /etc/config/firewall.org

	cat <<-EOF > /etc/config/firewall
		config defaults
		    option syn_flood      1
		    option input          REJECT
		    option output         ACCEPT
		    option forward        REJECT
		# Uncomment this line to disable ipv6 rules
		#    option disable_ipv6   1

		config zone
		    option name           lan
		    list   network        'lan'
		    option input          ACCEPT
		    option output         ACCEPT
		    option forward        ACCEPT

		config zone
		    option name           wan
		    list   network        'wan'
		    list   network        'wan6'
		    option input          REJECT
		    option output         ACCEPT
		    option forward        DROP
		    option masq           1
		    option mtu_fix        1

		config zone
		    option name           vrrp
		    list   network        'vrrp'
		    option input          ACCEPT
		    option output         ACCEPT
		    option forward        REJECT

		config forwarding
		    option src            lan
		    option dest           wan

		# We need to accept udp packets on port 68,
		# see https://dev.openwrt.org/ticket/4108
		config rule
		    option name           Allow-DHCP-Renew
		    option src            wan
		    option proto          udp
		    option dest_port      68
		    option target         ACCEPT
		    option family         ipv4

		# Allow IPv4 ping
		config rule
		    option name           Allow-Ping
		    option src            wan
		    option proto          icmp
		    option icmp_type      echo-request
		    option family         ipv4
		    option target         ACCEPT

		config rule
		    option name           Allow-IGMP
		    option src            wan
		    option proto          igmp
		    option family         ipv4
		    option target         ACCEPT

		# Allow DHCPv6 replies
		# see https://github.com/openwrt/openwrt/issues/5066
		config rule
		    option name           Allow-DHCPv6
		    option src            wan
		    option proto          udp
		    option dest_port      546
		    option family         ipv6
		    option target         ACCEPT

		config rule
		    option name           Allow-MLD
		    option src            wan
		    option proto          icmp
		    option src_ip         fe80::/10
		    list icmp_type        '130/0'
		    list icmp_type        '131/0'
		    list icmp_type        '132/0'
		    list icmp_type        '143/0'
		    option family         ipv6
		    option target         ACCEPT

		# Allow essential incoming IPv6 ICMP traffic
		config rule
		    option name           Allow-ICMPv6-Input
		    option src            wan
		    option proto          icmp
		    list icmp_type        echo-request
		    list icmp_type        echo-reply
		    list icmp_type        destination-unreachable
		    list icmp_type        packet-too-big
		    list icmp_type        time-exceeded
		    list icmp_type        bad-header
		    list icmp_type        unknown-header-type
		    list icmp_type        router-solicitation
		    list icmp_type        neighbour-solicitation
		    list icmp_type        router-advertisement
		    list icmp_type        neighbour-advertisement
		    option limit          1000/sec
		    option family         ipv6
		    option target         ACCEPT

		# Allow essential forwarded IPv6 ICMP traffic
		config rule
		    option name           Allow-ICMPv6-Forward
		    option src            wan
		    option dest           *
		    option proto          icmp
		    list icmp_type        echo-request
		    list icmp_type        echo-reply
		    list icmp_type        destination-unreachable
		    list icmp_type        packet-too-big
		    list icmp_type        time-exceeded
		    list icmp_type        bad-header
		    list icmp_type        unknown-header-type
		    option limit          1000/sec
		    option family         ipv6
		    option target         ACCEPT

		config rule
		    option name           Allow-IPSec-ESP
		    option src            wan
		    option dest           lan
		    option proto          esp
		    option target         ACCEPT

		config rule
		    option name           Allow-ISAKMP
		    option src            wan
		    option dest           lan
		    option dest_port      500
		    option proto          udp
		    option target         ACCEPT

		# VRRP ( Accept packets only from $SETUP_VRRP_PEER_HOSTNAME )
		config rule
		    option name           $SETUP_VRRP_ALLOW_PEER_RULE_NAME
		    option src            vrrp
		    option src_ip         '${SETUP_VRRP_PEER_IPV4}'
		    option dest_ip        '224.0.0.18'
		    option proto          '112'
		    option target         ACCEPT

		config rule
		    option name           $SETUP_VRRP_DENY_OTHER_RULE_NAME
		    option src            vrrp
		    option dest_ip        '224.0.0.18'
		    option proto          '112'
		    option target         DROP

		# Proxmox
		config rule
		    option name           $SETUP_MGMT_BLOCK_RULE_NAME
		    option src            lan
		    option dest           wan
		    option dest_ip        '${SETUP_MGMT_NET}'
		    option target         REJECT
	EOF
}

# =====================================
# ネットワークサービスの再起動
# =====================================

reload_network () {
	/etc/init.d/network restart
}

wait_for_nic_up () {
	local polling_wait_max=30
	local wait_count=0
	while ! ping -c 1 -W 2 8.8.8.8 > /dev/null 2>&1; do
		if [ $wait_count -ge $polling_wait_max ]; then
			echo "Network timeout"
			exit 1
		fi
		sleep 2
		wait_count=$((wait_count + 1))
	done
}

# =====================================
# keepalived 設定
# =====================================

install_packages () {
	# OpenWrt 25 以降はパッケージ管理コマンドが opkg → apk へ変更される
	opkg update
	opkg install keepalived iputils-arping tcpdump
}

write_etc_keepalived_keepalived_conf () {
	cp /etc/keepalived/keepalived.conf /etc/keepalived/keepalived.conf.org

	init_etc_keepalived_keepalived_conf
}

write_etc_keepalived_notify_master_sh () {
	init_etc_keepalived_notify_master_sh
}

write_etc_keepalived_notify_backup_sh () {
	cat <<-EOF > /etc/keepalived/notify-backup.sh
		#!/bin/sh
		logger -t keepalived "$SETUP_NODENAME became BACKUP"
	EOF

	chmod +x /etc/keepalived/notify-backup.sh
}

write_etc_keepalived_notify_fault_sh () {
	cat <<-EOF > /etc/keepalived/notify-fault.sh
		#!/bin/sh
		logger -t keepalived "$SETUP_NODENAME entered FAULT state"
	EOF

	chmod +x /etc/keepalived/notify-fault.sh
}

write_etc_config_keepalived () {
	cp /etc/config/keepalived /etc/config/keepalived.org

	cat <<-EOF > /etc/config/keepalived
		config globals 'globals'
		    option alt_config_file "/etc/keepalived/keepalived.conf"
	EOF
}

# =====================================
# 初回起動設定の解除
# =====================================

edit_etc_rc_local () {
	sed -i '\#setup.sh > /root/setup.log 2>&1#d' /etc/rc.local
}

setup_main() {
	wait_for_config_files
	echo "Creating config files..."
	write_etc_config_network
	write_etc_config_dhcp
	write_etc_config_firewall
	reload_network
	wait_for_nic_up
	echo "Installing packages..."
	install_packages
	echo "Creating files..."
	write_etc_keepalived_keepalived_conf
	write_etc_keepalived_notify_master_sh
	write_etc_keepalived_notify_backup_sh
	write_etc_keepalived_notify_fault_sh
	write_etc_config_keepalived
	edit_etc_rc_local
	echo "Setup completed."
}

setup_main "$@"

# /etc/init.d/init_interfaces の自動実行設定
/etc/init.d/init_interfaces enable

# /root/setup.sh を削除
rm "$0"

reboot
