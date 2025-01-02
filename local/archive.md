# Archive and delete an LXC container

**Warning:** This cannot be undone. Some of the container's contents and configuration are saved, but restoring it will be a manual process for the foreseeable future.

**TODO:** Archived containers should get auto-deleted after a little while.

**Parameters**
* --confirm: "y" to auto-confirm this (required for non-interactive sessions)
```bash
confirmation="$(loadopt "confirm")"
```

**Sanity-check invocation**
```bash
myinvocation="archive"
if [ "${*:1:1}" != "$myinvocation" ]; then
    fail "[$myinvocation]: Invalid invocation"
fi
shift
```

Get the name of the container to be deleted. Should be passed as the next argument directly after the name of the script.
```bash
if [ "$#" -lt 1 ]; then
    fail "No container name given"
	exit 1
fi
lxcname="$1"
shift
```

**Make sure this is running on an lxchost**
```bash
if ! command -v lxc-destroy >/dev/null; then
    fail "lxc-destroy is not available; is this an LXC host?"
	exit 1
fi
```

**Make sure the container name matches exactly one container**
This script will continue even if a matching container isn't found so that aborted container deployments can be cleaned up.
```bash
matches="$(sudo lxc-ls 2>/dev/null | grep -cP "\\b$lxcname\\b")"
if [ "$matches" -eq 0 ]; then
    fail "$lxcname: not found"
    exit 1
elif [ "$matches" -gt 1 ]; then
	fail "$lxcname is ambiguous and matches multiple containers"
	exit 1
fi
```

**Ask the user for confirmation**
```bash
if [ "$confirmation" != "y" ]; then
	if ! ask "Really destroy $lxcname?"; then
		fail "User canceled"
		exit 1
	fi
fi

echo "Deleting $lxcname!"
```

**Delete the container's knockd entry**
These lines delete a matching knockd entry for this container, and then delete a trailing blank line from the config file if one exists. sed doesn't seem to want to do this in a single operation without the sed command getting ugly.
```bash
sed -i -e "/^\\[$lxcname\\]\$/,+5d;" /etc/knockd.conf
sed -i -e '${/^$/d;}' /etc/knockd.conf
service knockd restart
```

**Get a label for the container**
This must be done before the container's nginx configuration is deleted.  `archive_label` will grab the first hostname available for the container *or* will use the container's name if a hostname is not available.
```bash
archive_label="$(biphrost -b hostnames get "$lxcname" 2>/dev/null | cat - <(echo "$lxcname") | head -n 1)"
```

**Delete the container's nginx configuration**
This will stop any web traffic to the container.
```bash
find /etc/nginx/sites-*/"$lxcname" -type l,f -delete >/dev/null 2>&1 && service nginx reload
```

**Delete the container's hosts file entry**
(If it exists)
```bash
sed -i -e "/^[0-9\\.]\\+\\s\\+$lxcname\$/d" /etc/hosts
```

**Disable the lxc user's service file**
```bash
if id -u "$lxcname" >/dev/null; then
    sudo -u "$lxcname" XDG_RUNTIME_DIR="/run/user/$(sudo -u "$lxcname" sh -c 'id -u')" sh -c "systemctl --user disable $lxcname-autostart"
fi
loginctl disable-linger "$lxcname" 2>/dev/null
```

**If the container is not running, then try starting it**
```bash
[ "$(biphrost -b status "$lxcname")" == 'RUNNING' ] || biphrost -b restart "$lxcname" >/dev/null 2>&1
```

**Make a fresh copy of the databases in the container**
When done, stop the container.
```bash
if [ "$(sudo biphrost -b status "$lxcname")" == 'RUNNING' ]; then
    biphrost @"$lxcname" backup dbs
    biphrost -b stop "$lxcname" >/dev/null 2>&1 || fail "Could not stop $lxcname"
fi
```

**Save selected files from the container's filesystem**
The most recent backup is saved for each database (hopefully, the backup was created just a moment ago), along with `public_html`.
In the code below, `$db` will look something like `domain_com` and `$archive` will look something like `20240319-120000.sql.tar.gz`.
```bash
timestamp="$(date +'%Y%m%d-%H%M%S')"
mkdir -p /srv/archive/"$archive_label"/"$timestamp"
prefix="/srv/lxc/$lxcname/rootfs"
while IFS= read -r -d '' db; do
    # The `find` command does not support a "most-recent-first" output sort without
    # a lot of additional faffing about; shellcheck is simply wrong here.
    # shellcheck disable=SC2012
    archive="$(ls -t "$db" | head -n 1)"
    rsync -a --chown=root:root "$prefix/srv/db/$db/$archive" /srv/archive/"$archive_label"/"$timestamp"/"$db"_"$archive"
done < <(find "$prefix"/srv/db -maxdepth 1 -mindepth 1 -type d -printf '%f\0')
while IFS= read -r -d '' site; do
    rsync -a --chown=root:root -R "$prefix/./srv/www/$site/public_html" /srv/archive/"$archive_label"/"$timestamp"/
    rsync -a --chown=root:root -R "$prefix/./srv/www/$site/php.ini" /srv/archive/"$archive_label"/"$timestamp"/
done < <(find "$prefix"/srv/www -maxdepth 1 -mindepth 1 -type d -printf '%f\0')
rsync -a --chown=root:root -R "$prefix/./home" /srv/archive/"$archive_label"/"$timestamp"/
rsync -a --chown=root:root -R "$prefix/./etc" /srv/archive/"$archive_label"/"$timestamp"/
```

**Destroy the container**
```bash
if [ "$(biphrost -b status "$lxcname")" != "NOTFOUND" ]; then
    lxc-destroy "$lxcname"
fi
```

**Delete the user and their home directory**
```bash
if id -u "$lxcname" >/dev/null; then
    userdel -r "$lxcname"
fi
```

**Make sure related directories are deleted**
This is risky. `sudo find /dir -maxdepth 1 -mindepth 1 -type d -iname "$lxcname" -delete` would be nice but `find` won't delete non-empty directories.
```bash
if [ -n "$lxcname" ] && [[ $lxcname =~ lxc[0-9]{4} ]]; then
    if [ -d "/home/$lxcname" ]; then
        find "/home/$lxcname" -delete
    fi
    if [ -d "/srv/lxc/$lxcname" ]; then
        find "/srv/lxc/$lxcname" -delete
    fi
fi
```