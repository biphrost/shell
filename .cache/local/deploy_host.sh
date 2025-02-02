#!/bin/bash


# Do not modify this file! This file is automatically generated from the source
# file at /home/rob/Code/biphrost-shell/local/deploy_host.md.
# Modify that file instead.
# source hash: 9e6fce28f74106efe1906e628cdea2ae

# begin-golem-injected-code

# Use any of these as necessary.
# Further reading on "$0" vs "$BASH_SOURCE" &etc.:
# https://stackoverflow.com/a/35006505
# https://stackoverflow.com/a/29835459
# shellcheck disable=SC2034
mypath=$(readlink -m "${BASH_SOURCE[0]}")
# shellcheck disable=SC2034
myname=$(basename "$mypath")
# shellcheck disable=SC2034
mydir=$(dirname "$mypath")
# shellcheck disable=SC2034
myshell=$(readlink /proc/$$/exe)

# Exit with an error if an undefined variable is referenced.
set -u

# If any command in a pipeline fails, that return code will be used as the
# return code for the whole pipeline.
set -o pipefail

# Halt with a non-zero exit status if a TERM signal is received by this PID.
# This is used by the fail() function along with $scriptpid.
trap "exit 1" TERM


##
# Return the filename component of a path; this is identical to calling
# "basename [path]"
#
path_filename () {
    local path=""
    path=$(realpath -s -m "$1")
    echo "${path##*/}"
}


##
# Return the parent directory of a path; this is identical to calling
# "dirname [path]", but it also cleans up extra slashes in the path.
#
path_directory () {
    local filename=""
    filename=$(path_filename "$1")
    realpath -s -m "${1%"$filename"}"
}


##
# Return the basename of the filename component of a path. For example, return
# "my_file" from "/path/to/my_file.txt".
#
path_basename () {
    local filename="" base="" ext=""
    filename=$(path_filename "$1")
    base="${filename%%.[^.]*}"
    ext="${filename:${#base} + 1}"
    if [ -z "$base" ] && [ -n "$ext" ]; then
        echo ".$ext"
    else
        echo "$base"
    fi
}


##
# Return the extension (suffix) of the filename component of a path. Example:
# return ".tar.gz" for "my_file.tar.gz", and "" for ".test".
#
path_extension () {
    local filename="" basename=""
    filename=$(path_filename "$1")
    basename=$(path_basename "$filename")
    echo "${filename##"$basename"}"
}


