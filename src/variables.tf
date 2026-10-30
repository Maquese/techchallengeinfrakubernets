variable "aws_region" {
  type    = string
  default = "us-east-1"
}
variable "vpc_id" {
  type    = string
  default = "vpc-0c04f9d3f5e86ae50"
}
variable "subnet_ids" {
  type    = list(string)
  default = ["subnet-02cd6e93afd15dae9", "subnet-02fb07eb66ab63955"]
}
variable "eks_role_name" {
  type    = string
  default = "LabRole"
}
variable "rds_password" {
  type      = string
  sensitive = true
  default   = "minha-senha"
}

variable "auth_lambda_function_name" {
  type    = string
  default = "auto-repara-auth"
}

variable "authorizer_lambda_function_name" {
  type    = string
  default = "auto-repara-authorizer"
}

variable "container_image_clienteveiculo" {
  type    = string
  default = "maquese/clienteveiculo:latest"
}

variable "rds_identifier_clienteveiculo" {
  type    = string
  default = "clienteveiculo-mysql"
}

variable "container_image_ositemestoque" {
  type    = string
  default = "maquese/ositemestoque:latest"
}

variable "rds_identifier_ositemestoque" {
  type    = string
  default = "ordemservico-mysql"
}

variable "container_image_orcamento" {
  type    = string
  default = "maquese/orcamento:latest"
}

variable "dynamo_identifier_orcamento" {
  type    = string
  default = "Orcamento"
}

variable "datadog_api_key" {
  type    = string
  default = "3e4f4e1d5e5dbb406cc861f33fb9a4ff"
}

variable "datadog_site" {
  type    = string
  default = "datadoghq.com"
}

variable "health_check_path" {
  type    = string
  default = "/health/live"
}