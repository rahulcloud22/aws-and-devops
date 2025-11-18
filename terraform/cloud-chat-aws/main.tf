
resource "aws_s3_bucket" "bucket" {
  bucket = "${var.application_name}-cloud-chat"
  tags   = var.tags
}

resource "aws_s3_bucket_policy" "bucket" {
  bucket = aws_s3_bucket.bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.bucket.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.this.arn
          }
        }
      }
    ]
  })
}

resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "cloud-chat-oac"
  description                       = "Origin access control for Portfolio"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100"
  tags                = var.tags

  origin {
    domain_name              = aws_s3_bucket.bucket.bucket_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
    origin_id                = "cloud-chat-s3-origin"
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "cloud-chat-s3-origin"
    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }

  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
      locations        = []
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}


resource "aws_cognito_user_pool" "pool" {
  name                     = "${var.application_name}-cognito-user-pool"
  username_attributes      = ["email"]
  auto_verified_attributes = []
  tags                     = var.tags
  lambda_config {
    pre_sign_up = aws_lambda_function.pre_signup.arn
  }
}

resource "aws_cognito_user_pool_client" "this" {
  name                                 = "local-webapp-client"
  user_pool_id                         = aws_cognito_user_pool.pool.id
  generate_secret                      = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows = [
    "code"
  ]
  allowed_oauth_scopes = [
    "openid",
    "email",
    "profile"
  ]
  supported_identity_providers = [
    "COGNITO"
  ]
  callback_urls = [
    "http://localhost:3000/callback",
    "https://${aws_cloudfront_distribution.this.domain_name}/callback"
  ]
  logout_urls = [
    "http://localhost:3000/",
    "https://${aws_cloudfront_distribution.this.domain_name}/"
  ]
  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]
}

resource "aws_cognito_user_pool_domain" "this" {
  domain       = "${var.application_name}-chatbot"
  user_pool_id = aws_cognito_user_pool.pool.id
}

data "archive_file" "pre_signup_zip" {
  type        = "zip"
  source_file = "${path.module}/scripts/cognito_lambda.js"
  output_path = "${path.module}/scripts/cognito_lambda.zip"
}

resource "aws_lambda_permission" "allow_cognito" {
  statement_id  = "AllowCognitoInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pre_signup.function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.pool.arn
}

resource "aws_lambda_function" "pre_signup" {
  function_name    = "${var.application_name}-cognito-lambda"
  role             = aws_iam_role.lambda_role.arn
  handler          = "cognito_lambda.handler"
  runtime          = "nodejs18.x"
  filename         = "cognito_lambda.zip"
  source_code_hash = data.archive_file.pre_signup_zip.output_base64sha256
}

resource "aws_apigatewayv2_api" "this" {
  name                       = "${var.application_name}-websocket"
  protocol_type              = "WEBSOCKET"
  route_selection_expression = "$request.body.action"
  tags                       = var.tags
}

# TODO: WebSocket Lambda Authorizer Cognito

resource "aws_apigatewayv2_integration" "connect" {
  api_id             = aws_apigatewayv2_api.this.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.chat_handler.invoke_arn
  integration_method = "POST"
}
resource "aws_apigatewayv2_route" "connect" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "$connect"
  target    = "integrations/${aws_apigatewayv2_integration.connect.id}"
}

resource "aws_apigatewayv2_route" "disconnect" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "$disconnect"
  target    = "integrations/${aws_apigatewayv2_integration.connect.id}"
}

resource "aws_apigatewayv2_route" "send_message" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "sendMessage"
  target    = "integrations/${aws_apigatewayv2_integration.connect.id}"
}

resource "aws_apigatewayv2_route" "get_messages" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "getMessages"
  target    = "integrations/${aws_apigatewayv2_integration.connect.id}"
}

resource "aws_apigatewayv2_stage" "dev" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "dev"
  auto_deploy = true
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/scripts/lambda_function.py"
  output_path = "${path.module}/scripts/lambda.zip"
}

resource "aws_iam_role" "lambda_role" {
  name = "${var.application_name}-chat-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "chat_handler" {
  function_name    = "${var.application_name}-chat-handler"
  role             = aws_iam_role.lambda_role.arn
  runtime          = "python3.14"
  handler          = "lambda_function.lambda_handler"
  filename         = "lambda.zip"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  depends_on       = [data.archive_file.lambda_zip]
  environment {
    variables = {
      DYNAMODB_CONNECTIONS_TABLE = aws_dynamodb_table.chat_connections.name
      DYNAMODB_MESSAGES_TABLE    = aws_dynamodb_table.chat_messages.name
      WS_ENDPOINT                = replace(aws_apigatewayv2_stage.dev.invoke_url, "wss://", "https://")
    }
  }
}

resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.chat_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*"
}

resource "aws_dynamodb_table" "chat_connections" {
  name         = "${var.application_name}-chat-connections"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "connectionId"
  tags         = var.tags
  attribute {
    name = "connectionId"
    type = "S"
  }
}

resource "aws_dynamodb_table" "chat_messages" {
  name         = "${var.application_name}-chat-messages"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "messageId"
  tags         = var.tags
  attribute {
    name = "messageId"
    type = "S"
  }
}

resource "aws_iam_role_policy" "chat_connections_ddb" {
  name = "ChatConnectionsDynamoDBAccess"
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.chat_connections.arn,
          aws_dynamodb_table.chat_messages.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_api_gw_connections" {
  name = "LambdaWebSocketManageConnections"
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "execute-api:ManageConnections"
        ]
        Resource = "arn:aws:execute-api:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:${aws_apigatewayv2_api.this.id}/*/POST/@connections/*"
      }
    ]
  })
}