output "db_password_secret_arn" {
  value = aws_secretsmanager_secret.db_password.arn
}

output "db_password_secret_name" {
  value = aws_secretsmanager_secret.db_password.name
}

output "db_password_value" {
  value     = random_password.db_password.result
  sensitive = true
}

output "jwt_secret_arn" {
  value = aws_secretsmanager_secret.jwt_secret.arn
}

output "jwt_secret_name" {
  value = aws_secretsmanager_secret.jwt_secret.name
}