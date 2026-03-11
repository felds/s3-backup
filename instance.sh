#!/usr/bin/env bash

BACKUP_NAME=""

WORDPRESS_DIR=""

# O comando para fazer dump do banco de dados
dump_database() {
    # mysqldump ...
}



SNS_TOPIC_ARN=""
S3_BUCKET=""

MIN_DB_BACKUP_SIZE=$(numfmt --from=iec 200M)
MIN_FILES_BACKUP_SIZE=$(numfmt --from=iec 500M)
MIN_BACKUP_SIZE=$(numfmt --from=iec 500M)

source backup.sh