#!/bin/bash

#
# psx-pi-smbshare setup script
#
# *What it does*
# This script will install and configure an smb share at /share
# It will also compile ps3netsrv from source to allow operability with PS3/Multiman
# It also configures the pi ethernet port to act as dhcp server for connected devices and allows those connections to route through wifi on wlan0
# Finally, XLink Kai is installed for online play.
#
# *More about the network configuration*
# This configuration provides an ethernet connected PS2 or PS3 a low-latency connection to the smb share running on the raspberry pi
# The configuration also allows for outbound access from the PS2 or PS3 if wifi is configured on the pi
# This setup should work fine out the box with OPL and multiman
# Per default configuration, the smbserver is accessible on 192.168.2.1


USER=`whoami`

# Make sure we're not root otherwise the paths will be wrong
if [ $USER = "root" ]; then
  echo "Do not run this script as root or with sudo"
  exit 1
fi

# Argument parsing
MINIMAL=false
for arg in "$@"; do
  case $arg in
    --minimal|-y)
      MINIMAL=true
      shift
      ;;
  esac
done

# Detect ethernet interface
detect_eth_iface() {
  iface=$(ip -o link show | awk -F': ' '/: e(n|th)[^:]*:/{print $2; exit}')
  if [ -z "$iface" ]; then
    iface=$(ip -o link show | awk -F': ' '!/lo|wl/ {print $2; exit}')
  fi
  echo "${iface:-eth0}"
}

ETH_IFACE="$(detect_eth_iface)"
echo "Detected Ethernet interface: $ETH_IFACE"

if [ "$MINIMAL" = true ]; then
  echo "Running in minimal mode (non-interactive)..."
  PS3NETSRV=false
  XLINKKAI=false
  WIFIACCESSPOINT=false
  ETHROUTE=false
else
  if whiptail --yesno "Would you like to enable ps3netsrv for PS3 support? (SMB is enabled either way for PS2 support etc.)" 8 55; then
    PS3NETSRV=true
  else
    PS3NETSRV=false
  fi

  if whiptail --yesno "Would you like to enable XLink Kai?" 8 55; then
    XLINKKAI=true
  else
    XLINKKAI=false
  fi

  if whiptail --yesno "Would you like to enable wifi access point for a direct wifi connection?" 8 55; then
    WIFIACCESSPOINT=true
  else
    WIFIACCESSPOINT=false
  fi

  if whiptail --yesno "Would you like to share wifi over ethernet, for devices without wifi? (Ethernet will no longer work for providing the pi an internet connection)" 9 55; then
    ETHROUTE=true
  else
    ETHROUTE=false
  fi
fi

# Update packages
sudo apt-get -y update
sudo apt-get -y upgrade

# Ensure basic tools are present
sudo apt-get -y install screen wget git curl coreutils iptables hostapd

# Install and configure Samba
sudo apt-get install -y samba samba-common-bin
cp samba-init.sh /home/${USER}/samba-init.sh
sed -i "s/userplaceholder/${USER}/g" /home/${USER}/samba-init.sh
chmod 755 /home/${USER}/samba-init.sh
sudo cp /home/${USER}/samba-init.sh /usr/local/bin
sudo mkdir -p /share
sudo chmod 1777 /share

# Install ps3netsrv if PS3NETSRV is true
if [ "$PS3NETSRV" = true ]; then
  sudo rm /usr/local/bin/ps3netsrv++
  sudo apt-get install -y git gcc
  git clone https://github.com/dirkvdb/ps3netsrv--.git
  cd ps3netsrv--
  git submodule update --init
  make CXX=g++
  sudo cp ps3netsrv++ /usr/local/bin
  cd ..
fi

if [ "$ETHROUTE" = true ]; then
  # Install wifi-to-eth route settings
  sudo apt-get install -y dnsmasq
  cp wifi-to-eth-route.sh /home/${USER}/wifi-to-eth-route.sh
else
  touch /home/${USER}/wifi-to-eth-route.sh
fi
chmod 755 /home/${USER}/wifi-to-eth-route.sh

if [ "$WIFIACCESSPOINT" = true ]; then
  # Install setup-wifi-access-point settings
  sudo apt-get install -y hostapd bridge-utils
  cp setup-wifi-access-point.sh /home/${USER}/setup-wifi-access-point.sh
else
  touch /home/${USER}/setup-wifi-access-point.sh
fi
chmod 755 /home/${USER}/setup-wifi-access-point.sh

# Install XLink Kai if XLINKKAI is true
if [ "$XLINKKAI" = true ]; then

# Remove old XLink Kai Repo if present
sudo rm -rf /etc/apt/sources.list.d/teamxlink.list

# Set up teamxlink repository and install XLink Kai