##
# Generate a pseudorandom string. Accepts an argument for the length of the
# string; if no string length is provided, then it defaults to generating a
# string between 12 and 25 characters long.
#
# Similar-looking characters are filtered out of the result string.
#
# shellcheck disable=SC2120
random_string () {
    local -i num_chars=0
    if [ $# -gt 0 ]; then
        num_chars=$1
    else
        num_chars=$((12 + RANDOM % 12))
    fi
    tr -dc _A-Z-a-z-0-9 < /dev/urandom | tr -d '/+oO0lLiI1\n\r' | head -c "$num_chars"
}


##
# Write a message to stderr and continue execution.
#
warn () {
    echo "Warning: $*" | fmt -w 80 >&2
}


##
# Write a message to stderr and exit immediately with a non-zero code.
#
fail () {
    echo -e "ERROR: $*" >&2
    pkill -TERM -g $$ "$myname" || kill TERM $$ >/dev/null 2>&1
    exit 1
}


##
# Ask the user a question and process the response, with options for defaults
# and timeouts.
#
ask () {
    # Options:
    #     --timeout N:     time out if there's no input for N seconds.
    #     --default ANS:   use ANS as the default answer on timeout or
    #                      if an empty answer is provided.
    #     --required:      don't accept a blank answer. Use this parameter
    #                      to make ask() accept any string.
    #
    # ask() gives the answer in its exit status, e.g.,
    # if ask "Continue?"; then ...
    local ans="" default="" prompt=""
    local -i timeout=0 required=0

    while [ $# -gt 0 ] && [[ "$1" ]]; do
        case "$1" in
            -d|--default)
                shift
                default=$1
                if [[ ! "$default" ]]; then warn "Missing default value"; fi
                default=$(tr '[:upper:]' '[:lower:]' <<< "$default")
                if [[ "$default" = "yes" ]]; then
                    default="y"
                elif [[ "$default" = "no" ]]; then
                    default="n"
                elif [ "$default" != "y" ] && [ "$default" != "n" ]; then
                    warn "Illegal default answer: $default"
                fi
                shift
            ;;

            -t|--timeout)
                shift
                if [[ ! "$1" ]]; then
                    warn "Missing timeout value"
                elif [[ ! "$1" =~ ^[0-9][0-9]*$ ]]; then
                    warn "Illegal timeout value: $1"
                else
                    timeout=$1
                fi
                shift
            ;;

            -r|--required)
                shift
                required=1
            ;;

            -*)
                warn "Unrecognized option: $1"
            ;;

            *)
                break
            ;;
        esac
    done

    # Sanity checks
    if [[ $timeout -ne 0  &&  ! "$default" ]]; then
        warn "ask(): Non-zero timeout requires a default answer"
        exit 1
    fi
    if [ "$required" -ne 0 ]; then
        if [ -n "$default" ] || [ "$timeout" -gt 0 ]; then
            warn "ask(): 'required' is not compatible with 'default' or 'timeout' parameters."
            exit 1
        fi
    fi
    if [[ ! "$*" ]]; then
        warn "Missing question"
        exit 1
    fi

    prompt="$*"
    if [ "$default" = "y" ]; then
        prompt="$prompt [Y/n] "
    elif [ "$default" = "n" ]; then
        prompt="$prompt [y/N] "
    elif [ "$required" -eq 1 ]; then
        prompt="$prompt (required) "
    else
        prompt="$prompt [y/n] "
    fi


    while [ -z "$ans" ]
    do
        if [[ $timeout -ne 0 ]]; then
            if ! read -r -t "$timeout" -p "$prompt" ans </dev/tty; then
                ans=$default
                echo
            else
                # Turn off timeout if answer entered.
                timeout=0
                if [[ ! "$ans" ]]; then ans=$default; fi
            fi
        else
            read -r -p "$prompt" ans <"$(tty)"
            if [[ ! "$ans" ]]; then
                if [ "$required" -eq 1 ]; then
                    warn "An answer is required."
                    ans=""
                else
                    ans=$default
                fi
            elif [ "$required" -eq 0 ]; then
                ans=$(tr '[:upper:]' '[:lower:]' <<< "$ans")
                if [ "$ans" = "yes" ]; then
                    ans="y"
                elif [ "$ans" = "no" ]; then
                    ans="n"
                fi
            fi 
        fi

        if [ "$required" -eq 0 ]; then
            if [ "$ans" != 'y' ] && [ "$ans" != 'n' ]; then
                warn "Invalid answer. Please use y or n."
                ans=""
            fi
        fi
    done

    if [ "$required" -eq 1 ]; then
        echo "$ans"
        return 0
    fi

    [[ "$ans" = "y" || "$ans" == "yes" ]]
}


##
# Return the value of a named option passed from the commandline.
# If it doesn't exist, exit with a non-zero status.
# This function can be invoked like so:
#     if var="$(loadopt "foo")"; then...
# 
loadopt () {
    local varname="$1" value="" found=""
    # Run through the longopts array and search for a "varname".
    for i in "${longopts[@]}"; do
        if [ -n "$found" ]; then
            echo "$i"
            return 0
        elif [ "$i" = "--$varname" ]; then
            # Matched varname, set found here so that the next loop iteration
            # picks up varname's value.
            found="$varname"
        fi
    done
    echo ""
    [ -n "$found" ]
}


##
# Require a named value from the user. If the value wasn't specified as a longopt
# when the script was invoked, then needopt() will call ask() to request the value
# from the user. Use this to get required values for your scripts.
#
needopt () {
    # Usage:
    #     varname=$(needopt varname -p "Prompt to the user" -m [regex])
    local varname="" prompt="" match="" i="" found="" value=""
    while [ $# -gt 0 ] && [[ "$1" ]]; do
        case "$1" in
            -p)
                shift
                if [ $# -gt 0 ]; then
                    prompt="$1"
                    shift
                fi
            ;;
            -m)
                shift
                if [ $# -gt 0 ]; then
                    match="$1"
                    shift
                fi
            ;;
            -*)
                warn "Unrecognized option: $1"
            ;;
            *)
                if [ -z "$varname" ]; then
                    varname="$1"
                    shift
                else
                    fail "needopt(): Unexpected value: $1"
                fi
            ;;
        esac
    done
    if [ -z "$varname" ]; then
        fail "needopt(): No varname was provided"
    fi
    if [ -z "$prompt" ]; then
        prompt="$varname"
    fi
    if ! value="$(loadopt "$varname")" || [[ ! $value =~ $match ]]; then
        while true; do
            value="$(ask -r "$prompt")"
            if [ -n "$value" ] && [[ $value =~ $match ]]; then
                break
            elif [ -n "$match" ]; then
                warn "needopt(): this value doesn't match the expected regular expression: $match"
            fi
        done
    fi
    # printf -v "$varname" '%s' "$value"
    echo "$value"
    return 0
}


