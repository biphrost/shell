# Return a list of hostnames for a container
or all containers on the server with `--all`, and optionally verify them with `--verify`.

**Sanity-check invocation**
```bash
myinvocation="hostnames get"
if [ "${*:1:2}" != "$myinvocation" ]; then
    fail "[$myinvocation]: Invalid invocation"
fi
shift; shift
```


**Validate container argument**
```bash
if loadopt "all" >/dev/null; then
    container="*"
else
    if [ $# -lt 1 ]; then
        fail "No container ID given"
    fi
    if ! [[ "$1" =~ ^lxc[0-9]{4}$ ]]; then
        fail "Invalid container ID"
    fi
    if [ ! -f /etc/nginx/sites-enabled/"$1" ]; then
        fail "No nginx configuration found for $1"
    fi
    if [ ! -d /home/"$1" ]; then
        fail "No homedir found for $1"
    fi
    container="$1"
fi
```


**Retrieve current hostnames from nginx configuration for this container**
```bash
# Shut up, shellcheck.
#shellcheck disable=SC2207,SC2086
declare -a hostnames=($(grep -orhP '^\s*server_name\s*\K[^\.]+\..+(?=;)' /etc/nginx/sites-enabled/$container))
if ! loadopt "verify" >/dev/null; then
    for hostname in "${hostnames[@]}"; do
        echo "$hostname"
    done
    exit 0
fi
```


**If --verify, then verify each hostname in the nginx configuration**
```bash
for hostname in "${hostnames[@]}"; do
    container="$(grep -l "^\\s*server_name\\s*.*\\s$hostname\\(\\s\\|;\\)" /etc/nginx/sites-enabled/* | xargs basename 2>/dev/null)"
    if [ -z "$container" ]; then
        continue
    fi
    randkey="$(biphrost -b mkrand 'a-z0-9' 32)"
    echo "$randkey" > /home/"$container"/.biphrost-domain-verification && chmod 0644 /home/"$container"/.biphrost-domain-verification
    response="$(curl -fkL -m 5 --dns-servers 1.1.1.1,4.4.4.4 "$hostname"/.well-known/biphrost-domain-verification 2>/dev/null)"
    if [ "$randkey" = "$response" ]; then
        echo "$hostname"
    fi
    rm /home/"$container"/.biphrost-domain-verification
done
```