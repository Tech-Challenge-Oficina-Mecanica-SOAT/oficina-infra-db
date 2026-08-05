# Plano de Implementação — oficina-infra-db (P4)

> **Como usar este documento:** cole na sessão do Claude Code após clonar o repositório recém-criado. Ele contém contexto suficiente para o assistente entender o que precisa ser feito sem consultar outros arquivos.

---

## Contexto geral

Sou integrante de um grupo de 4 pessoas fazendo o Tech Challenge da Fase 3 do curso SOAT/FIAP. Nossa aplicação é uma API .NET para uma oficina mecânica (já entregue nas Fases 1 e 2 com Clean Architecture completa, 476 testes, 90,5% de cobertura).

Na Fase 3 dividimos o projeto em 4 repositórios:

- **oficina-mecanica-api** — Aplicação .NET (dono: P1)
- **oficina-lambda-auth** — Lambda para autenticação por CPF (dono: P2)
- **oficina-infra-k8s** — Cluster EKS + manifestos Kubernetes (dono: P3)
- **oficina-infra-db** — VPC + RDS + Secrets Manager (dono: eu, P4)

Este repositório é **infraestrutura base compartilhada**. Ele destrava todos os outros. A VPC deste repositório é consumida pelo EKS do P3 e potencialmente pela Lambda do P2.

## Ambiente de execução

**AWS Academy Learner Lab** — não é uma conta AWS normal.

Limitações críticas que afetam decisões técnicas:

- **Budget:** US$50 por conta
- **Região fixa:** us-east-1
- **IAM extremamente restrito:** NÃO é possível criar IAM roles próprias. Devemos usar apenas as pré-criadas:
  - `LabRole` — role genérica com permissões amplas para vários serviços
  - `LabInstanceProfile` — instance profile para EC2
  - `LabEksClusterRole` — role específica para EKS (Cluster e Node)
- **RDS:** apenas `db.t3.micro`, storage `gp2` até 100 GB, **Multi-AZ não permitido**, Enhanced Monitoring não suportado
- **Credenciais AWS expiram a cada sessão de 4 horas** — precisam ser renovadas do console do Academy antes de cada `terraform apply`
- **NAT Gateway continua cobrando mesmo com sessão encerrada** — rotina obrigatória de `terraform destroy` ao final do dia se não for continuar no dia seguinte

## O que este repositório entrega

**Recursos AWS:**

1. VPC (10.0.0.0/16) com 2 AZs
2. 2 subnets públicas (10.0.1.0/24, 10.0.2.0/24)
3. 2 subnets privadas (10.0.10.0/24, 10.0.20.0/24)
4. 1 NAT Gateway (single_nat_gateway=true para economia)
5. Internet Gateway
6. Route tables adequadas
7. Security Group do RDS (permite 5432 de qualquer coisa dentro da VPC — refinaremos depois)
8. RDS PostgreSQL 15.7 db.t3.micro Single-AZ, encryption at rest
9. Secret no Secrets Manager com senha aleatória do RDS
10. Secret no Secrets Manager com JWT SecretKey (compartilhada com Lambda P2 e API P1)

**Contratos publicados** (consumidos pelos outros repos):

**Parameter Store** (não sensíveis):
```
/oficina/{env}/network/vpc-id
/oficina/{env}/network/vpc-cidr
/oficina/{env}/network/public-subnet-ids       (StringList: ID1,ID2)
/oficina/{env}/network/private-subnet-ids      (StringList: ID1,ID2)
/oficina/{env}/db/endpoint
/oficina/{env}/db/port
/oficina/{env}/db/name
/oficina/{env}/db/username
/oficina/{env}/db/security-group-id
```

**Secrets Manager** (sensíveis):
```
oficina/{env}/db-password
oficina/{env}/jwt-secret-key
```

Onde `{env}` é `homolog` ou `prod`.

## Escolhas arquiteturais e justificativas

**Categoria "boa prática mantida":**

