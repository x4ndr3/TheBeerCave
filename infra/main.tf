terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
  
  default_tags {
    tags = {
      Project     = "TheBeerCave"
      Environment = "Production"
      Owner       = "TheBeerCaveScotland"
      ManagedBy   = "Terraform"
    }
  }
}

# --- S3 Static Site ---

resource "aws_s3_bucket" "site" {
  bucket = "${var.project_name}-site-${random_id.suffix.hex}"
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket = aws_s3_bucket.site.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontServicePrincipal"
        Effect    = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.site.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.site.arn
          }
        }
      }
    ]
  })
}

# --- CloudFront ---

resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "${var.project_name}-oac"
  description                       = "OAC for The Beer Cave"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "site" {
  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
    origin_id                = "S3-${aws_s3_bucket.site.id}"
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  comment             = "The Beer Cave Scotland"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.site.id}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# --- DynamoDB ---

resource "aws_dynamodb_table" "messages" {
  name           = "${var.project_name}-messages"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

# --- Lambda ---

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/contact-form/index.mjs"
  output_path = "${path.module}/lambda/contact-form.zip"
}

resource "aws_lambda_function" "contact_form" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.project_name}-contact-form"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "index.handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "nodejs20.x"

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.messages.name
    }
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.project_name}-lambda-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "dynamodb_access" {
  name = "dynamodb-access"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Scan"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.messages.arn
      }
    ]
  })
}

# --- API Gateway ---

resource "aws_apigatewayv2_api" "api" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"
  cors_configuration {
    allow_origins = ["*"] # Restrict to CloudFront domain in prod
    allow_methods = ["POST", "GET", "OPTIONS"]
    allow_headers = ["content-type", "authorization"]
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id           = aws_apigatewayv2_api.api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.contact_form.invoke_arn
}

resource "aws_apigatewayv2_route" "contact" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "POST /contact"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.contact_form.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*/contact"
}

# --- Cognito User Pool ---

resource "aws_cognito_user_pool" "admin" {
  name = "${var.project_name}-admin-pool"

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = true
  }

  auto_verified_attributes = ["email"]

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true
  }
}

resource "aws_cognito_user_pool_client" "admin" {
  name         = "${var.project_name}-admin-client"
  user_pool_id = aws_cognito_user_pool.admin.id

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

  generate_secret = false
}

# --- Get Messages Lambda ---

data "archive_file" "get_messages_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/get-messages/index.mjs"
  output_path = "${path.module}/lambda/get-messages.zip"
}

resource "aws_lambda_function" "get_messages" {
  filename         = data.archive_file.get_messages_zip.output_path
  function_name    = "${var.project_name}-get-messages"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "index.handler"
  source_code_hash = data.archive_file.get_messages_zip.output_base64sha256
  runtime          = "nodejs20.x"

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.messages.name
    }
  }
}

resource "aws_lambda_permission" "apigw_get_messages" {
  statement_id  = "AllowExecutionFromAPIGatewayGetMessages"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_messages.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*/messages"
}

# --- API Gateway Authorizer ---

resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.api.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "${var.project_name}-cognito-authorizer"

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.admin.id]
    issuer   = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.admin.id}"
  }
}

resource "aws_apigatewayv2_integration" "get_messages" {
  api_id           = aws_apigatewayv2_api.api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.get_messages.invoke_arn
}

resource "aws_apigatewayv2_route" "get_messages" {
  api_id             = aws_apigatewayv2_api.api.id
  route_key          = "GET /messages"
  target             = "integrations/${aws_apigatewayv2_integration.get_messages.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

# --- Outputs ---

output "cloudfront_url" {
  value = aws_cloudfront_distribution.site.domain_name
}

output "api_url" {
  value = aws_apigatewayv2_api.api.api_endpoint
}

output "s3_bucket_name" {
  value = aws_s3_bucket.site.id
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.site.id
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.admin.id
}

output "cognito_client_id" {
  value = aws_cognito_user_pool_client.admin.id
}
