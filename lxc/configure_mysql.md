# Auto-Configure MySQL (or MariaDB)

This command auto-configures a previously-installed MySQL (or MariaDB) for low-memory VPS environments.

**Make sure MySQL or MariaDB is already installed**
```bash
dpkg -l mariadb-server >/dev/null 2>&1 || dpkg -l mysql-server >/dev/null 2>&1 || fail "MariaDB or MySQL are not installed"
```

**Adjust MySQL performance for low memory VPS environments**
Some of these settings need to be adjusted according to the amount of system resources available. A little bit of math is done here to try to build a configuration that will do a good job of sharing resources on the host.

`scale_factor` is used to adjust the number of total instances per processor core. If you want to dedicate more computing power to each site, decrease this value; if you expect your sites to be idle most of the time and you want to squeeze as many as possible onto the server, then increase it. `15` is probably a good value for most small shared hosting environments.

```bash
cpu_count=$(getconf _NPROCESSORS_ONLN)
mem_avail="$(("$(grep -oP '(?<=MemTotal:)\s*[0-9]+' /proc/meminfo)"/1020))"
scale_factor=15

# Total number of instances of MySQL expected to be running on the host hardware
instances=$((((cpu_count - 1) * scale_factor) + 5))

# Set a base memory usage of up to 80% of available memory divided across all instances.
base_mem_value=$((((mem_avail / instances) * 8) / 10))

# Assuming shared hardware, allow for up to half the cores to be utilized
# by a MYSQL process at any given moment.
thread_pool_size=$((cpu_count < 2 ? 1 : cpu_count / 2))

# Allow up to 100 threads per available core.
thread_pool_max_threads=$((thread_pool_size * 100))

# Allow up to 1.5 connections per thread. More than this, and connections
# will start getting rejected.
max_connections=$((thread_pool_max_threads * 3 / 2))

thread_stack="$(printf '%sK' "$((base_mem_value * 1020 / thread_pool_max_threads / 4))")"

# Dedicate maximum available memory for each instance to the InnoDB buffer pool.
innodb_buffer_pool_size="$(printf '%sM' "$base_mem_value")"
innodb_log_buffer_size="$(printf '%sM' "$((base_mem_value / 4))")"
key_buffer_size="$(printf '%sM' "$((base_mem_value / 8))")"

# Temporary tables are allocated per connection, so they can gobble a lot of
# memory during peak workloads.
tmp_table_size="$(printf '%sK' "$((base_mem_value * 1020 / max_connections))")"

sort_buffer_size="$(printf '%sK' "$((base_mem_value * 1020 / max_connections))")"
read_rnd_buffer_size="$(printf '%sK' "$((base_mem_value * 1020 / max_connections))")"
read_buffer_size="$(printf '%sK' "$((base_mem_value * 1020 / max_connections / 2))")"
join_buffer_size="$(printf '%sK' "$((base_mem_value * 1020 / max_connections / 4))")"
```

```bash
cat <<EOF | tee /etc/mysql/conf.d/mysql.cnf >/dev/null
#
# MySQL tuning for low memory environments.
#
# This configuration is intended for LXC environments where there's
# approximately one site per container. Additional sites may require
# max_connections or other values to be adjusted.
#

[mysqld]
pid-file                  = /var/run/mysqld/mysqld.pid
socket                    = /var/run/mysqld/mysqld.sock
datadir                   = /var/lib/mysql
log-error                 = /var/log/mysql/error.log
bind-address              = 127.0.0.1
skip-networking           = 1
skip_name_resolve
skip_external_locking
performance_schema        = off
thread_handling           = pool-of-threads
thread_pool_size          = $thread_pool_size
thread_pool_max_threads   = $thread_pool_max_threads
thread_pool_idle_timeout  = 5
max_connections           = $max_connections
innodb_buffer_pool_size   = $innodb_buffer_pool_size
innodb_log_buffer_size    = $innodb_log_buffer_size
key_buffer_size           = $key_buffer_size
tmp_table_size            = $tmp_table_size
sort_buffer_size          = $sort_buffer_size
read_buffer_size          = $read_buffer_size
read_rnd_buffer_size      = $read_rnd_buffer_size
join_buffer_size          = $join_buffer_size
thread_stack              = $thread_stack
EOF
```

`skip-networking`: These environments are configured to connect to MySQL over the Unix socket, which is more performant. There's no need to connect over TCP, so we save a tiny bit of overhead here.

`skip-name-resolve`: Name resolution is used on MySQL servers that are accessible by the internet, which is insane in modern terms. All MySQL instances should be protected by iptables and access should be limited to trusted networks only, so turn this feature off to save a possible DNS round trip for each connection. (Lookups are only done for connections //not// coming from localhost, supposedly, but there are any number of conditions where this behavior may not work as expected, so turn it off anyway.)

`skip-external-locking`: By default, certain database engines in MySQL will manage external locks for their data files in case you're running multiple instances of MySQL out of the same data directory or you have other external programs attempting to access the data files directly. You're smart, so you're not doing that, so disable this to gain a tiny little speedup.

`performance_schema = off`: The `performance_schema` system can be used to diagnose database quirks and performance problems, but it's enabled by default and it is the single largest optional consumer of memory in the MySQL ecosystem. It should be off by default in production systems and turned on if needed for troubleshooting purposes.

`thread-handling = pool-of-threads`: The MySQL default is `thread-per-connection`. `pool-of-threads` is a recently-updated approach that shares a set of threads between inbound connections. This has an advantage over setting `max_connections`: with max_connections, incoming connections are rejected during high traffic periods, but with pool-of-threads, incoming connections are still queued by the thread scheduler, allowing a server to gracefully handle bursty traffic at the expense of getting a bit slower.

`thread_pool_size`: This value should be configured to the number of available CPUs. In this case, it's assumed that there may be multiple instances of MySQL running on this hardware, so half of available cores get used here.

`thread-pool-max-threads`: I can't find any good writeups that adequately describe the difference between this value and `thread-pool-size`, but it sounds to me like thread-pool-size refers to the number of threads that can be simultaneously executing instructions, while thread-pool-max-threads is the total number of threads allowed in the thread pool at any given time.

`thread-pool-idle-timeout`: The number of seconds before an idle thread is terminated. For normal web-based workloads, this can be a small value that keeps a minimal thread pool during slow periods.

`innodb_buffer_pool_size`: There is a great deal of literature floating around the web that repeats the adage that this value should be "about 80% of available RAM", but that advice comes from some time between 2000 and 2007 and was specific to the InnoDB developer's environment, which had around 1G of RAM at the time. More current literature convincingly argues that this value should be no bigger than the size of your overall database. In single-database environments, this can be reduced from the 128MB default value, and is the second-largest single consumer of RAM in MySQL deployments. To determine the size of your database, use `SELECT table_schema AS "Database", SUM(data_length + index_length) / 1024 / 1024 AS "Size (MB)" FROM information_schema.TABLES GROUP BY table_schema;`. In this configuration, `innodb_buffer_pool_size` is set to the amount of system memory that's expected to be available for this instance of MySQL on the host.


**Clean up**
```bash
service mysql restart
```

**Test login**
```bash
if ! echo -e 'SELECT "OK";' | sudo mysql -s; then
    fail "Could not connect to the MySQL server process as root";
fi
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
