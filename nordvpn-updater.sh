#!/bin/sh

# Source: https://github.com/caleb9/asuswrt-merlin-nordvpn-wg-updater
#
# Note: the script depends on `jq` command which is not available by
# default on Asus routers. Download the binary from
# https://github.com/jqlang/jq/releases, rename to `jq`, execute
# `chmod +x jq`, and put it in /opt/usr/bin
#
# The script assumes that NordVPN wireguard client has already been
# set up and enabled on the router. Use
# https://github.com/sfiorini/NordVPN-Wireguard script to obtain
# initial wireguard configuration config.
#
# Put the script in /jffs/scripts/ folder and set its executable flag:
#
#     chmod a+rx /jffs/scripts/*
#
# Schedule execution e.g. every hour and log to
# /var/log/nordvpn-updater.log:
#
#     cru a nordvpn-updater "00 * * * * /bin/sh /jffs/scripts/nordvpn-updater.sh wgc5  > /var/log/nordvpn-updater.log 2>&1"
#
# Add the above line to /jffs/scripts/services-start so it gets
# reapplied after a reboot.


if [ "$#" -ne 1 ]; then
    echo "Usage: $0 wgc_client_instance"
    echo "Example: $0 wgc5"
    exit 1
fi

client=$1

# Only update settings for an enabled client. This avoids dealing with
# private key and other complex settings.
wgc_enabled=$(nvram get "$client"_enable)
if [ -z "$wgc_enabled" ]; then
    echo "$(date): $client is not set up or is disabled"
    exit 2
fi

# Query NordVPN API for recommended server (commands adapted from
# sfiorini/NordVPN-Wireguard)
curl -s "https://api.nordvpn.com/v1/servers/recommendations?&filters\[servers_technologies\]\[identifier\]=wireguard_udp&limit=1" \
    | /opt/usr/bin/jq -r '.[]|.hostname, .station, (.technologies|.[].metadata|.[].value)' \
	 > /tmp/Peer.txt

endpoint=$(grep -m 1 -o '.*' /tmp/Peer.txt | tail -n 1)
address=$(grep -m 2 -o '.*' /tmp/Peer.txt | tail -n 1)
public_key=$(grep -m 3 -o '.*' /tmp/Peer.txt | tail -n 1)

rm /tmp/Peer.txt

server=$(echo "$endpoint" | cut -f 1 -d \.)

echo "$(date): setting $client to $server"

nvram set "$client"_desc="$server (recommended)"
nvram set "$client"_ep_addr="$endpoint"
nvram set "$client"_ep_addr_r="$address"
nvram set "$client"_ppub="$public_key"

wg set "$client" peer "$public_key" endpoint "$endpoint":51820
