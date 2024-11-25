# Deploy a new Biphrost host

This builds a server environment for hosting unprivileged LXC containers with Incus and an nginx reverse proxy for web requests.

**IMPORTANT**
At this time, this file is just for documentation purposes and should not be executed.

**Variables**
These aren't expected to change often (so they don't need to be runtime parameters), but they can be updated here if necessary.
```bash
sysadmin_email="sysop@biphrost.net"
```

**TODO**
Need to use a DigitalOcean (or other VPS provider) API to instantiate and connect to the new server here.

**Install required packages**
```bash
sudo apt install -y lxc libvirt0 libpam-cgfs bridge-utils uidmap acl btrfs-progs
```

**Create the lxcusers group if it doesn't exist**
```bash
getent group lxcusers || sudo groupadd lxcusers
```

**Turn on kernel support for unprivileged user namespace cloning**
```bash
sudo sysctl kernel.unprivileged_userns_clone=1
echo "kernel.unprivileged_userns_clone=1" | sudo tee -a /etc/sysctl.conf >/dev/null
```

**Open up the iptables FORWARD chain policy**
Otherwise, containers can't make dns requests, install packages, etc.
```bash
sudo iptables -P FORWARD ACCEPT
sudo netfilter-persistent save
```

**Enable IP Masquerading**
This allows knockd to forward inbound ssh connections to their destination container.
```bash
sudo iptables -t nat -A POSTROUTING -j MASQUERADE
sudo netfilter-persistent save
```

**Generate the lxc global configuration files**
Note: `lxc.apparmor.profile` needs to be `unconfined` here for non-root users to be able to start containers. See also https://wiki.debian.org/LXC#Unprivileged_container . This issue seems to cause issues for root trying to start a container too.
```bash
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
```

**Create the LXC host volume**
All of the LXC containers will share a single BTRFS volume. This helps prevent exhausting inodes in the host file system and also provides instant LXC snapshots.

There are some important options in the fstab entry for the btrfs backing filesystem:

* **noatime:** This is the most important. btrfs is a copy-on-write filesystem that maintains access timestamps ("relatime") by default. This means that certain filesystem operations that touch large numbers of files can cause the metadata block for every file to be updated for each operation.
* **autodefrag:** Improves performance even on SSD hardware.
* **compress=zstd:** Gets some free filesystem savings and also speeds up reads and writes.
* **usersubvol_rm_allowed:** Required to allow non-root users to remove subvolumes (necessary for snapshots and shutting down containers).

```bash
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
```

**Create the network bridge**
The file `/etc/dnsmasq.d/lxc` is required to prevent dnsmasq from trying to grab all the network interfaces, which breaks everything.
```bash
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
```

