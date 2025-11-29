
#Definimos el provedor de AWS
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

#Creamos la tabla de DynamoDB
resource "aws_dynamodb_table" "url_table" {
  name         = "Tabla1"
  hash_key     = "short_id"
  billing_mode = "PAY_PER_REQUEST"

  attribute {
    name = "short_id"
    type = "S"
  }
  tags = {
    Name = "url-shortener-map"
  }
}

#Rol para la lambda IAM
resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda-url-shortener-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

#Politica para Acceder a DynamoDb
resource "aws_iam_policy" "lambda_policy" {
  name        = "lambda-url-shortener-policy"
  description = "Permire acceso a Dynamo y ClouWatch logs"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      #Permiso para escribir logs en ClouWatch 
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:createLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:*:*:*"
      },
      #Permisos para leer y escribir en la Tabla
      {
        Effect = "Allow",
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem"
        ],
        Resource = aws_dynamodb_table.url_table.arn
      }
    ]
  })
}

#Adjunta la polituca al Rol
resource "aws_iam_role_policy_attachment" "lambda_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

#Variable para el nombre de la tabla
variable "dynamo_table_name" {
  description = "El nombre de la Tabla"
  default     = "Tabla1"
}

# 1. Empaquetado del Código
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "../dist"
  output_path = "lambda_package.zip"
}

# 2. Definición de la Función Lambda con el method Post
resource "aws_lambda_function" "shorten_url_lambda" {
  function_name    = var.lambda_function_name
  handler          = "handler.handler"
  runtime          = "nodejs20.x"
  role             = aws_iam_role.lambda_exec_role.arn
  filename         = data.archive_file.lambda_zip.output_path
  timeout          = 10
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256


  # Variables de Entorno
  environment {
    variables = {
      DYNAMODB_TABLE_NAME = var.dynamo_table_name
      BASE_URL            = "${aws_apigatewayv2_api.http_api.api_endpoint}" # Se actualiza con el endpoint
    }
  }
}

# Creación del API Gateway 
resource "aws_apigatewayv2_api" "http_api" {
  name          = "UrlShortenerAPI"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]

    allow_methods = ["POST", "GET", "OPTIONS"]

    allow_headers = ["*"]
  }
}


# Integración de Lambda con API Gateway
resource "aws_apigatewayv2_integration" "shorten_lambda_integration" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_method     = "POST"
  integration_uri        = aws_lambda_function.shorten_url_lambda.invoke_arn
  passthrough_behavior   = "WHEN_NO_MATCH"
  payload_format_version = "2.0"
}

# Definición de la Ruta: POST /shorten
resource "aws_apigatewayv2_route" "shorten_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /shorten"
  target    = "integrations/${aws_apigatewayv2_integration.shorten_lambda_integration.id}"
}

# Despliegue del API
resource "aws_apigatewayv2_stage" "api_stage" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}

# Permiso para que API Gateway invoque la Lambda
resource "aws_lambda_permission" "apigw_lambda_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.shorten_url_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

#Definimos la lambda con method GET
resource "aws_lambda_function" "surl_redirect_lambda" {
  function_name = "UrlRedirectFunction"
  handler       = "redirect_handler.handler" # archivo.export
  runtime       = "nodejs20.x"
  role          = aws_iam_role.lambda_exec_role.arn
  timeout       = 10

  # Código de la función (empaquetado)
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  # Variables de Entorno
  environment {
    variables = {
      DYNAMODB_TABLE_NAME = var.dynamo_table_name
      BASE_URL            = "https://${aws_apigatewayv2_api.http_api.api_endpoint}" # Se actualiza con el endpoint
    }
  }
}


# 1. Permiso para que API Gateway invoque la Lambda de Redirección
resource "aws_lambda_permission" "redirect_apigw_permission" {
  statement_id = "AllowExecutionFromAPIGatewayRedirect"
  action       = "lambda:InvokeFunction"
  # Apunta a la nueva función Lambda de redirección
  function_name = aws_lambda_function.surl_redirect_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

# 2. Integración de la Lambda de Redirección con API Gateway
resource "aws_apigatewayv2_integration" "redirect_lambda_integration" {
  api_id             = aws_apigatewayv2_api.http_api.id
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
  # Apunta al ARN de invocación de la nueva Lambda
  integration_uri        = aws_lambda_function.surl_redirect_lambda.invoke_arn
  payload_format_version = "2.0"
}

# 3. Definición de la Ruta: GET /{short_id}
resource "aws_apigatewayv2_route" "redirect_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /{short_id}"
  target    = "integrations/${aws_apigatewayv2_integration.redirect_lambda_integration.id}"
}
