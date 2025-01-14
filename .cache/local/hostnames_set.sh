#!/bin/bash


# Do not modify this file! This file is automatically generated from the source
# file at /home/rob/Code/biphrost-shell/local/hostnames_set.md.
# Modify that file instead.
# source hash: 0aedad89399534c53d2d18597cefc18d

# begin-golem-injected-code

# Use any of these as necessary.
# Further reading on "$0" vs "$BASH_SOURCE" &etc.:
# https://stackoverflow.com/a/35006505
# https://stackoverflow.com/a/29835459
# shellcheck disable=SC2034
mypath=$(readlink -m "${BASH_SOURCE[0]}")
# shellcheck disable=SC2034
myname=$(basename "$mypath")
# shellcheck disable=SC2034
mydir=$(dirname "$mypath")
# shellcheck disable=SC2034
myshell=$(readlink /proc/$$/exe)

# Exit with an error if an undefined variable is referenced.
set -u

# If any command in a pipeline fails, that return code will be used as the
# return code for the whole pipeline.
set -o pipefail

# Halt with a non-zero exit status if a TERM signal is received by this PID.
# This is used by the fail() function along with $scriptpid.
trap "exit 1" TERM


##
# Return the filename component of a path; this is identical to calling
# "basename [path]"
#
path_filename () {
    local path=""
    path=$(realpath -s -m "$1")
    echo "${path##*/}"
}


##
# Return the parent directory of a path; this is identical to calling
# "dirname [path]", but it also cleans up extra slashes in the path.
#
path_directory () {
    local filename=""
    filename=$(path_filename "$1")
    realpath -s -m "${1%"$filename"}"
}


##
# Return the basename of the filename component of a path. For example, return
# "my_file" from "/path/to/my_file.txt".
#
path_basename () {
    local filename="" base="" ext=""
    filename=$(path_filename "$1")
    base="${filename%%.[^.]*}"
    ext="${filename:${#base} + 1}"
    if [ -z "$base" ] && [ -n "$ext" ]; then
        echo ".$ext"
    else
        echo "$base"
    fi
}


##
# Return the extension (suffix) of the filename component of a path. Example:
# return ".tar.gz" for "my_file.tar.gz", and "" for ".test".
#
path_extension () {
    local filename="" basename=""
    filename=$(path_filename "$1")
    basename=$(path_basename "$filename")
    echo "${filename##"$basename"}"
}


