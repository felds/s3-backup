#!/usr/bin/env bash

# 
# Este script foi criado pelo Felds <dev@felds.com.br>
# 
# Ele cria um arquivo de backup para um site WordPress contendo:
# - Todos os arquivos do site (excl. caches e .git)
# - Um dump do banco de dados
# 
# Em seguida, este arquivo é enviado para um bucket S3.
# 
# Para usá-lo, crie um script que define as variáveis necessárias
# antes de executar estes script.
# 




# TODO: auto-delete daily backups 14days+ old (now it's 3 for testing)
# TODO: act upon dead man's switch


REQUIRED_VARS=(
    BACKUP_NAME
    WORDPRESS_DIR
    MYSQL_DATABASE
    MYSQL_USERNAME
    MYSQL_PASSWORD
    SNS_TOPIC_ARN
    S3_BUCKET
    MIN_DB_BACKUP_SIZE
    MIN_FILES_BACKUP_SIZE
    MIN_BACKUP_SIZE
)

# Check if the required vars are set and not empty
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        echo "Erro: Env var $var not set."
        exit 1
    fi
done


# =====================================================================


DATE=$(date +%Y%m%d_%H%M%S)
BACKUPS_BASE_DIR="$HOME/backups"

BACKUP_DIR="${BACKUPS_BASE_DIR}/${BACKUP_NAME}"
LOGS_FILE="${BACKUPS_BASE_DIR}/${BACKUP_NAME}.log"

BACKUP_FILE_PREFIX="${BACKUP_NAME}_${DATE}"


# SNS Configuration
IMDS_TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id -H "X-aws-ec2-metadata-token: $IMDS_TOKEN")
HOSTNAME=$(hostname)

# S3 Configuration
S3_DAILY_PREFIX="daily/${BACKUP_NAME}"
S3_WEEKLY_PREFIX="weekly/${BACKUP_NAME}"

# SSM Configuration
SSM_PARAMETER_NAME="/backups/next-backup-due/${BACKUP_NAME}"
SSM_DUE_TO=$(date -d '+2 days' '+%Y-%m-%d')

# Monitoring variables
START_TIME=$(date +%s)
BACKUP_SUCCESS=true
ERROR_LOG=""



# =====================================================================
#                           Helper functions
# =====================================================================


# Log function with SNS notification capability
log_message() {
    local message="$1"
    local level="$2"  # 'ERROR' or 'INFO'
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "[$timestamp] $message"
    echo "[$timestamp] $message" >> $LOGS_FILE

    if [ "$level" = "ERROR" ]; then
        ERROR_LOG="${ERROR_LOG}\n${message}"
        BACKUP_SUCCESS=false
    fi
}


# Function to send SNS notification
send_notification() {
    local status="$1"
    local message="$2"
    local subject="WordPress Backup $status - $BACKUP_NAME $HOSTNAME ($INSTANCE_ID)"
    local formatted_message=$(echo -e "$message")

    aws sns publish \
        --topic-arn "$SNS_TOPIC_ARN" \
        --subject "$subject" \
        --message "$formatted_message"
}


# Function to check disk space
check_disk_space() {
    local required_space=$(($MIN_BACKUP_SIZE * 2))
    local available_space=$(df -B1 $BACKUP_DIR | awk 'NR==2 {print $4}')

    if [ "$available_space" -lt "$required_space" ]; then
        log_message "Low disk space: ${available_space}GB available, ${required_space}GB required" "ERROR"
        return 1
    fi
    return 0
}


# Function to check if a file has the minimum expected size
check_backup_size() {
    local min_size_bytes="$1"
    local file="$2"
    local label="$3"
    local backup_size_bytes=$(du -b $file | cut -f1)
    if [ $backup_size_bytes -lt $min_size_bytes ]; then
        local backup_size_human=$(numfmt --to=iec $backup_size_bytes)
        local min_size_human=$(numfmt --to=iec $min_size_bytes)
        log_message "Backup size \"$label\" ($backup_size_human) is smaller than expected minimum ($min_size_human)" "ERROR"
        send_notification "WARNING" "Backup size is suspiciously small\n${ERROR_LOG}"
    fi
}


# Determine if a weekly backup should be created
is_weekly() {
    local day_of_week=$(date +%u)
    [ "$day_of_week" = "7" ] # 7 = sunday
}


# =====================================================================
#                           Check prerequisites
# =====================================================================


# Start backup process
log_message "Starting backup process..." "INFO"


# Check for AWS CLI
if ! command -v aws &> /dev/null; then
    log_message "AWS CLI is not installed" "ERROR"
    exit 1
fi


# Create backup directory (if needed)
mkdir -p $BACKUP_DIR


# Check disk space
check_disk_space || {
    send_notification "FAILED" "Insufficient disk space for backup - ${ERROR_LOG}"
    exit 1
}


# =====================================================================
#                           Create backups
# =====================================================================


# MySQL database backup with size check
log_message "Starting database backup..." "INFO"
if ! mariadb-dump --no-tablespaces --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD $MYSQL_DATABASE > $BACKUP_DIR/$BACKUP_FILE_PREFIX.sql 2>/dev/null ; then
    log_message "Database backup failed" "ERROR"
    send_notification "FAILED" "Database backup failed\n${ERROR_LOG}"
    exit 1
fi


# Check if database backup is empty
if [ ! -s "$BACKUP_DIR/$BACKUP_FILE_PREFIX.sql" ]; then
    log_message "Database backup is empty" "ERROR"
    send_notification "FAILED" "Database backup is empty\n${ERROR_LOG}"
    exit 1
fi


