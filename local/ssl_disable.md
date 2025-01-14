# Disable SSL service on a container

This disables access to port 443 and SSL connections for a given container's hostnames.

**Usage**
```
biphrost hostnames ssl disable <container-id>
```

**Sanity-check invocation**
```bash
myinvocation="ssl disable"
if [ "${*:1:2}" != "$myinvocation" ]; then
    fail "[$myinvocation]: Invalid invocation"
fi
shift; shift
```

**Get the id of the target container and verify it**
```bash
if [ "$#" -lt 1 ]; then
    fail "No container or hostnames specified"
fi
containerid="$1"
if [ "$(biphrost -b status "$containerid")" = "NOTFOUND" ]; then
    fail "Invalid container ID: $containerid"
fi
shift
```

**Look for a current nginx configuration for this container**
If one isn't found, no further action needs to be taken, but this isn't considered an error.
```bash
if [ ! -f /etc/nginx/sites-available/"$containerid" ]; then
    exit 0
fi
```

**Get the current hostnames for this container**
This is used for logging purposes at the end of this command.
```bash
# shellcheck disable=SC2207
hostnames=($(biphrost -b hostnames get "$containerid"))
```

**Disable `listen 443 ssl`**
Comment out this line in the configuration file, if it exists (it *should* exist).
```bash
sed -i 's/^\(\s*\)\(#\s*\)\?\(listen 443.*ssl.*;\)$/\1# \3/g' /etc/nginx/sites-available/"$containerid"
```

**Set `use_https` to `disabled`**
```bash
# shellcheck disable=SC2016
sed -i 's/^\(\s*\)\(#\s*\)\?set \$use_https .*;$/\1set \$use_https "disabled";/g' /etc/nginx/sites-available/"$containerid"
```

**Comment out the `ssl_*` directives**
```bash
sed -i 's/^\(\s*\)\(#\s*\)\?\(ssl_.*;\)$/\1# \3/g' /etc/nginx/sites-available/"$containerid"
```

**Comment out any `301` redirects**
Some older site configurations may have a block that looks like:
```
if ($https = "") {
    return 301 https://$server_name$request_uri;
}
```
...and this needs to be commented out if present:
```bash
perl -0777 -pi -e 's/\n(\h*)(if \(\$https = ""\) {)\h*\n\h*(return 301 https:\/\/\$server_name\$request_uri;)\h*\n\h*(})\h*/\n\1# \2\n\1#     \3\n\1# \4/' /etc/nginx/sites-available/"$containerid"
```

**Reload nginx**
```bash
nginx -t || fail "There was an error while updating the nginx configuration for $containerid"
service nginx restart
```

**Log the change**
```bash
echo "$(date +'%F')" "$(date +'%T')" "${hostnames[0]}" "SSL has been disabled for $containerid: ${hostnames[*]}"
```

