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
variable "rds_endpoint" { type = string }
variable "rds_security_group_id" { type = string }
variable "rds_password" {
  type      = string
  sensitive = true
}
variable "lambda_function_arn" { type = string }
variable "container_image" {
  type    = string
  default = "maquese/techchallenge-3:v1"
}