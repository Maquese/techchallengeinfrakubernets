variable "aws_region" {
  type    = string
  default = "us-east-1"
}
variable "vpc_id" {
  type    = string
  default = "vpc-0b8ea6480aff3581d"
}
variable "subnet_ids" {
  type    = list(string)
  default = ["subnet-01799be41421baa8d", "subnet-0d850838bbd1a4e72", "subnet-0a6b760a3d564676b"]
}
variable "eks_role_name" {
  type    = string
  default = "LabRole"
}
variable "rds_password" {
  type      = string
  default = "minha-senha"
}
variable "container_image" {
  type    = string
  default = "maquese/techchallenge-3:v1"
}

variable "auth_lambda_function_name" {
  type    = string
  default = "auto-repara-auth"
}

variable "authorizer_lambda_function_name" {
  type    = string
  default = "auto-repara-authorizer"
}

variable "rds_identifier" {
  type    = string
  default = "techchallenge-mysql"
}