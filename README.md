# s3-backup

Backs up a database and a directory to S3. Each backup run produces a single `.full.tar.gz` archive containing the database dump and the files tarball, uploaded to both a daily and (on Sundays) a weekly S3 prefix. Status notifications are sent via SNS and a dead man's switch is updated in SSM Parameter Store after every successful run. A companion Lambda function (`lambda/dead_mans_switch.py`) runs on a schedule and sends an SNS alert if any backup becomes overdue.

## Setup

1. Clone this repo to the target machine:
   ```sh
   git clone https://github.com/felds/s3-backup.git /opt/s3-backup
   ```

2. Create an instance script somewhere on the machine (e.g. `~/backup-myapp.sh`) following the template below, then make it executable:
   ```sh
   chmod +x ~/backup-myapp.sh
   ```

3. Schedule it to run periodically.

   **With cron:**
   ```
   0 3 * * * /bin/bash ~/backup-myapp.sh
   ```

   **With systemd timers** (for systems without cron):

   Create the unit files under your user's systemd directory:

   **`~/.config/systemd/user/backup-myapp.service`**
   ```ini
   [Unit]
   Description=Backup myapp

   [Service]
   Type=oneshot
   ExecStart=/bin/bash /home/user/backup-myapp.sh
   ```

   **`~/.config/systemd/user/backup-myapp.timer`**
   ```ini
   [Unit]
   Description=Run backup-myapp daily at 3am

   [Timer]
   OnCalendar=*-*-* 03:00:00
   Persistent=true

   [Install]
   WantedBy=timers.target
   ```

   Enable lingering so your user's services start at boot without an active session, then enable the timer:
   ```sh
   loginctl enable-linger $USER
   systemctl --user daemon-reload
   systemctl --user enable --now backup-myapp.timer
   ```

   `Persistent=true` ensures the backup runs on next boot if the machine was off at the scheduled time.

   **Verifying the setup:**
   ```sh
   # Check the timer is active and see when it will next run
   systemctl --user status backup-myapp.timer

   # List all user timers
   systemctl --user list-timers

   # Check the last run's output and exit status
   journalctl --user -u backup-myapp.service -n 50

   # Run the backup manually
   systemctl --user start backup-myapp.service
   ```

## IAM policy

The EC2 instance (or IAM user) running the script needs the following permissions. Replace `{S3_BUCKET}`, `{BACKUP_NAME}`, `{SNS_TOPIC_ARN}`, and the region/account in the SSM resource with your actual values.

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject"
            ],
            "Resource": [
                "arn:aws:s3:::{S3_BUCKET}/daily/{BACKUP_NAME}/*",
                "arn:aws:s3:::{S3_BUCKET}/weekly/{BACKUP_NAME}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": "s3:ListBucket",
            "Resource": "arn:aws:s3:::{S3_BUCKET}",
            "Condition": {
                "StringLike": {
                    "s3:prefix": [
                        "daily/{BACKUP_NAME}/*",
                        "weekly/{BACKUP_NAME}/*"
                    ]
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": "sns:Publish",
            "Resource": "{SNS_TOPIC_ARN}"
        },
        {
            "Effect": "Allow",
            "Action": "ssm:PutParameter",
            "Resource": "arn:aws:ssm:*:*:parameter/backups/next-backup-due/{BACKUP_NAME}"
        }
    ]
}
```

## Dead man's switch

The `lambda/dead_mans_switch.py` function checks SSM Parameter Store daily for overdue backups and publishes an SNS alert for each one. It reads all parameters under `/backups/next-backup-due/` (written by `base.sh` after every successful run) and compares them against today's date.

### 1. Customize the function

Edit `lambda/dead_mans_switch.py` and set `SNS_TOPIC_ARN` to your alerts topic:

```python
SNS_TOPIC_ARN = 'arn:aws:sns:{REGION}:{ACCOUNT_ID}:{TOPIC_NAME}'
```

### 2. Create the IAM role

```sh
aws iam create-role \
  --role-name backup-dead-mans-switch \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "lambda.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }'

aws iam attach-role-policy \
  --role-name backup-dead-mans-switch \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

aws iam put-role-policy \
  --role-name backup-dead-mans-switch \
  --policy-name backup-dead-mans-switch-policy \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": "ssm:GetParametersByPath",
        "Resource": "arn:aws:ssm:*:*:parameter/backups/next-backup-due/*"
      },
      {
        "Effect": "Allow",
        "Action": "sns:Publish",
        "Resource": "{SNS_TOPIC_ARN}"
      }
    ]
  }'
```

### 3. Deploy the function

```sh
cd lambda
zip dead_mans_switch.zip dead_mans_switch.py

aws lambda create-function \
  --function-name backup-dead-mans-switch \
  --runtime python3.13 \
  --role arn:aws:iam::{ACCOUNT_ID}:role/backup-dead-mans-switch \
  --handler dead_mans_switch.lambda_handler \
  --zip-file fileb://dead_mans_switch.zip
```

To update an already-deployed function after making changes:

```sh
cd lambda
zip dead_mans_switch.zip dead_mans_switch.py

aws lambda update-function-code \
  --function-name backup-dead-mans-switch \
  --zip-file fileb://dead_mans_switch.zip
```

### 4. Schedule with EventBridge

This example runs daily at 9 AM UTC. Replace `{REGION}` and `{ACCOUNT_ID}` with your values.

```sh
aws events put-rule \
  --name backup-dead-mans-switch-schedule \
  --schedule-expression "cron(0 9 * * ? *)" \
  --state ENABLED

aws lambda add-permission \
  --function-name backup-dead-mans-switch \
  --statement-id backup-dead-mans-switch-schedule \
  --action lambda:InvokeFunction \
  --principal events.amazonaws.com \
  --source-arn arn:aws:events:{REGION}:{ACCOUNT_ID}:rule/backup-dead-mans-switch-schedule

aws events put-targets \
  --rule backup-dead-mans-switch-schedule \
  --targets "Id=backup-dead-mans-switch,Arn=arn:aws:lambda:{REGION}:{ACCOUNT_ID}:function:backup-dead-mans-switch"
```

## Instance script

The instance script is where all site-specific configuration lives. It defines two functions — `dump_database` and `backup_files` — that pipe their output to stdout, then sources `base.sh` to run the actual backup logic.

```bash
#!/usr/bin/env bash

BACKUP_NAME="myapp"           # Used for S3 prefixes, local folder names, and notifications

# Optional: set where backups are stored locally before sourcing base.sh.
# Default is $HOME/backups
# BACKUPS_BASE_DIR="$(dirname "$0")/backups"

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

### Local backup storage

By default, backups are stored in `$HOME/backups/{BACKUP_NAME}/` before being uploaded to S3. To store them alongside your instance script instead, uncomment the `BACKUPS_BASE_DIR` line:

```bash
BACKUPS_BASE_DIR="$(dirname "$0")/backups"
```

The script keeps only the most recent `.full.tar.gz` file in the local folder; older backups are cleaned up automatically.

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

This function should write a gzipped tar stream to stdout (`tar -czf -`). `base.sh` will save it as a `.tar.gz` file. For DB-only backups with no files to archive, set `MIN_FILES_BACKUP_SIZE=0` and have the function output nothing.

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

**DB-only backup** — if there are no files to archive:
```bash
backup_files() {
    return 0
}

MIN_FILES_BACKUP_SIZE=0
```
