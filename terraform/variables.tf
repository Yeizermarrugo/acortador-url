variable "lambda_function_name" {
  description = "Nombre de la función Lambda principal"
  type        = string
  default     = "url-shortener-lambda"
}

# variable "dynamo_table_name" {
#   description = "Nombre de la tabla DynamoDB"
#   type        = string
#   default     = "shortener-table"
# }

# variable "domain" {
#   description = "Dominio base para las URLs cortas"
#   type        = string
#   default     = "https://miweb.com"
# }