- 2 AZs na VPC — RDS DB Subnet Group exige mínimo 2 subnets em AZs diferentes, mesmo Single-AZ
- Subnets privadas para RDS — banco nunca exposto à internet
- NAT Gateway (em vez de nodes na subnet pública) — isolamento correto de rede
- storage_encrypted = true no RDS — evidência LGPD para Fase 5
- Senha do RDS via Secrets Manager — nunca em texto plano
- Security Group restritivo (será refinado quando P3 e P2 criarem seus SGs)

**Categoria "simplificação consciente":**

- RDS Single-AZ (Multi-AZ não permitido pelo Academy)
- db.t3.micro (único Burstable permitido)
- Sem Enhanced Monitoring (não suportado)
- Backup retention 1 dia (mínimo permitido; em produção seria 7+)
- 1 NAT Gateway ao invés de 2 (economia; em produção seria 1 por AZ)

Tudo isso será documentado no **ADR-009** do repositório oficina-mecanica-api.

## Estrutura de pastas esperada

```
oficina-infra-db/
├── .github/
│   └── workflows/
│       ├── plan.yml
│       └── apply.yml
├── envs/
│   ├── homolog/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── terraform.tfvars.example
│   │   └── backend.tf
│   └── prod/
│       └── (mesma estrutura)
├── modules/
│   ├── vpc/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── secrets/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── rds/
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── migrations/
│   └── run-migrations.sh
├── docs/
│   ├── ARCHITECTURE.md
│   └── diagrama-er.png
├── .gitignore
└── README.md
```

## Passo a passo executável

### Etapa 1: Bootstrap (0,5 dia)

1. Clonar o repositório recém-criado localmente
2. Criar estrutura de pastas conforme acima
3. Criar `.gitignore`:
```
**/.terraform/*
*.tfstate
*.tfstate.*
*.tfplan
*.tfvars
!*.tfvars.example
.terraformrc
```
4. Criar README.md placeholder (será finalizado na Etapa 9)
5. Criar workflow mínimo `.github/workflows/plan.yml` que roda `terraform fmt -check` e `terraform validate`
6. Fazer PR inicial, mergear em main após CI passar

### Etapa 2: Setup local AWS Academy (0,5 dia)

1. Instalar AWS CLI e Terraform (versão 1.9+)
2. No AWS Academy: Start Lab → aguardar bolinha verde → AWS Details → copiar credenciais
3. Configurar `~/.aws/credentials` com Access Key + Secret + Session Token
4. Configurar `~/.aws/config` com `region=us-east-1`
5. Testar: `aws sts get-caller-identity` deve retornar ARN válido
6. Documentar em um script `refresh-creds.sh` (não commitado) o processo de renovar credenciais toda sessão

### Etapa 3: Módulo VPC (2 dias)

Usar o módulo comunitário `terraform-aws-modules/vpc/aws` versão ~> 5.5. Não escrever VPC do zero — é padrão da indústria e é maduro.

Arquivo `modules/vpc/main.tf`:

```hcl
terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.5"

  name = "oficina-vpc-${var.environment}"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b"]
  private_subnets = ["10.0.10.0/24", "10.0.20.0/24"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true  # economia
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tags necessárias para EKS descobrir subnets
  public_subnet_tags = {
    "kubernetes.io/role/elb"                                  = 1
    "kubernetes.io/cluster/oficina-eks-${var.environment}"    = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"                         = 1
    "kubernetes.io/cluster/oficina-eks-${var.environment}"    = "shared"
  }

  tags = {
    Project     = "oficina-mecanica"
    Environment = var.environment
    ManagedBy   = "terraform"
    Repository  = "oficina-infra-db"
  }
}

# Publicar no Parameter Store
resource "aws_ssm_parameter" "vpc_id" {
  name  = "/oficina/${var.environment}/network/vpc-id"
  type  = "String"
  value = module.vpc.vpc_id
}

resource "aws_ssm_parameter" "vpc_cidr" {
  name  = "/oficina/${var.environment}/network/vpc-cidr"
  type  = "String"
  value = module.vpc.vpc_cidr_block
}

resource "aws_ssm_parameter" "public_subnet_ids" {
  name  = "/oficina/${var.environment}/network/public-subnet-ids"
  type  = "StringList"
  value = join(",", module.vpc.public_subnets)
}

resource "aws_ssm_parameter" "private_subnet_ids" {
  name  = "/oficina/${var.environment}/network/private-subnet-ids"
  type  = "StringList"
  value = join(",", module.vpc.private_subnets)
}
```

