# Create a new container (lxc)

This assumes the setup laid out in [[build_lxc_host]].

**Parameters**
* `--copy`: create a copy of an existing container
* `--hostnames` (required): set the hostnames for the new container
```bash
copy_from="$(loadopt "copy")"
hostnames="$(needopt "hostnames")"
```

**Get the hostnames and validate them**
Ensure none of the hostnames match a "biphrost" pattern (that would be naughty). Any invalid hostnames will cause the entire operation to fail. The first hostname in the list becomes the default hostname.
```bash
# For a simple space-delimited list of things in a string, this really is the nicest way to convert
# the string into an array. readarray et al all get more complicated. For one matter, readarray
# will not collapse delimiters, i.e., "thing  thing2 thing3" causes an empty element to be added
# to the array. The "right" ways, in this application, are all just a mess.
# Shut up, shellcheck.
# shellcheck disable=SC2206
hostnames=($hostnames)
# Shut up, shellcheck.
# shellcheck disable=SC2068
for hostname in ${hostnames[@]}; do
    if ! [[ "$hostname" =~ ^([A-Za-z0-9-]+\.)+[A-Za-z0-9-]+$ ]]; then
        fail "Invalid hostname: $hostname does not look like a routable network hostname"
    fi
    #if [[ "$hostname" =~ "biphrost" ]]; then
    #    fail "Invalid hostname: $hostname (cannot contain 'biphrost')"
    #fi
done
if [ ${#hostnames[@]} -eq 0 ]; then
    fail "No valid hostnames were given"
fi
```

**Start the log**
```bash
echo "$(date +'%F')" "$(date +'%T')" "$(hostname)" "Creating a new LXC container with hostnames: ${hostnames[*]}"
```

**Create the unprivileged lxc user**
This scans the host system for existing lxc users and generates a new lxc username, and then creates the user.
* The `10#` in the arithmetic function forces bash to interpret the value in base 10. Otherwise, values > 7 with leading zeros are interpreted as octals. That's a fun bug that blows up a whole lot of things.
* If /usr/local/sbin/lxc_login is being used to juggle inbound ssh connections, then the shell needs to be changed to `/usr/bin/bash`.
```bash
container=$(printf 'lxc%04d' $(( 10#"$(echo 'lxc0000' | cat - /etc/passwd | grep -Po '(?<=^lxc)[0-9]+' | sort -r | head -n 1)" + 1)))
echo "$(date +'%F')" "$(date +'%T')" "$(hostname)" "Container will be $container"
sudo adduser --disabled-login --shell /usr/bin/false --quiet --gecos "" "$container" >/dev/null 2>&1
sudo usermod -a -G lxcusers "$container" >/dev/null 2>&1
sudo mkdir -p "/home/$container/.config/lxc"
sudo mkdir -p "/home/$container/.config/systemd/user"
sudo mkdir -p "/home/$container/.ssh"
sudo touch "/home/$container/.ssh/authorized_keys"
sudo chmod 0750 "/home/$container/.ssh"
sudo chmod 0640 "/home/$container/.ssh/authorized_keys"
sudo chown -R "$container":"$container" "/home/$container"
```

**Create the user's lxc config files**
These values will get compiled by the `lxc-create` command into a container runtime config file in `/srv/lxc/$lxcusername/config`; if you need to mess about with a container's configuration without destroying and rebuilding it, then edit that file instead.
```bash
echo "$(date +'%F')" "$(date +'%T')" "$(hostname)" "Creating config files"
uidmap=$(sed -n "s/^$container:\\([0-9]\\+\\):\\([0-9]\\+\\)/\\1 \\2/p" /etc/subuid)
gidmap=$(sed -n "s/^$container:\\([0-9]\\+\\):\\([0-9]\\+\\)/\\1 \\2/p" /etc/subgid)
cat <<EOF | sudo -u "$container" tee /home/"$container"/.config/lxc/default.conf >/dev/null
lxc.idmap = u 0 $uidmap
lxc.idmap = g 0 $gidmap
lxc.include = /etc/lxc/default.conf
EOF
echo "lxc.lxcpath = /srv/lxc" | sudo -u "$container" tee /home/"$container"/.config/lxc/lxc.conf >/dev/null
```

**Set ACLs on the user's home directory**
```bash
hostuid=$(echo "$uidmap" | cut -d ' ' -f 1)
sudo -u "$container" mkdir -p /home/"$container"/.local/share
sudo setfacl -m u:"$hostuid":x /home/"$container"
sudo setfacl -m u:"$hostuid":x /home/"$container"/.local
sudo setfacl -m u:"$hostuid":x /home/"$container"/.local/share
```

**Get a static IP for this container and add it to /etc/hosts**
```bash
# The following line figures out the next available IP address
nextip="10.0.0.$(diff -u <(grep -Po '^10\.[0-9\.]+' /etc/hosts | cut -d '.' -f 4 | sort -n) <(seq 2 254) | grep -Po '(?<=^\+)[0-9]+$' | head -n 1)"
echo "$nextip    $container" | sudo tee -a /etc/hosts >/dev/null
echo "$(date +'%F')" "$(date +'%T')" "$(hostname)" "$container's local IP will be $nextip"
```

