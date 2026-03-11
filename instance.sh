#!/usr/bin/env bash

BACKUP_NAME=""

# O comando para fazer dump do banco de dados
dump_database() {
    # mysqldump ...
}

# O comando para gerar o arquivo de backup dos arquivos
backup_files() {
    local WORDPRESS_DIR=""
    tar -czf - \
        --exclude="wp-content/cache/*" \
        --exclude="wp-content/debug.log" \
        --exclude="wp-content/uploads/cache/*" \
        --exclude="*.git" \
        -C "$WORDPRESS_DIR" .
}



SNS_TOPIC_ARN=""
S3_BUCKET=""

MIN_DB_BACKUP_SIZE=$(numfmt --from=iec 200M)
MIN_FILES_BACKUP_SIZE=$(numfmt --from=iec 500M)
MIN_BACKUP_SIZE=$(numfmt --from=iec 500M)

source backup.sh