# Install and configure Apache

**Usage**
```
biphrost @<container-id> install apache
```

**Sanity-check invocation**
```bash
myinvocation="install apache"
if [ "${*:1:2}" != "$myinvocation" ]; then
    fail "[$myinvocation]: Invalid invocation"
fi
shift; shift
```

**Get the container label or hostname**
Used for logging.
```bash
containerid="$(cat /root/.label 2>/dev/null <(hostname) | head -n 1)"
```

**Start the log**
```bash
echo "$(date +'%F')" "$(date +'%T')" "$containerid" "Installing Apache"
```

**Create the `/srv/www` directory**
```bash
mkdir -p /srv/www
```

**Install Apache packages**
...and also `patch`, because it's required for a config file update below.
```bash
DEBIAN_FRONTEND=noninteractive apt-get -qy install apache2 libapache2-mod-security2 patch cron >/dev/null
```

**Make sure Apache is using mpm_event and other required modules are enabled.**
```bash
a2enmod mpm_event rewrite ssl proxy_fcgi >/dev/null 2>&1
```

**Run Apache as `www-data:www-data`**
Apache *shouldn't* need to run as the same user or group as any of the files in a web root, but this note is left here in case that needs to be changed in the future.
```bash
sed -i -e 's/^\s*#\?\s*export\s\+APACHE_RUN_USER=.*/export APACHE_RUN_USER=www-data/g' /etc/apache2/envvars
sed -i -e 's/^\s*#\?\s*export\s\+APACHE_RUN_GROUP=.*/export APACHE_RUN_GROUP=www-data/g' /etc/apache2/envvars
```

**Enable support for `index.shtml`**
This is super uncommon anymore but occasionally some software will try to use it and tracking this down again when it breaks is annoying.
```
sed -i '/DirectoryIndex/ s/$/ index.shtml/' /etc/apache2/mods-available/dir.conf
```

**Make Apache a little quieter.**
By default, Apache announces some operating system and environmental information that really doesn't need to be announced. This config update disables that behavior. It doesn't make the server more secure against a dedicated adversary but it does prevent the server's software version information from getting indexed by bots.
```bash
cat <<'EOF' | tee /etc/apache2/conf-available/httpd.conf >/dev/null
<IfModule mpm_event_module>
    KeepAlive On
    KeepAliveTimeout 2
    MaxKeepAliveRequests 500

    ThreadsPerChild 20
    ServerLimit 15
    MaxRequestWorkers 300
    MaxSpareThreads 200
    MaxConnectionsPerChild 10000
</IfModule>

<Directory /srv/>  
    Options Indexes FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>

ServerTokens Prod
ServerSignature Off
EOF
a2enconf httpd >/dev/null 2>&1
```

**Ensure that deflate is enabled**
```bash
a2enmod deflate >/dev/null 2>&1
```

**If this is inside a container, then set up mod_remoteip**
Apache servers running inside containerized hosts should assume that the upstream host is acting as a proxy for web traffic. Without `mod_remoteip`, containers will always see the wrong IP address for the request.
```bash
cat <<'EOF' | tee /etc/apache2/conf-available/remoteip.conf >/dev/null
RemoteIPHeader X-Forwarded-For
RemoteIPTrustedProxy 10.0.0.1
EOF
a2enconf remoteip >/dev/null 2>&1
a2enmod remoteip >/dev/null 2>&1
```

**Configure cron to kick Apache every night**
Apache has some gradual, long-term memory leaks that can cause strange behaviors on hosts with moderate traffic and long uptimes.
```bash
EDITOR="cat" crontab -e 2>/dev/null | cat - <(echo; echo '0 1 * * * /usr/sbin/apachectl graceful') | crontab -
```

**Set up logrotate**
You probably don't want the access.log and error.log files for all your sites to just grow and grow and grow. Hopefully you're doing offsite backups too, and unrotated log files can make a small mess of that. Let's tell logrotate to handle the log files for hosted sites:
```bash
cat <<'EOF' | tee /etc/logrotate.d/websites >/dev/null
/srv/www/*/logs/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    dateext
    notifempty
    create 600 root root
    sharedscripts
    postrotate
        service apache2 graceful >/dev/null
    endscript
    prerotate
        if [ -d /etc/logrotate.d/httpd-prerotate ]; then
            run-parts /etc/logrotate.d/httpd-prerotate
        fi
    endscript
}
EOF
```

**Post-install cleanup**
Some default files should be removed because they are unused for this configuration and can cause confusion.
```bash
rm -f /etc/apache2/sites-enabled/000-default.conf
rm -f /etc/apache2/sites-available/000-default.conf
rm -f /etc/apache2/sites-enabled/default-ssl.conf
rm -f /etc/apache2/sites-available/default-ssl.conf
```

**Restart Apache**
```bash
service apache2 restart >/dev/null 2>&1 || fail "Apache could not be restarted; a sysop needs to troubleshoot the Apache configuration."
```

**Finish the log**
```bash
echo "$(date +'%F')" "$(date +'%T')" "$containerid" "Apache installation complete."
```
