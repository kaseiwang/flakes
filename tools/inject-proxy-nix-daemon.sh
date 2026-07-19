#!/usr/bin/env bash
set -euo pipefail

unit="${UNIT:-nix-daemon.service}"
dropin_name="${DROPIN_NAME:-10-proxy.conf}"
proxy_url="${1:-socks5h://10.10.2.1:1080}"
no_proxy="${NO_PROXY_VALUE:-localhost,127.0.0.1,::1}"

tmpfile="$(mktemp)"
cleanup() {
  rm -f "$tmpfile"
}
trap cleanup EXIT

cat >"$tmpfile" <<EOF
[Service]
Environment="http_proxy=${proxy_url}"
Environment="https_proxy=${proxy_url}"
Environment="all_proxy=${proxy_url}"
Environment="HTTP_PROXY=${proxy_url}"
Environment="HTTPS_PROXY=${proxy_url}"
Environment="ALL_PROXY=${proxy_url}"
Environment="NO_PROXY=${no_proxy}"
EOF

apply_dropin() {
  systemctl edit --runtime --drop-in="$dropin_name" --stdin "$unit" <"$tmpfile"
  systemctl daemon-reload
  systemctl restart "$unit"
  systemctl show "$unit" --property=ActiveState,SubState,Environment
}

if [[ "${EUID}" -eq 0 ]]; then
  apply_dropin
else
  sudo sh -c '
    set -e
    systemctl edit --runtime --drop-in="$1" --stdin "$2" <"$3"
    systemctl daemon-reload
    systemctl restart "$2"
    systemctl show "$2" --property=ActiveState,SubState,Environment
  ' sh "$dropin_name" "$unit" "$tmpfile"
fi
