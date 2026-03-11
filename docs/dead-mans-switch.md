# Dead man's switch

The `lambda/dead_mans_switch.py` function checks SSM Parameter Store daily for overdue backups and publishes an SNS alert for each one. It reads all parameters under `/backups/next-backup-due/` (written by `base.sh` after every successful run) and compares them against today's date.

## 1. Customize the function

Edit `lambda/dead_mans_switch.py` and set `SNS_TOPIC_ARN` to your alerts topic:

```python
SNS_TOPIC_ARN = 'arn:aws:sns:<REGION>:<ACCOUNT_ID>:<TOPIC_NAME>'
```

## 2. Create the IAM role

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

## 3. Deploy the function

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

## 4. Schedule with EventBridge

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
