''
  #!/bin/sh
  set -eu
  umask 077
  cp /usr/share/ax6000/etc/config/* /etc/config/
  chmod 600 /etc/config/*
  # Preserve accounts created by packages; only replace root's password hash.
  awk 'NR == FNR { hash=$0; next } BEGIN { FS=OFS=":" } $1 == "root" { $2=hash } { print }' \
    /usr/share/ax6000/root-password-hash /etc/shadow > /etc/shadow.ax6000
  chmod 600 /etc/shadow.ax6000
  mv /etc/shadow.ax6000 /etc/shadow
  exit 0
''