# Process arguments. Golem will load any "--variable value" pairs into the
# "longopts" array. Your command script can then call the needopt() function to
# load this value into a variable.
# Example: if your command script needs a "hostname" value, the user can supply
# that with, "golem --hostname 'host.name' your command", and the "your_command.sh"
# file can use "hostname=needopt(hostname)" to create a variable named "hostname"
# with the value "host.name" (or ask the user for it).
declare -a longopts=()
declare -a args=()
while [ $# -gt 0 ] && [[ "$1" ]]; do
    case "$1" in
        --)
            # Stop processing arguments.
            break
            ;;
        --*)
            longopts+=("$1")
            shift
            if [ $# -lt 1 ] || [[ "$1" =~ ^--.+ ]]; then
                longopts+=("")
            else
                longopts+=("$1")
                shift
            fi
            ;;
        *)
            args+=("$1")
            shift
            ;;
    esac
done
# Reset the arguments list to every argument that wasn't a --longopt.
set -- "${args[@]}"
unset args


################################################################################
#                                                                              #
#    Main program                                                              #
#                                                                              #
################################################################################

# end-golem-injected-code

# This script appears to require sudo, so make sure the user has the necessary access.
# If they do, then run a sudo command now so that script execution doesn't trip
# on a password prompt later.
if ! groups | grep -qw '\(sudo\|root\)'; then
    fail "It looks like this command script requires superuser access and you're not in the 'sudo' group"
elif [ "$(sudo whoami </dev/null)" != "root" ]; then
    fail "Your 'sudo' command seems to be broken"
fi

sysadmin_email="sysop@biphrost.net"
echo "Installing: lxc libvirt0 libpam-cgfs bridge-utils uidmap acl btrfs-progs..."
if sudo apt install -y lxc libvirt0 libpam-cgfs bridge-utils uidmap acl btrfs-progs >/dev/null; then
    echo "Successfully installed all packages"
else
    fail "Failed to install one or more of: lxc libvirt0 libpam-cgfs bridge-utils uidmap acl btrfs-progs"
fi
getent group lxcusers || sudo groupadd lxcusers
sudo sysctl kernel.unprivileged_userns_clone=1
echo "kernel.unprivileged_userns_clone=1" | sudo tee -a /etc/sysctl.conf >/dev/null
sudo iptables -P FORWARD ACCEPT
sudo netfilter-persistent save
sudo iptables -t nat -A POSTROUTING -j MASQUERADE
sudo netfilter-persistent save
cat <<'EOF' | sudo tee /etc/lxc/default.conf >/dev/null
lxc.apparmor.profile       = unconfined
lxc.apparmor.allow_nesting = 0
lxc.mount.auto             = proc:mixed sys:ro cgroup:mixed
lxc.net.0.type             = veth
lxc.net.0.link             = lxcbr0
lxc.net.0.flags            = up
lxc.net.0.hwaddr           = 00:FF:xx:xx:xx:xx
EOF
sudo touch /etc/lxc/lxc-usernet
echo 'lxc.lxcpath = /srv/lxc' | sudo tee /etc/lxc/lxc.conf >/dev/null
cat <<'EOF' | sudo tee /etc/default/lxc-net >/dev/null
USE_LXC_BRIDGE="true"
LXC_ADDR="10.0.0.1"
LXC_NETWORK="10.0.0.0/24"
EOF
# Get the total number of 1GB "blocks" on the root volume
total_disk_size="$(df -B 1073741824 --output=size / | tail -n +2 | grep -o '[0-9]*')"
# The LXC volume will take up 81.25% of the root volume -- this works out pretty well for most builds.
lxc_disk_size=$((total_disk_size * 8125 / 10000))
sudo mkdir -p /srv/lxc
sudo qemu-img create -f raw -o preallocation=off /lxc_disk.raw "$lxc_disk_size"G
sudo mkfs.btrfs -L LXCDiskImage -m single -f /lxc_disk.raw
echo "/lxc_disk.raw  /srv/lxc        btrfs   noatime,autodefrag,compress=zstd,user_subvol_rm_allowed 0  1" | sudo tee -a /etc/fstab >/dev/null
sudo mount -a
sudo chgrp lxcusers /srv/lxc
sudo chmod 0775 /srv/lxc
sudo brctl addbr lxcbr0
cat <<'EOF' | sudo tee -a /etc/network/interfaces >/dev/null

