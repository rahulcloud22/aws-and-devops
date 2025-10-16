import pulumi
import pulumi_aws as aws
import json
import zipfile

config = pulumi.Config()
project_name = config.require("project_name")

lambda_role = aws.iam.Role("lambda_role",
    name=project_name + "-role",
    assume_role_policy=json.dumps({
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Action": "sts:AssumeRole",
            "Principal": {
                "Service": "lambda.amazonaws.com",
            }
        }]
    }))

aws.iam.RolePolicyAttachment("lambda_basic_execution",
    role=lambda_role.name,
    policy_arn="arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole")

zip_path = "lambda_function.zip"
with zipfile.ZipFile(zip_path, "w") as z:
    z.write("lambda_function.py")

lambda_function = aws.lambda_.Function("lambda_function",
    name=project_name + "-function",
    role=lambda_role.arn,
    runtime="python3.12",
    handler="lambda_function.handler", 
    timeout=120,
    code=pulumi.FileArchive(zip_path))

log_group = aws.cloudwatch.LogGroup("lambda_log_group",
    name=pulumi.Output.concat("/aws/lambda/", lambda_function.name),
    retention_in_days=7
)

pulumi.export("lambda_name", lambda_function.name)
pulumi.export("lambda_arn", lambda_function.arn)
pulumi.export("role_arn", lambda_role.arn)
