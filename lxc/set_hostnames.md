# Configure hostnames inside a container

Hostname validation has already been handled by the biphrost script that calls this script.

The primary hostname should be the first hostname provided in the argument list.

**Usage**
```
biphrost @<container-id> set hostnames primaryhostname hostname2 hostname3 etc
```

**Sanity-check invocation**
```bash
myinvocation="set hostnames"
if [ "${*:1:2}" != "$myinvocation" ]; then
    fail "[$myinvocation]: Invalid invocation"
fi
shift; shift
```

**TODO**
* Update Apache/etc. config in the container

**Load hostnames from the argument list**
The primary hostname is expected to be the first argument in the list.
```bash
if [ $# -lt 1 ]; then
    fail "No hostnames given"
fi
all_hostnames="$*"
default_hostname="$1"
shift
alias_names="$*"
```

**Get the container label or hostname**
Used for logging.
```bash
containerid="$(cat /root/.label 2>/dev/null <(hostname) | head -n 1)"
```

**Start the log**
```bash
echo "$(date +'%F')" "$(date +'%T')" "$containerid" "Setting hostnames: $all_hostnames"
```

**Set the primary hostname in the container**
```bash
echo "$(date +'%F')" "$(date +'%T')" "$containerid" "Setting primary hostname."
echo "$default_hostname" | tee /etc/hostname >/dev/null
hostname -F /etc/hostname
```

**Regenerate the hosts file for the container.**
```bash
echo "$(date +'%F')" "$(date +'%T')" "$containerid" "Updating hosts file."
cat <<EOF | tee /etc/hosts >/dev/null
# IP4
127.0.0.1          $all_hostnames localhost
10.0.0.1           lxchost

# IP6
::1                $all_hostnames ip6-localhost ip6-loopback
ff02::1            ip6-allnodes
ff02::2            ip6-allrouters

EOF
```

**Update an Apache configuration, if available**
Pretty much all containers should have at most one Apache site configuration. There may be the occasional exception, which will need to be handled by a sysop. In all other cases, we can automatically fix an Apache config.
```bash
apache_config="$(find /etc/apache2/sites-available -maxdepth 1 -type f -regex '.*/.*[A-Za-z0-9-]+\.[a-z]+\.conf$' 2>/dev/null)"
count="$(echo -n "$apache_config" | grep -c '^')"
if [ "$count" -eq 0 ]; then
    echo "$(date +'%F')" "$(date +'%T')" "$containerid" "No Apache config files found; skipping reconfiguration."
elif [ "$count" -gt 1 ]; then
    echo "$(date +'%F')" "$(date +'%T')" "$containerid" "More than one Apache config file was found; skipping reconfiguration."
else
    echo "$(date +'%F')" "$(date +'%T')" "$containerid" "Updating Apache configuration at $apache_config"
    sed -i 's/\(\s*#\?\s*ServerName\s\+\).*$/\1'"$default_hostname"'/g' "$apache_config"
    sed -i 's/\(\s*#\?\s*ServerAlias\s\+\).*$/\1'"$alias_names"'/g' "$apache_config"
    if ! apachectl configtest; then
        fail "'apachectl configtest' failed; sysop intervention is required."
    fi
    apachectl graceful
fi
```

**Done.**
```bash
echo "$(date +'%F')" "$(date +'%T')" "$containerid" "Hostname configuration completed."
```


## TODO

* There should probably be some sanity-checking done on the hostnames parameter