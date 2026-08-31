data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda"
  output_path = "${path.module}/../lambda.zip"
  excludes    = ["node_modules", "index.test.js", "package-lock.json"]
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/items-handler"
  retention_in_days = 14
}

resource "aws_lambda_function" "items" {
  function_name    = "items-handler"
  role             = aws_iam_role.lambda.arn
  handler          = "index.handler"
  runtime          = "nodejs22.x"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = var.table_name
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy_attachment.lambda_basic,
  ]
}
