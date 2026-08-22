terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.31.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.38.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "1.19.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_iam_role" "lab" {
  name = var.eks_role_name
}
data "aws_eks_cluster_auth" "main" {
  name = aws_eks_cluster.main.name
}

data "aws_db_instance" "main" {
  db_instance_identifier = var.rds_identifier
}

data "aws_security_group" "rds" {
  filter {
    name   = "group-name"
    values = ["rds-sg"]
  }

  vpc_id = var.vpc_id
}

data "aws_lambda_function" "auth" {
  function_name = var.auth_lambda_function_name
}

data "aws_lambda_function" "authorizer" {
  function_name = var.authorizer_lambda_function_name
}

provider "kubernetes" {
  host                   = aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.main.token
}

provider "kubectl" {
  host                   = aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.main.token
  load_config_file       = false
}


resource "aws_eks_cluster" "main" {
  name     = "cluster-eks"
  role_arn = data.aws_iam_role.lab.arn
  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_public_access  = true
    endpoint_private_access = true
  }
}

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "cluster-eks-nodes"
  node_role_arn   = data.aws_iam_role.lab.arn
  subnet_ids      = var.subnet_ids
  scaling_config {
    desired_size = 2
    min_size     = 1
    max_size     = 4
  }
  instance_types = ["t3.micro"]
  capacity_type  = "ON_DEMAND"
}

resource "aws_security_group_rule" "allow_eks_to_rds" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id        = data.aws_security_group.rds.id
  source_security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

resource "kubernetes_config_map_v1" "appsettings" {
  metadata {
    name = "appsettings-config"
  }
  data = {
    ASPNETCORE_ENVIRONMENT = "Production"
    ASPNETCORE_URLS        = "http://+:80"
    "appsettings.Production.json" = jsonencode({
      Logging      = { LogLevel = { Default = "Information", Microsoft = "Warning", "Microsoft.Hosting.Lifetime" = "Information" } }
      AllowedHosts = "*"
    })
  }
  depends_on = [aws_eks_node_group.main]
}

resource "kubernetes_secret_v1" "app" {
  metadata {
    name = "app-secrets"
  }
  type = "Opaque"
  data = {
    "ConnectionStrings__DefaultConnection" = "Server=${data.aws_db_instance.main.address};Port=3306;Database=Tests;User=root;Password=${var.rds_password};"
    "Jwt__SecretKey"                       = "sua-chave-super-secreta-muito-longa-para-256bits-change-me"
    "Jwt__Issuer"                          = "GestaoAutoRepara"
    "Jwt__Audience"                        = "GestaoAutoReparaUsers"
    "Jwt__ExpirationMinutes"               = "60"
  }
  depends_on = [aws_eks_node_group.main]
}

resource "kubernetes_deployment_v1" "app" {
  metadata {
    name = "auto-repara-deployment"
  }
  spec {
    replicas = 1
    selector {
      match_labels = { app = "auto-repara-api" }
    }
    template {
      metadata {
        labels = { app = "auto-repara-api" }
      }
      spec {
        container {
          name              = "auto-repara-api"
          image             = var.container_image
          image_pull_policy = "IfNotPresent"
          env_from {
            config_map_ref {
              name = kubernetes_config_map_v1.appsettings.metadata[0].name
            }
          }
          env_from {
            secret_ref {
              name = kubernetes_secret_v1.app.metadata[0].name
            }
          }
          port {
            name           = "http"
            container_port = 80
            protocol       = "TCP"
          }
          resources {
            requests = { cpu = "100m", memory = "200Mi" }
            limits   = { cpu = "500m", memory = "512Mi" }
          }
        }
      }
    }
  }
  depends_on = [kubernetes_config_map_v1.appsettings, kubernetes_secret_v1.app]
}

resource "kubernetes_service_v1" "app" {
  metadata {
    name = "auto-repara-svc"
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-scheme"  = "internet-facing"
      "service.beta.kubernetes.io/aws-load-balancer-subnets" = join(",", var.subnet_ids)
    }
  }
  spec {
    selector = { app = "auto-repara-api" }
    port {
      name        = "http"
      port        = 80
      target_port = "http"
    }
    type = "LoadBalancer"
  }
  wait_for_load_balancer = true
  depends_on             = [kubernetes_deployment_v1.app]
}

resource "kubectl_manifest" "metrics_server" {
  yaml_body  = file("${path.module}/components.yaml")
  depends_on = [aws_eks_node_group.main]
}

locals {
  application_base_url = "http://${kubernetes_service_v1.app.status[0].load_balancer[0].ingress[0].hostname}"
}

resource "aws_api_gateway_rest_api" "main" {
  name = "example"
  body = jsonencode({
    openapi = "3.0.1"
    info    = { title = "example", version = "1.0" }
    components = { securitySchemes = { lambda_authorizer = {
      type                         = "apiKey"
      name                         = "Authorization"
      in                           = "header"
      x-amazon-apigateway-authtype = "custom"
      x-amazon-apigateway-authorizer = {
        type                         = "token"
        authorizerUri                = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${data.aws_lambda_function.authorizer.arn}/invocations"
        authorizerResultTtlInSeconds = 0
      }
    } } }
    paths = {
      "/auth/usuario" = { post = { x-amazon-apigateway-integration = {
        httpMethod           = "POST"
        payloadFormatVersion = "1.0"
        type                 = "AWS_PROXY"
        uri                  = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${data.aws_lambda_function.auth.arn}/invocations"
      } } }
      "/" = { get = { x-amazon-apigateway-integration = {
        httpMethod           = "GET"
        payloadFormatVersion = "1.0"
        type                 = "HTTP_PROXY"
        uri                  = "${local.application_base_url}/swagger/index.html"
      } } }
      "/api/Cliente/BuscarCliente" = { get = {
        security = [{ lambda_authorizer = [] }]
        x-amazon-apigateway-integration = {
          httpMethod           = "GET"
          payloadFormatVersion = "1.0"
          type                 = "HTTP_PROXY"
          uri                  = "${local.application_base_url}/api/Cliente/BuscarCliente"
        }
      } }
    }
  })
}

resource "aws_lambda_permission" "auth_api_gateway" {
  statement_id  = "AllowApiGatewayInvokeAuth"
  action        = "lambda:InvokeFunction"
  function_name = data.aws_lambda_function.auth.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "authorizer_api_gateway" {
  statement_id  = "AllowApiGatewayInvokeAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = data.aws_lambda_function.authorizer.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  triggers    = { redeployment = sha1(jsonencode(aws_api_gateway_rest_api.main.body)) }
  lifecycle { create_before_destroy = true }
  depends_on = [aws_lambda_permission.auth_api_gateway, aws_lambda_permission.authorizer_api_gateway]
}

resource "aws_api_gateway_stage" "main" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = "example"
}

output "api_url" { value = "https://${aws_api_gateway_rest_api.main.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.main.stage_name}" }
output "load_balancer_url" { value = local.application_base_url }
output "eks_cluster_name" { value = aws_eks_cluster.main.name }
