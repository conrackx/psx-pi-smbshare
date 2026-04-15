#!/bin/bash

# Share Wifi with Eth device
#
#
# This script is created to work with Raspbian Stretch
# but it can be used with most of the distributions
# by making few changes.
#
# Make sure you have already installed `dnsmasq`
# Please modify the variables according to your need
# Don't forget to change the name of network interface
# Check them with `ifconfig`

ip_address="192.168.2.1"
netmask="24"
dhcp_range_start="192.168.2.2"
dhcp_range_end="192.168.2.100"
dhcp_time="12h"
eth="eth0"
# Detect if eth exists, fallback to eth0
if ! ip link show "$eth" >/dev/null 2>&1; then
  eth=$(ip -o link show | awk -F': ' '/: e(n|th)[^:]*:/{print $2; exit}')
  eth=${eth:-eth0}
fi
wlan="wlan0"

sudo systemctl start network-online.target &> /dev/null

sudo iptables -F
sudo iptables -t nat -F
sudo iptables -t nat -A POSTROUTING -o $wlan -j MASQUERADE
sudo iptables -A FORWARD -i $wlan -o $eth -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i $eth -o $wlan -j ACCEPT

sudo sh -c "echo 1 > /proc/sys/net/ipv4/ip_forward"

# Use 'ip' instead of deprecated 'ifconfig'
sudo ip addr flush dev $eth
sudo ip addr add $ip_address/$netmask dev $eth
sudo ip link set $eth up

# Remove default route created by dhcpcd
sudo ip route del 0/0 dev $eth &> /dev/null || true

sudo systemctl stop dnsmasq

sudo rm -rf /etc/dnsmasq.d/*

echo -e "interface=$eth\n\
bind-dynamic\n\
server=1.1.1.1\n\
domain-needed\n\
bogus-priv\n\
dhcp-range=$dhcp_range_start,$dhcp_range_end,$dhcp_time" > /etc/dnsmasq.d/custom-dnsmasq.conf

sudo systemctl start dnsmasq