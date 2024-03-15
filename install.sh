#!/bin/sh

# https://github.com/caleb9/asuswrt-merlin-nordvpn-wg-updater
#
# Installation script for nordvpn-updater.sh


# Bail out on error
set -e

# Colors
col_n="\033[0m"
col_r="\033[0;31m"
col_g="\033[0;32m"
col_y="\033[0;33m"

fail() {
    echo
    echo -e "${col_r}Installation failed${col_n}"
    exit 1
}

# Check Asuswrt-Merlin version
buildno=$(nvram get buildno)
printf "Asuswrt-Merlin version: "
if [ "$(echo "$buildno" | cut -f1 -d.)" -lt 388 ]; then
    echo -e "${col_r}${buildno}${col_n}"
    echo "Minimum supported version is 388, please upgrade your firmware on router's \
Administration / Firmware Upgrade page"
    fail
else
    echo -e "${col_g}${buildno}${col_n}"
fi

# Check if user-scripts are enabled
jffs_enabled=$(nvram get jffs2_scripts)
printf "JFFS partition: "
if [ "$jffs_enabled" != "1" ]; then
    echo -e "${col_r}disabled${col_n}"
    echo "Enable JFFS partition on router's Administration -> System page, and re-run the script."
    fail
fi
echo -e "${col_g}enabled${col_n}"


# Check architecture and map it to jq naming convention
jq_dir="/opt/usr/bin"
jq_file="${jq_dir}/jq"
arch=$(uname -m)
printf "Router architecture: "
case "$arch" in
    "aarch64")
	echo -e "${col_g}${arch}${col_n}"
	arch="arm64"
	;;
    "armv7l")
	echo -e "${col_g}${arch}${col_n}"
	arch="armel"
	;;
    *)
	if ! [ -f "$jq_file" ]; then
	    # Bail out of downloading jq automatically and offer manual setup :(
	    echo -e "${col_r}${arch}${col_n}"
	    echo
	    echo "I cannot guess the 'jq' binary for $arch."
	    echo "Try finding the 'jq-linux-{arch}' file manually on "
	    echo "    https://github.com/jqlang/jq/releases"
	    echo "and execute the following:"
	    echo
	    echo "    mkdir -p /opt/usr/bin"
	    echo "    wget -O $jq_file \
https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-{correct arch suffix}"
	    echo "    chmod +x $jq_file"
	    echo
	    echo "Confirm jq works with 'jq --version' and re-run the script."
	    echo
	    echo -e "${col_y}Please create an issue on"
	    echo -e "    https://github.com/caleb9/asuswrt-merlin-nordvpn-wg-updater/issues${col_n}"
	    fail
	else
	    echo -e "$jq_file: ${col_y}installed manually${col_n}"
	fi
esac

echo

# Find existing WireGuard NordVPN clients
nordvpn_addr_regex="^wgc[[:digit:]]+_ep_addr=[[:alnum:]]+\.nordvpn\.com$"
nordvpn_wgc_addrs=$(nvram show 2>/dev/null | grep -E "$nordvpn_addr_regex")

# Print list of enabled clients
echo "Enabled WireGuard NordVPN clients:"
client_count=0
clients=""
for addr in $nordvpn_wgc_addrs; do
    client=$(echo "$addr" | cut -f1 -d_)
    server=$(echo "$addr" | cut -f2 -d=)
    is_enabled=$(nvram get "${client}"_enable)
    if [ "$is_enabled" != "1" ]; then
	continue
    fi
    client_count=$((client_count+1))
    clients="$clients $client"
    echo "[$client_count] $client ($server)"
done
clients=$(echo "$clients" | xargs)

if [ $client_count -lt 1 ]; then
    echo "No enabled WireGuard NordVPN clients found :(."
    echo "Set up and enable at least one client in the router's web interface."
    echo "Use the script from"
    echo "    https://github.com/sfiorini/NordVPN-Wireguard"
    echo "to generate an initial WireGuard config file."
    fail
fi

# Let user select the client instance to keep updated
while true; do
    printf "Select client instance for recommended server [1-%s, e: exit]: " "$client_count"
    read -r index
    index=$(echo "$index" | xargs)
    if [ "$index" = "e" ] || [ "$index" = "E" ]; then
	echo "Bye"
	exit 0
    fi

    is_numeric=$(echo "$index" | grep -E "^[0-9]+$")
    if [ -z "$is_numeric" ] || [ "$index" -lt 1 ] || [ "$index" -gt $client_count ]; then
	echo -e "${col_r}Invalid value${col_n}"
    else
	break	
    fi
done
client_instance=$(echo "$clients" | cut -f"$index" -d\ )

# Install jq
if [ -f "$jq_file" ]; then
    echo "'jq' already installed in $jq_dir"
else
    jq_remote_file="jq-linux-$arch"
    jq_url="https://github.com/jqlang/jq/releases/download/jq-1.7.1/$jq_remote_file"
    echo "Downloading $jq_remote_file into $jq_dir"
    mkdir -p -m 755 "$jq_dir"
    wget -qO "$jq_file" "$jq_url"
fi
if ! [ -x "$jq_file" ]; then
    chmod 755 "$jq_file"
fi

# Install nordvpn-updater.sh
echo "Downloading nordvpn-updater.sh to /jffs/scripts"
wget -qO /jffs/scripts/nordvpn-updater.sh \
     https://raw.githubusercontent.com/caleb9/asuswrt-merlin-nordvpn-wg-updater/main/nordvpn-updater.sh
chmod 755 /jffs/scripts/nordvpn-updater.sh

# Schedule execution
schedule="00 */2 * * *"
log_file="/var/log/nordvpn-updater-${client_instance}.log"
job_id="nordvpn-updater-$client_instance"
cru="cru a $job_id "
while true; do
    printf "Schedule setting %s to recommended server every two-hours? " "$client_instance"
    printf "[Y/n, c: custom-schedule]: "
    read -r update_crontab
    case $(echo "$update_crontab" | xargs) in
	"" | "y" | "Y")
	    break
	    ;;
	"n" | "N")
	    cru=""
	    break
	    ;;
	"c" | "C")
	    printf "Enter custom cron schedule (note: input not validated) "
	    printf "[default: %s]: " "$schedule"
	    read -r schedule_custom
	    schedule_custom=$(echo "$schedule_custom" | xargs)
	    if [ "$schedule_custom" != "" ]; then
		schedule="$schedule_custom"
	    fi
	    break
	    ;;
	*)
	    echo -e "${col_r}Invalid value${col_n}"
	    ;;
    esac
done

sed -i "/$job_id/d" /jffs/scripts/services-start # Remove any old entries
if [ "$cru" != "" ]; then
    command="/bin/sh /jffs/scripts/nordvpn-updater.sh $client_instance > $log_file 2>&1"
    cru="$cru \"$schedule $command\""
    echo "Adding schedule to crontab"
    eval "$cru"
    echo "Saving schedule in /jffs/scripts/services-start"
    echo "$cru" >> /jffs/scripts/services-start
    echo "Last execution output log file: $log_file"
else
    echo -e "${col_y}nordvpn-updater.sh will NOT execute automatically${col_n}"
fi

# Initial run
printf "Do you wish to run nordvpn-updater.sh now? [Y/n]: "
read -r run_now
case $(echo "$run_now" | xargs) in
    "" | "y" | "Y")
	sh /jffs/scripts/nordvpn-updater.sh "$client_instance"
	;;
    *)
	;;
esac

echo
echo -e "${col_g}Installation completed${col_n}"
