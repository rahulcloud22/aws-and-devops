# import requests
import json
import re
import uuid
import boto3
from botocore.exceptions import ClientError
import time
import os
import logging

s3 = boto3.client("s3")
transcribe = boto3.client("transcribe")
dynamodb = boto3.resource("dynamodb")
sfn = boto3.client("stepfunctions")
bedrock = boto3.client("bedrock-runtime", region_name=os.environ.get("AWS_REGION", "us-east-1"))

# Configure logger
logger = logging.getLogger()
log_level = os.environ.get("LOG_LEVEL", "INFO").upper()
logger.setLevel(getattr(logging, log_level, logging.INFO))
formatter = logging.Formatter('%(asctime)s %(levelname)s %(name)s - %(message)s')

TABLE = os.environ["AUDIOS_TABLE_NAME"]
BUCKET_NAME = os.environ["AUDIOS_BUCKET_NAME"]
STEP_FUNCTION_ARN = os.environ["STEP_FUNCTION_ARN"]
BEDROCK_MODEL_ID = os.environ.get("BEDROCK_MODEL_ID", "us.amazon.nova-lite-v1:0")

table = dynamodb.Table(TABLE)

def normalize_bedrock_json(text):
	if not text:
		return "{}"

	cleaned = text.strip()
	if cleaned.startswith("```"):
		match = re.match(r"```(?:json)?\s*(.*?)\s*```", cleaned, re.IGNORECASE | re.DOTALL)
		if match:
			cleaned = match.group(1).strip()

	try:
		parsed = json.loads(cleaned)
		return json.dumps(parsed)
	except json.JSONDecodeError:
		logger.warning("Bedrock returned non-JSON content: %s", cleaned)
		return cleaned


