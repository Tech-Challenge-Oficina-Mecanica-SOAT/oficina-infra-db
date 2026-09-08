# oficina-infra-db

> Repositório de infraestrutura base (VPC + RDS + Secrets Manager) da oficina mecânica: Tech Challenge Fase 3 (SOAT/FIAP).

## Propósito

Este é o repositório responsável pela infraestrutura base compartilhada do projeto: **VPC**, **RDS PostgreSQL** e **Secrets Manager**. Ele publica contratos (via Parameter Store e Secrets Manager) consumidos pelos outros três repositórios do grupo, e por isso **precisa ser aplicado primeiro**.

**Tecnologias utilizadas:** Terraform, AWS (VPC, RDS, Secrets Manager, Systems Manager Parameter Store, S3, DynamoDB), PostgreSQL, GitHub Actions, .NET/EF Core (para migrations), Make.

## Pré-requisitos

- **Git**, com suporte a submódulos (veja a seção [Módulo VPC vendorizado](#módulo-vpc-vendorizado-git-submodule)).
- **Terraform** `>= 1.9.0`.
- **AWS CLI**, instalado e configurado para a região `us-east-1`.
- **GNU Make**, usado para orquestrar todos os comandos do projeto (veja a seção [Comandos disponíveis](#comandos-disponíveis-make)).
- **Credenciais AWS válidas** da AWS Academy Learner Lab (veja abaixo) ou uma conta pessoal.
- **.NET SDK 8.0**, necessário apenas para rodar as migrations do EF Core localmente contra o banco.

## Ambiente: AWS Academy Learner Lab

Este projeto roda no **AWS Academy Learner Lab**, que impõe restrições importantes ao design da infraestrutura:

| Restrição do Academy | Impacto neste repositório |
|---|---|
| Budget de US$ 50 por conta | Rotina de `make destroy` obrigatória ao final de cada sessão (veja seção de custos) |
| Região fixa `us-east-1` | Todos os recursos são fixados nessa região |
| IAM restrito (sem criação de roles próprias; apenas `LabRole` / `LabInstanceProfile` / `LabEksClusterRole`) | Este repositório não cria nenhuma role/policy IAM própria |
| RDS limitado a `db.t3.micro`, storage `gp2`, sem Multi-AZ, sem Enhanced Monitoring/Performance Insights | O módulo `rds` já vem configurado com essas limitações fixas (não são escolhas de design, são imposições do ambiente) |
| Credenciais AWS expiram a cada 4 horas | O `apply` é sempre manual (`workflow_dispatch`); se a sessão expirar no meio da execução, o job falha e precisa ser reiniciado com credenciais novas |
| NAT Gateway cobra mesmo com a sessão do Lab encerrada | Rotina de `make destroy` recomendada ao final de cada sessão de trabalho |

### Configurando as credenciais do AWS Academy localmente

1. No painel do AWS Academy Learner Lab, clique em **AWS Details -> Show** para ver `aws_access_key_id`, `aws_secret_access_key` e `aws_session_token`.
2. Exporte as três variáveis no terminal (ou cole o conteúdo em `~/.aws/credentials`, perfil `default`):
   ```bash
   export AWS_ACCESS_KEY_ID="..."
   export AWS_SECRET_ACCESS_KEY="..."
   export AWS_SESSION_TOKEN="..."
   export AWS_DEFAULT_REGION="us-east-1"
   ```
3. Essas credenciais expiram em 4 horas. Repita o processo sempre que expirarem (inclusive antes de rodar `make apply`, `make migrate` ou os comandos de `make destroy*`).

> Também é possível usar uma **conta AWS pessoal** em vez do lab (por exemplo, para testes enquanto o lab está indisponível). Nesse caso, configure um profile separado (`aws configure --profile pessoal` + `export AWS_PROFILE=pessoal`) e garanta que o usuário IAM tenha permissões suficientes para VPC, RDS, Secrets Manager, SSM, S3 e DynamoDB. Lembre-se de que, fora do lab, os custos são reais e não têm o teto de crédito do Academy.

## Módulo VPC vendorizado (git submodule)

O módulo `modules/vpc` usa internamente o módulo comunitário [`terraform-aws-modules/terraform-aws-vpc`](https://github.com/terraform-aws-modules/terraform-aws-vpc), vendorizado como **git submodule** em `modules/vpc/vendor/terraform-aws-vpc/`. Isso é intencional: evita depender do Terraform Registry em tempo de `apply` e trava a versão do módulo comunitário usada pelo projeto.

**Importante:** ao clonar este repositório, é necessário inicializar o submódulo, ou o `terraform init` (disparado por `make init`) falhará por falta dos arquivos do módulo vendorizado:

```bash
git clone --recurse-submodules <url-do-repositorio>
# ou, se já clonou sem a flag acima:
git submodule update --init --recursive
```

Os workflows de CI/CD (`plan.yml` e `apply.yml`) já fazem checkout com `submodules: recursive` automaticamente.

## Comandos disponíveis (Make)

Todo o fluxo do projeto, bootstrap do backend, plan, apply, destroy, status, custos e migrations, é orquestrado pelo `Makefile` na raiz do repositório. Rode `make help` a qualquer momento para ver a lista completa.

O ambiente padrão é `ENV=homolog`. Para rodar contra `prod`, passe `ENV=prod` em qualquer comando, ou use os atalhos `make homolog <comando>` / `make prod <comando>`.

### Bootstrap do backend remoto (S3 + DynamoDB)

Os ambientes (`envs/homolog` e `envs/prod`) usam um backend remoto S3 (para o state) + DynamoDB (para lock), definidos em `bootstrap/`. **Não é necessário rodar isso manualmente**, todos os comandos abaixo (`init`, `plan`, `apply`, `destroy`, `destroy-check`, `migrate`) já chamam `make bootstrap` internamente, que cria o backend automaticamente caso ele ainda não exista:

```bash
make bootstrap   # opcional: cria o backend isoladamente, se quiser rodar à parte
```

Isso cria o bucket S3 `oficina-infra-db-terraform-state` (versionado e criptografado) e a tabela DynamoDB `oficina-infra-db-lock`. Esse passo só precisa ser feito uma vez por conta AWS (ou sempre que a conta for reiniciada do zero).

### Comandos de infraestrutura

| Comando | O que faz |
|---|---|
| `make init` | Verifica credenciais, garante que o backend existe e inicializa o Terraform no ambiente |
| `make plan` | Gera o plano Terraform (`terraform plan`) |
| `make apply` | Aplica a infraestrutura (`terraform apply -auto-approve`) |
| `make status` | Lista VPCs, RDS, NAT Gateways e Security Groups ativos na AWS para o ambiente |
| `make cost` | Mostra uma estimativa de custo por hora/dia dos recursos principais |
| `make logs` | Mostra o log do Terraform do ambiente (se existir) |

```bash
make init
make plan
make apply
make apply ENV=prod
```

### Comandos de destruição (níveis de segurança)

O Makefile expõe três níveis de destruição, do mais seguro ao mais agressivo:

| Comando | Nível | Descrição |
|---|---|---|
| `make destroy-check` | - | Dry-run: simula o que seria destruído, sem executar nada |
| `make destroy` | 1 | Remove apenas os recursos gerenciados pelo Terraform (recomendado, use sempre primeiro) |
| `make destroy-force` | 2 | Roda o destroy normal e, se falhar, limpa recursos órfãos (NAT Gateways, Security Groups, ENIs) via `force-destroy.sh` |
| `make destroy-all` | 3 | **Destruição total**: recursos do Terraform **+** o backend inteiro (bucket S3 e tabela DynamoDB). Use com extremo cuidado, e nunca em `prod` |
| `make clean` | - | Limpa apenas recursos órfãos, sem destruir o state |

**Regra de ouro:** sempre use `make destroy` primeiro. Só recorra a `make destroy-force` se o destroy normal falhar. `make destroy-all` é reservado para resetar o backend por completo (ex: recomeçar do zero em uma conta de testes) e pede confirmação explícita digitando `DESTRUIR_TUDO`.

> **Atenção ao bucket versionado:** o bucket do state tem versionamento ativado. Se for rodar `make destroy-all`, esvazie todas as versões do bucket antes (via `aws s3api list-object-versions` + `delete-objects`), ou o `aws s3 rb --force` pode falhar silenciosamente em deixar o bucket órfão.

```bash
make destroy-check
make destroy
make homolog destroy-force
make destroy-all ENV=homolog
```

### Comandos de manutenção

| Comando | O que faz |
|---|---|
| `make verify` | Verifica se as credenciais AWS configuradas são válidas |
| `make migrate` | Roda as migrations do EF Core contra o RDS do ambiente (usa `migrations/run-migrations.sh`) |
| `make bootstrap-destroy` | Destroi **apenas** o backend (S3 + DynamoDB), pedindo confirmação `DESTRUIR_BACKEND` |

```bash
make verify
make migrate API_REPO=../oficina-mecanica-api
```

## Ambientes

- **homolog:** ambiente principal para testes. Configuração em [envs/homolog/main.tf](envs/homolog/main.tf#L1).
- **prod:** cópia equivalente. Configuração em [envs/prod/main.tf](envs/prod/main.tf#L1).

Use `ENV=homolog` (padrão) ou `ENV=prod` em qualquer comando `make`, ou os atalhos:

```bash
make homolog plan
make prod status
```

## Como rodar (fluxo completo)

```bash
make init                 # inicializa (cria o backend se necessário)
make plan                 # revisa o que será criado
make apply                # aplica a infraestrutura
make status                # confirma os recursos ativos na AWS
```

## CI/CD

- **Plan workflow:** [`.github/workflows/plan.yml`](.github/workflows/plan.yml#L1): Roda `terraform fmt -check` e `terraform validate` (para `homolog` e `prod`) automaticamente em PRs para `main` e `homolog`.
- **Apply workflow:** [`.github/workflows/apply.yml`](.github/workflows/apply.yml#L1): Disparo **manual** (`workflow_dispatch`), pois depende de credenciais AWS que expiram a cada 4h e não podem ficar armazenadas de forma duradoura. Executa `terraform apply` no ambiente escolhido (`homolog` ou `prod`).
- **Migrations workflow:** [`.github/workflows/migrations.yml`](.github/workflows/migrations.yml#L1): Pode ser disparado manualmente (`workflow_dispatch`) **ou automaticamente** quando há push nos caminhos `migrations/**` nas branches `main`, `master` ou `develop`. Em ambos os casos depende das mesmas credenciais AWS de curta duração.
- **AI Code Review:** [`.github/workflows/ai-code-review.yml`](.github/workflows/ai-code-review.yml#L1): Roda automaticamente em PRs e posta um comentário de revisão gerado por IA (Google Gemini) focado em segurança, boas práticas de Terraform e restrições do AWS Academy. Não substitui a revisão humana. Requer o secret `GEMINI_API_KEY`.

### Configurar GitHub Secrets

- **`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_SESSION_TOKEN`:** necessários para os workflows `apply` e `migrations`. Adicione em `Settings → Secrets and variables → Actions`. Atenção: as credenciais do AWS Academy expiram a cada 4 horas, atualize-as antes de disparar esses workflows.
- **`GEMINI_API_KEY`:** necessário apenas para o workflow `ai-code-review` (opcional).

### Como usar os workflows

- **Plan (automático):** abra um PR para `main` ou `homolog`; o workflow `plan` valida os arquivos Terraform dos dois ambientes.
- **Apply (manual):** vá em `Actions → Terraform Apply → Run workflow`, escolha o ambiente (`homolog` ou `prod`) e garanta que os secrets AWS estejam válidos no momento da execução.
- **Migrations (manual ou automático):** dispare manualmente em `Actions → Run Database Migrations → Run workflow`, ou deixe rodar automaticamente ao dar push em `migrations/**`. Requer que o repositório `oficina-mecanica-api` esteja acessível (o workflow faz checkout dele automaticamente).

## Migrations (EF Core)

O RDS fica em subnets **privadas** (sem acesso público), então rodar as migrations localmente exige uma destas duas opções:

1. **Abrir o Security Group temporariamente** para o seu IP público (mais simples, requer lembrar de reverter depois).
2. **Usar uma instância EC2 bastion** na subnet pública, com acesso SSH/port-forward até o RDS (mais seguro, requer provisionar a instância à parte, pois este repositório não inclui esse bastion).

O comando `make migrate` chama [migrations/run-migrations.sh](migrations/run-migrations.sh#L1), que busca automaticamente o endpoint, porta, nome do banco e usuário no Parameter Store, e a senha no Secrets Manager, depois roda `dotnet ef database update` contra o repositório da API.

Uso recomendado (local, opção 1 acima):

```bash
# 1. Renove as credenciais AWS (Academy ou pessoal) e exporte-as no terminal
# 2. Rode via Makefile, apontando para o ambiente e o caminho local do repositório da API
make migrate ENV=homolog API_REPO=../oficina-mecanica-api
```

Também é possível rodar via GitHub Actions, veja o workflow `migrations.yml` na seção de CI/CD acima. Nesse caso o runner precisa do .NET SDK (já configurado no workflow) e das mesmas credenciais AWS de curta duração.

## Contratos publicados

Consumidos pelos outros repositórios do grupo (`oficina-infra-k8s` para a VPC; `oficina-mecanica-api` e `oficina-lambda-auth` para o DB e o JWT):

**Parameter Store** (`{env}` = `homolog` ou `prod`):
```
/oficina/{env}/network/vpc-id              → consumido por oficina-infra-k8s
/oficina/{env}/network/vpc-cidr            → consumido por oficina-infra-k8s
/oficina/{env}/network/public-subnet-ids   → consumido por oficina-infra-k8s
/oficina/{env}/network/private-subnet-ids  → consumido por oficina-infra-k8s
/oficina/{env}/db/endpoint                 → consumido por oficina-mecanica-api
/oficina/{env}/db/port                     → consumido por oficina-mecanica-api
/oficina/{env}/db/name                     → consumido por oficina-mecanica-api
/oficina/{env}/db/username                 → consumido por oficina-mecanica-api
/oficina/{env}/db/security-group-id        → consumido por oficina-mecanica-api / oficina-infra-k8s
```

**Secrets Manager:**
```
oficina/{env}/db-password       → consumido por oficina-mecanica-api
oficina/{env}/jwt-secret-key    → consumido por oficina-mecanica-api e oficina-lambda-auth
```

## Como fazer destroy (importante para o budget)

O NAT Gateway continua sendo cobrado mesmo com a sessão do AWS Academy encerrada (ou, em conta pessoal, mesmo sem nenhuma "sessão" para encerrar). Sempre que não for continuar no mesmo dia, rode:

```bash
make destroy               # ambiente padrão (homolog)
make destroy ENV=prod
```

Rotina recomendada por sessão de trabalho (4h no Academy):
1. Iniciar o Lab (ou exportar credenciais da conta pessoal).
2. `make apply` no ambiente desejado.
3. Trabalhar/testar.
4. `make destroy` antes de encerrar, se não for continuar no mesmo dia.

Se `make destroy` falhar por algum motivo, use `make destroy-force` (limpa recursos órfãos automaticamente) antes de tentar de novo. Reserve `make destroy-all` apenas para resetar o backend por completo.

Custo estimado por sessão de 4h com rotina disciplinada: ~US$ 0,25 (NAT Gateway + RDS), dentro do budget de US$ 50 da conta (ou de forma equivalente em conta pessoal).

## Repositórios relacionados

Este repositório é a infraestrutura base compartilhada e destrava os outros três repositórios do grupo:

- [`oficina-mecanica-api`](https://github.com/Tech-Challenge-Oficina-Mecanica-SOAT/oficina-mecanica-api) - API .NET - consome DB e JWT.
- [`oficina-lambda-auth`](https://github.com/Tech-Challenge-Oficina-Mecanica-SOAT/oficina-lambda-auth) - Lambda de autenticação por CPF - consome JWT.
- [`oficina-infra-k8s`](https://github.com/Tech-Challenge-Oficina-Mecanica-SOAT/oficina-infra-k8s) - Cluster EKS e manifestos Kubernetes - consome a VPC.

## Estrutura do projeto

```
.
├── Makefile           # Orquestra bootstrap, plan, apply, destroy, status, custos e migrations
├── force-destroy.sh    # Script auxiliar usado por 'make destroy-force' e 'make clean'
├── bootstrap/           # Backend remoto (S3 + DynamoDB): Criado automaticamente via 'make bootstrap'
├── modules/
│   ├── vpc/           # VPC, subnets, NAT/IGW (via módulo vendorizado) + parâmetros SSM
│   ├── secrets/       # Secrets Manager: senha do RDS e JWT secret key
│   └── rds/           # Instância RDS PostgreSQL + Security Group + parâmetros SSM
├── envs/
│   ├── homolog/        # Workspace Terraform do ambiente de homologação
│   └── prod/           # Workspace Terraform do ambiente de produção
├── migrations/         # Script para rodar migrations do EF Core contra o RDS (via 'make migrate')
├── docs/                # Documentação (este README complementa docs/ARCHITECTURE.md)
└── .github/workflows/  # CI/CD (plan, apply, migrations, ai-code-review)
```

- **`modules/vpc`**: cria a VPC, subnets públicas/privadas em duas AZs, Internet Gateway e um NAT Gateway; publica IDs e CIDRs no Parameter Store.
- **`modules/secrets`**: cria os dois segredos no Secrets Manager (senha do RDS gerada aleatoriamente e chave JWT).
- **`modules/rds`**: cria a instância PostgreSQL em subnets privadas, o Security Group e o DB Subnet Group; publica endpoint e metadados no Parameter Store.
- **`envs/homolog` e `envs/prod`**: cada um instancia os três módulos acima com o mesmo código, variando apenas a variável `environment`, o que garante paridade entre os ambientes.

## Arquitetura

- Documentação de arquitetura, diagrama de rede e decisões de design em [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
- O repositório entrega VPC compartilhada, RDS PostgreSQL em subnets privadas e Secrets Manager para credenciais de banco e JWT.
- Cada ambiente contém um arquivo `terraform.tfvars.example` com placeholders: [envs/homolog/terraform.tfvars.example](envs/homolog/terraform.tfvars.example#L1) e [envs/prod/terraform.tfvars.example](envs/prod/terraform.tfvars.example#L1).