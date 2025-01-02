# Add a user account to a container

**Usage**
```
biphrost @<container-id> user add <username>
```

**Parameters**
* `username` (required): the username for the new user account.

**Sanity-check invocation**
```bash
myinvocation="user add"
if [ "${*:1:2}" != "$myinvocation" ]; then
    fail "[$myinvocation]: Invalid invocation"
fi
shift; shift
```

**Get the username to be added**
```bash
if [ "$#" -lt 1 ]; then
    fail "No username specified"
fi
username="$1"
shift
```

**Get the container label or hostname**
Used for logging.
```bash
containerid="$(cat /root/.label 2>/dev/null <(hostname) | head -n 1)"
```

**Start the log**
```bash
echo "$(date +'%F')" "$(date +'%T')" "$containerid" "Adding user \"$username\" to $(hostname)"
```

**Make sure the `lxcusers` group exists**
All users are members of `lxcusers` in these environments. (Each container is considered "shared" by all users that are given access to it.)
```bash
if ! getent group lxcusers >/dev/null; then
    echo "$(date +'%F')" "$(date +'%T')" "$containerid" "Group \"lxcusers\" does not exist; creating it."
    addgroup --quiet lxcusers 2>&1 || fail "Error while creating \"lxcusers\" group"
fi
```

**Create the user account**
No ssh keys are automatically added (so the user does not get ssh access by default), but everything is otherwise set up for it.
```bash
if getent passwd "$username" >/dev/null; then
    echo "$(date +'%F')" "$(date +'%T')" "$containerid" "User \"$username\" already exists; no further changes will be made."
else
    adduser --quiet --disabled-password --gecos '' "$username" 2>&1 || fail "Error while creating user \"$username\""
    usermod -a -G lxcusers "$username"
    mkdir -p "/home/$username/.ssh"
    touch "/home/$username/.ssh/authorized_keys"
    chown -R "$username":"$username" "/home/$username/.ssh"
    chmod 0700 "/home/$username/.ssh"
    chmod 0600 "/home/$username/.ssh/authorized_keys"
    echo "$(date +'%F')" "$(date +'%T')" "$containerid" "Created new user account \"$username\"."
fi
```
