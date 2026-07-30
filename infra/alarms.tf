resource "aws_sns_topic" "alerts" {
  name = "christiansantiago-dev-alerts"
}

# Confirmed out of band. AWS emails a link, and until it is clicked the
# subscription stays pending and delivers nothing while Terraform reports success.
resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# A quiet site produces no datapoints, and the default for a gap is to hold the
# previous state. All three alarms below read a gap as healthy instead, so an
# idle week cannot leave one latched.

# Any error at all. The handler's only failure path is DynamoDB, so a single one
# is already news.
resource "aws_cloudwatch_metric_alarm" "counter_errors" {
  alarm_name        = "${local.counter_name}-errors"
  alarm_description = "The visitor counter returned an error. Check /aws/lambda/${local.counter_name}."

  namespace   = "AWS/Lambda"
  metric_name = "Errors"
  dimensions  = { FunctionName = aws_lambda_function.counter.function_name }

  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]

  # The only alarm here worth a recovery email, because it is the only one that
  # means the site is currently broken.
  ok_actions = [aws_sns_topic.alerts.arn]
}

# Two periods, not one: at this traffic a single cold start can be the whole
# sample, and 1.4s of that is the runtime starting rather than anything wrong.
resource "aws_cloudwatch_metric_alarm" "counter_latency" {
  alarm_name        = "${local.counter_name}-latency-p95"
  alarm_description = "p95 latency at the API stayed above 2s across two windows."

  namespace   = "AWS/ApiGateway"
  metric_name = "Latency"
  dimensions  = { ApiId = aws_apigatewayv2_api.counter.id }

  # Latency rather than IntegrationLatency, since it includes the gateway's own
  # overhead and is therefore what the visitor waits.
  extended_statistic  = "p95"
  period              = 300
  evaluation_periods  = 2
  comparison_operator = "GreaterThanThreshold"
  threshold           = 2000
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# The stage throttle caps a five minute window near 6,000 invocations, which is
# the ceiling on the bill rather than a warning. This sits an order of magnitude
# under it, above anything a shared LinkedIn post produces.
resource "aws_cloudwatch_metric_alarm" "counter_invocations" {
  alarm_name        = "${local.counter_name}-invocation-spike"
  alarm_description = "The counter was invoked over 500 times in five minutes."

  namespace   = "AWS/Lambda"
  metric_name = "Invocations"
  dimensions  = { FunctionName = aws_lambda_function.counter.function_name }

  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 500
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
}
