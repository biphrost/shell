# Configure PHP

This is a post-installation step that does some housekeeping for common PHP setups (mostly php-fpm).

**Usage**
```
biphrost @<container-id> configure php
```

**Sanity-check invocation**
```bash
myinvocation="configure php"
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

**Examine current PHP installations**
There's no point in doing anything further if PHP is not installed in this container. If it's not found, this is not considered an error. If it is found, we'll need to know which version and whether it's php-fpm or php-cgi.
```bash
php_installations="$(dpkg -l | grep -oP '^ii\s+\Kphp[0-9]+(\.[0-9]+)*-(fpm|cgi)(?=\s)' | sort -r)"
php_version="$(echo "$php_installations" | grep -o '[0-9]\+\(\.[0-9]\+\)' | head -n 1)"
if echo "$php_installations" | grep "$php_version" | grep -q 'fpm'; then
    php_installed="fpm"
elif echo "$php_installations" | grep "$php_version" | grep -q 'cgi'; then
    php_installed="cgi"
else
    exit 0
fi
```

**Start the log**
```bash
echo "$(date +'%F')" "$(date +'%T')" "$containerid" "Configuring PHP $php_version ($php_installed) on $(hostname)"
```

**Create a php-fpm pool config file and configure it to use the latest available version of php.**
If this installation is using php-fpm, then this pool config file is required.
```bash
if [ "$php_installed" = "fpm" ]; then
    if [ ! -f /etc/php/"$php_version"/fpm/pool.d/www.conf ]; then
        # There should be a preinstalled php-fpm pool config file here. Something is wrong.
        fail "No php-fpm config was found at /etc/php/$php_version/fpm/pool.d/www.conf, configuration cannot be completed"
    fi
    echo "$(date +'%F')" "$(date +'%T')" "$containerid" "Creating php-fpm pool config file for $(hostname)"
    poolconfig="/etc/php/$php_version/fpm/pool.d/$(hostname).conf"
    mv /etc/php/"$php_version"/fpm/pool.d/www.conf "$poolconfig"
    if [ ! -f "$poolconfig" ]; then
        fail "Failed to copy pool config file to $poolconfig; aborting."
    fi
    sudo sed -i -e "s/^\\[www\\]$/\\[$(hostname)\\]/" "$poolconfig"
    sudo sed -i -e "s/^group =.*$/group = lxcusers/" "$poolconfig"
    sudo sed -i -e "s:^listen =.*$:listen = /var/run/php/php${php_version}-fpm_$(hostname).sock:" "$poolconfig"
    sudo sed -i -e 's/^;\\?catch_workers_output =.*$/catch_workers_output = yes/' "$poolconfig"
    sudo sed -i -e "s:^;\\?php_admin_value\\[error_log\\] =.*$:php_admin_value[error_log] = /srv/www/$(hostname)/logs/error.log:" "$poolconfig"
    sudo sed -i -e "s/^;\\?php_admin_flag\\[log_errors\\] =.*$/php_admin_flag[log_errors] = on/" "$poolconfig"
    sudo sed -i -e "s/^;\\?security\\.limit_extensions =.*$/security.limit_extensions = .html .phtml .php/" "$poolconfig"
fi
```

**Create the systemd service file.**
```bash
if [ "$php_installed" = "fpm" ]; then
    echo "$(date +'%F')" "$(date +'%T')" "$containerid" "Creating the systemd service file"
cat <<'EOF' | sed "s/\\\$phpversion/$php_version/g" | sed "s/\\\$site_address/$(hostname)/g" | sed "s:\\\$poolconfig:$poolconfig:g" | tee /etc/systemd/system/php-"$(hostname)".service >/dev/null
[Unit]
Description=The PHP FastCGI Process Manager
After=network.target

[Service]
Type=notify
PIDFile=/var/run/php/$site_address.pid
ExecStartPre=
ExecStart=/usr/sbin/php-fpm$phpversion --nodaemonize --fpm-config $poolconfig --php-ini /srv/www/$site_address/php.ini 
ExecReload=/bin/kill -USR2 $MAINPID
ExecStop=/bin/kill -s QUIT $MAINPID
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    /bin/systemctl -q enable /etc/systemd/system/php-"$(hostname)".service >/dev/null
    /bin/systemctl -q daemon-reload
fi
```

**Start the php-fpm process.**
```bash
if [ "$php_installed" = "fpm" ]; then
    echo "$(date +'%F')" "$(date +'%T')" "$containerid" "Starting php-fpm for $(hostname)"
    /usr/sbin/service php-"$(hostname)" start
fi
```

**Finish the log**
```bash
echo "$(date +'%F')" "$(date +'%T')" "$containerid" "PHP configuration complete."
```
