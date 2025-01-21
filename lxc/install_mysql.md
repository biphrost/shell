# Install and Configure MySQL (using MariaDB)

This command installs [MariaDB](https://mariadb.org/), an open source drop-in replacement for MySQL. MariaDB should be binary-compatible with the MySQL ABI and it is the default installation candidate for mysql* packages in Debian.

MariaDB has been found to [perform slightly better than Percona](https://blog.kernl.us/2019/10/wordpress-database-performance-showdown-mysql-vs-mariadb-vs-percona/) in small installations, so it's a better pick for single-application containers and VPS environments. Percona may be a better choice for distributed database systems because of their greater focus on cluster support.

**Usage**
```
biphrost @<container-id> install mysql
```

**Sanity-check invocation**
```bash
myinvocation="install mysql"
if [ "${*:1:2}" != "$myinvocation" ]; then
    fail "[$myinvocation]: Invalid invocation"
fi
shift; shift
```

**Get the container label or hostname**
Used for logging.
```bash
containerid="$(cat /root/.label 2>/dev/null <(hostname) | head -n 1)"
```

**Start the log**
```bash
echo "$(date +'%F')" "$(date +'%T')" "$containerid" "Installing mariadb on $(hostname)"
```

**Install MariaDB**
MariaDB is present in Debian main repositories, so installation is straightforward:
```bash
DEBIAN_FRONTEND=noninteractive sudo apt-get -qy install mariadb-server >/dev/null
```

**Clean up**
```bash
service mysql restart
```

**Test passwordless login**
```bash
if ! echo -e 'SELECT "OK";' | sudo mysql -s; then
    fail "Could not connect to the MySQL server process as root"
fi
```

**Complete the log**
```bash
echo "$(date +'%F')" "$(date +'%T')" "$containerid" "mariadb installation complete."
```

## References

* https://dba.stackexchange.com/questions/305708/understanding-thread-pool-and-max-connection-in-mariadb
* https://mariadb.com/resources/blog/10-database-tuning-tips-for-peak-workloads/
* https://mariadb.com/kb/en/query-cache/
* https://stackoverflow.com/questions/45412537/should-i-turn-off-query-cache-in-mysql
* https://www.percona.com/doc/percona-server/8.0/performance/threadpool.html
* https://mariadb.com/kb/en/thread-pool-in-mariadb/
* https://stackoverflow.com/questions/40189226/how-to-make-mysql-use-less-memory
* https://dba.stackexchange.com/questions/27328/how-large-should-be-mysql-innodb-buffer-pool-size
* https://stackoverflow.com/questions/1733507/how-to-get-size-of-mysql-database
