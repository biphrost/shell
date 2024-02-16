# Initialize a container

This must be run *after* the network is configured and up (because `apt upgrade` and `apt install ...` require it).

**Parameters**
* --label: the label (name) for the container to be inited
```bash
label="$(needopt label -m '^lxc[0-9]{4}$')"
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
echo "$(date +'%T')" "$(date +'%F')" "Initializing operating system environment in $label"
```

**Update packages, install some common requirements**
```bash
if apt-get -y purge joe gcc-9-base libavahi* >/dev/null && apt-get -y autoremove >/dev/null; then
    echo "$(date +'%T') Removed cruft"
fi
if apt-get -y update >/dev/null; then
    echo "$(date +'%T') Retrieved package updates"
fi
if apt-get -y upgrade >/dev/null; then
    echo "$(date +'%T') Installed package updates"
fi
if apt-get -y install apt-utils patch sudo rsync openssh-server git logrotate >/dev/null; then
    echo "$(date +'%T') Installed apt-utils, patch, sudo, rsync, sshd, git, and logrotate"
fi
```

**Configure the hostname**
```bash
echo "$label" > /etc/hostname
hostname -F /etc/hostname
```

**Configure sshd**
```bash
# shellcheck disable=SC2086
sed -i 's/^#*\s*PermitRootLogin\s\+.*$/PermitRootLogin no\nAllowGroups '$label'/g' /etc/ssh/sshd_config
sed -i 's/^#*\s*X11Forwarding\s\+.*$/X11Forwarding no/g' /etc/ssh/sshd_config
sed -i 's/^#*\s*PasswordAuthentication\s\+.*$/PasswordAuthentication no/g' /etc/ssh/sshd_config
if ! sshd -t; then
    fail "$(date +'%T') Error updating sshd configuration in $label"
fi
service ssh restart
```

**Set some defaults for the root account**
vim.basic has some problems in some terminal environments that you really don't want to have to troubleshoot as root.
```bash
update-alternatives --set editor /usr/bin/vim.basic
update-alternatives --set vi /usr/bin/vim.basic
```

**Create the LXC user inside the container**
This is done so that applications installed inside the container have a safe, valid, unprivileged, default user account. When a user connects to their container over ssh, they will be dropped in to this user account.
```bash
adduser --quiet --disabled-password --gecos '' "$label" >/dev/null
mkdir -p "/home/$label/.ssh"
touch "/home/$label/.ssh/authorized_keys"
chown -R "$label":"$label" "/home/$label/.ssh"
chmod 0750 "/home/$label/.ssh"
chmod 0640 "/home/$label/.ssh/authorized_keys"
```
