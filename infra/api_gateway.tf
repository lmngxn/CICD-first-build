locals {
  lambda_invoke_uri = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.items.arn}/invocations"
}

# REST API
resource "aws_api_gateway_rest_api" "items" {
  name = "items-api-${var.stage_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# /items resource
resource "aws_api_gateway_resource" "items" {
  rest_api_id = aws_api_gateway_rest_api.items.id
  parent_id   = aws_api_gateway_rest_api.items.root_resource_id
  path_part   = "items"
}

# /items/{id} resource
resource "aws_api_gateway_resource" "item" {
  rest_api_id = aws_api_gateway_rest_api.items.id
  parent_id   = aws_api_gateway_resource.items.id
  path_part   = "{id}"
}

# Methods
resource "aws_api_gateway_method" "get_items" {
  rest_api_id      = aws_api_gateway_rest_api.items.id
  resource_id      = aws_api_gateway_resource.items.id
  http_method      = "GET"
  authorization    = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_method" "post_items" {
  rest_api_id      = aws_api_gateway_rest_api.items.id
  resource_id      = aws_api_gateway_resource.items.id
  http_method      = "POST"
  authorization    = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_method" "get_item" {
  rest_api_id      = aws_api_gateway_rest_api.items.id
  resource_id      = aws_api_gateway_resource.item.id
  http_method      = "GET"
  authorization    = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_method" "put_item" {
  rest_api_id      = aws_api_gateway_rest_api.items.id
  resource_id      = aws_api_gateway_resource.item.id
  http_method      = "PUT"
  authorization    = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_method" "delete_item" {
  rest_api_id      = aws_api_gateway_rest_api.items.id
  resource_id      = aws_api_gateway_resource.item.id
  http_method      = "DELETE"
  authorization    = "NONE"
  api_key_required = true
}

# AWS_PROXY integrations (all route to the same Lambda)
resource "aws_api_gateway_integration" "get_items" {
  rest_api_id             = aws_api_gateway_rest_api.items.id
  resource_id             = aws_api_gateway_resource.items.id
  http_method             = aws_api_gateway_method.get_items.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = local.lambda_invoke_uri
}

resource "aws_api_gateway_integration" "post_items" {
  rest_api_id             = aws_api_gateway_rest_api.items.id
  resource_id             = aws_api_gateway_resource.items.id
  http_method             = aws_api_gateway_method.post_items.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = local.lambda_invoke_uri
}

resource "aws_api_gateway_integration" "get_item" {
  rest_api_id             = aws_api_gateway_rest_api.items.id
  resource_id             = aws_api_gateway_resource.item.id
  http_method             = aws_api_gateway_method.get_item.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = local.lambda_invoke_uri
}

resource "aws_api_gateway_integration" "put_item" {
  rest_api_id             = aws_api_gateway_rest_api.items.id
  resource_id             = aws_api_gateway_resource.item.id
  http_method             = aws_api_gateway_method.put_item.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = local.lambda_invoke_uri
}

resource "aws_api_gateway_integration" "delete_item" {
  rest_api_id             = aws_api_gateway_rest_api.items.id
  resource_id             = aws_api_gateway_resource.item.id
  http_method             = aws_api_gateway_method.delete_item.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = local.lambda_invoke_uri
}

# Lambda invoke permission for API Gateway
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.items.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.items.execution_arn}/*/*"
}

# Deployment — triggers redeployment when any method or integration changes
resource "aws_api_gateway_deployment" "items" {
  rest_api_id = aws_api_gateway_rest_api.items.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.items.id,
      aws_api_gateway_resource.item.id,
      aws_api_gateway_method.get_items.id,
      aws_api_gateway_method.post_items.id,
      aws_api_gateway_method.get_item.id,
      aws_api_gateway_method.put_item.id,
      aws_api_gateway_method.delete_item.id,
      aws_api_gateway_integration.get_items.id,
      aws_api_gateway_integration.post_items.id,
      aws_api_gateway_integration.get_item.id,
      aws_api_gateway_integration.put_item.id,
      aws_api_gateway_integration.delete_item.id,
    ]))
  }

  depends_on = [
    aws_api_gateway_integration.get_items,
    aws_api_gateway_integration.post_items,
    aws_api_gateway_integration.get_item,
    aws_api_gateway_integration.put_item,
    aws_api_gateway_integration.delete_item,
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# CloudWatch log group for API Gateway access logs
resource "aws_cloudwatch_log_group" "api_gw" {
  name              = "/aws/api-gateway/items-api-${var.stage_name}"
  retention_in_days = 14
}

# Account-level setting: grants API Gateway permission to write to CloudWatch
resource "aws_api_gateway_account" "main" {
  cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch.arn
}

# Stage
resource "aws_api_gateway_stage" "dev" {
  deployment_id = aws_api_gateway_deployment.items.id
  rest_api_id   = aws_api_gateway_rest_api.items.id
  stage_name    = var.stage_name

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      httpMethod     = "$context.httpMethod"
      resourcePath   = "$context.resourcePath"
      status         = "$context.status"
      responseLength = "$context.responseLength"
      requestTime    = "$context.requestTime"
    })
  }

  depends_on = [aws_api_gateway_account.main]
}

# API key
resource "aws_api_gateway_api_key" "items" {
  name = "items-api-key-${var.stage_name}"
}

# Usage plan with throttle and quota limits
resource "aws_api_gateway_usage_plan" "items" {
  name = "items-usage-plan-${var.stage_name}"

  api_stages {
    api_id = aws_api_gateway_rest_api.items.id
    stage  = aws_api_gateway_stage.dev.stage_name
  }

  throttle_settings {
    rate_limit  = 10
    burst_limit = 20
  }

  quota_settings {
    limit  = 100
    period = "DAY"
  }
}

# Associate API key with usage plan
resource "aws_api_gateway_usage_plan_key" "items" {
  key_id        = aws_api_gateway_api_key.items.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.items.id
}
