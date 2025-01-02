# Start a container

This command will attempt to start a non-running container and wait until its status changes to `RUNNING` (as reported by [[status]]).

Get the name of the container. Should be passed as the next argument directly after the name of the script.
```bash
shift
if [ "$#" -lt 1 ]; then
    fail "No container specified"
fi
container="$1"
shift
```

Get the container's current status.
```bash
status="$(biphrost -b status "$container")"
```

If the container isn't located on this system, fail.
```bash
if [ "$status" = "NOTFOUND" ]; then
    fail "Container $container was not found"
fi
```

If the container is in an error state, fail.
```bash
if [ "$status" = "ERROR" ]; then
    fail "$container's current status is ERROR. It requires attention from a sysop before it can be started."
fi
```

If the container is running, do nothing.
```bash
if [ "$status" = "RUNNING" ]; then
    exit 0
fi
```

Otherwise, try to start it and wait for its status to change.
Note: This command changed from "lxc-start" to "lxc-unpriv-start" in Debian 11 (Buster). Running "lxc-start" causes an incomprehensible error message on unprivileged accounts. Yay.
```bash
start_time="$(date '+%s')"
sudo -u "$container" lxc-unpriv-start -n "$container" 2>/dev/null
while [ "$(date '+%s' -d "$start_time seconds ago")" -lt 60 ]; do
    status="$(biphrost -b status "$container")"
    case "$status" in
        RUNNING)
            exit 0
            ;;
        ERROR)
            fail "There was an error starting $container"
            ;;
        NOTFOUND)
            fail "$container has disappeared?!"
            ;;
    esac
    sleep 1
done
fail "Timeout expired while waiting for $container to start"
```