# The lxc bridge interface
auto lxcbr0
iface lxcbr0 inet static
    address 10.0.0.1
    netmask 255.255.255.0
    bridge_ports regex eth*
    bridge_stp off
    bridge_fd 0
    bridge_waitport 0
    bridge_maxwait 0
EOF
echo '1' | sudo tee /proc/sys/net/ipv4/ip_forward >/dev/null
sudo iptables -t nat -A POSTROUTING -o "$(ip route get 8.8.8.8 | grep -Po '(?<=dev )[a-z0-9]+')" -j MASQUERADE
cat <<'EOF' | sudo tee /etc/lxc/lxc-usernet >/dev/null
@lxcusers veth lxcbr0 250
EOF
echo -e "\\n\\n# LXC containers\\n10.0.0.1    lxchost\\n" | sudo tee -a /etc/hosts >/dev/null
sudo service lxc-net restart
cat <<'EOF' | sudo tee -a /etc/ssh/sshd_config >/dev/null

Match group lxcusers
    AllowAgentForwarding  no
    AllowTcpForwarding    no
    X11Forwarding         no
    PermitTunnel          no
    GatewayPorts          no
    ForceCommand          /usr/local/sbin/lxc_login
EOF
sudo service ssh reload
cat <<'EOF' | sudo tee /usr/local/sbin/lxc_login >/dev/null
#!/bin/bash  
    
my_lxc="$(whoami)"  
echo "Looking for $my_lxc"  
lxc_status=$(lxc-ls -f | grep "^$my_lxc")  
if [ -z "$lxc_status" ]; then  
   echo "You do not have any containers on this system. Goodbye."  
   exit 1  
fi  
echo "Connecting to $my_lxc"  
lxc_status=$(echo "$lxc_status" | xargs | cut -d ' ' -f 2)  
if [ "$lxc_status" != "RUNNING" ]; then  
   echo "Your container is not running. Attempting to start it..."  
   lxc-unpriv-start -n "$(whoami)" || { echo "Failed to start your container. Please contact a system administrator."; exit 1; }  
fi  
lxc-unpriv-attach -n "$my_lxc" && exit 0
EOF
sudo chmod 0755 /usr/local/sbin/lxc_login
sudo apt -y install curl openssl dnsutils
sudo mkdir -p /usr/local/sbin/letsencrypt
wget https://raw.githubusercontent.com/dehydrated-io/dehydrated/master/dehydrated -q -O - | sudo tee /usr/local/sbin/letsencrypt/dehydrated >/dev/null
sudo chmod 0755 /usr/local/sbin/letsencrypt/dehydrated
sudo mkdir -p /etc/letsencrypt && sudo chmod 0644 /etc/letsencrypt
wget https://raw.githubusercontent.com/dehydrated-io/dehydrated/master/docs/examples/config -q -O - | sed -e 's%^#\?\s*CHALLENGETYPE=.*$%CHALLENGETYPE="http-01"%' -e 's%^#\?\s*CONFIG_D=.*$%CONFIG_D="/etc/letsencrypt"%' -e "s%^#\\?[[:space:]]*CONTACT_EMAIL=.*\$%CONTACT_EMAIL=\"$sysadmin_email\"%" | sudo tee /etc/letsencrypt/config >/dev/null
cat <<EOF | sudo tee /etc/systemd/system/biphrost-ssl-renewal.service >/dev/null
[Unit]
Description=Biphrost automatic SSL renewal service
After=network.target
Wants=biphrost-ssl-renewal.timer

[Service]
Type=oneshot
User=root
Group=root
ExecStartPre=
ExecStart=/usr/local/sbin/biphrost ssl renew

[Install]
WantedBy=multi-user.target
EOF
hour="$(tr -dc '0-9' </dev/urandom | fold -w 2 | grep -m 1 '\(23\|00\|01\|02\)')"
minute="$(tr -dc '0-9' </dev/urandom | fold -w 2 | grep -m 1 '[0-5][0-9]')"
cat <<EOF | sudo tee /etc/systemd/system/biphrost-ssl-renewal.timer >/dev/null
[Unit]
Description=Biphrost automatic SSL renewal timer
Requires=biphrost-ssl-renewal.service

[Timer]
Unit=biphrost-ssl-renewal.service
OnCalendar=*-*-* $hour:$minute:00
AccuracySec=60s