##
# Generate a pseudorandom string. Accepts an argument for the length of the
# string; if no string length is provided, then it defaults to generating a
# string between 12 and 25 characters long.
#
# Similar-looking characters are filtered out of the result string.
#
# shellcheck disable=SC2120
random_string () {
    local -i num_chars=0
    if [ $# -gt 0 ]; then
        num_chars=$1
    else
        num_chars=$((12 + RANDOM % 12))
    fi
    tr -dc _A-Z-a-z-0-9 < /dev/urandom | tr -d '/+oO0lLiI1\n\r' | head -c "$num_chars"
}


##
# Write a message to stderr and continue execution.
#
warn () {
    echo "Warning: $*" | fmt -w 80 >&2
}


##
# Write a message to stderr and exit immediately with a non-zero code.
#
fail () {
    echo -e "ERROR: $*" >&2
    pkill -TERM -g $$ "$myname" || kill TERM $$ >/dev/null 2>&1
    exit 1
}


##
# Ask the user a question and process the response, with options for defaults
# and timeouts.
#
ask () {
    # Options:
    #     --timeout N:     time out if there's no input for N seconds.
    #     --default ANS:   use ANS as the default answer on timeout or
    #                      if an empty answer is provided.
    #     --required:      don't accept a blank answer. Use this parameter
    #                      to make ask() accept any string.
    #
    # ask() gives the answer in its exit status, e.g.,
    # if ask "Continue?"; then ...
    local ans="" default="" prompt=""
    local -i timeout=0 required=0

    while [ $# -gt 0 ] && [[ "$1" ]]; do
        case "$1" in
            -d|--default)
                shift
                default=$1
                if [[ ! "$default" ]]; then warn "Missing default value"; fi
                default=$(tr '[:upper:]' '[:lower:]' <<< "$default")
                if [[ "$default" = "yes" ]]; then
                    default="y"
                elif [[ "$default" = "no" ]]; then
                    default="n"
                elif [ "$default" != "y" ] && [ "$default" != "n" ]; then
                    warn "Illegal default answer: $default"
                fi
                shift
            ;;

            -t|--timeout)
                shift
                if [[ ! "$1" ]]; then
                    warn "Missing timeout value"
                elif [[ ! "$1" =~ ^[0-9][0-9]*$ ]]; then
                    warn "Illegal timeout value: $1"
                else
                    timeout=$1
                fi
                shift
            ;;

            -r|--required)
                shift
                required=1
            ;;

            -*)
                warn "Unrecognized option: $1"
            ;;

            *)
                break
            ;;
        esac
    done

    # Sanity checks
    if [[ $timeout -ne 0  &&  ! "$default" ]]; then
        warn "ask(): Non-zero timeout requires a default answer"
        exit 1
    fi
    if [ "$required" -ne 0 ]; then
        if [ -n "$default" ] || [ "$timeout" -gt 0 ]; then
            warn "ask(): 'required' is not compatible with 'default' or 'timeout' parameters."
            exit 1
        fi
    fi
    if [[ ! "$*" ]]; then
        warn "Missing question"
        exit 1
    fi

    prompt="$*"
    if [ "$default" = "y" ]; then
        prompt="$prompt [Y/n] "
    elif [ "$default" = "n" ]; then
        prompt="$prompt [y/N] "
    elif [ "$required" -eq 1 ]; then
        prompt="$prompt (required) "
    else
        prompt="$prompt [y/n] "
    fi


    while [ -z "$ans" ]
    do
        if [[ $timeout -ne 0 ]]; then
            if ! read -r -t "$timeout" -p "$prompt" ans </dev/tty; then
                ans=$default
                echo
            else
                # Turn off timeout if answer entered.
                timeout=0
                if [[ ! "$ans" ]]; then ans=$default; fi
            fi
        else
            read -r -p "$prompt" ans <"$(tty)"
            if [[ ! "$ans" ]]; then
                if [ "$required" -eq 1 ]; then
                    warn "An answer is required."
                    ans=""
                else
                    ans=$default
                fi
            elif [ "$required" -eq 0 ]; then
                ans=$(tr '[:upper:]' '[:lower:]' <<< "$ans")
                if [ "$ans" = "yes" ]; then
                    ans="y"
                elif [ "$ans" = "no" ]; then
                    ans="n"
                fi
            fi 
        fi

        if [ "$required" -eq 0 ]; then
            if [ "$ans" != 'y' ] && [ "$ans" != 'n' ]; then
                warn "Invalid answer. Please use y or n."
                ans=""
            fi
        fi
    done

    if [ "$required" -eq 1 ]; then
        echo "$ans"
        return 0
    fi

    [[ "$ans" = "y" || "$ans" == "yes" ]]
}


##
# Return the value of a named option passed from the commandline.
# If it doesn't exist, exit with a non-zero status.
# This function can be invoked like so:
#     if var="$(loadopt "foo")"; then...
# 
loadopt () {
    local varname="$1" value="" found=""
    # Run through the longopts array and search for a "varname".
    for i in "${longopts[@]}"; do
        if [ -n "$found" ]; then
            echo "$i"
            return 0
        elif [ "$i" = "--$varname" ]; then
            # Matched varname, set found here so that the next loop iteration
            # picks up varname's value.
            found="$varname"
        fi
    done
    echo ""
    [ -n "$found" ]
}


##
# Require a named value from the user. If the value wasn't specified as a longopt
# when the script was invoked, then needopt() will call ask() to request the value
# from the user. Use this to get required values for your scripts.
#
needopt () {
    # Usage:
    #     varname=$(needopt varname -p "Prompt to the user" -m [regex])
    local varname="" prompt="" match="" i="" found="" value=""
    while [ $# -gt 0 ] && [[ "$1" ]]; do
        case "$1" in
            -p)
                shift
                if [ $# -gt 0 ]; then
                    prompt="$1"
                    shift
                fi
            ;;
            -m)
                shift
                if [ $# -gt 0 ]; then
                    match="$1"
                    shift
                fi
            ;;
            -*)
                warn "Unrecognized option: $1"
            ;;
            *)
                if [ -z "$varname" ]; then
                    varname="$1"
                    shift
                else
                    fail "needopt(): Unexpected value: $1"
                fi
            ;;
        esac
    done
    if [ -z "$varname" ]; then
        fail "needopt(): No varname was provided"
    fi
    if [ -z "$prompt" ]; then
        prompt="$varname"
    fi
    if ! value="$(loadopt "$varname")" || [[ ! $value =~ $match ]]; then
        while true; do
            value="$(ask -r "$prompt")"
            if [ -n "$value" ] && [[ $value =~ $match ]]; then
                break
            elif [ -n "$match" ]; then
                warn "needopt(): this value doesn't match the expected regular expression: $match"
            fi
        done
    fi
    # printf -v "$varname" '%s' "$value"
    echo "$value"
    return 0
}


