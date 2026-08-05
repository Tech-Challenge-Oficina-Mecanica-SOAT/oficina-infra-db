terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = "oficina-infra-db-terraform-state"

  acl    = "private"

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = {
    Name        = "oficina-infra-db-terraform-state"
    Environment = "infra"
    ManagedBy   = "terraform"
  }
}

resource "aws_dynamodb_table" "terraform_lock" {
  name         = "oficina-infra-db-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name        = "oficina-infra-db-lock"
    Environment = "infra"
    ManagedBy   = "terraform"
  }
}
