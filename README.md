# Tech Challenge Infra Kubernetes

## Objetivo

Este repositório provisiona a infraestrutura necessária para executar a API da solução Auto Repara em um cluster Amazon EKS, com acesso via API Gateway, autenticação via Lambda, banco de dados RDS MySQL e monitoramento com Datadog.

O projeto foi estruturado para automatizar a criação e atualização do ambiente em AWS usando Terraform e GitHub Actions.

## Visão geral da arquitetura

```mermaid
flowchart TD
    A[GitHub Actions] --> B[Terraform CI]
    A --> C[Terraform Deploy]

    B --> D[Validação do Terraform]
    B --> E[Plan de infraestrutura]
    C --> F[Provisionamento AWS]

    F --> G[EKS Cluster]
    F --> H[Node Group]
    F --> I[RDS MySQL]
    F --> J[API Gateway]
    F --> K[Lambda Auth]
    F --> L[Lambda Authorizer]

    G --> M[Kubernetes Deployment]
    M --> N[LoadBalancer Service]
    N --> O[API .NET em container]
    O --> I
    O --> P[Datadog Agent]
    P --> Q[Datadog]

    J --> R[Cliente / Usuários / API do negócio]
    K --> R
    L --> R
```

## Tecnologias utilizadas

- Terraform
- AWS EKS
- Amazon RDS MySQL
- Amazon API Gateway
- AWS Lambda
- Kubernetes
- Helm
- Datadog
- GitHub Actions
- Docker / containers

## Estrutura do repositório

```text
techchallengeinfrakubernets/
├── .github/
│   └── workflows/
│       ├── terraform-ci.yml
│       └── terraform-deploy.yml
├── src/
│   ├── main.tf
│   ├── variables.tf
│   └── components.yaml
├── actions-runner/
├── .gitignore
└── README.md
```

## Pré-requisitos

Antes de executar ou fazer deploy deste ambiente, verifique se você possui:

- Conta AWS ativa com permissões para criar EKS, RDS, API Gateway, Lambda e IAM
- Terraform instalado
- AWS CLI configurado
- kubectl instalado
- Acesso ao cluster EKS (via `aws eks update-kubeconfig`)
- Secrets configurados no GitHub Actions:
  - `AWS_ACCESS_KEY_ID`
  - `AWS_SECRET_ACCESS_KEY`
  - `AWS_SESSION_TOKEN`
  - `AWS_REGION`
  - `TF_VAR_RDS_PASSWORD`
- Um runner self-hosted configurado com o label `eks-runner` para as pipelines do GitHub Actions

## Componentes principais

### EKS

- Cria o cluster EKS (`cluster-eks`)
- Define um node group com escalabilidade mínima e máxima
- Habilita a comunicação com o banco RDS e com os serviços da aplicação

### Banco de dados

- Utiliza um RDS MySQL já existente identificado por `techchallenge-mysql`
- O security group do RDS é ajustado para aceitar tráfego do cluster EKS

### Aplicação

- Faz deploy de três aplicações independentes, cada uma com seu `Deployment`, `Service` do tipo `LoadBalancer` e `HorizontalPodAutoscaler`:
  - Cliente/veículo (`container_image_clienteveiculo`)
  - Itens de estoque (`container_image_ositemestoque`)
  - Orçamento e ordem de serviço (`container_image_orcamento`)
- Compartilha o ConfigMap `appsettings-config`, pois as configurações ASP.NET são iguais entre os containers
- Mantém secrets separados por aplicação; ClienteVeiculo e OsItemEstoque usam suas próprias instâncias RDS, e Orcamento recebe as configurações de dados da própria aplicação
- O Terraform configura uma resource policy na tabela DynamoDB `Orcamento` para permitir operações de dados à role `LabRole`. O launch template do node group habilita IMDSv2 com hop limit 2 para permitir que os pods obtenham as credenciais do nó; assim, outros pods que alcançarem o IMDS também poderão usar as permissões da role.
- Encaminha as rotas do API Gateway para o Load Balancer da aplicação correspondente

### API Gateway

- Cria um REST API com rotas para autenticação e endpoints da API principal
- Usa Lambda authorizer para proteger endpoints de negócio
- Redireciona requisições para os serviços internos do Kubernetes

### Observabilidade

- Instala o operador do Datadog via Helm
- Configura o Datadog Agent para monitorar o cluster EKS
- Habilita coleta de logs, APM e observabilidade de clusters

## Pipeline de CI/CD

### CI: Terraform validate

Arquivo: `.github/workflows/terraform-ci.yml`

A pipeline executa quando há:

- push em branches `feature/*`
- pull request para `main`

Etapas:

