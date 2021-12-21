
provider "aws" {
  region = "us-east-1"
}

resource "aws_dynamodb_table" "tf_modules" {
  name = "tf_modules"
  billing_mode = "PAY_PER_REQUEST"

  hash_key = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

resource "aws_dynamodb_table" "tf_providers" {
  name = "tf_providers"
  billing_mode = "PAY_PER_REQUEST"

  hash_key = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

# 2 roles
data "aws_iam_policy_document" "iam_for_lambda" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    effect = "Allow"
    sid = ""
  }
}

data "aws_iam_policy_document" "modules_lambda_policy_document" {
  statement {
    actions = ["dynamodb:GetItem","dynamodb:Query"]
    resources = [aws_dynamodb_table.tf_modules.arn, "${aws_dynamodb_table.tf_modules.arn}/index/*"]
    effect = "Allow"
  }
}

resource "aws_iam_policy" "modules_lambda_policy" {
  name = "modules-lambda-policy"
  path = "/"
  policy = data.aws_iam_policy_document.modules_lambda_policy_document.json
}

resource "aws_iam_role" "modules_lambda_role" {
  name = "modules-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.iam_for_lambda.json
}

resource "aws_iam_role_policy_attachment" "modules_role_policy_attachment" {
  role = aws_iam_role.modules_lambda_role.name
  policy_arn = aws_iam_policy.modules_lambda_policy.arn
}

data "aws_iam_policy_document" "providers_lambda_policy_document" {
  statement {
    actions = ["dynamodb:GetItem","dynamodb:Query"]
    resources = [aws_dynamodb_table.tf_providers.arn, "${aws_dynamodb_table.tf_providers.arn}/index/*"]
    effect = "Allow"
  }
}

resource "aws_iam_policy" "providers_lambda_policy" {
  name = "providers-lambda-policy"
  path = "/"
  policy = data.aws_iam_policy_document.providers_lambda_policy_document.json
}

resource "aws_iam_role" "providers_lambda_role" {
  name = "providers-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.iam_for_lambda.json
}

resource "aws_iam_role_policy_attachment" "providers_role_policy_attachment" {
  role = aws_iam_role.providers_lambda_role.name
  policy_arn = aws_iam_policy.providers_lambda_policy.arn
}

# 4 lambdas
resource "aws_lambda_function" "modules_source_lambda" {
  function_name = "modules_source_lambda"
  role = aws_iam_role.modules_lambda_role.arn
  handler = "index.handler"
  runtime = "nodejs14.x"
  filename = "src/lambdas/module_source_lambda.js"

  environment {
    variables = {
      TABLE_NAME = (aws_dynamodb_table.tf_modules.id)
    }
  }
}

resource "aws_lambda_function" "modules_versions_lambda" {
  function_name = "modules_versions_lambda"
  role = aws_iam_role.modules_lambda_role.arn
  handler = "index.handler"
  runtime = "nodejs14.x"
  filename = "src/lambdas/module_versions_lambda.js"

  environment {
    variables = {
      TABLE_NAME = (aws_dynamodb_table.tf_modules.id)
    }
  }
}

resource "aws_lambda_function" "providers_package_lambda" {
  function_name = "providers_package_lambda"
  role = aws_iam_role.providers_lambda_role.arn
  handler = "index.handler"
  runtime = "nodejs14.x"
  filename = "src/lambdas/provder_package_lambda.js"

  environment {
    variables = {
      TABLE_NAME = (aws_dynamodb_table.tf_providers.id)
    }
  }
}

resource "aws_lambda_function" "providers_versions_lambda" {
  function_name = "providers_versions_lambda"
  role = aws_iam_role.providers_lambda_role.arn
  handler = "index.handler"
  runtime = "nodejs14.x"
  filename = "src/lambdas/module_versions_lambda.js"

  environment {
    variables = {
      TABLE_NAME = (aws_dynamodb_table.tf_providers.id)
    }
  }
}

# 1 api gw
resource "aws_api_gateway_rest_api" "terraform_registry" {
  body = file("src/api-definition.yaml")

  name = "terraform_registry"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_deployment" "terraform_registry" {
  rest_api_id = aws_api_gateway_rest_api.terraform_registry.id

  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.terraform_registry.body))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "terraform_registry" {
  deployment_id = aws_api_gateway_deployment.terraform_registry.id
  rest_api_id   = aws_api_gateway_rest_api.terraform_registry.id
  stage_name    = "v1"
}