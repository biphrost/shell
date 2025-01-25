# Configure Apache

This is a post-installation step that does some housekeeping for common Apache setups.

**Usage**
```
biphrost @<container-id> configure apache
```

**Sanity-check invocation**
```bash
myinvocation="configure apache"
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

**Make sure Apache is installed**
There's no point in doing anything further if Apache is not installed in this container. If it's not found, this is not considered an error.
**Note:** Weirdly, `grep -q...` seems to return an incorrect status code here. `>/dev/null` works as expected.
```bash
if ! dpkg -l | grep '^ii\s\+apache2\s\+' >/dev/null; then
    exit 0
fi
```

**Start the log**
```bash
echo "$(date +'%F')" "$(date +'%T')" "$containerid" "Configuring Apache on $(hostname)"
```

**Create an owner user for Apache's server root**
We need a generic user account to own the web directory. We already have `lxcusers` set up for the generic group, and other user accounts will be added to that as needed.
```bash
if ! getent passwd lxcuser >/dev/null; then
    echo "$(date +'%F')" "$(date +'%T')" "$(hostname)" "Creating \"lxcuser\" account for Apache"
    useradd -d /home/lxcuser -M -s /bin/false "lxcuser"
    passwd -d -l lxcuser >/dev/null
fi
usermod -a -G lxcusers lxcuser
```

**Pre-configure Apache's server root directory**
If Apache's been installed, then there's going to need to be a directory for storing and serving a web application, logs, etc.

Since all biphrost commands should be repeatable without side effects, we'll check for an existing directory under `/srv/www` and rename it if needed.

`echo -n "$..." | grep -c '^'` is used instead of `wc -l` because it turns out that `wc` is not reliable here: it returns `1` if there are no results and you don't use `-n` with `echo`, and it returns `0` if there is one result and you use `-n` with `echo`.

`0755` and `0644` are used for directory and file permissions here so that Apache can run as `www-data:www-data` and still have read access to everything. In a different sort of multi-user environment, we might want to change this so that Apache is running as the same group as the users, and use `0750` and `0640` instead; but in this case, I think we can assume that there's already minimal user access to the containers, and it's better to have Apache running under it's normal user and group.
```bash
if [ ! -d /srv/www/"$(hostname)" ]; then
    webdir="$(find /srv/www -mindepth 1 -maxdepth 1 -type d 2>/dev/null)"
    count="$(echo -n "$webdir" | grep -c '^')"
    if [ "$count" -eq 1 ]; then
        echo "$(date +'%F')" "$(date +'%T')" "$(hostname)" "Found website root at $webdir; moving it to /srv/www/$(hostname)"
        mv /srv/www/"$webdir" /srv/www/"$(hostname)"
        rm /etc/apache2/sites-enabled/* 2>/dev/null
        rm /etc/apache2/sites-available/* 2>/dev/null
    elif [ "$count" -gt 1 ]; then
        echo "$(date +'%F')" "$(date +'%T')" "$(hostname)" "Multiple website roots found; none of them will be moved"
    else
        echo "$(date +'%F')" "$(date +'%T')" "$(hostname)" "Creating new web server directories"
    fi
fi
mkdir -p /srv/www/"$(hostname)"/public_html
mkdir -p /srv/www/"$(hostname)"/logs
mkdir -p /srv/www/"$(hostname)"/tmp
chown lxcuser:lxcusers /srv/www/"$(hostname)"
chown -R lxcuser:lxcusers /srv/www/"$(hostname)"/public_html /srv/www/"$(hostname)"/tmp
chmod 0755 /srv/www
chmod 0755 /srv/www/"$(hostname)"
chmod 0755 /srv/www/"$(hostname)"/public_html
find /srv/www/"$(hostname)"/public_html -type d -exec chmod 0755 '{}' \;
find /srv/www/"$(hostname)"/public_html -type f -exec chmod 0644 '{}' \;
```

**Check for a PHP installation**
The next few steps are specific to sites using PHP with Apache. We'll need to know if it's php-fpm or CGI or something else, and what version is installed.
```bash
php_installations="$(dpkg -l | grep -oP '^ii\s+\Kphp[0-9]+(\.[0-9]+)*-(fpm|cgi)(?=\s)' | sort -r)"
php_version="$(echo "$php_installations" | grep -o '[0-9]\+\(\.[0-9]\+\)' | head -n 1)"
if echo "$php_installations" | grep "$php_version" | grep 'fpm'; then
    php_installed="fpm"
elif echo "$php_installations" | grep "$php_version" | grep 'cgi'; then
    php_installed="cgi"
else
    php_installed=""
fi
```

**Generate a php.ini configuration file.**
If PHP is also installed, then generate a `php.ini` starter configuration. Note that the `display_errors = off` line is appropriate for production sites but may not be desirable for dev sites.
```bash
if [ "$php_installed" != "" ]; then
cat <<'EOF' | sed "s/\\\$site_address/$(hostname)/g" | tee /srv/www/"$(hostname)"/php.ini >/dev/null
expose_php          = Off
open_basedir        = "/srv/www/$site_address/public_html/:/srv/www/$site_address/tmp/:/srv/www/$site_address/localenv.php"
upload_tmp_dir      = "/srv/www/$site_address/tmp/"
upload_max_filesize = 50M
post_max_size       = 60M
auto_prepend_file   = "/srv/www/$site_address/localenv.php"
display_errors      = off
EOF
fi
```

**Create a file that fixes common PHP environment issues**
* This file uses the `auto_prepend_file` option in the `php.ini` configuration above to load after Apache has invoked PHP but before any application code is run.
* Applications installed in proxied environments, where the proxying server handles the https connection to the client and then creates an http connection to the application, will incorrectly behave as though they are running over http instead of https. This can cause some problems, including redirect loops to incorrect canonical urls. It would be nice if this could be fixed in the Apache site configuration, but Apache doesn't seem to support setting the REQUEST_SCHEME environment variable (?).
```bash
if [ "$php_installed" != "" ]; then
cat <<'EOF' | sudo tee "/srv/www/$(hostname)/localenv.php" >/dev/null
<?php

if ( isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https' ) {
    $_SERVER['HTTPS'] = 'on';
    $_SERVER['REQUEST_SCHEME'] = 'https';
    $_ENV['REQUEST_SCHEME'] = 'https';
}
EOF
fi
```

**Create the Apache site config file.**
The `LogFormat` option here properly records the remoteip for clients reaching Apache through a proxy, as long as the earlier `remoteip` configuration step is completed.
```bash
handler=""
if [ "$php_installed" = "fpm" ]; then
    handler="proxy:unix:/var/run/php/php$php_version-fpm_$(hostname).sock|fcgi://localhost/"
fi
cat <<'EOF' | sed "s#\\\$handler#$handler#g" | sed "s/\\\$site_address/$(hostname)/g" | tee /etc/apache2/sites-available/"$(hostname)".conf >/dev/null
<VirtualHost *:80 *:443>
    ServerName $site_address
    # ServerAlias

    RewriteEngine On

    # Force SSL for this site if SSL is available.
    <IfFile "/etc/letsencrypt/certs/default/fullchain.pem">
        RewriteCond %{SERVER_PORT} !443
        RewriteRule ^(.*)$ https://%{HTTP_HOST}$1 [R,L]
    </IfFile>

    DocumentRoot /srv/www/$site_address/public_html/

    # Block accesses to .git files and directories.
    RewriteRule ^(.*/)?\.git(/.*)?     - [F,L]
    RewriteRule ^(.*/)?\.gitignore     - [F,L]
    # And composer.
    RewriteRule ^(.*/)?composer.json.* - [F,L]
    RewriteRule ^(.*/)?composer.lock.* - [F,L]
    
    <Directory /srv/www/$site_address/public_html>
        AllowOverride all
        Options -Indexes

        # Apache 2.x
        <IfModule !mod_authz_core.c>
            Order allow,deny
            Allow from all
        </IfModule>

        # Apache 2.4
        <IfModule mod_authz_core.c>
            Require all granted
        </IfModule>
    </Directory>

    <IfFile "/etc/letsencrypt/certs/default/fullchain.pem">
        <If "%{SERVER_PORT} -eq 443">
            SSLEngine on
            SSLCertificateFile /etc/letsencrypt/certs/default/fullchain.pem
            SSLCertificateKeyFile /etc/letsencrypt/certs/default/privkey.pem
        </If>
    </IfFile>

    <IfFile "/usr/bin/php">
        <FilesMatch "\.(php|html|phtml)$">
            SetHandler "$handler"
        </FilesMatch>
    </IfFile>

    SetEnv TMPDIR /srv/www/$site_address/tmp

    LogFormat "%a %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\"" custom
    ErrorLog /srv/www/$site_address/logs/error.log
    CustomLog /srv/www/$site_address/logs/access.log custom
    Alias /tmp /srv/www/$site_address/tmp
</VirtualHost>
EOF
```

**Update server aliases**
Extract a list of hostnames from `/etc/hosts`, deduplicate them, remove the primary hostname for the container, and, if any are left, then add them to `ServerAlias` in the Apache config file generated above.
```bash
aliases="$(grep -oP '(?<=\W)([a-zA-Z0-9-]+\.)+[a-zA-Z]+(?=\W)' /etc/hosts | sort -u | grep -v "^$(hostname)\$")"
alias_count="$(echo -n "$aliases" | grep -c '^')"
if [ "$alias_count" -gt 0 ]; then
    sed -i -e 's/^\(\s*\)\(#\s*\)\?ServerAlias.*/\1ServerAlias '"$(echo "$aliases" | xargs)"'/g' /etc/apache2/sites-available/"$(hostname)".conf
fi
```

**Enable the site config and restart Apache**
```bash
/usr/sbin/a2ensite "$(hostname)" >/dev/null
/usr/sbin/apachectl graceful
```

**Finish the log**
```bash
echo "$(date +'%F')" "$(date +'%T')" "$containerid" "Apache configuration complete."
```
