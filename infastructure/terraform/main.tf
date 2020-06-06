provider "aws" {
  version = "~> 2.0"
  region  = "us-west-2"
}

data "aws_caller_identity" "current" { }
data "aws_region" "current" {}

resource "aws_iam_role" "iam_for_lambda" {
  name = "iam_for_lambda"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_lambda_function" "test_lambda" {
  filename      = "../../main.zip"
  function_name = "drewTestFunction"
  role          = aws_iam_role.iam_for_lambda.arn
  handler       = "main"

  # The filebase64sha256() function is available in Terraform 0.11.12 and later
  # For Terraform 0.11.11 and earlier, use the base64sha256() function and the file() function:
  # source_code_hash = "${base64sha256(file("lambda_function_payload.zip"))}"
  source_code_hash = filebase64sha256("../../main.zip")

  runtime = "go1.x"
}

# API Gateway
resource "aws_api_gateway_rest_api" "api" {
  name = "myapi"
  description = "Just Playing Around W/ Lamdbda and API Gateway."
}

resource "aws_api_gateway_resource" "resource" {
  path_part   = "resource"
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  rest_api_id = aws_api_gateway_rest_api.api.id
}

//Add API Key here? 
resource "aws_api_gateway_method" "method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.resource.id
  http_method   = "GET"
  authorization = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_integration" "integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.resource.id
  http_method             = aws_api_gateway_method.method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.test_lambda.invoke_arn
}

# Lambda - Can I give lambda an IAM Role? 
resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name =  aws_lambda_function.test_lambda.function_name
  principal     = "apigateway.amazonaws.com"

  # More: http://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-control-access-using-iam-policies-to-invoke-api.html
  source_arn = "arn:aws:execute-api:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.api.id}/*/${aws_api_gateway_method.method.http_method}${aws_api_gateway_resource.resource.path}"
}


resource "aws_api_gateway_deployment" "test" {
  //depends_on  = aws_api_gateway_integration.integration
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "test"
}

resource "aws_api_gateway_stage" "live" {
  stage_name    = "live"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.test.id
}


resource "aws_api_gateway_api_key" "mykey" {
  name = "my_key"
}

resource "aws_api_gateway_usage_plan" "myusageplan" {
  name = "my_usage_plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_deployment.test.stage_name
  }
}

resource "aws_api_gateway_usage_plan_key" "main" {
  key_id        = aws_api_gateway_api_key.mykey.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.myusageplan.id
}