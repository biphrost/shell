# Restart a container

This command is a simple, convenient wrapper around the [[stop]] and [[start]] commands.

Get the name of the container. Should be passed as the next argument directly after the name of the script.
```bash
shift
if [ "$#" -lt 1 ]; then
    fail "No container specified"
fi
container="$1"
shift
```

Attempt to stop the container. If that command fails, it will produce output to `STDERR`, so we don't need to do anything fancy here.
```bash
biphrost -b stop "$container" || fail ""
```

And then attempt to start the same container.
```bash
biphrost -b start "$container" || fail ""
```

Notify user.
```bash
echo "$(date +'%F')" "$(date +'%T')" "$(hostname)" "Successfully restarted $container"
```