resource "aws_s3_bucket" "bucket" {
  bucket = "${var.application_name}-audio-summarizer"
  tags   = var.tags
}

resource "aws_s3_bucket_versioning" "uploads" {
  bucket = aws_s3_bucket.bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_cors_configuration" "uploads" {
  bucket = aws_s3_bucket.bucket.id
  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = [
      "PUT",
      "GET"
    ]
    allowed_origins = [
      "http://localhost:3000",
      "http://localhost:5173",
      "http://localhost:5174",
      "https://${aws_cloudfront_distribution.this.domain_name}/"
    ]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "${var.application_name}-oac"
  description                       = "Origin access control for Frontend"
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
    origin_id                = "audio-summarizer-s3-origin"
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "audio-summarizer-s3-origin"
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

resource "aws_dynamodb_table" "audios" {
  name         = "${var.application_name}-audios"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "audioId"
  tags         = var.tags
  attribute {
    name = "audioId"
    type = "S"
  }
}

resource "aws_iam_role" "lambda_role" {
  name = "${var.application_name}-audio-summarizer-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_role_policy" {
  name = "${var.application_name}-audio-summarizer-lambda-role-policy"
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          "${aws_s3_bucket.bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:GetItem"
        ],
        Resource = aws_dynamodb_table.audios.arn
      },
      {
        Effect = "Allow",
        Action = [
          "transcribe:StartTranscriptionJob",
          "transcribe:GetTranscriptionJob"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "bedrock:InvokeModel"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "states:StartExecution"
        ],
        Resource = "arn:aws:states:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:stateMachine:${var.application_name}-pipeline"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "archive_file" "audio_lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/scripts/audio_lambda.py"
  output_path = "${path.module}/scripts/audio_lambda.zip"
}

resource "aws_lambda_function" "audio_handler" {
  function_name    = "${var.application_name}-audio-handler"
  role             = aws_iam_role.lambda_role.arn
  runtime          = "python3.14"
  handler          = "audio_lambda.lambda_handler"
  filename         = "scripts/audio_lambda.zip"
  source_code_hash = data.archive_file.audio_lambda_zip.output_base64sha256
  depends_on       = [data.archive_file.audio_lambda_zip]
  environment {
    variables = {
      AUDIOS_BUCKET_NAME = aws_s3_bucket.bucket.bucket
      AUDIOS_TABLE_NAME  = aws_dynamodb_table.audios.name
      STEP_FUNCTION_ARN  = "arn:aws:states:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:stateMachine:${var.application_name}-pipeline"
    }
  }
}

resource "aws_apigatewayv2_api" "http_api" {
  name          = "audio-api"
  protocol_type = "HTTP"
  cors_configuration {
    allow_origins = [
      "http://localhost:5174",
      "https://${aws_cloudfront_distribution.this.domain_name}/"
    ]
    allow_methods = ["POST", "OPTIONS", "GET"]
    allow_headers = ["content-type"]
    max_age       = 300
  }
}

resource "aws_apigatewayv2_integration" "upload" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.audio_handler.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "audio_handler" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /audio_handler"
  target    = "integrations/${aws_apigatewayv2_integration.upload.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "api" {
  statement_id  = "AllowExecutionFromApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.audio_handler.function_name
  principal     = "apigateway.amazonaws.com"
}


resource "aws_iam_role" "step_functions_role" {
  name = "${var.application_name}-sf-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "states.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "sf_lambda_policy" {
  name = "${var.application_name}-sf-lambda-policy"
  role = aws_iam_role.step_functions_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "lambda:InvokeFunction"
      ]
      Resource = aws_lambda_function.audio_handler.arn
    }]
  })
}

resource "aws_sfn_state_machine" "audio_pipeline" {
  name     = "${var.application_name}-pipeline"
  role_arn = aws_iam_role.step_functions_role.arn
  definition = jsonencode({
    StartAt = "START_AUDIO_TRANSCRIPTION",
    States = {
      "START_AUDIO_TRANSCRIPTION" = {
        Type     = "Task",
        Resource = aws_lambda_function.audio_handler.arn,
        Parameters = {
          stage       = "START_AUDIO_TRANSCRIPTION",
          "audioId.$" = "$.audioId",
        },
        Next = "GET_TRANSCRIPTION_STATUS"
      }
      "GET_TRANSCRIPTION_STATUS" = {
        Type     = "Task"
        Resource = aws_lambda_function.audio_handler.arn
        Parameters = {
          stage       = "GET_TRANSCRIPTION_STATUS"
          "audioId.$" = "$.audioId"
          "jobName.$" = "$.jobName"
        }
        Next = "CHECK_TRANSCRIPTION_STATUS"
      }
      "CHECK_TRANSCRIPTION_STATUS" = {
        Type = "Choice"
        Choices = [
          {
            Variable     = "$.status"
            StringEquals = "TRANSCRIPTION_COMPLETED"
            Next         = "PROCESS_TRANSCRIPT"
          },
          {
            Variable     = "$.status"
            StringEquals = "TRANSCRIPTION_FAILED"
            Next         = "FAILED_STATE"
          }
        ]
        Default = "WAIT_5_SECONDS"
      }
      "PROCESS_TRANSCRIPT" = {
        Type     = "Task"
        Resource = aws_lambda_function.audio_handler.arn
        Parameters = {
          stage       = "PROCESS_TRANSCRIPT"
          "audioId.$" = "$.audioId"
          "jobName.$" = "$.jobName"
        }
        Next = "SUMMARIZE_USING_BEDROCK"
      }
      WAIT_5_SECONDS = {
        Type    = "Wait"
        Seconds = 5
        Next    = "GET_TRANSCRIPTION_STATUS"
      }
      SUCCESS = {
        Type = "Succeed"
      }
      FAILED_STATE = {
        Type  = "Fail"
        Error = "TranscriptionFailed"
        Cause = "Transcription job returned FAILED status"
      }
      SUMMARIZE_USING_BEDROCK = {
        Type     = "Task",
        Resource = aws_lambda_function.audio_handler.arn,
        Parameters = {
          stage       = "GET_SUMMARY_FROM_TRANSCRIPT",
          "audioId.$" = "$.audioId"
        },
        Next = "SUCCESS"
      }
    }
  })
}