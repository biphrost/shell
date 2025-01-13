# Get the SSL status of a container

This command will return only one of two values: `enabled` or `disabled`. It returns `enabled` if the container has an nginx configuration and that configuration has all necessary options for SSL turned on; otherwise, it returns `disabled`.

(A `NOTFOUND` error may be returned for invalid container IDs.)

The exit status will be non-zero for any errors or if the SSL status is `disabled`, otherwise it will be `0`. This allows callers to use e.g. `if biphrost ssl status <container-id>; then...`.

**Usage**
```
sudo biphrost ssh status <container-id>
```

**Parameters**
* `container-id` (required): the identifier of the container to which this user should be added.

**Sanity-check invocation**
```bash
myinvocation="ssl status"
if [ "${*:1:2}" != "$myinvocation" ]; then
    fail "[$myinvocation]: Invalid invocation"
fi
shift; shift
```

**Get the name of the container. Should be passed as the next argument directly after the name of the script.**
```bash
if [ "$#" -lt 1 ]; then
    echo "NOTFOUND"
	exit 1
fi
containerid="$1"
shift
```

**Look for a current nginx configuration for this container**
```bash
if [ ! -f /etc/nginx/sites-available/"$containerid" ]; then
    echo "disabled"
    exit 1
fi
```

**Test for the `$use_https` variable**
This is present in newer site configurations.
```bash
# shellcheck disable=SC2016
if grep -q '^\s*set \$use_https\s\+"disabled";' /etc/nginx/sites-available/"$containerid"; then
    echo "disabled"
    exit 1
fi
```

**Test for `listen 443 ssl`**
This must be present and not commented. (The trailing `;` is not included in the pattern here because other http options may follow `ssl`.)
```bash
if ! grep -q '^\s*listen 443 [^#;]*ssl\W' /etc/nginx/sites-available/"$containerid"; then
    echo "disabled"
    exit 1
fi
```

**Test for remaining SSL options**
`ssl_certificate`, `ssl_certificate_key`, and `ssl_protocols` are all required by nginx for a valid SSL configuration.
```bash
if ! grep -q '^\s*ssl_certificate\s\+' /etc/nginx/sites-available/"$containerid" || ! grep -q '^\s*ssl_certificate_key\s\+' /etc/nginx/sites-available/"$containerid" || ! grep -q '^\s*ssl_protocols\s\+' /etc/nginx/sites-available/"$containerid"; then
    echo "disabled"
    exit 1
fi
```

**Assume this container has a valid and working SSL configuration**
```bash
echo "enabled"
```