Criar `variables.tf` e `outputs.tf` correspondentes.

### Etapa 4: Módulo Secrets Manager (0,5 dia)

Cria dois secrets: senha do RDS (gerada aleatoriamente) e JWT SecretKey compartilhada.

`modules/secrets/main.tf`:

```hcl
resource "random_password" "db" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "db_password" {
  name                    = "oficina/${var.environment}/db-password"
  description             = "Senha RDS PostgreSQL - ${var.environment}"
  recovery_window_in_days = 30  # ambiente acadêmico permite destroy imediato

  tags = {
    Project     = "oficina-mecanica"
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db.result
}

resource "random_password" "jwt" {
  length  = 64
  special = false  # base64-safe
}

resource "aws_secretsmanager_secret" "jwt_key" {
  name                    = "oficina/${var.environment}/jwt-secret-key"
  description             = "JWT SecretKey compartilhada entre Lambda auth-cpf e API principal"
  recovery_window_in_days = 30
}

resource "aws_secretsmanager_secret_version" "jwt_key" {
  secret_id     = aws_secretsmanager_secret.jwt_key.id
  secret_string = random_password.jwt.result
}
```

### Etapa 5: Módulo RDS (2 dias)

Consome VPC info do Parameter Store publicado pelo próprio repo:

`modules/rds/main.tf`:

```hcl
data "aws_ssm_parameter" "vpc_id" {
  name = "/oficina/${var.environment}/network/vpc-id"
}

data "aws_ssm_parameter" "private_subnet_ids" {
  name = "/oficina/${var.environment}/network/private-subnet-ids"
}

locals {
  vpc_id             = data.aws_ssm_parameter.vpc_id.value
  private_subnet_ids = split(",", data.aws_ssm_parameter.private_subnet_ids.value)
}

resource "aws_db_subnet_group" "postgres" {
  name       = "oficina-db-subnet-group-${var.environment}"
  subnet_ids = local.private_subnet_ids

  tags = {
    Project     = "oficina-mecanica"
    Environment = var.environment
  }
}

resource "aws_security_group" "rds" {
  name        = "oficina-rds-sg-${var.environment}"
  description = "Security Group do RDS PostgreSQL"
  vpc_id      = local.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Project     = "oficina-mecanica"
    Environment = var.environment
    Name        = "oficina-rds-sg-${var.environment}"
  }
}

# Regra de ingress permissiva DENTRO da VPC
# Refinaremos com SG-to-SG referencing quando P2 e P3 criarem seus SGs
resource "aws_security_group_rule" "rds_ingress_from_vpc" {
  type              = "ingress"
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  cidr_blocks       = ["10.0.0.0/16"]
  security_group_id = aws_security_group.rds.id
  description       = "Postgres 5432 desde toda a VPC (será refinado)"
}

resource "aws_db_instance" "postgres" {
  identifier     = "oficina-db-${var.environment}"
  engine         = "postgres"
  engine_version = "15.7"
  instance_class = "db.t3.micro"

  allocated_storage     = 20
  max_allocated_storage = 20
  storage_type          = "gp2"
  storage_encrypted     = true  # LGPD

  db_name  = "oficina_mecanica"
  username = "oficina_admin"
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible = false
  multi_az            = false  # Academy não permite

  monitoring_interval          = 0  # Academy não permite Enhanced
  performance_insights_enabled = false

  backup_retention_period = 1
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  skip_final_snapshot = true
  deletion_protection = false
  apply_immediately   = true

  tags = {
    Project     = "oficina-mecanica"
    Environment = var.environment
    Name        = "oficina-db-${var.environment}"
  }
}

# Publicar endpoints no Parameter Store
resource "aws_ssm_parameter" "db_endpoint" {
  name  = "/oficina/${var.environment}/db/endpoint"
  type  = "String"
  value = aws_db_instance.postgres.address
}

resource "aws_ssm_parameter" "db_port" {
  name  = "/oficina/${var.environment}/db/port"
  type  = "String"
  value = tostring(aws_db_instance.postgres.port)
}

resource "aws_ssm_parameter" "db_name" {
  name  = "/oficina/${var.environment}/db/name"
  type  = "String"
  value = aws_db_instance.postgres.db_name
}

resource "aws_ssm_parameter" "db_username" {
  name  = "/oficina/${var.environment}/db/username"
  type  = "String"
  value = aws_db_instance.postgres.username
}

resource "aws_ssm_parameter" "db_security_group_id" {
  name  = "/oficina/${var.environment}/db/security-group-id"
  type  = "String"
  value = aws_security_group.rds.id
}
```