# WordPress files backup
log_message "Starting WordPress files backup..." "INFO"
if ! tar -czf $BACKUP_DIR/$BACKUP_FILE_PREFIX.tar.gz \
    --exclude="wp-content/cache/*" \
    --exclude="wp-content/debug.log" \
    --exclude="wp-content/uploads/cache/*" \
    --exclude="*.git" \
    -C $WORDPRESS_DIR .; then
    
    log_message "WordPress files backup failed" "ERROR"
    send_notification "FAILED" "WordPress files backup failed\n${ERROR_LOG}"
    exit 1
fi

# Check for expected file sizes
check_backup_size $MIN_DB_BACKUP_SIZE       "$BACKUP_DIR/$BACKUP_FILE_PREFIX.sql"      "Database"
check_backup_size $MIN_FILES_BACKUP_SIZE    "$BACKUP_DIR/$BACKUP_FILE_PREFIX.tar.gz"   "Site files"


# Create final backup archive
log_message "Creating final backup archive..." "INFO"
if ! tar -czf $BACKUP_DIR/$BACKUP_FILE_PREFIX.full.tar.gz \
    -C $BACKUP_DIR $BACKUP_FILE_PREFIX.sql $BACKUP_FILE_PREFIX.tar.gz; then
    
    log_message "Final archive creation failed" "ERROR"
    send_notification "FAILED" "Final archive creation failed\n${ERROR_LOG}"
    exit 1
fi

# Check for expected file sizes
check_backup_size $MIN_BACKUP_SIZE "$BACKUP_DIR/$BACKUP_FILE_PREFIX.full.tar.gz" "Final backup"


# =====================================================================
#                           Upload to S3
# =====================================================================


DAILY_S3_URI="s3://$S3_BUCKET/$S3_DAILY_PREFIX/$BACKUP_FILE_PREFIX.full.tar.gz"
WEEKLY_S3_URI="s3://$S3_BUCKET/$S3_WEEKLY_PREFIX/$BACKUP_FILE_PREFIX.full.tar.gz"


# Upload to S3 daily location with frequency tag
log_message "Uploading to S3 daily backup location..." "NOTICE"
if ! aws s3 cp "$BACKUP_DIR/$BACKUP_FILE_PREFIX.full.tar.gz" "$DAILY_S3_URI" &>/dev/null; then
    log_message "S3 upload failed" "ERROR"
    send_notification "FAILED" "S3 upload failed\n${ERROR_LOG}"
    exit 1
fi

# If it's sunday, copy to weekly location with frequency tag
if is_weekly; then
    log_message "Copying backup to weekly location" "NOTICE"
    if ! aws s3 cp "$DAILY_S3_URI" "$WEEKLY_S3_URI" &>/dev/null; then
        log_message "Weekly backup copy failed" "ERROR"
        send_notification "WARNING" "Backup was saved but weekly copy failed\n${ERROR_LOG}"
    else
        log_message "Weekly backup copy successful" "INFO"
    fi
fi

# Verify S3 upload (now checks both locations if weekly)
log_message "Verifying upload to S3..." "INFO"
if ! aws s3 ls "$DAILY_S3_URI" &>/dev/null; then
    log_message "S3 upload verification failed - $DAILY_S3_URI" "ERROR"
    send_notification "FAILED" "S3 upload verification failed\n${ERROR_LOG}"
    exit 1
fi

if is_weekly; then
    if ! aws s3 ls "$WEEKLY_S3_URI" &>/dev/null; then
        log_message "Weekly backup verification failed - $WEEKLY_S3_URI" "ERROR"
        send_notification "WARNING" "Daily backup OK but weekly copy verification failed\n${ERROR_LOG}"
    fi
fi


# =====================================================================
#                       Dead man's switch
# =====================================================================

if ! aws ssm put-parameter \
    --name $SSM_PARAMETER_NAME \
    --value $SSM_DUE_TO \
    --type String \
    --overwrite &>/dev/null; then

    log_message "Couldn't add dead man's switch param ${SSM_PARAMETER_NAME} (due: ${SSM_DUE_TO})" "ERROR"
    send_notification "WARNING" "$ERROR_LOG"
else
    log_message "Dead man's switch param added ${SSM_PARAMETER_NAME} (due: ${SSM_DUE_TO})" "INFO"
fi


# =====================================================================
#                           Cleanup
# =====================================================================


# Cleanup temporary files
rm $BACKUP_DIR/$BACKUP_FILE_PREFIX.sql
rm $BACKUP_DIR/$BACKUP_FILE_PREFIX.tar.gz

# Keep only most recent local backup
cd $BACKUP_DIR
ls -t *.full.tar.gz | tail -n +2 | xargs -r rm


# =====================================================================
#                           Final Status
# =====================================================================


# Calculate execution time
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
DURATION_MINUTES=$((DURATION / 60))

# Send success notification
if [ "$BACKUP_SUCCESS" = true ]; then
    BACKUP_SIZE=$(du -h "$BACKUP_DIR/$BACKUP_FILE_PREFIX.full.tar.gz" | cut -f1)
    SUCCESS_MESSAGE="Backup completed successfully\n\nDetails:\n"
    SUCCESS_MESSAGE+="- Duration: ${DURATION_MINUTES} minutes\n"
    SUCCESS_MESSAGE+="- Backup size: ${BACKUP_SIZE}\n"
    SUCCESS_MESSAGE+="- S3 path: $DAILY_S3_URI"
    if is_weekly; then
        SUCCESS_MESSAGE+="\n- Weekly backup: $WEEKLY_S3_URI"
    fi
    send_notification "SUCCESS" "$SUCCESS_MESSAGE"
fi

log_message "Backup process completed in ${DURATION_MINUTES} minutes" "INFO"
