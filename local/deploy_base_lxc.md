# Deploy a new LXC container (with optional installations)

This command creates a new container and preinstalls a selection of software depending on the options passed to it. It does not install end-user applications, but it does install the server components that those applications would require. It does not do any application-specific configuration, but it does preconfigure some of the server components where it makes sense to do so (for example, configuring Apache and PHP to talk to each other if they're both installed).

**Usage**
```
biphrost deploy base lxc --hostnames "<primaryhostname> [hostname] [hostname]..." [--apache] [--mysql] [--php 7.3]
```

**Sanity-check invocation**
```bash
myinvocation="deploy base lxc"
if [ "${*:1:3}" != "$myinvocation" ]; then
    fail "[$myinvocation]: Invalid invocation"
fi
shift; shift; shift
```

**Load required parameters**
```bash
hostnames="$(needopt "hostnames")"
```

**Create the new LXC**
```bash
# shellcheck disable=SC2086
biphrost -b new lxc --hostnames "$hostnames"
```

**Retrieve the ID of the newly-created container**
Beware of the potential for problems with parallel execution here. The API will need to take precautions when assigning simultaneous queued tasks to a target server.
```bash
containerid="$(find /home/*/.config/lxc -maxdepth 1 -type d -printf '%CY.%Cj %p\n' | sort | tail -n 1 | grep -oP '(?<=/home/)lxc[0-9]{4}(?=/)')"
if [ -z "$containerid" ]; then
    fail "Could not get a container ID?! Sysop intervention is required."
fi
```

**Configure the hostnames for this container**
Hostname configuration has already happened inside the container, but this step generates the nginx configuration for the container on the bastion host.
```bash
# shellcheck disable=SC2086
biphrost -b hostnames set "$containerid" $hostnames
```

**Optionally install Apache**
```bash
if loadopt "apache"; then
    biphrost -b @"$containerid" install apache
fi
```

**Optionally install PHP**
The `php` option can specify the version of PHP to be installed; otherwise, it defaults to current LTS.
```bash
if loadopt "php"; then
    phpversion="$(loadopt "php")"
    if [ -z "$phpversion" ]; then
        phpversion="8.3"
    fi
    biphrost -b @"$containerid" install php --version "$phpversion"
fi
```

**Optionally install MySQL**
This, of course, actually installs MariaDB. The configuration step adjusts the database server configuration for the resources available to the container.
```bash
if loadopt "mysql"; then
    biphrost -b @"$containerid" install mysql
fi
```

**Configure everything**
With all server software installations complete, we can now run any configuration steps as needed. Each configuration step will examine the server environment and coordinate with other server packages as needed.
Order matters here, because some components will have trouble starting services that depend on other components.
```bash
if loadopt "mysql"; then
    biphrost -b @"$containerid" configure mysql
fi
if loadopt "php"; then
    biphrost -b @"$containerid" configure php
fi
if loadopt "apache"; then
    biphrost -b @"$containerid" configure apache
fi
```

**Done**
```bash
echo "$(date +'%F')" "$(date +'%T')" "$(hostname)" "New LXC deployment has been completed."
```