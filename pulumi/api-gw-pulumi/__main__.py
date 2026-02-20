"""An AWS Python Pulumi program"""

import pulumi
import pulumi_aws as aws
import pulumi_archive as archive
import json

stack = pulumi.get_stack()
config = pulumi.Config()
region = aws.get_region().name
account_id = aws.get_caller_identity().account_id
application = config.get("application")
environment = {
    "dev": "development"
}

cw_log_group = aws.cloudwatch.LogGroup("cw_log_group",
    name=f"/aws/lambda/{application}-lambda",
    retention_in_days=14)

logging_policy_def = aws.iam.get_policy_document(statements=[{
    "effect": "Allow",
    "actions": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
    ],
    "resources": ["arn:aws:logs:*:*:*"],
}])

logging_policy = aws.iam.Policy("logging_policy",
    name=f"{application}-logging-policy",
    path="/",
    description="IAM policy for logging from a lambda",
    policy=logging_policy_def.json)

role = aws.iam.Role("lambda_role",
    name = f"{application}-lambda-role",
    assume_role_policy=json.dumps({
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": { "Service": "lambda.amazonaws.com" },
            "Action": "sts:AssumeRole"
        }]
    })
)

policy_attachment = aws.iam.RolePolicyAttachment("policy_attachment",
    role=role.name,
    policy_arn=logging_policy.arn)

lambda_zip = archive.get_file(type="zip",
    source_file="lambda.py",
    output_path="lambda_function.zip")

lambda_function = aws.lambda_.Function("lambda",
    name=f"{application}-lambda",
    code=pulumi.FileArchive("lambda_function.zip"),
    runtime=aws.lambda_.Runtime.PYTHON3D12,
    role=role.arn,
    handler="lambda.handler",
    opts = pulumi.ResourceOptions(depends_on=[
            policy_attachment,
            cw_log_group,
        ]))

apigw = aws.apigatewayv2.Api("api_gateway",
    name=f"{application}-http-api",
    protocol_type="HTTP")

allow_apigw = aws.lambda_.Permission("allow_apigw",
    statement_id="AllowExecutionFromAPIGateway",
    action="lambda:InvokeFunction",
    function=lambda_function.name,
    principal="apigateway.amazonaws.com",
    source_arn= apigw.id.apply(lambda id: f"arn:aws:execute-api:{region}:{account_id}:{id}/*"))

dev_stage = aws.apigatewayv2.Stage("dev_stage",
    name="dev-stage",
    api_id=apigw.id,
    stage_variables = {
        "environment": environment[stack]
    })

all_route = aws.apigatewayv2.Route("all_route",
    api_id=apigw.id,
    route_key="$default")

health_route = aws.apigatewayv2.Route("health_route",
    api_id=apigw.id,
    route_key="ANY /health")

apigw_lambda_integration = aws.apigatewayv2.Integration("apigw_lambda_integration",
    api_id=apigw.id,
    integration_type="AWS_PROXY",
    connection_type="INTERNET",
    description="Lambda Integration",
    integration_method="POST",
    integration_uri=lambda_function.invoke_arn,
    passthrough_behavior="WHEN_NO_MATCH")

get_health_route = aws.apigatewayv2.Route("get_health_route",
    api_id=apigw.id,
    route_key="GET /health",
    target=apigw_lambda_integration.id.apply(lambda id: f"integrations/{id}")) #integrations/Calling __str__ on an Output[T]  if apply is not used # works like promises in node


pulumi.export("role_arn",role.arn)
pulumi.export("apigw_arn",apigw.arn)
pulumi.export("stack",stack)

