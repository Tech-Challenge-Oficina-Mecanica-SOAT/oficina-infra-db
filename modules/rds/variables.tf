variable "environment" {
  description = "Ambiente (homolog ou prod)"
  type        = string
}

variable "vpc_id" {
  description = "ID da VPC onde o RDS será criado"
  type        = string
}

variable "private_subnet_ids" {
  description = "IDs das subnets privadas para o DB Subnet Group"
  type        = list(string)
}

variable "db_password" {
  description = "Senha do banco (vinda do Secrets Manager)"
  type        = string
  sensitive   = true
}