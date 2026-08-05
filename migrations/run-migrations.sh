#!/usr/bin/env bash
set -euo pipefail

# Parâmetros
ENV=${1:-homolog}
API_REPO_PATH=${2:-../oficina-mecanica-api}

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🔍 Buscando credenciais do RDS para ambiente $ENV...${NC}"

# Função para pegar parâmetro do SSM com validação
get_ssm_parameter() {
    local param_name=$1
    local value
    value=$(aws ssm get-parameter --name "$param_name" --query Parameter.Value --output text 2>/dev/null) || {
        echo -e "${RED}❌ Erro: Parâmetro SSM não encontrado: $param_name${NC}"
        exit 1
    }
    echo "$value"
}

# Função para pegar secret do Secrets Manager com validação
get_secret() {
    local secret_name=$1
    local value
    value=$(aws secretsmanager get-secret-value --secret-id "$secret_name" --query SecretString --output text 2>/dev/null) || {
        echo -e "${RED}❌ Erro: Secret não encontrado: $secret_name${NC}"
        exit 1
    }
    echo "$value"
}

# Busca as credenciais
DB_ENDPOINT=$(get_ssm_parameter "/oficina/$ENV/db/endpoint")
DB_PORT=$(get_ssm_parameter "/oficina/$ENV/db/port")
DB_NAME=$(get_ssm_parameter "/oficina/$ENV/db/name")
DB_USER=$(get_ssm_parameter "/oficina/$ENV/db/username")
DB_PASSWORD=$(get_secret "oficina/$ENV/db-password")

# Valida se todos os valores foram obtidos
if [[ -z "$DB_ENDPOINT" || -z "$DB_PORT" || -z "$DB_NAME" || -z "$DB_USER" || -z "$DB_PASSWORD" ]]; then
    echo -e "${RED}❌ Erro: Não foi possível obter todas as credenciais.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Credenciais obtidas com sucesso!${NC}"
echo -e "${YELLOW}📊 Conectando ao banco: $DB_ENDPOINT:$DB_PORT/$DB_NAME${NC}"

# Verifica se a pasta da API existe
if [[ ! -d "$API_REPO_PATH" ]]; then
    echo -e "${RED}❌ Erro: Pasta da API não encontrada: $API_REPO_PATH${NC}"
    exit 1
fi

cd "$API_REPO_PATH"

# Verifica se o dotnet está instalado
if ! command -v dotnet &> /dev/null; then
    echo -e "${RED}❌ Erro: dotnet não está instalado.${NC}"
    exit 1
fi

# Configura a connection string de forma segura
# Usa uma variável temporária que não aparece nos logs
export ConnectionStrings__DefaultConnection="Host=$DB_ENDPOINT;Port=$DB_PORT;Database=$DB_NAME;Username=$DB_USER;Password=$DB_PASSWORD;Trust Server Certificate=true"

echo -e "${YELLOW}🔄 Aplicando migrations...${NC}"

# Roda as migrations com timeout para evitar travamentos
timeout 300 dotnet ef database update \
    --project src/OficinaMecanica.Infrastructure \
    --startup-project src/OficinaMecanica.API \
    --verbose

# Verifica se o comando foi bem-sucedido
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Migrations aplicadas com sucesso!${NC}"
else
    echo -e "${RED}❌ Erro ao aplicar migrations.${NC}"
    exit 1
fi

# Limpa a variável de ambiente após uso (opcional)
unset ConnectionStrings__DefaultConnection