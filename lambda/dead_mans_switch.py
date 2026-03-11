import datetime as dt

import boto3

PARAM_PREFIX = '/backups/next-backup-due/'
SNS_TOPIC_ARN = 'arn:aws:sns:<REGION>:<ACCOUNT_ID>:<TOPIC_NAME>'

def lambda_handler(event, context):
    ssm = boto3.client('ssm')
    sns = boto3.client('sns')

    now = dt.datetime.now()

    response = ssm.get_parameters_by_path(Path=PARAM_PREFIX)
    for param in response['Parameters']:
        match param:
            case {"Name": str(name), "Value": str(value)}:
                due_date = dt.datetime.strptime(value, '%Y-%m-%d')
                print(f"Got due date {due_date=} for param {name=}")

                if due_date > now:
                    print("We still have time...")
                else:
                    print("Past due date...")

                    website_name = name.split('/')[-1]

                    sns.publish(
                        TopicArn=SNS_TOPIC_ARN,
                        Subject=f"WordPress Backup OVERDUE - {website_name}",
                        Message=f"A backup for the website {website_name} was due in {value} but is now overdue. Please take action."
                    )