# Process arguments. Golem will load any "--variable value" pairs into the
# "longopts" array. Your command script can then call the needopt() function to
# load this value into a variable.
# Example: if your command script needs a "hostname" value, the user can supply
# that with, "golem --hostname 'host.name' your command", and the "your_command.sh"
# file can use "hostname=needopt(hostname)" to create a variable named "hostname"
# with the value "host.name" (or ask the user for it).
declare -a longopts=()
declare -a args=()
while [ $# -gt 0 ] && [[ "$1" ]]; do
    case "$1" in
        --)
            # Stop processing arguments.
            break
            ;;
        --*)
            longopts+=("$1")
            shift
            if [ $# -lt 1 ] || [[ "$1" =~ ^--.+ ]]; then
                longopts+=("")
            else
                longopts+=("$1")
                shift
            fi
            ;;
        *)
            args+=("$1")
            shift
            ;;
    esac
done
# Reset the arguments list to every argument that wasn't a --longopt.
set -- "${args[@]}"
unset args


################################################################################
#                                                                              #
#    Main program                                                              #
#                                                                              #
################################################################################

# end-golem-injected-code

myinvocation="hostnames set"
if [ "${*:1:2}" != "$myinvocation" ]; then
    fail "[$myinvocation]: Invalid invocation"
fi
shift; shift
if [ "$#" -lt 1 ]; then
    fail "No container or hostnames specified"
fi
containerid="$1"
if [ "$(biphrost -b status "$containerid")" = "NOTFOUND" ]; then
    fail "Invalid container ID: $containerid"
fi
shift
hostnames="$*"
primary_hostname=""
for hostname in $hostnames; do
    if ! [[ "$hostname" =~ ^([A-Za-z0-9-]+\.)+[A-Za-z0-9-]+$ ]]; then
        fail "Invalid hostname: $hostname does not look like a routable network hostname"
    fi
    #if [[ "$hostname" =~ "biphrost" ]]; then
    #    fail "Invalid hostname: $hostname (cannot contain 'biphrost')"
    #fi
    if [ -z "$primary_hostname" ]; then
        primary_hostname="$hostname"
    fi
done
if [ -z "$primary_hostname" ]; then
    fail "No valid hostnames were given"
fi
# shellcheck disable=SC2086
biphrost -b @"$containerid" set hostnames $hostnames
ssl_status="$(biphrost -b ssl status "$containerid")"
rm -f /etc/nginx/sites-enabled/"$containerid"
rm -f /etc/nginx/sites-available/"$containerid"
cat <<'EOF' | tee /etc/nginx/sites-available/"$containerid" >/dev/null
server {

    set $container_id "$$containerid";
    set $use_https    "disabled";

    server_name $$hostnames;
    listen 80;

    # listen 443 ssl;
    # ssl_certificate     /home/$container_id/ssl/$$primary_hostname/fullchain.pem;
    # ssl_certificate_key /home/$container_id/ssl/$$primary_hostname/privkey.pem;
    # ssl_protocols       TLSv1.2;

    access_log /var/log/nginx/access.log normal;

    location ^~ /.well-known/acme-challenge/ {
        alias /home/$container_id/acme-challenge/;
    }

    location = /.well-known/biphrost-domain-verification {
        alias /home/$container_id/.biphrost-domain-verification;
    }

    location / {

        set $https_redirect "$use_https$https";
        if ($https_redirect = "enabled") {
            return 301 https://$server_name$request_uri;
        }

        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_pass http://$container_id;
        client_max_body_size 0;

        location ~* \.(css|gif|ico|jpg|js|png|svg|swf|txt|woff)$ {
            proxy_cache static;
            proxy_pass http://$container_id;
        }
    }
}
EOF
# shellcheck disable=SC2016
sed -i 's/\$\$containerid/'"$containerid"'/g' /etc/nginx/sites-available/"$containerid"
# shellcheck disable=SC2016
sed -i 's/\$\$hostnames/'"$hostnames"'/g' /etc/nginx/sites-available/"$containerid"
# shellcheck disable=SC2016
sed -i 's/\$\$primary_hostname/'"$primary_hostname"'/g' /etc/nginx/sites-available/"$containerid"
ln -s /etc/nginx/sites-available/"$containerid" /etc/nginx/sites-enabled/"$containerid"
if [ "$ssl_status" = "enabled" ]; then
    biphrost -b ssl enable "$containerid"
fi
if ! nginx -t >/dev/null; then
    rm -f /etc/nginx/sites-enabled/"$containerid"
    fail "nginx could not be restarted because there is an error in its configuration"
else
    service nginx restart
    echo "$(date +'%F')" "$(date +'%T')" "$(hostname)" "Hostname configuration complete for $containerid: $hostnames"
fi