def lambda_handler(event, context):  
	# Detect if called from API Gateway (has body) or Step Functions
	logger.info("Received event: %s", json.dumps(event))
	if "body" in event:
		if isinstance(event["body"], str):
			try:
				event = json.loads(event["body"])
			except Exception as e:
				logger.exception("Failed to parse event body as JSON: %s", e)
				raise
		else:
			event = event["body"]
	stage = event.get("stage")
	logger.info("Handling stage: %s", stage)

	if stage == "CREATE_AUDIO_UPLOAD":
		logger.info("Creating audio upload record and presigned URL")
		audio_id = f"aud-{uuid.uuid4().hex[:10]}"
		file_name = f"{audio_id}.mp3"

		table.put_item(Item={
			"audioId": audio_id,
			"status": "AUDIO_CREATED"
		})

		upload_url = s3.generate_presigned_url(
			"put_object",
			Params={
				"Bucket": BUCKET_NAME,
				"Key": file_name,
				"ContentType": "audio/mpeg"
			},
			ExpiresIn=300
		)

		data = {
			"uploadUrl": upload_url,
			"key": file_name,
			"audioId": audio_id,
			"status": "AUDIO_CREATED"
		}
		resp = {
				"statusCode": 200,
				"headers": {"Content-Type": "application/json"},
				"body": json.dumps(data)
			}
		logger.info("CREATE_AUDIO_UPLOAD response: %s", resp)
		return resp
	elif stage == "CHECK_AUDIO_STATUS":
			audio_id = event["audioId"]
			logger.info("Checking status for audio %s", audio_id)
			response = table.get_item(Key={"audioId": audio_id})
			item = response.get("Item")
			if item:
				body = {
					"audioId": audio_id,
					"status": item["status"]
				}
				if item["status"] == "TRANSCRIPT_PROCESSED":
					body["transcriptText"] = item.get("transcriptText", "")
				elif item["status"] == "SUMMARY_GENERATED":
					body["transcriptText"] = item.get("transcriptText", "")
					body["summary"] = item.get("summary", "")
				data = body
				data["statusCode"] = 200
			else:
				logger.warning("Audio not found: %s", audio_id)
				data = {
					"message": "Audio not found"
				}
				data["statusCode"] = 404
			return {
				"statusCode": 200,
				"body": json.dumps(data)
			}
	
	elif stage == "START_STEP_FUNCTION":
		audio_id = event["audioId"]
		logger.info("Starting step function for audio %s", audio_id)
		table.update_item(
			Key={"audioId": audio_id},
			UpdateExpression="SET #s = :s",
			ExpressionAttributeNames={"#s": "status"},
			ExpressionAttributeValues={":s": "STARTING_STEP_FUNCTION"}
		)

		try:
			response = sfn.start_execution(
			stateMachineArn=STEP_FUNCTION_ARN,
			input=json.dumps({
					"audioId": audio_id
			}))
		except Exception:
			logger.exception("Failed to start step function for %s", audio_id)
			raise
		logger.info("Step function start response: %s", response)
		return {
			"statusCode": 200,
			"body": json.dumps({
				"executionArn": response["executionArn"],
				"audioId": audio_id,
				"status": "STARTING_STEP_FUNCTION"
			})
		}

	elif stage == "START_AUDIO_TRANSCRIPTION":
		audio_id = event["audioId"]
		logger.info("Starting transcription for audio %s", audio_id)
		job_name = f"{audio_id}-{int(time.time())}"
		media_uri = f"s3://{BUCKET_NAME}/{audio_id}.mp3"

		table.update_item(
				Key={"audioId": audio_id},
				UpdateExpression="SET #s = :s",
				ExpressionAttributeNames={"#s": "status"},
				ExpressionAttributeValues={":s": "STARTING_TRANSCRIPTION"}
		)

		try:
			response = transcribe.start_transcription_job(
        TranscriptionJobName=job_name,
        Media={'MediaFileUri': media_uri},
        MediaFormat='mp3',  # mp3, mp4, wav, etc.
        LanguageCode='en-US',
        
        OutputBucketName=BUCKET_NAME,  # saves transcript JSON to same S3 bucket
        OutputKey=f"transcripts/{job_name}.json"
    )
		except Exception:
			logger.exception("Transcribe start failed for %s", job_name)
			raise

		table.update_item(
				Key={"audioId": audio_id},
				UpdateExpression="SET #s = :s",
				ExpressionAttributeNames={"#s": "status"},
				ExpressionAttributeValues={":s": "STARTED_TRANSCRIPTION"}
		)

		logger.info("START_AUDIO_TRANSCRIPTION response: job=%s output=%s", job_name, f"s3://{BUCKET_NAME}/transcripts/{job_name}.json")
		data = {
			"audioId": audio_id,
			"status": "STARTED_TRANSCRIPTION",
			"jobName": job_name,
			"media": media_uri,
			"output": f"s3://{BUCKET_NAME}/transcripts/{job_name}.json"
		}
		return data

	elif stage == "GET_TRANSCRIPTION_STATUS":
		audio_id = event["audioId"]
		job_name = event["jobName"]
		logger.info("Getting transcription status for job %s", job_name)
		response = transcribe.get_transcription_job(TranscriptionJobName=job_name)
		job_status = response['TranscriptionJob']['TranscriptionJobStatus']
		if job_status == 'COMPLETED':
			status = "TRANSCRIPTION_COMPLETED"
		elif job_status == 'FAILED':
			status = "TRANSCRIPTION_FAILED"
		else:
			status = "TRANSCRIPTION_IN_PROGRESS"
		table.update_item(
			Key={"audioId": audio_id},
			UpdateExpression="SET #s = :s",
			ExpressionAttributeNames={"#s": "status"},
			ExpressionAttributeValues={":s": status}
		)
		logger.info("Transcription job %s status: %s", job_name, job_status)
		data = {
			"audioId": audio_id,
			"status": status,
			"jobName": job_name,
			"output": f"s3://{BUCKET_NAME}/transcripts/{job_name}.json" if job_status == 'COMPLETED' else None
		}
		data["statusCode"] = 200
		return data

	elif stage == "PROCESS_TRANSCRIPT":
		audio_id = event["audioId"]
		job_name = event["jobName"]
		logger.info("Processing transcript for audio %s, job %s", audio_id, job_name)
		transcript_s3_key = f"transcripts/{job_name}.json"

		# Download the transcript JSON from S3
		try:
			transcript_object = s3.get_object(Bucket=BUCKET_NAME, Key=transcript_s3_key)
			transcript_data = json.loads(transcript_object['Body'].read().decode('utf-8'))
		except Exception:
			logger.exception("Failed to fetch or parse transcript from s3://%s/%s", BUCKET_NAME, transcript_s3_key)
			raise

		# Extract the transcript text
		transcript_text = transcript_data['results']['transcripts'][0]['transcript']

		table.update_item(
			Key={"audioId": audio_id},
			UpdateExpression="SET #s = :s, transcriptText = :t",
			ExpressionAttributeNames={"#s": "status"},
			ExpressionAttributeValues={":s": "TRANSCRIPT_PROCESSED", ":t": transcript_text}
		)

		data = {
			"audioId": audio_id,
			"status": "TRANSCRIPT_PROCESSED"
		}
		return data

	elif stage == "GET_SUMMARY_FROM_TRANSCRIPT":
		audio_id = event["audioId"]
		logger.info("Generating summary for audio %s", audio_id)
		response = table.get_item(Key={"audioId": audio_id})
		item = response.get("Item")
		transcript = item.get("transcriptText", "")
		# time.sleep(2)  # Simulate processing time

		prompt = f"""
		Convert the following meeting transcript into valid JSON.
		Return only JSON with this structure:
		{{
			"summary": "brief meeting summary",
			"key_points": [
				"point 1",
				"point 2"
			],
			"decisions": [
				"decision 1"
			],
			"action_items": [
				"action item 1"
			]
		}}

		Rules:
		- Return only valid JSON.
		- Do not wrap the response in markdown code fences.
		- Keep summaries concise.
		- Use empty arrays if no decisions or action items are mentioned.


		Transcript:
		{transcript}
		"""
		try:
			response = bedrock.invoke_model(
				modelId=BEDROCK_MODEL_ID,
				body=json.dumps({
					"messages": [{
						"role": "user",
						"content": [{"text": prompt}]}]
				})
			)
		except ClientError as e:
			if e.response.get("Error", {}).get("Code") == "ValidationException" and "inference profile" in str(e):
				logger.warning("Bedrock model ID %s is not supported for on-demand invocation. Falling back to us.amazon.nova-lite-v1:0", BEDROCK_MODEL_ID)
				response = bedrock.invoke_model(
					modelId="us.amazon.nova-lite-v1:0",
					body=json.dumps({
						"messages": [{
							"role": "user",
							"content": [{"text": prompt}]}]
					})
				)
			else:
				raise

		result = json.loads(response["body"].read())
		summary_text = result["output"]["message"]["content"][0]["text"]
		summary = normalize_bedrock_json(summary_text)
		logger.info("Summary generated: %s", summary)
		table.update_item(
				Key={"audioId": audio_id},
				UpdateExpression="SET #s = :s, summary = :summary",
				ExpressionAttributeNames={
					"#s": "status"
				},
				ExpressionAttributeValues={
						":s": "SUMMARY_GENERATED", 
						":summary": summary
				}
			)
		
		data = {
			"audioId": audio_id,
			"summary": summary,
			"status": "SUMMARY_GENERATED"
		}
		return data
	else:
			raise Exception(f"Unknown stage: {stage}")