**Generate the lxc-usernet configuration file**
lxc-net seems to handle the network interface quota in a strange way in [/etc/lxc/lxc-usernet](https://linuxcontainers.org/lxc/manpages/man5/lxc-usernet.5.html). Specifying a per-user quota doesn't seem to work if the users share the same group, which is a shame. So, a group specification is created here that should be sufficient for most LXC hosts.
```bash
cat <<'EOF' | sudo tee /etc/lxc/lxc-usernet >/dev/null
@lxcusers veth lxcbr0 250
EOF
```

**Prepare /etc/hosts**
The `/etc/hosts` file will be updated as each container is created or deleted.
```bash
echo -e "\\n\\n# LXC containers\\n10.0.0.1    lxchost\\n" | sudo tee -a /etc/hosts >/dev/null
```

**Start LXC networking**
```bash
sudo service lxc-net restart
```

**Update the sshd config for lxcusers**
Here is a helpful article for configuring the local `~/.ssh/config` file for connecting through a bastion host: https://www.redhat.com/sysadmin/ssh-proxy-bastion-proxyjump
This is an amazingly helpful gist for configuring the server side of ssh proxying through bastion hosts: https://gist.github.com/smoser/3e9430c51e23e0c0d16c359a2ca668ae
(This may not be necessary anymore now that knockd/iptables handles proxying ssh connections to containers.)
```bash
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
```

**Create the magic login script for lxcusers**
This is the `ForceCommand` script specified in `/etc/ssh/sshd_config`. When an lxcuser successfully authenticates over ssh, this script looks for their container, boots them if it's not found, starts it if it's not running, and drops them into it. As far as I know, there's no reasonable way for this user to escape their lxc jail.
```bash
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
```

# Install Dehydrated (LetsEncrypt)
This is adapted from [[ projects/southyubanet/sysadmin/install_letsencrypt_web/ ]].

**Install required dependencies**
```bash
sudo apt -y install curl openssl dnsutils
```

**Get the current version of dehydrated from https://github.com/dehydrated-io/dehydrated **
(Dehydrated was previously found at https://github.com/lukas2511/dehydrated)
I'd prefer to have 0700 permissions here on the Dehydrated script, but:
* I want Dehydrated to be run from individual lxc crontabs that get cleaned up when the container is deleted;
* I want to be able to easily generate new certs for any container on demand;
* I don't want root or sudo to be required to run any of this;
* Shell scripts can't be setuid;
* And regular users won't have access to the lxchost anyway.
```bash
sudo mkdir -p /usr/local/sbin/letsencrypt
wget https://raw.githubusercontent.com/dehydrated-io/dehydrated/master/dehydrated -q -O - | sudo tee /usr/local/sbin/letsencrypt/dehydrated >/dev/null
sudo chmod 0755 /usr/local/sbin/letsencrypt/dehydrated
```

**Get a current config file**
This block also updates a few of the config values.
```bash
sudo mkdir -p /etc/letsencrypt && sudo chmod 0644 /etc/letsencrypt
wget https://raw.githubusercontent.com/dehydrated-io/dehydrated/master/docs/examples/config -q -O - | sed -e 's%^#\?\s*CHALLENGETYPE=.*$%CHALLENGETYPE="http-01"%' -e 's%^#\?\s*CONFIG_D=.*$%CONFIG_D="/etc/letsencrypt"%' -e "s%^#\\?[[:space:]]*CONTACT_EMAIL=.*\$%CONTACT_EMAIL=\"$sysadmin_email\"%" | sudo tee /etc/letsencrypt/config >/dev/null
```

**Create an "update" shell script**
This shell script will be called by the crontab of each individual lxc user account.
```bash
cat <<'EOF' | sudo tee /usr/local/sbin/letsencrypt/update.sh >/dev/null
#!/bin/bash
#
# Renew LetsEncrypt SSL certs for a container.
#
# Usage: update.sh [containername]
#
# [containername]: optional lxcNNNN identifier for the container to renew. If no containername
# is provided, then update.sh will search for containers with SSL certs that are more than 60
# days old, pick one at random, and try to renew it.

if [ $# -lt 1 ]; then
    target="$(find /home/*/ssl/* -maxdepth 1 -type d -ctime +60 -printf '%CY.%Cj %p\n' | shuf | head -n 1 | grep -oP '(?<=/home/)lxc[0-9]+')"
else
    target="$1"
fi

if [ -z "$target" ]; then
    exit 1
fi

if [[ ! "$target" =~ lxc[0-9]{4} ]]; then
    echo "Invalid container name: $target"
    exit 1
fi

if [ ! -d "/home/$target" ]; then
    echo "Error: there is no home directory for $target"
    exit 1
fi

# Ensure the ssl and acme-challenge directories exist.
firstrun=0
if [ ! -d "/home/$target/ssl" ]; then
    firstrun=1
    mkdir -p "/home/$target/ssl"
fi
mkdir -p "/home/$target/acme-challenge"

# Get the hostnames that are being routed to this container.
# They should all be listed in /etc/hosts.
# Here is what this mess does:
#     1. Get all the lines from /etc/hosts that start with "10.", followed by
#        the lxc name we're looking for;
#     2. Get all of the hostnames on each of those lines (this will work even
#        if there are multiple matching lines);
#     3. Convert it into a series of lines, one hostname per line;
#     4. Remove any duplicate entries;
#     5. Output the length of each hostname along with the hostname;
#     6. Sort by hostname length (shortest to longest);
#     7. Print just the hostname on each line;
#     8. Merge all of the lines into a single space-separated line;
#     9. Output this to the lxc's hostnames file.
if [ -x /usr/local/sbin/biphrost ]; then
    /usr/local/sbin/biphrost -b get hostnames "$target" --verify | xargs | tee "/home/$target/ssl/hostnames" >/dev/null
else
    grep -o "^10\\.[0-9\\.]\\+[[:space:]]\\+$target[[:space:]]\\+.*$" /etc/hosts | sed -e "s/^10\\.[0-9\\.]\\+[[:space:]]\\+$target[[:space:]]\\+//" -e 's/\s\+/\n/g' | sort -u | while read -r hostname; do
        echo ${#hostname} "$hostname"
    done | sort -n | cut -d ' ' -f 2 | xargs | tee "/home/$target/ssl/hostnames" >/dev/null
fi

if [ ! -s "/home/$target/ssl/hostnames" ]; then
    echo "Error: failed to generate the hostnames file for $target"
    exit 1
fi

# Dehydrated doesn't offer a way to use a different .well-known directory on
# the commandline and doesn't offer a way to include config files, and we want
# each container user to handle its own LetsEncrypt renewal. So, copy the
# current Dehydrated global config, rewrite the wellknown parameter, and continue.
cp /etc/letsencrypt/config "/home/$target/le_config"
sed -i -e "s%^#\\?[[:space:]]*WELLKNOWN=.*\$%WELLKNOWN=\"/home/$target/acme-challenge\"%" "/home/$target/le_config"

# If this is the first run for Dehydrated for this host, then terms etc. need
# to be accepted.
if [ $firstrun -gt 0 ]; then
    /usr/local/sbin/letsencrypt/dehydrated -f "/home/$target/le_config" --domains-txt "/home/$target/ssl/hostnames" -o "/home/$target/ssl" --register --accept-terms
fi

# Request a LetsEncrypt update and exit with its status code.
/usr/local/sbin/letsencrypt/dehydrated -f "/home/$target/le_config" --domains-txt "/home/$target/ssl/hostnames" -o "/home/$target/ssl" -c
exitcode=$?

# Cleanup.
rm "/home/$target/le_config"

exit $exitcode
EOF
sudo chmod 0755 /usr/local/sbin/letsencrypt/update.sh
```


# Install and configure nginx

These steps configure nginx to run on the container host and forward inbound web connections to specific containers.

**Set the default redirect URL**
Crawlers and bots will frequently make http requests for domains that aren't hosted by this server. Those requests need to be redirected elsewhere.
```bash
redirect_url=$(ask -r "Enter the default redirect URL for this server:")
```

**Install nginx**
```bash
sudo apt-get install -y nginx
```

**Create directories for Biphrost-specific configuration files**
```bash
mkdir -p /etc/nginx/biphrost
mkdir -p /etc/nginx/biphrost/lists
```

**Create a deny list for some URI patterns**
This is a security measure that helps harden hosted sites against some common issues. Generally the individual applications can already be expected to reject these requests, but blocking them here helps to ensure that broken or misconfigured sites are somewhat better protected.

These patterns are matched against nginx's `$uri` variable, which has already been normalized, so they can only match the file part of a request.
```bash
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
```

**Create `request_filters.conf`**
This file is included by vhosts to block common likely-malicious requests.

It would be super nice if this file could be added to some kind of a global `http` or `server` block instead, but I haven't been able to find a way to make that work in nginx. nginx doesn't allow `map` blocks inside of `server` blocks, and it doesn't allow `location` blocks outside of `server` blocks, and it complains if you `include` a file that adds another `location /` to a configuration file that already has a `location /`, and repeated tests suggest that generic `server` blocks don't work properly in a vhost environment.

So the only way to do this is to have each vhost `include biphrost/request_filters.conf` inside their `location` block inside their `server` block.

This is configured to return a bare `404` instead of `403` to, hopefully, discourage scanners and pentesters and other nuisances from trial-and-error poking their way through the request denial patterns.
```bash
cat <<'EOF' | tee /etc/nginx/biphrost/request_filters.conf >/dev/null
##
# request_filters.conf: included by vhosts
##

if ($deny_access) {
    return 404;
}
EOF
```

**Configure logging and other biphrost-specific nginx features**
```bash
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
```

**Create the default site config file**
This is the file that tells nginx what to do if the request doesn't match any of the hosted sites. It will tell the browser to go to `$redirect_url` instead.
```bash
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
```

**Handle remote address rewrites for Cloudflare IPs**
You may host sites that use Cloudflare's services. By default, every request for those sites will be from Cloudflare's IP address. But, they also set a header with the original request IP; nginx can be configured to use that IP instead, but should only do so if the request is coming from Cloudflare. Fortunately, they publish a list of their IP space, so we can put something together that will handle this nicely.
```bash
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
```

**Restart nginx**
Test the nginx configuration; if it's okay, then restart nginx.
```bash
sudo nginx -qt && sudo service nginx restart
```

**Allow web traffic to reach nginx**
```bash
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT
sudo netfilter-persistent save
```

**Allow web traffic through to the containers**
```bash
sudo iptables -A FORWARD -p tcp --dport 80 -d 10.0.0.1/24 -j ACCEPT
sudo iptables -A FORWARD -p tcp --dport 443 -d 10.0.0.1/24 -j ACCEPT
sudo netfilter-persistent save
```

References:
* https://krackout.wordpress.com/2020/03/08/unprivileged-linux-containers-lxc-in-debian-10-buster/
* https://unix.stackexchange.com/questions/177030/what-is-an-unprivileged-lxc-container/177031
* https://serverfault.com/questions/882364/lxc-container-not-connecting-to-bridge-on-startup
* https://wiki.debian.org/LXC/CGroupV2
* https://wiki.debian.org/BridgeNetworkConnections#Manual_bridge_setup
* https://archives.flockport.com/lxc-networking-guide/
* https://askubuntu.com/questions/446831/how-to-let-built-in-dhcp-assign-a-static-ip-to-lxc-container-based-on-name-not
* https://serverfault.com/questions/620709/how-to-auto-start-unprivileged-lxc-containers
* https://stanislas.blog/2018/02/setup-network-bridge-lxc-net/#use-static-ips
* https://www.linode.com/docs/guides/beginners-guide-to-lxd-reverse-proxy/