### Etapa 6: Migrations do EF Core (1 dia)

O RDS está em subnet privada. Duas opções para rodar migrations:

**Opção A (mais simples):** abrir temporariamente o SG do RDS para o seu IP público, rodar migration, remover regra.

**Opção B (mais correta):** criar EC2 bastion pequena com Session Manager, usar port-forward.

Recomendação: **Opção A** para o projeto acadêmico. Script `migrations/run-migrations.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ENV=${1:-homolog}
API_REPO_PATH=${2:-../oficina-mecanica-api}

echo "Buscando credenciais do RDS ambiente $ENV..."
DB_ENDPOINT=$(aws ssm get-parameter --name "/oficina/$ENV/db/endpoint" --query Parameter.Value --output text)
DB_PORT=$(aws ssm get-parameter --name "/oficina/$ENV/db/port" --query Parameter.Value --output text)
DB_NAME=$(aws ssm get-parameter --name "/oficina/$ENV/db/name" --query Parameter.Value --output text)
DB_USER=$(aws ssm get-parameter --name "/oficina/$ENV/db/username" --query Parameter.Value --output text)
DB_PASSWORD=$(aws secretsmanager get-secret-value --secret-id "oficina/$ENV/db-password" --query SecretString --output text)

cd "$API_REPO_PATH"

export ConnectionStrings__DefaultConnection="Host=$DB_ENDPOINT;Port=$DB_PORT;Database=$DB_NAME;Username=$DB_USER;Password=$DB_PASSWORD;Trust Server Certificate=true"

dotnet ef database update \
  --project src/OficinaMecanica.Infrastructure \
  --startup-project src/OficinaMecanica.API

echo "Migrations aplicadas."
```

### Etapa 7: Ambientes homolog e prod (0,5 dia)

Duplicar `envs/homolog` para `envs/prod`, trocar todas as ocorrências.

`envs/homolog/main.tf`:

```hcl
terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = "us-east-1"
}

module "vpc" {
  source      = "../../modules/vpc"
  environment = "homolog"
}

module "secrets" {
  source      = "../../modules/secrets"
  environment = "homolog"
}

module "rds" {
  source      = "../../modules/rds"
  environment = "homolog"
  db_password = module.secrets.db_password_value

  depends_on = [module.vpc, module.secrets]
}
```

### Etapa 8: CI/CD (1 dia)

**Complicação do Academy:** credenciais expiram a cada 4h. GitHub Actions rodando de madrugada não conseguirá fazer `terraform apply` sem credenciais válidas.

**Estratégia recomendada:** CI só valida (plan), apply é sempre manual da minha máquina ou via `workflow_dispatch` com Secrets atualizados semanalmente.

`.github/workflows/plan.yml`:

```yaml
name: Terraform Plan
on:
  pull_request:
    branches: [main, homolog]

jobs:
  validate:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        env: [homolog, prod]
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.9.0
      - name: Format check
        run: terraform fmt -check -recursive
      - name: Validate ${{ matrix.env }}
        run: |
          cd envs/${{ matrix.env }}
          terraform init -backend=false
          terraform validate
```

