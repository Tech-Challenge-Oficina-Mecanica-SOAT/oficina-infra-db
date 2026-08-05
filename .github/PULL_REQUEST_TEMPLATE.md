## O que este PR faz

- Adiciona workflows CI/CD (plan + apply) e script de migrations
- Cria `envs/prod` e exemplos de `terraform.tfvars`
- Atualiza `README.md` com instruções de uso

## Checklist
- [ ] Rodar `terraform fmt` e `terraform validate` localmente
- [ ] Verificar `envs/prod/main.tf`
- [ ] Configurar GitHub Secrets (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN)
- [ ] Revisão de segurança antes de executar `apply` em `prod`

## Como testar
1. Abrir PR e esperar o workflow `Terraform Plan` passar.
2. Para aplicar em `homolog`, usar `Actions → Terraform Apply (manual)` e fornecer credenciais válidas.