[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable biphrost-ssl-renewal.service
systemctl enable biphrost-ssl-renewal.timer
systemctl start biphrost-ssl-renewal.timer
redirect_url=$(ask -r "Enter the default redirect URL for this server:")
echo "Installing: nginx..."
if sudo apt-get install -y nginx >/dev/null; then
    echo "Successfully installed all packages"
else
    fail "Failed to install one or more of: nginx"
fi
mkdir -p /etc/nginx/biphrost
mkdir -p /etc/nginx/biphrost/lists
cat <<'EOF' | tee /etc/nginx/biphrost/lists/uri_filters >/dev/null
# Path traversal nonsense.
~/\.\.                            1;

# Apache special files.
~/\.htaccess(/.*|$)               1;

# Git-related files and directories.
~/\.git(/.*|$)                    1;
~/\.gitignore                     1;
~/\.gitconfig                     1;

# WordPress.
~/wp-config\.php                  1;
~/xml-?rpc\.php                   1;
EOF
cat <<'EOF' | tee /etc/nginx/biphrost/request_filters.conf >/dev/null
##
# request_filters.conf: included by vhosts
##

if ($deny_access) {
    return 404;
}
EOF
cat <<'EOF' | tee /etc/nginx/conf.d/biphrost.conf >/dev/null
##
# Basic Settings
##

server_tokens off;


##
# Global security settings.
##

map $uri $deny_access {
    include biphrost/lists/uri_filters;
}


##
# Logging Settings
##

map $time_iso8601 $date {
    ~([^T]+) $1;
}
 
map "$time_iso8601.$msec" $time {
    ~\T(\d+:\d+:\d+)[^.]+\.\d+(\.\d+)$ $1$2;
}

log_format normal '$date $time $request_time $status $upstream_cache_status $host $remote_addr $remote_user "$request" $body_bytes_sent "$http_referer" "$http_user_agent" "$http_x_forwarded_for"';

# Disable nginx's default access log. It will have to be re-enabled in each site config.
access_log off;


##
# Caching
##

proxy_cache_path     /var/cache/nginx keys_zone=static:50m;
proxy_cache_key      $host$request_uri;
proxy_cache_min_uses 2;
proxy_cache_methods  GET;
proxy_cache_valid    200 5m;
proxy_cache_bypass   $cookie_nocache $arg_nocache $http_nocache;

EOF
cat <<'EOF' | sed "s|\\\$redirect_url|$redirect_url|g" | sudo tee /etc/nginx/sites-available/default >/dev/null
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;

    server_name _;

    return 302 $redirect_url;
}
EOF
cat <<'EOF' | sudo tee /root/cf_ip_update.sh >/dev/null
#!/bin/bash
curl -s "https://www.cloudflare.com/ips-v4" | grep '^[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\(/[0-9]\+\)\?$' | tee /tmp/cloudflare_ip4 >/dev/null
if [ ! -s /tmp/cloudflare_ip4 ]; then
    fail "Could not retrieve a valid list of IPv4 addresses from https://www.cloudflare.com/ips-v4"
fi
curl -s "https://www.cloudflare.com/ips-v6" | grep '^[0-9a-f:/]\+$' | tee /tmp/cloudflare_ip6 >/dev/null
if [ ! -s /tmp/cloudflare_ip6 ]; then
    fail "Could not retrieve a valid list of IPv6 addresses from https://www.cloudflare.com/ips-v64"
fi
cat /tmp/cloudflare_ip4 /tmp/cloudflare_ip6 | sed 's/^\(.*\)$/set_real_ip_from \1;/' | cat - <(echo "real_ip_header CF-Connecting-IP;") | tee /etc/nginx/conf.d/cloudflare_real_ip.conf >/dev/null
rm /tmp/cloudflare_ip4
rm /tmp/cloudflare_ip6
nginx -qt && service nginx restart
EOF
sudo chmod 0750 /root/cf_ip_update.sh
minutes=$(shuf -i 0-59 -n 1)
sudo EDITOR=cat crontab -e 2>/dev/null | cat - <(echo; echo "$minutes 0 * * * /root/cf_ip_update.sh") | sudo crontab -
sudo nginx -qt && sudo service nginx restart
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT
sudo netfilter-persistent save
sudo iptables -A FORWARD -p tcp --dport 80 -d 10.0.0.1/24 -j ACCEPT
sudo iptables -A FORWARD -p tcp --dport 443 -d 10.0.0.1/24 -j ACCEPT
sudo netfilter-persistent save
