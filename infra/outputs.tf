# The execute-api URL, used to curl the counter directly. Visitors reach it
# through CloudFront at the site's own domain instead.
output "counter_url" {
  value = "${aws_apigatewayv2_api.counter.api_endpoint}/api/count"
}

# Copied into the repository variables the workflows read. An ARN is an identifier
# and grants nothing on its own, so these are variables rather than secrets.
output "ci_role_arns" {
  value = {
    deploy = aws_iam_role.deploy.arn
    plan   = aws_iam_role.plan.arn
    apply  = aws_iam_role.apply.arn
  }
}
