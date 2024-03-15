#!/bin/sh

# Source: https://github.com/caleb9/asuswrt-merlin-nordvpn-wg-updater
#
# Uninstalation script for nordvpn-updater.sh

# Bail out on error
set -e

# Colors
col_n="\033[0m"
col_r="\033[0;31m"
col_g="\033[0;32m"
col_y="\033[0;33m"

echo -e "${col_r}This will completely remove nordvpn-updater from the router!${col_n}"
printf "Are you sure? [y/N]: "
read -r confirm
confirm=$(echo "$confirm" | xargs)
case "$confirm" in
    "y" | "Y")
	echo "removing execution schedule from crontab"
	sed -i '/nordvpn-updater/d' /var/spool/cron/crontabs/"$USER"
	echo "removing execution schedule from /jffs/scripts/services-start"
	sed -i '/nordvpn-updater/d' /jffs/scripts/services-start
	echo "removing files"
	rm -rfv /jffs/scripts/nordvpn-updater.sh
	rm -rfv /opt/usr/bin
	rm -rfv /var/log/nordvpn-updater*.log
	echo -e "${col_g}Done${col_n}"
	echo
	echo "Note that any WireGuard client instances configured by the script are left untouched."
	echo "You can reset an instance completely by first disabling in in the web UI"
	echo "(VPN -> VPN Client -> Wireguard) and then executing the following command"
	echo "(replace \"wgc2\" with the client instance you wish to clean up, exercise care!):"
	echo
	echo "    for v in \$(nvram show | grep wgc2_ | cut -f1 -d=); do nvram unset \$v; done"
	echo
	;;
    *)
	echo -e "${col_y}Cancelled${col_n}"
	exit 0
	;;
esac
