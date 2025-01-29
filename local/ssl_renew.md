# SSL Renew

Renew the Let's Encrypt certificates for one or more containers, if their existing certificates are expiring soon or their hostnames have changed.

**Usage**
```
biphrost ssl renew [container-id]
```

**Parameters**
* `container-id` (optional): the identifier of the container to renew. If no `container-id` is provided, then this will search for containers with SSL certs that are more than 60 days old, pick one at random, and try to renew it.

**Sanity-check invocation**
```bash
myinvocation="ssl renew"
if [ "${*:1:2}" != "$myinvocation" ]; then
    fail "[$myinvocation]: Invalid invocation"
fi
shift; shift
```

**Get the optional target container**
```bash
if [ $# -lt 1 ]; then
    target="$(find /home/*/ssl/* -maxdepth 1 -type d -ctime +60 -printf '%CY.%Cj %p\n' | shuf | head -n 1 | grep -oP '(?<=/home/)lxc[0-9]+')"
else
    target="$1"
fi
if [ -z "$target" ]; then
    echo "$(date +'%F')" "$(date +'%T')" "$(hostname): No container IDs were provided and no containers were found to update"
    exit 0
fi
```

**Start the log**
```bash
echo "$(date +'%F')" "$(date +'%T')" "$(hostname): Renewing SSL certificate for $target"
```

**Sanity-check the target**
```bash
if [[ ! "$target" =~ lxc[0-9]{4} ]]; then
    fail "Invalid container name: $target"
fi

if [ ! -d "/home/$target" ]; then
    fail "No home directory was found for $target"
fi
```

**Ensure the `ssl`, `acme-challenge`, and related directories exist and are owned by the container user.**
```bash
firstrun=0
if [ ! -d "/home/$target/ssl" ]; then
    firstrun=1
fi
mkdir -p "/home/$target/acme-challenge"
mkdir -p "/home/$target/accounts"
mkdir -p "/home/$target/chains"
mkdir -p "/home/$target/ssl"
chown -R "$target":"$target" "/home/$target/acme-challenge"
chown -R "$target":"$target" "/home/$target/accounts"
chown -R "$target":"$target" "/home/$target/chains"
chown -R "$target":"$target" "/home/$target/ssl"
chmod 0755 "/home/$target/acme-challenge"
```

**Get the hostnames that are being routed to this container.**
For historical record, there was a section here that would try to read container hostnames from `/etc/hosts`. Container hostnames are no longer stored there, so this snippet just demonstrates how this could be done if it's needed again later.
```
# Here is what this mess does:
#     1. Get all the lines from /etc/hosts that start with "10.", followed by
#        the lxc name we're looking for;
#     2. Get all of the hostnames on each of those lines (this will work even
#        if there are multiple matching lines);
#     3. Convert it into a series of lines, one hostname per line;
#     4. Remove any duplicate entries;
#     5. Output the length of each hostname along with the hostname;
#     6. Sort by hostname length (shortest to longest);
#     7. Print just the hostname on each line;
#     8. Merge all of the lines into a single space-separated line;
#     9. Output this to the lxc's hostnames file.
grep -o "^10\\.[0-9\\.]\\+[[:space:]]\\+$target[[:space:]]\\+.*$" /etc/hosts | sed -e "s/^10\\.[0-9\\.]\\+[[:space:]]\\+$target[[:space:]]\\+//" -e 's/\s\+/\n/g' | sort -u | while read -r hostname; do  
    echo ${#hostname} "$hostname"  
done | sort -n | cut -d ' ' -f 2 | xargs | tee "/home/$target/ssl/hostnames" >/dev/null  
```

The `hostnames` file should be left in the container's home directory because it's used as a validation check when enabling SSL.
```bash
biphrost -b hostnames get "$target" --verify | xargs | tee "/home/$target/ssl/hostnames" >/dev/null
```

**Ensure we have some hostnames for our certificate request**
```bash
if [ ! -s "/home/$target/ssl/hostnames" ] || ! grep -q '[A-Za-z0-9.-]\+' "/home/$target/ssl/hostnames"; then
    fail "Failed to generate the hostnames file for $target; is its DNS pointed here?"
fi
```

**Hostnames file should be owned by the LXC user**
```bash
chown "$target" /home/"$target"/ssl/hostnames
```

**Copy our letsencrypt config to the container's home directory and update it**
Dehydrated doesn't offer a way to use a different `.well-known` directory on the commandline and doesn't offer a way to include config files, and we want each container user to handle its own LetsEncrypt renewal, because that reduces the risk of something going horribly wrong with `dehydrated` while it's running as root.

So, copy the current Dehydrated global config, rewrite the `wellknown` parameter, and continue.
```bash
cp /etc/letsencrypt/config "/home/$target/le_config"
sed -i -e "s%^#\\?[[:space:]]*WELLKNOWN=.*\$%WELLKNOWN=\"/home/$target/acme-challenge\"%" "/home/$target/le_config"
chown "$target":"$target" "/home/$target/le_config"
```

**Handle possible acceptance-of-terms**
If this is the first run for Dehydrated for this host, then terms etc. need to be accepted.
```bash
if [ $firstrun -gt 0 ]; then
    echo "$(date +'%F')" "$(date +'%T')" "$(hostname): Accepting terms of service for first run with $target"
    sudo -u "$target" /usr/local/sbin/letsencrypt/dehydrated -f "/home/$target/le_config" --domains-txt "/home/$target/ssl/hostnames" -o "/home/$target/ssl" --register --accept-terms
fi
```

**Request a LetsEncrypt update and get its exit status.**
```bash
sudo -u "$target" /usr/local/sbin/letsencrypt/dehydrated -f "/home/$target/le_config" --domains-txt "/home/$target/ssl/hostnames" -o "/home/$target/ssl" -c
exitcode=$?
```

**Cleanup and done.**
```bash
rm "/home/$target/le_config"
if [ "$exitcode" -eq 0 ]; then
    echo "$(date +'%F')" "$(date +'%T')" "$(hostname): Completed successfully for $target"
else
    echo "$(date +'%F')" "$(date +'%T')" "$(hostname): Dehydrated returned a non-zero exit status for $target"
    exit "$exitcode"
fi
```