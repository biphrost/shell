# Enable SSL service on a container

This enables access to port 443 and SSL connections for a given container's hostnames.

**Usage**
```
biphrost hostnames ssl enable <container-id>
```

**Sanity-check invocation**
```bash
myinvocation="ssl enable"
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
If an nginx configuration isn't found, `ssl disable` doesn't consider this an error, but this command does -- disabling ssl for a container that isn't already receiving traffic won't have any effect, but here we're trying to enable ssl, which is incompatible with a broken or missing configuration, so that's an error.
```bash
if [ ! -f /etc/nginx/sites-available/"$containerid" ]; then
    fail "No nginx configuration found for $containerid"
fi
```

**Get the current hostnames for this container**
This will be used for a sanity check on the container's SSL certificates as well as for logging purposes at the end of the command. These hostnames are retrieved from the container's current nginx configuration.
```bash
# shellcheck disable=SC2207
hostnames=($(biphrost -b hostnames get "$containerid"))
```

**Sanity-check the container's SSL certificate**
If the certificate doesn't already exist, or the hostnames in it don't match the current nginx configuration, or the certificate is old, then try running `ssl renew...` and re-check before failing.
```bash
attempts=1
while :; do
    if [ -f /home/"$containerid"/ssl/hostnames ]; then
        if  [ "$(find /home/"$containerid"/ssl/hostnames -type f -newermt "30 days ago" 2>&1)" = "/home/$containerid/ssl/hostnames" ]; then
            if [ "${hostnames[*]}" = "$(cat /home/"$containerid"/ssl/hostnames)" ]; then
                break
            fi
        fi
    else
        if [ $attempts -lt 2 ]; then
            attempts=$((attempts + 1))
            biphrost -b ssl renew "$containerid"
        else
            fail "SSL can not be enabled because the certificate's hostnames don't match the container's configuration"
        fi
    fi
done
```

**Enable `listen 443 ssl`**
Un-comment out this line in the configuration file, if it exists (it *should* exist).
```bash
sed -i 's/^\(\s*\)\(#\s*\)\?\(listen 443.*ssl.*;\)$/\1\3/g' /etc/nginx/sites-available/"$containerid"
```

**Set `use_https` to `enabled`**
```bash
# shellcheck disable=SC2016
sed -i 's/^\(\s*\)\(#\s*\)\?set \$use_https .*;$/\1set \$use_https "enabled";/g' /etc/nginx/sites-available/"$containerid"
```

**Enable the `ssl_*` directives**
```bash
sed -i 's/^\(\s*\)\(#\s*\)\?\(ssl_.*;\)$/\1\3/g' /etc/nginx/sites-available/"$containerid"
```

**Un-comment out any `301` redirects**
Some older site configurations may have a block that looks like:
```
if ($https = "") {
    return 301 https://$server_name$request_uri;
}
```
...and this needs to be re-enabled if present:
```bash
perl -0777 -pi -e 's/\n(\h*)(#\h*)?(if \(\$https = ""\) {)\h*\n\h*(#\h*)?(return 301 https:\/\/\$server_name\$request_uri;)\h*\n\h*(#\h*)?(})\h*/\n\1\3\n\1    \5\n\1\7/' /etc/nginx/sites-available/"$containerid"
```

**Reload nginx**
```bash
nginx -t || fail "There was an error while updating the nginx configuration for $containerid"
service nginx restart
```

**Log the change**
```bash
echo "$(date +'%F')" "$(date +'%T')" "${hostnames[0]}" "SSL has been enabled for $containerid: ${hostnames[*]}"
```

