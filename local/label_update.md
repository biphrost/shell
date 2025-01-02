# Update the label (lxc name) for a container

This places a small read-only file in `/root/.label` (on the container's filesystem) with the container's ID, typically only used for logging purposes.

**Usage**
```
sudo biphrost label update <container-id>
```

**Parameters**
* `container-id` (required): the identifier of the container to which this user should be added.

**Sanity-check invocation**
```bash
myinvocation="label update"
if [ "${*:1:2}" != "$myinvocation" ]; then
    fail "[$myinvocation]: Invalid invocation"
fi
shift; shift
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
echo "$(date +'%T')" "$(date +'%F')" "$container" "Updating container label"
```

**Verify that the container exists and is running.**
```bash
case $(biphrost -b status "$container") in
    RUNNING)
    ;;
    NOTFOUND)
        fail "$(date +'%T')" "$(date +'%F')" "$container" "Container does not exist"
    ;;
    *)
        fail "$(date +'%T')" "$(date +'%F')" "$container" "Container is not running"
    ;;
esac
```

**Update the label file**
```bash
echo "$container" | sudo -u "$container" lxc-unpriv-attach -n "$container" -e -- sh -c "tee /root/.label >/dev/null && chmod 0400 /root/.label"
```
