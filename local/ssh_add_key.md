# Add an ssh key to a container (and get its ssh access config)

This adds an ssh key to the specified container. If the container doesn't already have ssh access enabled, this will enable it. The ssh configuration that the user will need for connecting to the container will be echoed.

**Usage**
```
echo my_public_key | sudo biphrost --info user@domain.com ssh add key <container-id>
```

**Parameters**
* `info` (required): the user's contact email address.
* `container-id` (required): the identifier of the container to which this user should be added.

**TODO**
* Should not add the ssh key if one already exists for this user
    * (Should the existing key be replaced? Probably...)

**Initialization**
Retrieve the username argument (required). This will replace the comment part of the public key before it's added to the lxc host.
```bash
user_info="$(needopt info)"
```

**Sanity-check invocation**
```bash
myinvocation="ssh add key"
if [ "${*:1:3}" != "$myinvocation" ]; then
    fail "[$myinvocation]: Invalid invocation"
fi
shift; shift; shift
```

**Get the name of the container. Should be passed as the next argument directly after the name of the script.**
```bash
if [ "$#" -lt 1 ]; then
    echo "NOTFOUND"
	exit 0
fi
container="$1"
shift
```

**Start the log**
```bash
echo "$(date +'%F')" "$(date +'%T')" "$container" "Adding ssh key"
```

**Verify that the container exists and is running.**
```bash
case $(biphrost -b status "$container") in
    RUNNING)
    ;;
    NOTFOUND)
        fail "$(date +'%F')" "$(date +'%T')" "$container" "Container does not exist"
    ;;
    *)
        fail "$(date +'%F')" "$(date +'%T')" "$container" "Container is not running"
    ;;
esac
```

**Extract the user's shell username from their contact info.**
A username is required to create an account inside the container. This will search for anything before the first '@', delete anything that's not a printable character (including the trailing newline added by `grep`), and then convert any series of remaining non-alphanumeric characters into a single underscore. This should be suitable for most unix-like usernames. Username collision is certainly a possibility here, but since each container is intended to host a single application and expected to have at most a few users, we should be okay for a while. It's tomorrow's problem!
```bash
username="$(echo "$user_info" | grep -o '^[^@]\+' | tr -dc '[:graph:]' | tr -cs '[:alnum:]' '_')"
```

**Retrieve the supplied key from stdin and replace its comment section (if it exists) with the user info.**
```bash
public_key="$(grep -o '^ssh-rsa [A-Za-z0-9+=/]*' </dev/stdin) $user_info $(date '+%Y-%m-%d')"
```

**Add this user account to the container**
If they already exist, nothing gets changed.
```bash
biphrost -b @"$container" user add "$username"
```

**Add this key to the container**
```bash
echo "$public_key" | sudo -u "$container" lxc-unpriv-attach -n "$container" -e -- sh -c "tee -a /home/$username/.ssh/authorized_keys >/dev/null"
```

**Add the container to the host's knockd config if it doesn't exist already**
```bash
if grep -oq '^\['"$container"'\]$' /etc/knockd.conf; then
    read -r knock1 knock2 knock3 <<< "$(grep -A5 "$container" /etc/knockd.conf | grep -Po '([0-9]+:udp,?)*' | grep -Po '[0-9]+' | tr -dc '0-9\n' | grep -Po '[0-9 ]+' | tr '\n' ' ')"
else
    echo "$(date +'%F')" "$(date +'%T')" "$container" "Creating knockd entry"
    lxcip="$(grep "\\b$container\\b" /etc/hosts | grep -oE '([0-9.]+){3}\.[0-9]+(?\b)')"
    { read -r knock1; read -r knock2; read -r knock3; } < <(tr -dc '0-9' </dev/urandom | head -c 1000 | grep -o '[2-8][0-9][0-9][0-9]' | head -n 3)
    cat <<EOF | sudo tee -a /etc/knockd.conf >/dev/null

[$container]
    sequence      = $knock1:udp,$knock2:udp,$knock3:udp
    seq_timeout   = 10
    cmd_timeout   = 5
    start_command = /usr/sbin/iptables -t nat -A PREROUTING -p tcp -s %IP% --dport 22 -j DNAT --to-destination $lxcip:22
    stop_command  = /usr/sbin/iptables -t nat -D PREROUTING -p tcp -s %IP% --dport 22 -j DNAT --to-destination $lxcip:22
EOF
    sudo service knockd restart
fi
```

**Return the ssh configuration for this container**
```bash
primary_name="$(biphrost -b hostnames get "$container" | head -n 1)"
echo "Host $primary_name"
echo "    HostName $(biphrost -b get hostip)"
echo "    User $container"
echo "    HostKeyAlias $primary_name"
echo "    IdentityFile /path/to/private/key"
echo "    ProxyCommand sh -c \"knock -u -d 100 %h ${knock1} ${knock2} ${knock3}; sleep 1; nc %h %p\""
echo "    ConnectTimeout 10"
echo "    ConnectionAttempts 1"
```


## todo

* Shouldn't add duplicate keys -- check to see if a specified key already exists in the container's ssh config before adding it.