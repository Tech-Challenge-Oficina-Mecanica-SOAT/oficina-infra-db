# oficina-infra-db

> Repositório de infraestrutura base (VPC + RDS + Secrets Manager) da oficina mecânica — Tech Challenge Fase 3 (SOAT/FIAP).

## Propósito

Este é o repositório responsável pela infraestrutura base compartilhada do projeto: **VPC**, **RDS PostgreSQL** e **Secrets Manager**. Ele publica contratos (via Parameter Store e Secrets Manager) consumidos pelos outros três repositórios do grupo, e por isso **precisa ser aplicado primeiro** — é ele quem "destrava" os demais repositórios.

**Tecnologias utilizadas:** Terraform, AWS (VPC, RDS, Secrets Manager, Systems Manager Parameter Store, S3, DynamoDB), PostgreSQL, GitHub Actions, .NET/EF Core (para migrations).

## Pré-requisitos

- **Git**, com suporte a submódulos (veja a seção [Módulo VPC vendorizado](#módulo-vpc-vendorizado-git-submodule)).
- **Terraform** `>= 1.9.0`.
- **AWS CLI**, instalado e configurado para a região `us-east-1`.
- **Credenciais do AWS Academy Learner Lab** (veja abaixo como configurá-las).
- **.NET SDK 8.0**, necessário apenas para rodar as migrations do EF Core localmente contra o banco.

## Ambiente: AWS Academy Learner Lab

Este projeto roda no **AWS Academy Learner Lab**, que impõe restrições importantes ao design da infraestrutura:

| Restrição do Academy | Impacto neste repositório |
|---|---|
| Budget de US$ 50 por conta | Rotina de `destroy` obrigatória ao final de cada sessão (veja seção de custos) |
| Região fixa `us-east-1` | Todos os recursos são fixados nessa região |
| IAM restrito (sem criação de roles próprias; apenas `LabRole` / `LabInstanceProfile` / `LabEksClusterRole`) | Este repositório não cria nenhuma role/policy IAM própria |
| RDS limitado a `db.t3.micro`, storage `gp2`, sem Multi-AZ, sem Enhanced Monitoring/Performance Insights | O módulo `rds` já vem configurado com essas limitações fixas (não são escolhas de design, são imposições do ambiente) |
| Credenciais AWS expiram a cada 4 horas | O `apply` é sempre manual (`workflow_dispatch`); se a sessão expirar no meio da execução, o job falha e precisa ser reiniciado com credenciais novas |
| NAT Gateway cobra mesmo com a sessão do Lab encerrada | Rotina de `destroy` recomendada ao final de cada sessão de trabalho |

### Configurando as credenciais do AWS Academy localmente

1. No painel do AWS Academy Learner Lab, clique em **AWS Details → Show** para ver `aws_access_key_id`, `aws_secret_access_key` e `aws_session_token`.
2. Exporte as três variáveis no terminal (ou cole o conteúdo em `~/.aws/credentials`, perfil `default`):
   ```bash
   export AWS_ACCESS_KEY_ID="..."
   export AWS_SECRET_ACCESS_KEY="..."
   export AWS_SESSION_TOKEN="..."
   export AWS_DEFAULT_REGION="us-east-1"
   ```
3. Essas credenciais expiram em ~4 horas. Repita o processo sempre que expirarem (inclusive antes de rodar `apply`, `migrations` ou os comandos de `destroy`).

## Módulo VPC vendorizado (git submodule)

O módulo `modules/vpc` usa internamente o módulo comunitário [`terraform-aws-modules/terraform-aws-vpc`](https://github.com/terraform-aws-modules/terraform-aws-vpc), vendorizado como **git submodule** em `modules/vpc/vendor/terraform-aws-vpc/`. Isso é intencional: evita depender do Terraform Registry em tempo de `apply` e trava a versão do módulo comunitário usada pelo projeto.

**Importante:** ao clonar este repositório, é necessário inicializar o submódulo, ou o `terraform init` falhará por falta dos arquivos do módulo vendorizado:

```bash
git clone --recurse-submodules <url-do-repositorio>
# ou, se já clonou sem a flag acima:
git submodule update --init --recursive
```

Os workflows de CI/CD (`plan.yml` e `apply.yml`) já fazem checkout com `submodules: recursive` automaticamente.

## Bootstrap do backend remoto (S3 + DynamoDB)

Os ambientes (`envs/homolog` e `envs/prod`) usam um backend remoto S3 (para o state) + DynamoDB (para lock), definidos em `bootstrap/`. **Esse backend precisa existir antes do primeiro `terraform init` em `envs/homolog` ou `envs/prod`.**

```bash
cd bootstrap
terraform init
terraform apply
```

Isso cria o bucket S3 `oficina-infra-db-terraform-state` (versionado e criptografado) e a tabela DynamoDB `oficina-infra-db-lock`, referenciados em `envs/homolog/backend.tf` e `envs/prod/backend.tf`. Esse passo só precisa ser feito uma vez por conta AWS Academy (ou sempre que a conta for reiniciada do zero).

## Ambientes

- **homolog:** ambiente principal para testes. Configuração em [envs/homolog/main.tf](envs/homolog/main.tf#L1).
- **prod:** cópia equivalente. Configuração em [envs/prod/main.tf](envs/prod/main.tf#L1).

## Como rodar

```bash
cd envs/homolog   # ou envs/prod
terraform init
terraform validate
terraform plan
terraform apply
```

## CI/CD

- **Plan workflow:** [`.github/workflows/plan.yml`](.github/workflows/plan.yml#L1) — roda `terraform fmt -check` e `terraform validate` (para `homolog` e `prod`) automaticamente em PRs para `main` e `homolog`.
- **Apply workflow:** [`.github/workflows/apply.yml`](.github/workflows/apply.yml#L1) — disparo **manual** (`workflow_dispatch`), pois depende de credenciais do AWS Academy que expiram a cada 4h e não podem ficar armazenadas de forma duradoura. Executa `terraform apply` no ambiente escolhido (`homolog` ou `prod`).
- **Migrations workflow:** [`.github/workflows/migrations.yml`](.github/workflows/migrations.yml#L1) — pode ser disparado manualmente (`workflow_dispatch`) **ou automaticamente** quando há push nos caminhos `migrations/**` nas branches `main`, `master` ou `develop`. Em ambos os casos depende das mesmas credenciais AWS de curta duração.
- **AI Code Review:** [`.github/workflows/ai-code-review.yml`](.github/workflows/ai-code-review.yml#L1) — roda automaticamente em PRs e posta um comentário de revisão gerado por IA (Google Gemini) focado em segurança, boas práticas de Terraform e restrições do AWS Academy. Não substitui a revisão humana. Requer o secret `GEMINI_API_KEY`.

### Configurar GitHub Secrets

- **`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_SESSION_TOKEN`:** necessários para os workflows `apply` e `migrations`. Adicione em `Settings → Secrets and variables → Actions`. Atenção: as credenciais do AWS Academy expiram a cada 4 horas — atualize-as antes de disparar esses workflows.
- **`GEMINI_API_KEY`:** necessário apenas para o workflow `ai-code-review` (opcional).

### Como usar os workflows

- **Plan (automático):** abra um PR para `main` ou `homolog`; o workflow `plan` valida os arquivos Terraform dos dois ambientes.
- **Apply (manual):** vá em `Actions → Terraform Apply → Run workflow`, escolha o ambiente (`homolog` ou `prod`) e garanta que os secrets AWS estejam válidos no momento da execução.
- **Migrations (manual ou automático):** dispare manualmente em `Actions → Run Database Migrations → Run workflow`, ou deixe rodar automaticamente ao dar push em `migrations/**`. Requer que o repositório `oficina-mecanica-api` esteja acessível (o workflow faz checkout dele automaticamente).

## Migrations (EF Core)

O RDS fica em subnets **privadas** (sem acesso público), então rodar as migrations localmente exige uma destas duas opções:

1. **Abrir o Security Group temporariamente** para o seu IP público (mais simples, requer lembrar de reverter depois).
2. **Usar uma instância EC2 bastion** na subnet pública, com acesso SSH/port-forward até o RDS (mais seguro, requer provisionar a instância à parte — este repositório não inclui esse bastion).

Script: [migrations/run-migrations.sh](migrations/run-migrations.sh#L1). Ele busca automaticamente o endpoint, porta, nome do banco e usuário no Parameter Store, e a senha no Secrets Manager, depois roda `dotnet ef database update` contra o repositório da API.

Uso recomendado (local, opção 1 acima):

```bash
# 1. Renove as credenciais AWS Academy (veja seção acima) e exporte-as no terminal
# 2. Rode o script apontando para o ambiente e o caminho local do repositório da API
./migrations/run-migrations.sh homolog ../oficina-mecanica-api
```

Também é possível rodar via GitHub Actions — veja o workflow `migrations.yml` na seção de CI/CD acima. Nesse caso o runner precisa do .NET SDK (já configurado no workflow) e das mesmas credenciais AWS de curta duração.

## Contratos publicados

Consumidos pelos outros repositórios do grupo (`oficina-infra-k8s` para a VPC; `oficina-mecanica-api` e `oficina-lambda-auth` para o DB e o JWT):

**Parameter Store** (`{env}` = `homolog` ou `prod`):
```
/oficina/{env}/network/vpc-id              → consumido por oficina-infra-k8s (P3)
/oficina/{env}/network/vpc-cidr            → consumido por oficina-infra-k8s (P3)
/oficina/{env}/network/public-subnet-ids   → consumido por oficina-infra-k8s (P3)
/oficina/{env}/network/private-subnet-ids  → consumido por oficina-infra-k8s (P3)
/oficina/{env}/db/endpoint                 → consumido por oficina-mecanica-api (P1)
/oficina/{env}/db/port                     → consumido por oficina-mecanica-api (P1)
/oficina/{env}/db/name                     → consumido por oficina-mecanica-api (P1)
/oficina/{env}/db/username                 → consumido por oficina-mecanica-api (P1)
/oficina/{env}/db/security-group-id        → consumido por oficina-mecanica-api (P1) / oficina-infra-k8s (P3)
```

**Secrets Manager:**
```
oficina/{env}/db-password       → consumido por oficina-mecanica-api (P1)
oficina/{env}/jwt-secret-key    → consumido por oficina-mecanica-api (P1) e oficina-lambda-auth (P2)
```

## Como fazer destroy (⚠️ importante para o budget)

O NAT Gateway continua sendo cobrado mesmo com a sessão do AWS Academy encerrada. Sempre que não for continuar no mesmo dia, rode:

```bash
cd envs/homolog   # ou envs/prod
terraform destroy
```

Rotina recomendada por sessão de trabalho (~4h no Academy):
1. Iniciar o Lab, renovar credenciais.
2. `terraform apply` no ambiente desejado.
3. Trabalhar/testar.
4. `terraform destroy` antes de encerrar, se não for continuar no mesmo dia.

Custo estimado por sessão de 4h com rotina disciplinada: ~US$ 0,25 (NAT Gateway + RDS), dentro do budget de US$ 50 da conta.

## Repositórios relacionados

Este repositório é a infraestrutura base compartilhada e destrava os outros três repositórios do grupo:

- [`oficina-mecanica-api`](../oficina-mecanica-api) — API .NET — consome DB e JWT.
- [`oficina-lambda-auth`](../oficina-lambda-auth) — Lambda de autenticação por CPF — consome JWT.
- [`oficina-infra-k8s`](../oficina-infra-k8s) — Cluster EKS e manifestos Kubernetes — consome a VPC.

> Ajuste os links acima para as URLs reais do GitHub assim que os repositórios estiverem publicados.

## Estrutura do projeto

```
.
├── bootstrap/        # Backend remoto (S3 + DynamoDB) — aplicado uma única vez
├── modules/
│   ├── vpc/           # VPC, subnets, NAT/IGW (via módulo vendorizado) + parâmetros SSM
│   ├── secrets/       # Secrets Manager: senha do RDS e JWT secret key
│   └── rds/           # Instância RDS PostgreSQL + Security Group + parâmetros SSM
├── envs/
│   ├── homolog/        # Workspace Terraform do ambiente de homologação
│   └── prod/           # Workspace Terraform do ambiente de produção
├── migrations/         # Script para rodar migrations do EF Core contra o RDS
├── docs/                # Documentação (este README complementa docs/ARCHITECTURE.md)
└── .github/workflows/  # CI/CD (plan, apply, migrations, ai-code-review)
```

- **`modules/vpc`**: cria a VPC, subnets públicas/privadas em duas AZs, Internet Gateway e um NAT Gateway; publica IDs e CIDRs no Parameter Store.
- **`modules/secrets`**: cria os dois segredos no Secrets Manager (senha do RDS gerada aleatoriamente e chave JWT).
- **`modules/rds`**: cria a instância PostgreSQL em subnets privadas, o Security Group e o DB Subnet Group; publica endpoint e metadados no Parameter Store.
- **`envs/homolog` e `envs/prod`**: cada um instancia os três módulos acima com o mesmo código, variando apenas a variável `environment` — o que garante paridade entre os ambientes.

## Arquitetura

- Documentação de arquitetura, diagrama de rede e decisões de design em [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
- O repositório entrega VPC compartilhada, RDS PostgreSQL em subnets privadas e Secrets Manager para credenciais de banco e JWT.
- Cada ambiente contém um arquivo `terraform.tfvars.example` com placeholders: [envs/homolog/terraform.tfvars.example](envs/homolog/terraform.tfvars.example#L1) e [envs/prod/terraform.tfvars.example](envs/prod/terraform.tfvars.example#L1).
