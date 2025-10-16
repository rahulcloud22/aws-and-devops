import time
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    logger.info("Sleeping for 90 seconds...")
    time.sleep(90)
    logger.info("Done sleeping. Returning now.")
    return {
        'statusCode': 200,
        'body': 'Hello from Pulumi Lambda!'
    }