`.github/workflows/apply.yml`:

```yaml
name: Terraform Apply (manual)
on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Ambiente'
        required: true
        default: 'homolog'
        type: choice
        options: [homolog, prod]

jobs:
  apply:
    runs-on: ubuntu-latest
    environment: ${{ inputs.environment }}
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
      - name: Configure AWS
        run: |
          mkdir -p ~/.aws
          cat > ~/.aws/credentials << EOF
          [default]
          aws_access_key_id=${{ secrets.AWS_ACCESS_KEY_ID }}
          aws_secret_access_key=${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws_session_token=${{ secrets.AWS_SESSION_TOKEN }}
          EOF
      - name: Apply
        run: |
          cd envs/${{ inputs.environment }}
          terraform init
          terraform apply -auto-approve
```

### Etapa 9: Documentação (1 dia)

`README.md` completo com:
- Propósito
- Arquitetura (diagrama)
- Pré-requisitos
- Como rodar (homolog e prod)
- Como rodar migrations
- Como fazer destroy (importante para budget)
- Contratos publicados (Parameter Store e Secrets)
- Links para os outros 3 repos

`docs/ARCHITECTURE.md` com:
- Diagrama Mermaid da VPC
- Diagrama ER do banco (via dbdiagram.io)
- Trade-offs documentados

## Ordem de execução prática

```
1. Bootstrap repo + gitignore + workflow básico (0,5d)
2. Setup local AWS Academy + credenciais (0,5d)
3. Estrutura de pastas
4. Módulo VPC → terraform apply em homolog → validar → destroy (2d)
5. Módulo Secrets → apply em homolog → validar → destroy (0,5d)
6. Módulo RDS → apply em homolog → validar conexão → destroy (2d)
7. Copiar homolog para prod, ajustar (0,5d)
8. Migrations funcionando (1d)
9. CI/CD workflows (1d)
10. Documentação (1d)
```

**Total: ~9 dias**. Se sobrar tempo, sobra folga para as tasks de dashboards/RFCs/vídeo.

## Checklist final

Antes de considerar o repositório "pronto":

- [ ] Branch main protegida, soat-architecture adicionado
- [ ] Módulos VPC, Secrets, RDS implementados
- [ ] Envs homolog e prod separados
- [ ] Parameter Store com 9 parâmetros publicados
- [ ] Secrets Manager com 2 secrets
- [ ] Migrations rodam contra RDS
- [ ] Testado destroy + apply repetidamente
- [ ] README completo
- [ ] Diagrama ER commitado
- [ ] Comunicado ao grupo que VPC está disponível

## Prompt inicial para o Claude Code

Quando abrir o Claude Code no repo recém-clonado, começar com:

```
Vou implementar este repositório de infraestrutura AWS seguindo o plano em docs/plano.md.

Contexto:
- Terraform 1.9+, AWS provider ~> 5.0
- Ambiente AWS Academy Learner Lab (us-east-1, budget US$50, IAM restrito)
- Usar LabRole/LabInstanceProfile/LabEksClusterRole pré-criadas
- Módulos comunitários: terraform-aws-modules/vpc/aws v5.5

Primeiro passo: crie a estrutura de pastas conforme o plano e o .gitignore.
Depois vamos por etapa: bootstrap → VPC → Secrets → RDS → envs → migrations → CI/CD → docs.
```

## Estimativa de custo

Se rotina de destroy for disciplinada (~4h de sessão × 20 sessões):

| Recurso | Custo por sessão |
|---|---|
| NAT Gateway | US$0,18 |
| RDS db.t3.micro | US$0,07 |
| **Total sessão** | **~US$0,25** |
| **Estimativa projeto** | **~US$5-8** |

Se esquecer ligado 24/7 por 1 semana: ~US$15 (30% do budget). Aceitável, mas evitar.