1. checkout do código
2. validação da branch de origem (feature/*)
3. instalação do Terraform
4. `terraform init -backend=false`
5. `terraform fmt -check -recursive`
6. `terraform validate`
7. criação automática de pull request para `main` quando o push estiver em feature

### Plan

A etapa de `plan`:

- configura credenciais AWS
- inicializa o Terraform com backend remoto
- executa `terraform plan -out=tfplan`

### Deploy

Arquivo: `.github/workflows/terraform-deploy.yml`

A pipeline é acionada por push na branch `main` e executa:

1. checkout do código
2. instalação do Terraform
3. configuração das credenciais AWS
4. `terraform init -reconfigure -input=false`
5. `terraform apply -target=aws_eks_cluster.main -input=false -auto-approve` para criar ou atualizar o cluster antes de configurar os providers Kubernetes e Helm
6. `terraform apply -input=false -auto-approve` para aplicar toda a infraestrutura

O apply direcionado é seguido pelo apply completo na mesma execução. Ele usa o state remoto para identificar o cluster existente; não remove recursos do state nem importa deployments automaticamente. Após um destroy, a próxima execução cria novamente o cluster. A configuração ainda requer os recursos AWS consultados por data sources, como a role, as instâncias RDS, o security group e as funções Lambda.

> `TF_VAR_rds_password`, `TF_VAR_datadog_api_key` e `TF_VAR_mercadopago_access_token` são enviadas por secrets do GitHub para o apply. Configure `TF_VAR_RDS_PASSWORD`, `DD_APIKEY` e `PAGSEGURO` como secrets do repositório; o deploy também aceita secrets do environment `production`. O plan da CI não seleciona esse environment, então `PAGSEGURO` deve estar disponível como secret do repositório. O valor é disponibilizado no pod de Orçamento como `MercadoPago__AccessToken`, correspondente à configuração .NET `MercadoPago:AccessToken`.
> O deployment de Orçamento também recebe credenciais temporárias para o DynamoDB por meio do Secret `aws-credentials`. Configure `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` e, opcionalmente, `AWS_REGION` como secrets no environment `production` do GitHub Actions. Essas credenciais também ficam armazenadas no state do Terraform; proteja o acesso ao backend S3.

## Como executar localmente

### 1) Clonar o repositório

```bash
git clone <url-do-repositorio>
cd techchallengeinfrakubernets
```

### 2) Configurar AWS

```bash
aws configure
aws sts get-caller-identity
```

### 3) Inicializar Terraform

```bash
cd src
terraform init -reconfigure -input=false
```

### 4) Validar a infraestrutura

```bash
terraform fmt -check -recursive
terraform validate
```

### 5) Gerar plano

```bash
terraform plan -out=tfplan
```

Sem `-input=false`, o Terraform solicita no terminal as variáveis obrigatórias que não foram definidas no ambiente.
Para evitar os prompts das credenciais temporárias usadas pelo pod de Orçamento, você pode defini-las antes do comando, sem adicioná-las a arquivos versionados:

```powershell
$env:TF_VAR_aws_access_key_id = "<access-key-id>"
$env:TF_VAR_aws_secret_access_key = "<secret-access-key>"
$env:TF_VAR_aws_session_token = "<session-token>"
terraform plan -out=tfplan
```

### 6) Aplicar infraestrutura

```bash
terraform apply -auto-approve
```

### 7) Verificar saídas

```bash
terraform output
```

Saídas esperadas:

- `api_url` 
- `load_balancer_url`
- `load_balancer_url_clienteveiculo`
- `load_balancer_url_ositemestoque`
- `load_balancer_url_orcamento`
- `eks_cluster_name`

## Acesso à aplicação e documentação

A aplicação é exposta através do API Gateway e também por um Load Balancer do Kubernetes.

### Swagger / OpenAPI

O Terraform configura um endpoint no API Gateway para expor a documentação Swagger da aplicação na rota raiz, acessível por:

```text
https://<api-id>.execute-api.<regiao>.amazonaws.com/prod/
```

Também é possível acessar diretamente a documentação da API a partir do load balancer, se a aplicação estiver rodando no EKS:

```text
http://<load-balancer-host>/swagger/index.html
```

### Postman

Para testar a API no Postman, use a URL base gerada pelo API Gateway:

```text
https://<api-id>.execute-api.<regiao>.amazonaws.com/prod
```

Se houver uma collection oficial do projeto, ela deve ser adicionada aqui no formato:

```text
https://www.postman.com/<workspace>/<collection>
```

## Observações importantes

- Os valores sensíveis devem sempre ficar em secrets, nunca em código versionado.
- O projeto usa um backend S3 para o state do Terraform.
- O cluster EKS e a aplicação dependem de permissões AWS previamente configuradas no ambiente do runner.
- O canal `prod` no API Gateway é a etapa final do deployment público da API.

## Boas práticas recomendadas

- Usar secret management para credenciais de banco e tokens
- Manter o Terraform em uma branch `feature/*` até merge em `main`
- Revisar sempre o plano antes de aplicar mudanças de infraestrutura
- Monitorar logs e métricas via Datadog após o deploy

## Referências rápidas

- Terraform: `src/main.tf`
- Variáveis: `src/variables.tf`
- Manifestos Kubernetes: `src/components.yaml`
- Pipeline CI: `.github/workflows/terraform-ci.yml`
- Pipeline Deploy: `.github/workflows/terraform-deploy.yml`
