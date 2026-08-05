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
