import time

def lambda_handler(event, context):
    print("Received event: " + str(event))
    if event["lifecycleStage"] == "TEST_TRAFFIC_SHIFT":
        time.sleep(110)  # Simulate some processing time
        print("Test traffic shift completed successfully.")
    return {"hookStatus": "SUCCEEDED"}