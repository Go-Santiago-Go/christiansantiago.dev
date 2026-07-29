# An HTTP API rather than a REST API. The REST product carries request
# validators, usage plans, and API keys, none of which this uses, and charges
# roughly three and a half times as much per million requests.
resource "aws_apigatewayv2_api" "counter" {
  name          = local.counter_name
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "counter" {
  api_id = aws_apigatewayv2_api.counter.id

  # Passes the request through untouched and returns whatever the function
  # gives back, so routing and response shaping stay in the Go code rather than
  # in mapping templates here.
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.counter.invoke_arn

  # Must match the events.APIGatewayV2HTTPRequest the handler unmarshals into.
  # Version 1.0 is the REST shape, and it decodes into an empty struct without
  # reporting an error.
  payload_format_version = "2.0"
}

# The prefix is part of the route because CloudFront forwards the path
# unchanged, so what the browser asks for is what arrives here.
resource "aws_apigatewayv2_route" "count" {
  api_id    = aws_apigatewayv2_api.counter.id
  route_key = "GET /api/count"
  target    = "integrations/${aws_apigatewayv2_integration.counter.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id = aws_apigatewayv2_api.counter.id

  # The literal name that means no stage prefix in the URL, so the routed path
  # is the path callers use.
  name        = "$default"
  auto_deploy = true

  # A public endpoint that writes to DynamoDB on every hit. This is the ceiling
  # on what an abusive caller can cost, and it sits far above anything a
  # personal site produces.
  default_route_settings {
    throttling_rate_limit  = 20
    throttling_burst_limit = 40
  }
}

# The execution role says what the function may do. This says who may invoke
# it, and without it API Gateway is refused and the caller sees a 500 raised
# before any of the handler code runs.
resource "aws_lambda_permission" "api" {
  statement_id  = "AllowInvokeFromHttpApi"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.counter.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.counter.execution_arn}/*/*"
}
