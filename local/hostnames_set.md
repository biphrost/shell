# Update the hostnames for a container

Updates local (lxc host) configuration with new hostnames for a container, and then invokes a `set hostnames` command to updat ethe configuration inside the container.

**Usage**
```
biphrost hostnames set <container-id> <hostname> <hostname> ...
```

**Notes:**
* Primary hostname is the first hostname in the list (affects names listed in ssl cert)
* Need to update the container's `/etc/hosts`
* ...and the container's `hostname`
* An SSL cert update should *not* be triggered here; users need to be able to add hostnames that may not yet be updated in DNS

**TODO**
* Pre-check for hostname collisions on the server

**Sanity-check invocation**
```bash
myinvocation="hostnames set"
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

**Get the hostnames and validate them**
Ensure none of the hostnames match a "biphrost" pattern (that would be naughty). Any invalid hostnames will cause the entire operation to fail. The first hostname in the list becomes the default hostname.
```bash
hostnames="$*"
primary_hostname=""
for hostname in $hostnames; do
    if ! [[ "$hostname" =~ ^([A-Za-z0-9-]+\.)+[A-Za-z0-9-]+$ ]]; then
        fail "Invalid hostname: $hostname does not look like a routable network hostname"
    fi
    #if [[ "$hostname" =~ "biphrost" ]]; then
    #    fail "Invalid hostname: $hostname (cannot contain 'biphrost')"
    #fi
    if [ -z "$primary_hostname" ]; then
        primary_hostname="$hostname"
    fi
done
if [ -z "$primary_hostname" ]; then
    fail "No valid hostnames were given"
fi
```

**Update the hostnames inside the container**
```bash
# shellcheck disable=SC2086
biphrost -b @"$containerid" set hostnames $hostnames
```

**Update the container's nginx configuration**
I *hate* the way this part is structured:
```
# listen 443 ssl;
set $use_https "disabled";
```
...because ideally this should all be controlled by just one line, and the way this is set up allows for the possibility of misconfigured ssl. But, in nginx's typically crippled configuration language, I can't put `listen` inside an `if` block, and I can't find a way to toggle some logic by the `listen` directive.

Also, you can't have `ssl_certificate` directives in `if` blocks either, so... we just toggle this by commenting and un-commenting lines, and it's SO GROSS UGH.

Likewise, there's a minor trap in:
```
set $https_redirect "$use_https$https";
if ($https_redirect = "enabled") {
```
...where someone might not realize that this works because `$https` is `""` when a connection is not using SSL. And this crude hack exists because compound `if` statements and nested `if` statements are both disallowed.

I could almost turn the whole thing inside-out with some `include` statements and ssl-conf files, but then nginx's wacky rules about where variables can and can't be used are going to become really important, and it's just going to get messy quickly.

Trying to do what should be fairly straightforward things in nginx always makes me consider dropping it altogether and going back to Apache for this use case. Do the saved cycles really matter as much as all the time I've burned trying to find workarounds for dumb limitations in nginx configs?

```bash
rm -f /etc/nginx/sites-enabled/"$containerid"
rm -f /etc/nginx/sites-available/"$containerid"
cat <<'EOF' | tee /etc/nginx/sites-available/"$containerid" >/dev/null
server {

    set $container_id "$$containerid";
    set $use_https    "disabled";

    server_name $$hostnames;
    listen 80;

    # listen 443 ssl;
    # ssl_certificate     /home/$container_id/ssl/$$primary_hostname/fullchain.pem;
    # ssl_certificate_key /home/$container_id/ssl/$$primary_hostname/privkey.pem;
    # ssl_protocols       TLSv1.2;

    access_log /var/log/nginx/access.log normal;

    location ^~ /.well-known/acme-challenge/ {
        alias /home/$container_id/acme-challenge/;
    }

    location = /.well-known/biphrost-domain-verification {
        alias /home/$container_id/.biphrost-domain-verification;
    }

    location / {

        set $https_redirect "$use_https$https";
        if ($https_redirect = "enabled") {
            return 301 https://$server_name$request_uri;
        }

        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_pass http://$container_id;
        client_max_body_size 0;

        location ~* \.(css|gif|ico|jpg|js|png|svg|swf|txt|woff)$ {
            proxy_cache static;
            proxy_pass http://$container_id;
        }
    }
}
EOF
# shellcheck disable=SC2016
sed -i 's/\$\$containerid/'"$containerid"'/g' /etc/nginx/sites-available/"$containerid"
# shellcheck disable=SC2016
sed -i 's/\$\$hostnames/'"$hostnames"'/g' /etc/nginx/sites-available/"$containerid"
# shellcheck disable=SC2016
sed -i 's/\$\$primary_hostname/'"$primary_hostname"'/g' /etc/nginx/sites-available/"$containerid"
ln -s /etc/nginx/sites-available/"$containerid" /etc/nginx/sites-enabled/"$containerid"
```

**Test the configuration and reload**
If the configuration test fails, then the newly-created configuration for this container is disabled (but not deleted) so that a subsequent attempt to reload nginx won't be complicated by this broken config.
```bash
if ! nginx -t >/dev/null; then
    rm -f /etc/nginx/sites-enabled/"$containerid"
    fail "nginx could not be restarted because there is an error in its configuration"
else
    service nginx restart
    echo "$(date +'%F')" "$(date +'%T')" "$(hostname)" "Hostname configuration complete for $containerid: $hostnames"
fi
```


