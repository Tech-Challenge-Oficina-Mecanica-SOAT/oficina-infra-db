resource "random_password" "db_password" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "db_password" {
  name                    = "/oficina/${var.environment}/db-password"
  recovery_window_in_days = 30

  tags = {
    Project     = "oficina-mecanica"
    Environment = var.environment
    ManagedBy   = "terraform"
    Repository  = "oficina-infra-db"
  }
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db_password.result
}

resource "random_password" "jwt_secret" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret" "jwt_secret" {
  name                    = "/oficina/${var.environment}/jwt-secret-key"
  recovery_window_in_days = 30

  tags = {
    Project     = "oficina-mecanica"
    Environment = var.environment
    ManagedBy   = "terraform"
    Repository  = "oficina-infra-db"
  }
}

resource "aws_secretsmanager_secret_version" "jwt_secret" {
  secret_id     = aws_secretsmanager_secret.jwt_secret.id
  secret_string = random_password.jwt_secret.result
}