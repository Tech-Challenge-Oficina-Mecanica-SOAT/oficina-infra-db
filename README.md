# oficina-infra-db

> Repositório de infraestrutura base (VPC + RDS + Secrets Manager) da oficina mecânica.

## **Purpose**
- **Repo:** : fornece VPC, RDS PostgreSQL e Secrets Manager para o conjunto de repositórios da oficina.

## **Prerequisites**
- **AWS CLI:** instalado e configurado para `us-east-1` (AWS Academy Lab).
- **Terraform:** versão `>= 1.9.0`.
- **dotnet SDK:** necessário apenas para rodar migrations localmente contra o banco.

## **Environments**
- **homolog:** ambiente principal para testes. Configuração em [envs/homolog/main.tf](envs/homolog/main.tf#L1).
- **prod:** cópia preparada em [envs/prod/main.tf](envs/prod/main.tf#L1).

## **CI / CD**
- **Plan workflow:** [`.github/workflows/plan.yml`](.github/workflows/plan.yml#L1) — roda `terraform fmt -check` e `terraform validate` em PRs para `main` e `homolog`.
- **Apply workflow:** [`.github/workflows/apply.yml`](.github/workflows/apply.yml#L1) — `workflow_dispatch` manual para executar `terraform apply`. Esse workflow usa os secrets `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` e `AWS_SESSION_TOKEN`.

### **Configure GitHub Secrets**
- **AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_SESSION_TOKEN:** adicione em `Settings → Secrets` no repositório se quiser executar o job `apply` via Actions. Atenção: as credenciais da AWS Academy expiram a cada 4 horas; o `apply` pode falhar se a sessão expirou.

## **Migrations (EF Core)**
- Script: [migrations/run-migrations.sh](migrations/run-migrations.sh#L1).
- Uso recomendado: rodar localmente após executar `terraform apply` no ambiente `homolog` (ou `prod`) e abrir temporariamente o acesso ao RDS para seu IP, conforme descrito em `docs/plano-01-oficina-infra-db.md`.

Exemplo (local):
```bash
# renovar credenciais AWS Academy via console e exportar no terminal
aws ssm get-parameter --name "/oficina/homolog/db/endpoint" --query Parameter.Value --output text
./migrations/run-migrations.sh homolog ../oficina-mecanica-api
```

## **How to use the workflows**
- **Plan (automatic):** Abra um PR; o workflow `plan` validará os arquivos Terraform.
- **Apply (manual):** Vá em `Actions → Terraform Apply` e escolha `Run workflow`. Garanta que os secrets AWS estejam válidos no momento de execução.

### **Run migrations via Actions (opcional)**
- Existe um workflow manual [`.github/workflows/migrations.yml`](.github/workflows/migrations.yml#L1) que executa o script `migrations/run-migrations.sh` em um runner. Para usá-lo configure os mesmos secrets AWS do `apply` e garanta que o runner tenha permissão para acessar o repositório `../oficina-mecanica-api` relativo ao checkout.

**Atenção:** O runner precisa do `dotnet SDK` e as credenciais AWS válidas (expiram em 4h). Recomendo usar este workflow apenas se você aceitar o risco da expiração; caso contrário, rode migrations localmente.

## **Architecture**
- Documentação de arquitetura em [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
- O repositório entrega VPC compartilhada, RDS PostgreSQL em subnets privadas, e Secrets Manager para credenciais de banco e JWT.
- Use `terraform init` dentro de `envs/homolog` ou `envs/prod` antes de `plan` ou `apply`.

## **Envs examples**
- Cada ambiente contém um arquivo `terraform.tfvars.example` com placeholders: [envs/homolog/terraform.tfvars.example](envs/homolog/terraform.tfvars.example#L1) e [envs/prod/terraform.tfvars.example](envs/prod/terraform.tfvars.example#L1).

## **Next steps**
- Verificar `envs/prod` e ajustar se necessário antes de rodar `apply` em `prod`.
- Se quiser, posso adicionar um job opcional que roda migrations via GitHub Actions (requer credenciais válidas no momento da execução). Solicite se desejar essa opção.
