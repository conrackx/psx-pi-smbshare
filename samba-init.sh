#!/bin/bash

#If a USB drive is present, do not initialize the samba share
USBDisk_Present=`sudo fdisk -l | grep /dev/sd`
if [ -n "${USBDisk_Present}" ]
then
    echo "exited to due to presence of USB storage"
    exit
fi

#if /usr/local/bin/ps3netsrv++ exists
if [ -f /usr/local/bin/ps3netsrv++ ]; then
  #restart ps3netsrv++
  pkill ps3netsrv++ || true
  /usr/local/bin/ps3netsrv++ -d /share &
fi

sudo tee /etc/samba/smb.conf >/dev/null <<'EOF'
[global]
  server role = standalone server
  server min protocol = NT1
  map to guest = Bad User
  workgroup = WORKGROUP
  security = user
  interfaces = 192.168.2.1/24
  bind interfaces only = Yes
  log file = /var/log/samba/log.%m
  max log size = 1000
  allow insecure wide links = yes

[share]
  comment = PSX SMB Share
  path = /share
  browsable = yes
  read only = no
  guest ok = yes
  create mask = 0777
  directory mask = 0777
  public = yes
  force user = root
  follow symlinks = yes
  wide links = yes
EOF

# Restart services
if systemctl list-unit-files | grep -q '^smbd'; then
  sudo systemctl restart smbd nmbd || true
else
  sudo service smbd restart || true
  sudo service nmbd restart || true
fi
