terraform {
  backend "s3" {
    bucket         = "oficina-infra-db-terraform-state"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "oficina-infra-db-lock"
    encrypt        = true
  }
}
