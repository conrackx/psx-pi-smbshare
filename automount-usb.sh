#!/bin/bash

#
# psx-pi-smbshare automout-usb script
#
# *What it does*
# This script configures raspbian to automount any usb storage to /media/sd<xy>
# This allows for use of USB & HDD in addition to Micro-SD
# It also creates a new Samba configuration which exposes the last attached USB drive @ //SMBSHARE/<PARTITION>

USER=`whoami`

# Update packages
sudo apt-get update

# Install NTFS Read/Write Support and udisks2
sudo apt-get install -y ntfs-3g udisks2

# Add user to disk group
sudo usermod -a -G disk ${USER}

# Create polkit rule
sudo mkdir -p /etc/polkit-1/rules.d/
sudo mkdir -p /etc/polkit-1/localauthority/50-local.d/

# For polkit > 105
sudo cat <<'EOF' | sudo tee /etc/polkit-1/rules.d/10-udisks2.rules
// Allow udisks2 to mount devices without authentication
// for users in the "disk" group.
polkit.addRule(function(action, subject) {
    if ((action.id == "org.freedesktop.udisks2.filesystem-mount-system" ||
         action.id == "org.freedesktop.udisks2.filesystem-mount" ||
         action.id == "org.freedesktop.udisks2.filesystem-mount-other-seat") &&
        subject.isInGroup("disk")) {
        return polkit.Result.YES;
    }
});
EOF

# For polkit <= 105
sudo cat <<'EOF' | sudo tee /etc/polkit-1/localauthority/50-local.d/10-udisks2.pkla
[Authorize mounting of devices for group disk]
Identity=unix-group:disk
Action=org.freedesktop.udisks2.filesystem-mount-system;org.freedesktop.udisks2.filesystem-mount;org.freedesktop.udisks2.filesystem-mount-other-seat
ResultAny=yes
ResultInactive=yes
ResultActive=yes
EOF

# Create udev rule
sudo cat <<'EOF' | sudo tee /etc/udev/rules.d/usbstick.rules
ACTION=="add", KERNEL=="sd[a-z][0-9]", TAG+="systemd", ENV{SYSTEMD_WANTS}="usbstick-handler@%k"
ENV{DEVTYPE}=="usb_device", ACTION=="remove", SUBSYSTEM=="usb", RUN+="/bin/systemctl --no-block restart usbstick-cleanup@%k.service"
EOF

# Configure systemd
sudo cat <<'EOF' | sudo tee /lib/systemd/system/usbstick-handler@.service
[Unit]
Description=Mount USB sticks
BindsTo=dev-%i.device
After=dev-%i.device

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/automount.sh %I
ExecStop=/usr/bin/udisksctl unmount -b /dev/%I
EOF

sudo cat <<'EOF' | sudo tee /lib/systemd/system/usbstick-cleanup@.service
[Unit]
Description=Cleanup USB sticks
BindsTo=dev-%i.device

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/samba-init.sh
EOF

# Configure script to run when an automount event is triggered
sudo cat <<'EOF' | sudo tee /usr/local/bin/automount.sh
#!/bin/bash

PART=$1
UUID=`blkid /dev/${PART} -o value -s UUID`
FS_LABEL=`lsblk -o name,label | grep ${PART} | awk '{print $2}'`

if [ -z ${PART} ]
then
    exit
fi

runuser userplaceholder -s /bin/bash -c "udisksctl mount -b /dev/${PART} --no-user-interaction"

if [ -f /usr/local/bin/ps3netsrv++ ]; then
    pkill ps3netsrv++
    /usr/local/bin/ps3netsrv++ -d /media/userplaceholder/$UUID
fi

# Create a new smb share for the mounted drive
sudo tee /etc/samba/smb.conf >/dev/null <<EOS
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
  comment = PSX USB SMB Share
  path = /media/userplaceholder/\$UUID
  browsable = yes
  read only = no
  guest ok = yes
  create mask = 0777
  directory mask = 0777
  public = yes
  force user = root
  follow symlinks = yes
  wide links = yes
EOS

# Restart services
if systemctl list-unit-files | grep -q '^smbd'; then
  sudo systemctl restart smbd nmbd || true
else
  sudo service smbd restart || true
  sudo service nmbd restart || true
fi
EOF

sudo sed -i "s/userplaceholder/${USER}/g" /usr/local/bin/automount.sh

# Make script executable
sudo chmod +x /usr/local/bin/automount.sh

# Reload udev rules and triggers
sudo udevadm control --reload-rules && sudo udevadm trigger
