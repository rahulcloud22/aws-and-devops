# import requests
import json
import uuid
import boto3
from botocore.exceptions import ClientError
import time
import os

DYNAMODB_CONNECTIONS_TABLE = os.environ.get("DYNAMODB_CONNECTIONS_TABLE")
DYNAMODB_MESSAGES_TABLE = os.environ.get("DYNAMODB_MESSAGES_TABLE")
WS_ENDPOINT = os.environ.get("WS_ENDPOINT")

dynamodb = boto3.client("dynamodb")
api_client = boto3.client(
				"apigatewaymanagementapi",
				endpoint_url=WS_ENDPOINT
		)

def lambda_handler(event, context):

	route_key = event.get('requestContext', {}).get('routeKey')
	connection_id = event.get('requestContext', {}).get('connectionId')
	
	print(f"Route Key: {route_key}, Connection ID: {connection_id}")
	
	if route_key == '$connect':
		print(f"Client connecting: {connection_id}")
		connection_id = event["requestContext"]["connectionId"]

		dynamodb.put_item(
				TableName=DYNAMODB_CONNECTIONS_TABLE,
				Item={
						"connectionId": {"S": connection_id},
						"connectedAt": {"N": str(int(time.time() * 1000))}
				}
		)

		return {
				'statusCode': 200,
				'body': json.dumps('Connected')
		}
    
	elif route_key == '$disconnect':
		print(f"Client disconnecting: {connection_id}")
		connection_id = event["requestContext"]["connectionId"]

		dynamodb.delete_item(
				TableName=DYNAMODB_CONNECTIONS_TABLE,
				Key={
						"connectionId": {"S": connection_id}
				}
		)
		return {
				'statusCode': 200,
				'body': json.dumps('Disconnected')
		}
	
	if route_key == 'getMessages':
		connection_id = event["requestContext"]["connectionId"]

		# Fetch last 50 messages
		response = dynamodb.scan(TableName=DYNAMODB_MESSAGES_TABLE, Limit=50)
		messages = response.get("Items", [])
		messages.sort(key=lambda x: int(x["timestamp"]["N"]))

		# Send all messages at once to avoid GoneException
		all_messages = [
				{
						"messageId": msg["messageId"]["S"],
						"timestamp": int(msg["timestamp"]["N"]),
						"senderId": msg["senderId"]["S"],
						"message": msg["message"]["S"]
				}
				for msg in messages
		]

		api_client.post_to_connection(
				ConnectionId=connection_id,
				Data=json.dumps({"messages": all_messages}).encode("utf-8")
		)

		return {"statusCode": 200}
	
	elif route_key == 'sendMessage':
		body = json.loads(event.get("body", "{}"))
		message = body.get("message")
		sender = body.get("sender")
		if message is None:
				return {"statusCode": 400, "body": "No message provided"}

		sender_connection_id = event["requestContext"]["connectionId"]
		
		dynamodb.put_item(
    TableName=DYNAMODB_MESSAGES_TABLE,
    Item={
        'messageId': {'S': str(uuid.uuid4())},
        'timestamp': {'N': str(int(time.time() * 1000))},
        'senderId': {'S': sender},
        'message': {'S': message}
			}
		)
		
		# Fetch all connections
		response = dynamodb.scan(TableName=DYNAMODB_CONNECTIONS_TABLE)
		connections = response.get("Items", [])

		# Send message to all connections
		for conn in connections:
				connection_id = conn["connectionId"]["S"]
				if connection_id == sender_connection_id:
						continue  # Skip sender
				try:
						api_client.post_to_connection(
								ConnectionId=connection_id,
								Data=json.dumps({
										"message": message,
										"sender": sender,
										"timestamp": int(time.time() * 1000)
								}).encode("utf-8")  # Must be bytes
						)
				except ClientError as e:
						# Handle stale connections
						if e.response["Error"]["Code"] == "GoneException":
								print(f"Stale connection, removing: {connection_id}")
								dynamodb.delete_item(
										TableName=DYNAMODB_CONNECTIONS_TABLE,
										Key={"connectionId": {"S": connection_id}}
								)
						else:
								print(f"Error sending to {connection_id}: {e}")
		
		return {
				'statusCode': 200,
				'body': json.dumps('Message received')
		}
	
	else:
		print(f"Unknown route: {route_key}")
		return {
				'statusCode': 400,
				'body': json.dumps('Unknown route')
		}