{
  # Declarative UCI configuration. Secret placeholders are resolved outside Nix.
  "etc/config/network" = ''
    config interface 'loopback'
      option device 'lo'
      option proto 'static'
      option ipaddr '127.0.0.1'
      option netmask '255.0.0.0'

    config globals 'globals'
      option packet_steering '1'
      option steering_flows '128'
      option dhcp_default_duid '00046b499ef1109444569aa75f35ad4d20e4'

    config device
      option name 'br-lan'
      option macaddr '4c:c6:4c:bd:41:bd'
      option type 'bridge'
      list ports 'lan2'
      list ports 'lan3'
      list ports 'lan4'
      option multicast '1'

    config interface 'lan'
      option device 'br-lan'
      option proto 'dhcp'
      option multipath 'off'
      option delegate '0'

    config device
      option name 'wan'
      option macaddr '4c:c6:4c:2c:17:84'

    config interface 'wan'
      option device 'wan'
      option proto 'pppoe'
      option username '990007260723'
      option password '@SECRET:pppoe_password@'
      option ipv6 'auto'
      option peerdns '0'
      list dns '223.5.5.5'
      list dns '223.6.6.6'

    config interface 'wan6'
      option device 'wan'
      option proto 'dhcpv6'

    config interface 'lan6'
      option proto 'dhcpv6'
      option device 'br-lan'
      option reqaddress 'try'
      option reqprefix 'auto'
      option norelease '1'
      option multipath 'off'
  '';

  "etc/config/wireless" = ''
    config wifi-device 'radio0'
      option type 'mac80211'
      option path 'platform/soc/18000000.wifi'
      option band '2g'
      option channel '1'
      option htmode 'HT20'
      option cell_density '0'
      option country 'CN'

    config wifi-iface 'default_radio0'
      option device 'radio0'
      option network 'lan'
      option mode 'ap'
      option ssid 'kaseinet2'
      option encryption 'psk-mixed'
      option key '@SECRET:wifi_password_0@'

    config wifi-device 'radio1'
      option type 'mac80211'
      option path 'platform/soc/18000000.wifi+1'
      option band '5g'
      option channel 'auto'
      option htmode 'HE160'
      option country 'CN'
      option cell_density '0'

    config wifi-iface 'default_radio1'
      option device 'radio1'
      option network 'lan'
      option mode 'ap'
      option ssid 'kaseinet'
      option encryption 'sae-mixed'
      option key '@SECRET:wifi_password_1@'
      option ocv '0'
  '';

  "etc/config/dhcp" = ''
    config dnsmasq
      option domainneeded '1'
      option localise_queries '1'
      option rebind_protection '1'
      option rebind_localhost '1'
      option local '/lan/'
      option domain 'lan'
      option expandhosts '1'
      option cachesize '1000'
      option readethers '1'
      option leasefile '/tmp/dhcp.leases'
      option resolvfile '/tmp/resolv.conf.d/resolv.conf.auto'
      option localservice '1'
      option ednspacket_max '1232'
      option port '0'

    config dhcp 'lan'
      option interface 'lan'
      option start '100'
      option limit '150'
      option leasetime '12h'
      option dhcpv4 'server'
      option ignore '1'
      option dynamicdhcp '0'

    config dhcp 'wan'
      option interface 'wan'
      option ignore '1'

    config odhcpd 'odhcpd'
      option maindhcp '0'
      option leasefile '/tmp/odhcpd.leases'
      option leasetrigger '/usr/sbin/odhcpd-update'
      option loglevel '4'
      option piodir '/tmp/odhcpd-piodir'
      option hostsdir '/tmp/hosts'
  '';

  "etc/config/firewall" = ''
    config defaults
      option syn_flood '1'
      option input 'REJECT'
      option output 'ACCEPT'
      option forward 'REJECT'

    config zone
      option name 'lan'
      list network 'lan'
      option input 'ACCEPT'
      option output 'ACCEPT'
      option forward 'ACCEPT'

    config zone
      option name 'wan'
      list network 'wan'
      list network 'wan6'
      option input 'REJECT'
      option output 'ACCEPT'
      option forward 'REJECT'
      option masq '1'
      option mtu_fix '1'

    config forwarding
      option src 'lan'
      option dest 'wan'

    config rule
      option name 'Allow-DHCP-Renew'
      option src 'wan'
      option proto 'udp'
      option dest_port '68'
      option target 'ACCEPT'
      option family 'ipv4'

    config rule
      option name 'Allow-Ping'
      option src 'wan'
      option proto 'icmp'
      option icmp_type 'echo-request'
      option family 'ipv4'
      option target 'ACCEPT'

    config rule
      option name 'Allow-IGMP'
      option src 'wan'
      option proto 'igmp'
      option family 'ipv4'
      option target 'ACCEPT'

    config rule
      option name 'Allow-DHCPv6'
      option src 'wan'
      option proto 'udp'
      option dest_port '546'
      option family 'ipv6'
      option target 'ACCEPT'

    config rule
      option name 'Allow-MLD'
      option src 'wan'
      option proto 'icmp'
      option src_ip 'fe80::/10'
      list icmp_type '130/0'
      list icmp_type '131/0'
      list icmp_type '132/0'
      list icmp_type '143/0'
      option family 'ipv6'
      option target 'ACCEPT'

    config rule
      option name 'Allow-ICMPv6-Input'
      option src 'wan'
      option proto 'icmp'
      list icmp_type 'echo-request'
      list icmp_type 'echo-reply'
      list icmp_type 'destination-unreachable'
      list icmp_type 'packet-too-big'
      list icmp_type 'time-exceeded'
      list icmp_type 'bad-header'
      list icmp_type 'unknown-header-type'
      list icmp_type 'router-solicitation'
      list icmp_type 'neighbour-solicitation'
      list icmp_type 'router-advertisement'
      list icmp_type 'neighbour-advertisement'
      option limit '1000/sec'
      option family 'ipv6'
      option target 'ACCEPT'

    config rule
      option name 'Allow-ICMPv6-Forward'
      option src 'wan'
      option dest '*'
      option proto 'icmp'
      list icmp_type 'echo-request'
      list icmp_type 'echo-reply'
      list icmp_type 'destination-unreachable'
      list icmp_type 'packet-too-big'
      list icmp_type 'time-exceeded'
      list icmp_type 'bad-header'
      list icmp_type 'unknown-header-type'
      option limit '1000/sec'
      option family 'ipv6'
      option target 'ACCEPT'

    config rule
      option name 'Allow-IPSec-ESP'
      option src 'wan'
      option dest 'lan'
      option proto 'esp'
      option target 'ACCEPT'

    config rule
      option name 'Allow-ISAKMP'
      option src 'wan'
      option dest 'lan'
      option dest_port '500'
      option proto 'udp'
      option target 'ACCEPT'

    config rule
      option src 'wan'
      option dest 'lan'
      option name 'ssh'
      option dest_port '22'
      option target 'ACCEPT'

    config rule
      option src 'wan'
      option dest 'lan'
      option name 'htps'
      option dest_port '443'
      option target 'ACCEPT'

    config rule
      option src 'wan'
      option dest 'lan'
      option name 'bt'
      option dest_port '12526'
      option target 'ACCEPT'
  '';

  "etc/config/dropbear" = ''
    # See https://openwrt.org/docs/guide-user/base-system/dropbear
    config dropbear main
      option enable '1'
      option PasswordAuth 'on'
      option RootPasswordAuth 'on'
      option Port         '22'
    #  option BannerFile   '/etc/banner'
  '';

  "etc/config/system" = ''
    config system
      option hostname 'OpenWrt'
      option timezone 'UTC'
      option ttylogin '0'
      option log_size '128'
      option urandom_seed '0'
      option compat_version '1.0'

    config timeserver 'ntp'
      option enabled '1'
      option enable_server '0'
      list server '0.openwrt.pool.ntp.org'
      list server '1.openwrt.pool.ntp.org'
      list server '2.openwrt.pool.ntp.org'
      list server '3.openwrt.pool.ntp.org'

    config led 'led_wan'
      option name 'wan'
      option sysfs 'rgb:network'
      option trigger 'netdev'
      option mode 'link tx rx'
      option dev 'wan'
  '';

  "etc/config/uhttpd" = ''
    config uhttpd 'main'
      list listen_http '0.0.0.0:80'
      list listen_http '[::]:80'
      list listen_https '0.0.0.0:443'
      list listen_https '[::]:443'
      option redirect_https '0'
      option home '/www'
      option rfc1918_filter '1'
      option max_requests '3'
      option max_connections '100'
      option cert '/etc/uhttpd.crt'
      option key '/etc/uhttpd.key'
      option cgi_prefix '/cgi-bin'
      list lua_prefix '/cgi-bin/luci=/usr/lib/lua/luci/sgi/uhttpd.lua'
      option script_timeout '60'
      option network_timeout '30'
      option http_keepalive '20'
      option tcp_keepalive '1'
      option ubus_prefix '/ubus'
      list ucode_prefix '/cgi-bin/luci=/usr/share/ucode/luci/uhttpd.uc'

    config cert 'defaults'
      option days '397'
      option key_type 'ec'
      option bits '2048'
      option ec_curve 'P-256'
      option country 'ZZ'
      option state 'Somewhere'
      option location 'Unknown'
      option commonname 'OpenWrt'
  '';

  "etc/config/luci" = ''
    config core 'main'
      option lang 'auto'
      option mediaurlbase '/luci-static/bootstrap'
      option resourcebase '/luci-static/resources'
      option ubuspath '/ubus/'

    config extern 'flash_keep'
      option uci '/etc/config/'
      option dropbear '/etc/dropbear/'
      option openvpn '/etc/openvpn/'
      option passwd '/etc/passwd'
      option opkg '/etc/opkg.conf'
      option firewall '/etc/firewall.user'
      option uploads '/lib/uci/upload/'

    config internal 'languages'

    config internal 'sauth'
      option sessionpath '/tmp/luci-sessions'
      option sessiontime '3600'

    config internal 'ccache'
      option enable '1'

    config internal 'themes'
      option Bootstrap '/luci-static/bootstrap'
      option BootstrapDark '/luci-static/bootstrap-dark'
      option BootstrapLight '/luci-static/bootstrap-light'

    config internal 'apply'
      option rollback '90'
      option holdoff '4'
      option timeout '5'
      option display '1.5'

    config internal 'diag'
      option dns 'openwrt.org'
      option ping 'openwrt.org'
      option route 'openwrt.org'
  '';

  "etc/config/rpcd" = ''
    config rpcd
      option socket /var/run/ubus/ubus.sock
      option timeout 30

    config login
      option username 'root'
      option password '$p$root'
      list read '*'
      list write '*'
  '';

  "etc/config/prometheus-node-exporter-lua" = ''
    config prometheus-node-exporter-lua 'main'
      option listen_interface 'loopback'
      option listen_port '9100'
      #option cert '/etc/uhttpd.crt'
      #option key '/etc/uhttpd.key'
  '';

}
