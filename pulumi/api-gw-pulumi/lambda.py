import json
def handler(event, context):
    response = {
        'statusCode': 200,
        'body': json.dumps('Success Changed: Your Lambda function has been triggered!')
    }
    return response
