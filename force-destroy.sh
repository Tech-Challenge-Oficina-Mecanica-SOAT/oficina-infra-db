#!/bin/bash
# force-destroy.sh - Script auxiliar para destruição forçada

ENV=${1:-homolog}
MODE=${2:-full}  # full ou clean-only

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

log "Iniciando limpeza do ambiente: $ENV"

cd envs/$ENV

# Se for apenas limpeza, pula a parte do Terraform
if [ "$MODE" != "clean-only" ]; then
    log "Tentando destroy normal..."
    terraform destroy -auto-approve || warn "Destroy normal falhou. Continuando com limpeza manual..."
fi

# Limpeza manual de recursos
log "Removendo NAT Gateways órfãos..."
aws ec2 describe-nat-gateways \
    --filter "Name=tag:Name,Values=*$ENV*" \
    --query 'NatGateways[?State==`available`].NatGatewayId' \
    --output text | while read -r NAT_ID; do
        [ -z "$NAT_ID" ] && continue
        log "Deletando NAT: $NAT_ID"
        aws ec2 delete-nat-gateway --nat-gateway-id "$NAT_ID"
    done

log "Removendo Security Groups órfãos..."
aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=*oficina*$ENV*" \
    --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
    --output text | while read -r SG_ID; do
        [ -z "$SG_ID" ] && continue
        log "Removendo SG: $SG_ID"
        aws ec2 delete-security-group --group-id "$SG_ID" 2>/dev/null || true
    done

log "Removendo ENIs órfãs..."
aws ec2 describe-network-interfaces \
    --filters "Name=tag:Name,Values=*$ENV*" \
    --query 'NetworkInterfaces[?Status==`available`].NetworkInterfaceId' \
    --output text | while read -r ENI_ID; do
        [ -z "$ENI_ID" ] && continue
        log "Removendo ENI: $ENI_ID"
        aws ec2 delete-network-interface --network-interface-id "$ENI_ID" 2>/dev/null || true
    done

log "✅ Limpeza concluída para $ENV!"