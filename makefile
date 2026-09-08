# Makefile para Oficina Infra DB
# Uso: make <comando> [VAR=valor]

.PHONY: help destroy destroy-force destroy-all clean verify migrate plan apply status cost logs destroy-check bootstrap bootstrap-destroy

# Default environment
ENV ?= homolog
API_REPO ?= ../oficina-mecanica-api

help: ## Mostra esta ajuda
	@echo "Comandos disponiveis:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-25s %s\n", $$1, $$2}'
	@echo ""
	@echo "Comandos de Infraestrutura:"
	@echo "  plan              - Gera plano Terraform"
	@echo "  apply             - Aplica infraestrutura"
	@echo "  status            - Mostra recursos ativos na AWS"
	@echo "  cost              - Estima custos"
	@echo "  logs              - Mostra logs do Terraform"
	@echo ""
	@echo "Comandos de Destruicao (NIVEIS DE SEGURANCA):"
	@echo "  destroy-check     - Simula destruicao (dry-run)"
	@echo "  destroy           - NIVEL 1: Remove recursos gerenciados (recomendado)"
	@echo "  destroy-force     - NIVEL 2: Remove recursos + limpa orfaos"
	@echo "  destroy-all       - NIVEL 3: Remove TUDO (S3 e DynamoDB) - PERIGO!"
	@echo ""
	@echo "Comandos de Manutencao:"
	@echo "  clean             - Limpa recursos orfaos"
	@echo "  migrate           - Roda migrations"
	@echo "  verify            - Verifica credenciais AWS"
	@echo "  bootstrap-destroy - Destroi o backend S3 + DynamoDB"
	@echo ""
	@echo "Comandos por Ambiente:"
	@echo "  make homolog <comando>  - Executa no homolog"
	@echo "  make prod <comando>     - Executa no prod"
	@echo ""
	@echo "Exemplos:"
	@echo "  make init                # Inicializa (cria backend se necessario)"
	@echo "  make plan"
	@echo "  make apply ENV=prod"
	@echo "  make destroy"
	@echo "  make homolog destroy-force"
	@echo "  make status ENV=prod"
	@echo ""
	@echo "REGRA DE OURO:"
	@echo "  Sempre use 'make destroy' primeiro!"
	@echo "  So use 'make destroy-force' se falhar."
	@echo "  NUNCA use 'make destroy-all' em producao!"

verify: ## Verifica credenciais AWS
	@echo "Verificando credenciais AWS..."
	@aws sts get-caller-identity &>/dev/null || (echo "ERRO: Credenciais invalidas!" && exit 1)
	@echo "Credenciais OK!"

bootstrap: ## Cria o backend S3 + DynamoDB se nao existir
	@echo "Verificando se o backend S3 existe..."
	@aws s3 ls s3://oficina-infra-db-terraform-state &>/dev/null || \
		(echo "Backend nao encontrado. Criando..." && \
		cd bootstrap && terraform init && terraform apply -auto-approve && \
		echo "Backend criado com sucesso!")

bootstrap-destroy: ## Destroi o backend S3 + DynamoDB (cuidado!)
	@echo "DESTRUINDO BACKEND S3 E DYNAMODB!"
	@echo "Isso vai remover o estado do Terraform permanentemente!"
	@read -p "Digite 'DESTRUIR_BACKEND' para confirmar: " confirm; \
	if [ "$$confirm" = "DESTRUIR_BACKEND" ]; then \
		cd bootstrap && terraform destroy -auto-approve; \
		echo "Backend destruido!"; \
	else \
		echo "Cancelado."; \
		exit 1; \
	fi

init: verify ## Inicializa Terraform (cria backend se necessario)
	@echo "Inicializando Terraform no ambiente $(ENV)..."
	@$(MAKE) bootstrap
	@cd envs/$(ENV) && terraform init

plan: verify ## Gera plano Terraform
	@echo "Gerando plano para $(ENV)..."
	@$(MAKE) bootstrap
	@cd envs/$(ENV) && terraform plan

apply: verify ## Aplica infraestrutura
	@echo "Aplicando infraestrutura em $(ENV)..."
	@$(MAKE) bootstrap
	@cd envs/$(ENV) && terraform apply -auto-approve
	@echo "Aplicacao concluida!"

destroy: verify ## [NIVEL 1] Destruicao segura (recomendado)
	@echo "Destruindo $(ENV) (modo seguro)..."
	@echo "Remove APENAS recursos gerenciados pelo Terraform"
	@$(MAKE) bootstrap
	@cd envs/$(ENV) && terraform destroy -auto-approve || \
		(echo "ERRO: Destroy normal falhou! Use 'make destroy-force'" && exit 1)
	@echo "Destruicao concluida!"
	@echo "Verifique com 'make status'"

destroy-force: verify ## [NIVEL 2] Destruicao forcada (se o destroy normal falhar)
	@echo "DESTRUICAO FORCADA - $(ENV)"
	@echo "Isso vai remover TODOS os recursos, incluindo orfaos!"
	@echo ""
	@echo "Antes de continuar, verifique:"
	@echo "  1. Voce ja tentou 'make destroy' e falhou?"
	@echo "  2. Voce esta em $(ENV) e tem certeza?"
	@echo ""
	@read -p "Digite 'FORCAR' para confirmar: " confirm; \
	if [ "$$confirm" = "FORCAR" ]; then \
		echo "Iniciando destruicao forcada..."; \
		chmod +x force-destroy.sh; \
		./force-destroy.sh $(ENV); \
		echo "Destruicao forcada concluida!"; \
		echo "Verifique com 'make status'"; \
	else \
		echo "Cancelado."; \
		exit 1; \
	fi

