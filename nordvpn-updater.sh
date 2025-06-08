#!/bin/sh

# Source: https://github.com/caleb9/asuswrt-merlin-nordvpn-wg-updater
#
# Use the `install.sh` script to set everything up. Alternatively,
# follow the manual instructions below.
#
# The script depends on `jq` command which is not available by default
# on Asus routers., or download the jq binary manually from
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
# Schedule execution e.g. every two hours and log to
# /var/log/nordvpn-updater.log:
#
#     cru a nordvpn-updater "00 */2 * * * /bin/sh /jffs/scripts/nordvpn-updater.sh wgc5 \
#      > /var/log/nordvpn-updater.log 2>&1"
#
# Add the above line to /jffs/scripts/services-start so it gets
# reapplied after a reboot.


# Bail out on error
set -e

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 wgc_client_instance [country]"
    echo "Examples:"
    echo " $0 wgc5"
    echo " $0 wgc5 Denmark"
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


jq="/opt/usr/bin/jq"
if [ "$#" -gt 1 ]; then
    # Country option specified, find out country code
    country=$2
    country_id=$(curl -s "https://api.nordvpn.com/v1/servers/countries" \
		     | "$jq" -r ".[] | select(.name |match(\"^$country$\";\"i\")) | [.id] | \"\(.[0])\"")
    if [ -z "$country_id" ]; then
	echo "$(date): could not find NordVPN server in $2"
	exit 3
    fi
    # Query NordVPN API for recommended server in selected country
    # (commands adapted from sfiorini/NordVPN-Wireguard)
    curl -s "https://api.nordvpn.com/v1/servers/recommendations?&filters\[servers_technologies\]\[identifier\]=wireguard_udp&filters\[country_id\]=$country_id&limit=1" \
	| "$jq" -r '.[]|.hostname, .station, (.technologies|.[].metadata|.[].value)' \
		> /tmp/Peer.txt
else
    # Query NordVPN API for recommended server (commands adapted from
    # sfiorini/NordVPN-Wireguard)
    curl -s "https://api.nordvpn.com/v1/servers/recommendations?&filters\[servers_technologies\]\[identifier\]=wireguard_udp&limit=1" \
	| "$jq" -r '.[]|.hostname, .station, (.technologies|.[].metadata|.[].value)' \
		> /tmp/Peer.txt
fi

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