sudo apt-get install -y ca-certificates curl gnupg
sudo mkdir -m 0755 -p /etc/apt/keyrings
sudo rm /etc/apt/keyrings/teamxlink.gpg
curl -fsSL https://dist.teamxlink.co.uk/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/teamxlink.gpg
sudo chmod a+r /etc/apt/keyrings/teamxlink.gpg
echo  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/teamxlink.gpg] https://dist.teamxlink.co.uk/linux/debian/static/deb/release/ /" | sudo tee /etc/apt/sources.list.d/teamxlink.list > /dev/null
sudo apt-get update
sudo apt-get install -y xlinkkai

# Write XLink Kai launch script
cat <<'EOF' > /home/${USER}/launchkai.sh
echo "Checking for XLink Kai updates"
sudo apt-get install xlinkkai -y
echo "Launching XLink Kai"
while true; do
    screen -dmS kai kaiengine
    sleep 5
done
EOF
else
touch /home/${USER}/launchkai.sh

#End of XLink Kai install
fi
chmod 755 /home/${USER}/launchkai.sh

# Create and apply firewall rules for SMB security
echo "Creating psx-smb-firewall script..."
sudo tee /usr/local/bin/psx-smb-firewall.sh >/dev/null <<'EOF'
#!/bin/bash
set -euo pipefail
IP_NET="192.168.2.0/24"
# Accept SMB from LAN
sudo iptables -C INPUT -p tcp -s $IP_NET --dport 445 -j ACCEPT 2>/dev/null || sudo iptables -I INPUT -p tcp -s $IP_NET --dport 445 -j ACCEPT
sudo iptables -C INPUT -p tcp -s $IP_NET --dport 137:139 -j ACCEPT 2>/dev/null || sudo iptables -I INPUT -p tcp -s $IP_NET --dport 137:139 -j ACCEPT
# Block SMB from elsewhere
sudo iptables -C INPUT -p tcp --dport 445 -j DROP 2>/dev/null || sudo iptables -A INPUT -p tcp --dport 445 -j DROP
sudo iptables -C INPUT -p tcp --dport 137:139 -j DROP 2>/dev/null || sudo iptables -A INPUT -p tcp --dport 137:139 -j DROP
EOF
sudo chmod 750 /usr/local/bin/psx-smb-firewall.sh
sudo /usr/local/bin/psx-smb-firewall.sh || true

# Install USB automount settings
cp automount-usb.sh /home/${USER}/automount-usb.sh
chmod 755 /home/${USER}/automount-usb.sh
/home/${USER}/automount-usb.sh

# Set up systemd services to replace crontab
echo "Configuring systemd services..."

# 1. psx-eth-ip.service: Static IP persistence
sudo tee /etc/systemd/system/psx-eth-ip.service >/dev/null <<EOF
[Unit]
Description=Assign static IP for PSX SMB share on $ETH_IFACE
After=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c '/sbin/ip addr add 192.168.2.1/24 dev $ETH_IFACE 2>/dev/null || true'
ExecStart=/bin/sh -c '/sbin/ip link set $ETH_IFACE up 2>/dev/null || true'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# 2. psx-samba-init.service: Run samba-init.sh
sudo tee /etc/systemd/system/psx-samba-init.service >/dev/null <<EOF
[Unit]
Description=PSX Pi SMB Share Initialization
After=network.target psx-eth-ip.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/samba-init.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# 3. psx-route.service: WiFi to Eth routing and AP
sudo tee /etc/systemd/system/psx-route.service >/dev/null <<EOF
[Unit]
Description=PSX Pi Networking (Route and AP)
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash /home/${USER}/wifi-to-eth-route.sh
ExecStartPost=/bin/bash /home/${USER}/setup-wifi-access-point.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# 4. psx-xlink.service: XLink Kai
sudo tee /etc/systemd/system/psx-xlink.service >/dev/null <<EOF
[Unit]
Description=XLink Kai Engine
After=network.target

[Service]
Type=simple
User=${USER}
ExecStart=/bin/bash /home/${USER}/launchkai.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Enable services
sudo systemctl daemon-reload
sudo systemctl enable psx-eth-ip.service psx-samba-init.service psx-route.service
if [ "$XLINKKAI" = true ]; then
  sudo systemctl enable psx-xlink.service
fi

# Cleanup old crontab entries if they exist
crontab -u ${USER} -l 2>/dev/null | grep -v "@reboot" | crontab -u ${USER} - || true

echo "Setup complete. Systemd services have been configured and enabled."

# Not a bad idea to reboot
if [ "$MINIMAL" = false ]; then
  if whiptail --yesno "Setup finished. A reboot is required to apply changes. Reboot now?" 8 45; then
    sudo reboot
  fi
else
  echo "Rebooting in 5 seconds..."
  sleep 5
  sudo reboot
fi
