resource "aws_security_group" "rds" {
  name        = "oficina-rds-${var.environment}"
  description = "Permite acesso ao PostgreSQL a partir da VPC"
  vpc_id      = var.vpc_id

  ingress {
    description = "PostgreSQL a partir de qualquer coisa dentro da VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Project     = "oficina-mecanica"
    Environment = var.environment
    ManagedBy   = "terraform"
    Repository  = "oficina-infra-db"
    Name        = "oficina-rds-${var.environment}"
  }
}

resource "aws_db_subnet_group" "this" {
  name       = "oficina-db-subnet-group-${var.environment}"
  subnet_ids = var.private_subnet_ids

  tags = {
    Project     = "oficina-mecanica"
    Environment = var.environment
    ManagedBy   = "terraform"
    Repository  = "oficina-infra-db"
  }
}

resource "aws_db_instance" "postgres" {
  identifier     = "oficina-db-${var.environment}"
  engine         = "postgres"
  engine_version = "15.19"
  instance_class = "db.t3.micro"

  allocated_storage     = 20
  max_allocated_storage = 20
  storage_type          = "gp2"
  storage_encrypted     = true

  db_name  = "oficina_mecanica"
  username = "oficina_admin"
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az                     = false
  publicly_accessible          = false
  backup_retention_period      = 1
  monitoring_interval          = 0
  performance_insights_enabled = false
  deletion_protection          = false
  skip_final_snapshot          = true
  apply_immediately            = true

  tags = {
    Project     = "oficina-mecanica"
    Environment = var.environment
    ManagedBy   = "terraform"
    Repository  = "oficina-infra-db"
    Name        = "oficina-db-${var.environment}"
  }
}

resource "aws_ssm_parameter" "db_endpoint" {
  name      = "/oficina/${var.environment}/db/endpoint"
  type      = "String"
  value     = aws_db_instance.postgres.address
  overwrite = true
}

resource "aws_ssm_parameter" "db_port" {
  name      = "/oficina/${var.environment}/db/port"
  type      = "String"
  value     = tostring(aws_db_instance.postgres.port)
  overwrite = true
}

resource "aws_ssm_parameter" "db_name" {
  name      = "/oficina/${var.environment}/db/name"
  type      = "String"
  value     = aws_db_instance.postgres.db_name
  overwrite = true
}

resource "aws_ssm_parameter" "db_username" {
  name      = "/oficina/${var.environment}/db/username"
  type      = "String"
  value     = aws_db_instance.postgres.username
  overwrite = true
}

resource "aws_ssm_parameter" "db_security_group_id" {
  name      = "/oficina/${var.environment}/db/security-group-id"
  type      = "String"
  value     = aws_security_group.rds.id
  overwrite = true
}
