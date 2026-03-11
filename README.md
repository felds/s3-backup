# s3-backup

Backs up a database and a directory to S3. Each backup run produces a single `.full.tar.gz` archive containing the database dump and the files tarball, uploaded to both a daily and (on Sundays) a weekly S3 prefix. Status notifications are sent via SNS and a dead man's switch is updated in SSM Parameter Store after every successful run.

## Setup

1. Clone this repo to the target machine:
   ```sh
   git clone https://github.com/felds/s3-backup.git /opt/s3-backup
   ```

2. Create an instance script somewhere on the machine (e.g. `~/backup-myapp.sh`) following the template below, then make it executable:
   ```sh
   chmod +x ~/backup-myapp.sh
   ```

3. Add a cron entry to run it on a schedule:
   ```
   0 3 * * * /bin/bash ~/backup-myapp.sh
   ```

## Instance script

The instance script is where all site-specific configuration lives. It defines two functions — `dump_database` and `backup_files` — that pipe their output to stdout, then sources `base.sh` to run the actual backup logic.

```bash
#!/usr/bin/env bash

BACKUP_NAME="myapp"           # Used for S3 prefixes, local folder names, and notifications

dump_database() { ... }       # Should output the database dump to stdout
backup_files() { ... }        # Should output a .tar.gz stream to stdout

SNS_TOPIC_ARN="arn:aws:sns:us-east-1:000000000000:backups"
S3_BUCKET="my-backups-bucket"

# Minimum expected sizes — used to detect suspiciously small backups
MIN_DB_BACKUP_SIZE=$(numfmt --from=iec 200M)
MIN_FILES_BACKUP_SIZE=$(numfmt --from=iec 500M)
MIN_BACKUP_SIZE=$(numfmt --from=iec 500M)

source /opt/s3-backup/base.sh
```

## `dump_database` examples

This function should write the full database dump to stdout. `base.sh` will redirect it to a `.sql` file.

**MySQL via Docker:**
```bash
dump_database() {
    docker exec my-mysql-container \
        mysqldump --no-tablespaces -u myuser -pmypassword mydb
}
```

**MySQL CLI (local):**
```bash
dump_database() {
    mysqldump --no-tablespaces -u myuser -pmypassword mydb
}
```

**SQLite:**
```bash
dump_database() {
    sqlite3 /var/lib/myapp/db.sqlite3 .dump
}
```

## `backup_files` examples

This function should write a gzipped tar stream to stdout (`tar -czf -`). `base.sh` will save it as a `.tar.gz` file.

**WordPress** — excludes cache directories and debug logs that don't need to be backed up:
```bash
backup_files() {
    tar -czf - \
        --exclude="wp-content/cache/*" \
        --exclude="wp-content/debug.log" \
        --exclude="wp-content/uploads/cache/*" \
        --exclude="*.git" \
        -C /var/www/html .
}
```

**Generic application** — adjust the excludes to match whatever your app generates at runtime:
```bash
backup_files() {
    tar -czf - \
        --exclude="node_modules" \
        --exclude=".git" \
        -C /var/www/myapp .
}
```