**Configure networking for the container**
```bash
cat <<EOF | sudo -u "$container" -- tee -a "/home/$container/.config/lxc/default.conf" >/dev/null
lxc.net.0.flags = up
lxc.net.0.ipv4.address = $nextip
lxc.net.0.ipv4.gateway = auto
EOF
```

**Create the container**
`--keyserver...` is used because the default keyserver, pool.sks-keyservers.net, seems to be having some networking issues (reported on e.g. https://discuss.linuxcontainers.org/t/3-0-unable-to-fetch-gpg-key-from-keyserver/2015/3)

If the `--copy` parameter was used, then copy an existing container instead of creating a new one. Copied containers need file ownership fixed and their LXC config file updated. `-l INFO` is critical because `lxc-copy` will routinely fail without any output or debugging info otherwise.
```bash
if [ -z "$copy_from" ]; then
    echo "$(date +'%F')" "$(date +'%T')" "$(hostname)" "Downloading image"
    sudo -u "$container" -- lxc-create -t download -B btrfs -n "$container" -- -d debian -r bullseye -a amd64 --keyserver keyserver.ubuntu.com >/dev/null 2>&1 && sleep 1
else
    uid_from_base=$(sed -n "s/^$copy_from:\\([0-9]\\+\\):\\([0-9]\\+\\)/\\1/p" /etc/subuid)
    gid_from_base=$(sed -n "s/^$copy_from:\\([0-9]\\+\\):\\([0-9]\\+\\)/\\1/p" /etc/subgid)
    uid_to_base="${uidmap/ */}"
    gid_to_base="${gidmap/ */}"
    sudo -u "$copy_from" sh -c "lxc-copy -s -e -D -n \"$copy_from\" -N \"$container\" --allowrunning -l INFO" && sleep 1
    sudo chown "${uidmap/ */}":"$container" /srv/lxc/"$container"
    sudo chown "$container":"$container" /srv/lxc/"$container"/config
    # This is the least awful incantation I can come up with for updating the
    # uid/gid attributes on all files in the new container.
    uid_diff=$((uid_to_base-uid_from_base))
    gid_diff=$((gid_to_base-gid_from_base))
    while read -r -d $'\0' uid gid file; do
        sudo chown -h $((uid+uid_diff)):$((gid+gid_diff)) "$file"
    done < <(find -P /srv/lxc/"$container"/rootfs/ -printf '%U %G %p\0')
    sudo sed -i -e "s/^lxc.idmap = u .*\$/lxc.idmap = u 0 $uidmap/g" -e "s/^lxc.idmap = g .*\$/lxc.idmap = g 0 $gidmap/g" -e "s/^lxc.net.0.ipv4.address = .*\$/lxc.net.0.ipv4.address = $nextip/g" /srv/lxc/"$container"/config
fi
```

**Create a systemd service file so that the container starts automatically on boot**
```bash
cat <<EOF | sudo tee /home/"$container"/.config/systemd/user/"$container"-autostart.service >/dev/null
[Unit]
Description="$container autostart"
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/lxc-unpriv-start -n $container
ExecStop=/usr/bin/lxc-stop -n $container
RemainAfterExit=1

[Install]
WantedBy=default.target
EOF
```

**Tell systemd to automatically start this service on reboot**
```bash
sudo chown "$container:$container" "/home/$container/.config/systemd/user/$container-autostart.service"
sudo loginctl enable-linger "$container"
sudo -u "$container" XDG_RUNTIME_DIR="/run/user/$(sudo -u "$container" -- id -u)" -- systemctl --user enable "$container-autostart"
sudo -u "$container" XDG_RUNTIME_DIR="/run/user/$(sudo -u "$container" -- id -u)" -- systemctl --user start "$container-autostart"
```

**Start the container**
```bash
echo "$(date +'%F')" "$(date +'%T')" "$(hostname)" "Starting $container"
biphrost -b start "$container" || fail "Error starting $container"
```

**Set the container's label**
```bash
biphrost -b label update "$container"
```

**Initialize the network inside the container**
```bash
echo "$(date +'%F')" "$(date +'%T')" "$(hostname)" "Initializing network in $container"
biphrost @"$container" init network
# shellcheck disable=SC2048,SC2086
biphrost @"$container" set hostnames ${hostnames[*]}
```

**Restart the container to ensure that the new network configuration starts cleanly**
```bash
echo "$(date +'%F')" "$(date +'%T')" "$(hostname)" "Restarting $container"
biphrost -b restart "$container"
```

**Initialize the server environment inside the container**
This step is skipped if the new container was copied from another container.
```bash
if [ -z "$copy_from" ]; then
    sudo biphrost @"$container" init environment --label "$container"
fi
```

**Done**
```bash
echo "$(date +'%F')" "$(date +'%T')" "$(hostname)" "Successfully created $container ($nextip)"
```


# TODO

**Repair cloned containers**
If a container has been cloned from another container, some tidying-up needs to be done to get everything back in order.
```todo
service php-* stop
usermod -l lxc0007 -d /home/lxc0007 -m lxc0001
```

Apparently I didn't record a per-site nginx configuration here before nuking all of the servers running this configuration. Oops. A new nginx site config will need to be put together.

`/home/lxcNNNN/ssl` directory needs to be cleaned up after a container is cloned from another container.


# References

* https://www.iana.org/assignments/well-known-uris/well-known-uris.xhtml
