# Lambda Scaling Project

This Pulumi stack deploys an AWS Lambda function with associated IAM roles and CloudWatch logging.

## Prerequisites

- [Pulumi CLI](https://www.pulumi.com/docs/get-started/install/)
- [Python 3.9 +](https://www.python.org/downloads/)
- [AWS CLI](https://aws.amazon.com/cli/)

## Initial Setup with Virtual Environment

1. Create and activate a Python virtual environment:
   ```bash
   python -m venv .venv
   source .venv/bin/activate
   ```

2. Install required Python packages:
   ```bash
   pip install pulumi pulumi-aws boto3
   ```

3. Login to Pulumi (if you haven't already):
   ```bash
   pulumi login
   ```

4. Verify AWS configuration:
   ```bash
   aws configure
   ```

## Stack Components

This stack creates the following AWS resources:

- AWS Lambda function with Python 3.12 runtime
- IAM role and policy attachments for Lambda execution
- CloudWatch log group with 7-day retention

## Configuration

1. Create a new stack:
   ```bash
   pulumi stack init dev
   ```

2. Configure the project name:
   ```bash
   pulumi config set project_name your-project-name
   ```

## Deployment

To deploy the stack:

```bash
pulumi preview

pulumi up
```

This will:
1. Create an IAM role for the Lambda function
2. Package the Python code into a ZIP file
3. Deploy the Lambda function
4. Set up CloudWatch logging

## Stack Outputs

After deployment, the stack will output:
- `lambda_name`: The name of the deployed Lambda function
- `lambda_arn`: The ARN of the Lambda function
- `role_arn`: The ARN of the IAM role

## Testing

You can test the Lambda function through the AWS Console or using the AWS CLI:

```bash
aws lambda invoke --function-name $(pulumi stack output lambda_name) output.json
```

Note: The function will run for 90 seconds before completing.

## Clean Up

To remove all resources:

```bash
pulumi destroy
```

## Project Structure

- `__main__.py`: Main Pulumi program that defines the AWS resources
- `lambda_function.py`: The Python code that runs in the Lambda function
- `Pulumi.yaml`: Project configuration file
- `Pulumi.dev.yaml`: Stack-specific configuration file