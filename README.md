# s3-backup

Backs up a database and a directory to S3. Each backup run produces a single `.full.tar.gz` archive containing the database dump and the files tarball, uploaded to both a daily and (on Sundays) a weekly S3 prefix. Status notifications are sent via SNS and a dead man's switch is updated in SSM Parameter Store after every successful run. A companion Lambda function (`lambda/dead_mans_switch.py`) runs on a schedule and sends an SNS alert if any backup becomes overdue.

## Quick start

1. Clone this repo to the target machine:
   ```sh
   git clone https://github.com/felds/s3-backup.git /opt/s3-backup
   ```

2. Create an [instance script](docs/instance-script.md) (e.g. `~/backup-myapp.sh`) and make it executable:
   ```sh
   chmod +x ~/backup-myapp.sh
   ```

3. Schedule it — via cron or systemd — and ensure the machine has the right [IAM permissions](docs/iam-policy.md). See [setup](docs/setup.md) for details.

## Documentation

- [Setup & scheduling](docs/setup.md)
- [IAM policy](docs/iam-policy.md)
- [Instance script](docs/instance-script.md)
- [Dead man's switch Lambda](docs/dead-mans-switch.md)
