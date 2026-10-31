{
  packages = [
    "luci-ssl"
    "luci-proto-ppp"
    "smartdns"
    "prometheus-node-exporter-lua"
    "prometheus-node-exporter-lua-wifi"
    "-sing-box"
  ];
  disabledServices = [
    "dnsmasq"
    "odhcpd"
    "smartdns"
  ];
}
