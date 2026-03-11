#!/usr/bin/env bash

BACKUP_NAME=""

WORDPRESS_DIR=""

MYSQL_DATABASE=""
MYSQL_USERNAME=""
MYSQL_PASSWORD=""

SNS_TOPIC_ARN=""
S3_BUCKET=""

MIN_DB_BACKUP_SIZE=$(numfmt --from=iec 200M)
MIN_FILES_BACKUP_SIZE=$(numfmt --from=iec 500M)
MIN_BACKUP_SIZE=$(numfmt --from=iec 500M)

source backup.sh