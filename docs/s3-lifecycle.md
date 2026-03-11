# S3 lifecycle policy

The recommended lifecycle policy keeps costs in check by expiring daily backups quickly and moving weekly backups to cold storage over time:

- **Daily** (`daily/`) — deleted after **3 days**; only the last few days are needed for quick recovery.
- **Weekly** (`weekly/`) — moved to **Glacier** after 30 days, then to **Deep Archive** after 180 days.

## Applying the policy

Save the following to `lifecycle.json`, then apply it to your bucket:

```sh
aws s3api put-bucket-lifecycle-configuration \
  --bucket {S3_BUCKET} \
  --lifecycle-configuration file://lifecycle.json
```

**`lifecycle.json`**
```json
{
    "Rules": [
        {
            "ID": "Cleanup Dailies",
            "Filter": {
                "Prefix": "daily/"
            },
            "Status": "Enabled",
            "Expiration": {
                "Days": 3
            }
        },
        {
            "ID": "Deep Storage Weeklies",
            "Filter": {
                "Prefix": "weekly/"
            },
            "Status": "Enabled",
            "Transitions": [
                {
                    "Days": 30,
                    "StorageClass": "GLACIER"
                },
                {
                    "Days": 180,
                    "StorageClass": "DEEP_ARCHIVE"
                }
            ]
        }
    ]
}
```

## Verifying

```sh
aws s3api get-bucket-lifecycle-configuration --bucket {S3_BUCKET}
```

## Adding rules to an existing configuration

`put-bucket-lifecycle-configuration` **replaces** the entire configuration — any existing rules not included in the new JSON will be deleted. To safely append rules, fetch the current config first, merge your changes, then re-apply:

```sh
aws s3api get-bucket-lifecycle-configuration --bucket {S3_BUCKET} > lifecycle.json
# edit lifecycle.json to add the new rules, then:
aws s3api put-bucket-lifecycle-configuration \
  --bucket {S3_BUCKET} \
  --lifecycle-configuration file://lifecycle.json
```