destroy-all: verify
	@echo "DESTRUICAO TOTAL DO $(ENV)"
	@read -p "Digite 'DESTRUIR_TUDO' para confirmar: " confirm; \
	if [ "$$confirm" = "DESTRUIR_TUDO" ]; then \
		echo "Removendo lock e digest do DynamoDB primeiro..."; \
		aws dynamodb delete-item \
			--table-name oficina-infra-db-lock \
			--key '{"LockID": {"S": "oficina-infra-db-terraform-state/$(ENV)/terraform.tfstate"}}' \
			2>/dev/null || true; \
		aws dynamodb delete-item \
			--table-name oficina-infra-db-lock \
			--key '{"LockID": {"S": "oficina-infra-db-terraform-state/$(ENV)/terraform.tfstate-md5"}}' \
			2>/dev/null || true; \
		chmod +x force-destroy.sh; \
		./force-destroy.sh $(ENV) || true; \
		echo "Removendo S3 e DynamoDB..."; \
		aws s3api list-object-versions --bucket oficina-infra-db-terraform-state \
			--query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' --output json 2>/dev/null | \
			aws s3api delete-objects --bucket oficina-infra-db-terraform-state --delete file:///dev/stdin 2>/dev/null || true; \
		aws s3 rm s3://oficina-infra-db-terraform-state --recursive || true; \
		aws s3 rb s3://oficina-infra-db-terraform-state --force || true; \
		aws dynamodb delete-table --table-name oficina-infra-db-lock || true; \
		echo "Tudo destruido!"; \
	else \
		echo "Cancelado."; \
		exit 1; \
	fi

destroy-check: verify ## Simula destruicao (dry-run)
	@echo "Simulando destruicao de $(ENV)..."
	@echo "Recursos que seriam removidos pelo Terraform:"
	@$(MAKE) bootstrap
	@cd envs/$(ENV) && terraform plan -destroy
	@echo ""
	@echo "Recursos orfaos que seriam limpos (destroy-force):"
	@echo "  - NAT Gateways com tag *$(ENV)*"
	@echo "  - Security Groups com 'oficina' e '$(ENV)'"
	@echo "  - ENIs orfas"
	@echo ""
	@echo "Para executar:"
	@echo "  make destroy          # Destruicao segura"
	@echo "  make destroy-force    # Destruicao forcada"

clean: verify ## Limpa recursos orfaos (sem destruir estado)
	@echo "Limpando recursos orfaos em $(ENV)..."
	@chmod +x force-destroy.sh
	@./force-destroy.sh $(ENV) --clean-only
	@echo "Limpeza concluida!"
	@echo "Verifique com 'make status'"

migrate: verify ## Roda migrations
	@echo "Rodando migrations em $(ENV)..."
	@$(MAKE) bootstrap
	@chmod +x migrations/run-migrations.sh
	@./migrations/run-migrations.sh $(ENV) $(API_REPO)
	@echo "Migrations concluidas!"

status: verify ## Status dos recursos AWS
	@echo "Verificando recursos do ambiente $(ENV)..."
	@echo ""
	@echo "VPCs:"
	@aws ec2 describe-vpcs --filters "Name=tag:Name,Values=*$(ENV)*" --query 'Vpcs[*].{ID:VpcId,Name:Tags[?Key==`Name`].Value|[0],State:State}' --output table 2>/dev/null || echo "Nenhuma VPC encontrada"
	@echo ""
	@echo "RDS Instances:"
	@aws rds describe-db-instances --query "DBInstances[?contains(DBInstanceIdentifier, '$(ENV)')].{ID:DBInstanceIdentifier,Status:DBInstanceStatus,Class:DBInstanceClass}" --output table 2>/dev/null || echo "Nenhum RDS encontrado"
	@echo ""
	@echo "NAT Gateways:"
	@aws ec2 describe-nat-gateways --filter "Name=tag:Name,Values=*$(ENV)*" --query 'NatGateways[*].{ID:NatGatewayId,State:State,VPC:VpcId}' --output table 2>/dev/null || echo "Nenhum NAT Gateway encontrado"
	@echo ""
	@echo "Security Groups:"
	@aws ec2 describe-security-groups --filters "Name=group-name,Values=*oficina*$(ENV)*" --query 'SecurityGroups[?GroupName!=`default`].{ID:GroupId,Name:GroupName}' --output table 2>/dev/null || echo "Nenhum Security Group encontrado"
	@echo ""
	@echo "Se houver recursos acima, voce esta GASTANDO dinheiro!"
	@echo "Use 'make destroy' para remover."

cost: ## Estima custos
	@echo "Estimando custos para $(ENV)..."
	@echo "NAT Gateway: ~$0.05/hora (US$ 1.20/dia)"
	@echo "RDS t3.micro: ~$0.02/hora (US$ 0.48/dia)"
	@echo "Total: ~$0.07/hora (US$ 1.68/dia)"
	@echo "DESTRUA AO FINAL DO DIA!"
	@echo "Use 'make destroy'"

logs: ## Mostra logs do Terraform
	@echo "Logs do Terraform para $(ENV)..."
	@cd envs/$(ENV) && tail -f terraform.log 2>/dev/null || echo "Nenhum log encontrado"

homolog: ## Executa comando no homolog
	@$(MAKE) ENV=homolog $(TARGET)

prod: ## Executa comando no prod
	@$(MAKE) ENV=prod $(TARGET)

default: help