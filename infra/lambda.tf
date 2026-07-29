locals {
  counter_name = "christiansantiago-dev-counter"
}

# Built by `make counter`, since Terraform packages code but cannot compile it.
data "archive_file" "counter" {
  type        = "zip"
  source_file = "${path.module}/../counter/bin/bootstrap"
  output_path = "${path.module}/build/counter.zip"
}

resource "aws_iam_role" "counter" {
  name        = local.counter_name
  description = "Execution role for the visitor counter function"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "counter" {
  name = "count-visits"
  role = aws_iam_role.counter.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # One action on one table. Deliberately no GetItem: the handler never
        # reads, because the count comes back from the write itself.
        Sid      = "IncrementCount"
        Effect   = "Allow"
        Action   = "dynamodb:UpdateItem"
        Resource = aws_dynamodb_table.visits.arn
      },
      {
        # The usual AWSLambdaBasicExecutionRole grants logs:CreateLogGroup
        # across the account. The group is created below, so the function only
        # needs to write streams into its own.
        Sid    = "WriteOwnLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "${aws_cloudwatch_log_group.counter.arn}:*"
      },
    ]
  })
}

# Left implicit, Lambda creates this on first invocation with no expiry and
# outside Terraform's state, so the logs bill forever and survive a destroy.
resource "aws_cloudwatch_log_group" "counter" {
  name              = "/aws/lambda/${local.counter_name}"
  retention_in_days = 14
}

resource "aws_lambda_function" "counter" {
  function_name = local.counter_name
  role          = aws_iam_role.counter.arn

  # provided.al2023 supplies an OS and no language runtime, so handler names
  # the executable to run rather than a symbol inside it.
  runtime       = "provided.al2023"
  handler       = "bootstrap"
  architectures = ["arm64"]

  filename = data.archive_file.counter.output_path

  # Compared against the deployed code. Without it Terraform diffs the filename,
  # sees the same path, and leaves a rebuilt binary undeployed.
  source_code_hash = data.archive_file.counter.output_base64sha256

  # CPU is allocated in proportion to memory, and this handler spends its life
  # waiting on one network call, so more would buy latency it cannot use.
  memory_size = 128

  # Generous against the handler's own 3s deadline. It exists to kill something
  # genuinely stuck, not to bound the normal path.
  timeout = 10

  environment {
    variables = {
      VISITS_TABLE = aws_dynamodb_table.visits.name
    }
  }

  # Without this the function can invoke, and create the log group, first.
  depends_on = [aws_cloudwatch_log_group.counter]
}
