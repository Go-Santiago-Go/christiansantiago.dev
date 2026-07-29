# The execute-api URL, used to curl the counter directly. Visitors reach it
# through CloudFront at the site's own domain instead.
output "counter_url" {
  value = "${aws_apigatewayv2_api.counter.api_endpoint}/api/count"
}
