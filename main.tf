terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # Use a recent version
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2" # Needed for zipping Lambda code
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# --- Variables ---
locals {
  project_name = "PollingAppTF"
  region       = "us-east-1"
  stage_name   = "v1"
}

# --- DynamoDB Table ---
resource "aws_dynamodb_table" "polls_table" {
  name         = "${local.project_name}-Polls"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PollID"

  attribute {
    name = "PollID"
    type = "S"
  }

  tags = {
    Name      = "${local.project_name}-Polls"
    ManagedBy = "Terraform"
  }
}

# --- IAM Role and Policy for Lambda ---
resource "aws_iam_role" "lambda_exec_role" {
  name = "${local.project_name}-LambdaRole"

  # Policy allowing Lambda service to assume this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = {
    ManagedBy = "Terraform"
  }
}

# Policy granting necessary DynamoDB permissions
resource "aws_iam_policy" "dynamodb_policy" {
  name        = "${local.project_name}-DynamoDBPolicy"
  description = "IAM policy for Lambda to access DynamoDB table"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = [
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:Scan",
        "dynamodb:UpdateItem",
        "dynamodb:Query"
      ],
      Effect   = "Allow",
      Resource = aws_dynamodb_table.polls_table.arn # Reference the table ARN
    }]
  })
}

# Attach DynamoDB policy to the role
resource "aws_iam_role_policy_attachment" "dynamodb_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.dynamodb_policy.arn
}

# Attach basic Lambda execution policy (for CloudWatch Logs)
resource "aws_iam_role_policy_attachment" "lambda_logs_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# --- Lambda Functions ---

# Data source to zip the code for each function
data "archive_file" "create_poll_zip" {
  type        = "zip"
  source_file = "create_poll.py"
  output_path = "create_poll.zip"
}
data "archive_file" "get_polls_zip" {
  type        = "zip"
  source_file = "get_polls.py"
  output_path = "get_polls.zip"
}
data "archive_file" "vote_poll_zip" {
  type        = "zip"
  source_file = "vote_poll.py"
  output_path = "vote_poll.zip"
}

# Create Poll Lambda
resource "aws_lambda_function" "create_poll" {
  function_name = "${local.project_name}-CreatePoll"
  filename      = data.archive_file.create_poll_zip.output_path
  source_code_hash = data.archive_file.create_poll_zip.output_base64sha256
  role          = aws_iam_role.lambda_exec_role.arn # Reference the role ARN
  handler       = "create_poll.lambda_handler"
  runtime       = "python3.11"

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.polls_table.name # Pass table name
    }
  }

  tags = { ManagedBy = "Terraform" }
}

# Get Polls Lambda
resource "aws_lambda_function" "get_polls" {
  function_name = "${local.project_name}-GetPolls"
  filename      = data.archive_file.get_polls_zip.output_path
  source_code_hash = data.archive_file.get_polls_zip.output_base64sha256
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "get_polls.lambda_handler"
  runtime       = "python3.11"

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.polls_table.name
    }
  }

  tags = { ManagedBy = "Terraform" }
}

# Vote Poll Lambda
resource "aws_lambda_function" "vote_poll" {
  function_name = "${local.project_name}-VotePoll"
  filename      = data.archive_file.vote_poll_zip.output_path
  source_code_hash = data.archive_file.vote_poll_zip.output_base64sha256
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "vote_poll.lambda_handler"
  runtime       = "python3.11"

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.polls_table.name
    }
  }

  tags = { ManagedBy = "Terraform" }
}

# --- API Gateway (HTTP API) ---
resource "aws_apigatewayv2_api" "polling_api" {
  name          = "${local.project_name}-Api"
  protocol_type = "HTTP"

  # CORS Configuration - Allow all origins for simplicity in this example
  # In production, restrict this to your actual frontend domain(s)
  cors_configuration {
    allow_origins = ["*"] # WARNING: Insecure for production!
    allow_methods = ["GET", "POST", "OPTIONS"] # OPTIONS is needed for CORS preflight
    allow_headers = ["Content-Type"]
    max_age       = 300
  }

  tags = { ManagedBy = "Terraform" }
}

# Integrations (linking API Gateway to Lambdas)
resource "aws_apigatewayv2_integration" "create_poll_int" {
  api_id           = aws_apigatewayv2_api.polling_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.create_poll.invoke_arn
  payload_format_version = "2.0"
}
resource "aws_apigatewayv2_integration" "get_polls_int" {
  api_id           = aws_apigatewayv2_api.polling_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.get_polls.invoke_arn
  payload_format_version = "2.0"
}
resource "aws_apigatewayv2_integration" "vote_poll_int" {
  api_id           = aws_apigatewayv2_api.polling_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.vote_poll.invoke_arn
  payload_format_version = "2.0"
}

# Routes (defining API paths)
resource "aws_apigatewayv2_route" "create_poll_route" {
  api_id    = aws_apigatewayv2_api.polling_api.id
  route_key = "POST /polls"
  target    = "integrations/${aws_apigatewayv2_integration.create_poll_int.id}"
}
resource "aws_apigatewayv2_route" "get_polls_route" {
  api_id    = aws_apigatewayv2_api.polling_api.id
  route_key = "GET /polls"
  target    = "integrations/${aws_apigatewayv2_integration.get_polls_int.id}"
}
resource "aws_apigatewayv2_route" "vote_poll_route" {
  api_id    = aws_apigatewayv2_api.polling_api.id
  route_key = "POST /polls/{pollId}/vote"
  target    = "integrations/${aws_apigatewayv2_integration.vote_poll_int.id}"
}

# Lambda Permissions (Allowing API Gateway to invoke Lambdas)
resource "aws_lambda_permission" "api_gw_create" {
  statement_id  = "AllowAPIGatewayInvokeCreate"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.create_poll.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.polling_api.execution_arn}/*/*"
}
resource "aws_lambda_permission" "api_gw_get" {
  statement_id  = "AllowAPIGatewayInvokeGet"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_polls.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.polling_api.execution_arn}/*/*"
}
 resource "aws_lambda_permission" "api_gw_vote" {
  statement_id  = "AllowAPIGatewayInvokeVote"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.vote_poll.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.polling_api.execution_arn}/*/*"
}

# Deployment Stage
resource "aws_apigatewayv2_stage" "api_stage" {
  api_id = aws_apigatewayv2_api.polling_api.id
  name   = local.stage_name
  auto_deploy = true

  # Add dependency to ensure routes are created before stage
  depends_on = [
    aws_apigatewayv2_route.create_poll_route,
    aws_apigatewayv2_route.get_polls_route,
    aws_apigatewayv2_route.vote_poll_route
  ]

   tags = { ManagedBy = "Terraform" }
}

# --- Outputs ---
output "api_base_url" {
  description = "Base URL for the Polling App API stage"
  value       = aws_apigatewayv2_stage.api_stage.invoke_url
}
output "dynamodb_table_name" {
    description = "Name of the DynamoDB table for polls"
    value = aws_dynamodb_table.polls_table.name
}