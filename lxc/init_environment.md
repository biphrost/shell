# Initialize a container

This must be run *after* the network is configured and up (because `apt upgrade` and `apt install ...` require it).

**Parameters**
* --label: the label (name) for the container to be inited
```bash
containerid="$(needopt label -m '^lxc[0-9]{4}$')"
```

**Set the timezone and locale**
This is already done in `init network`, but... that doesn't seem to survive a container restart? Hmmm.
We do this here because we want consistent timestamps in the setup log. This *should* be a fairly safe command to run before starting the log...
```bash
timedatectl set-timezone America/Los_Angeles
localedef -i en_US -f UTF-8 en_US.UTF-8
```

**Start the log**
```bash
echo "$(date +'%F')" "$(date +'%T')" "$containerid" "Initializing operating system environment"
```

**Update packages, install some common requirements**
This isn't an aggressive stripdown of preinstalled packages, but we can nuke a few that are especially large, unnecessary, or problematic.
* `exim4-base` was added to this list because the package managed to land in Debian repos with a problem and it doesn't seem to be required by anything else.
* `ssl_cert` was added to this list also because it landed in Debian repos with a problem, isn't required by anything else, and was causing `apt` operations to fail.
```bash
apt-get -y purge joe gcc-9-base libavahi* exim4-base ssl_cert >/dev/null 2>&1
apt-get -y autoremove >/dev/null 2>&1
echo "$(date +'%F')" "$(date +'%T')" "$containerid" "Removed cruft"
if apt-get -y update >/dev/null; then
     echo "$(date +'%F')" "$(date +'%T')" "$containerid" "Retrieved package updates"
fi
if apt-get -y upgrade >/dev/null; then
     echo "$(date +'%F')" "$(date +'%T')" "$containerid" "Installed package updates"
fi
if apt-get -y install apt-utils patch sudo rsync openssh-server git logrotate >/dev/null; then
     echo "$(date +'%F')" "$(date +'%T')" "$containerid" "Installed apt-utils, patch, sudo, rsync, sshd, git, and logrotate"
fi
```

**Configure the hostname**
```bash
if [ ! -s /etc/hostname ]; then
    echo "$containerid" | tee /etc/hostname >/dev/null
fi
hostname -F /etc/hostname
```

**Configure sshd**
```bash
# shellcheck disable=SC2086
sed -i 's/^#*\s*PermitRootLogin\s\+.*$/PermitRootLogin no\nAllowGroups '$containerid'/g' /etc/ssh/sshd_config
sed -i 's/^#*\s*X11Forwarding\s\+.*$/X11Forwarding no/g' /etc/ssh/sshd_config
sed -i 's/^#*\s*PasswordAuthentication\s\+.*$/PasswordAuthentication no/g' /etc/ssh/sshd_config
if ! sshd -t; then
    fail "$(date +'%F')" "$(date +'%T')" "$containerid" "There is an error in the sshd configuration"
fi
service ssh restart
```

**Set some defaults for the root account**
vim.basic has some problems in some terminal environments that you really don't want to have to troubleshoot as root.
```bash
update-alternatives --set editor /usr/bin/vim.basic
update-alternatives --set vi /usr/bin/vim.basic
```

**Create the LXC users group**
This is an unprivileged group that will be used for ssh users as well as some services.
```bash
if ! getent group lxcusers; then
    echo "$(date +'%F')" "$(date +'%T')" "$containerid" "Group \"lxcusers\" does not exist; creating it."
    addgroup --quiet lxcusers 2>&1 || fail "Error while creating \"lxcusers\" group"
fi
```
