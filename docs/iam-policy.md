# IAM policy

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
