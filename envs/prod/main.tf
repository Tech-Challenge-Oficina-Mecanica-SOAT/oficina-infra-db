terraform {
  required_version = ">= 1.9.0"
  required_providers {
    # NOTA: o modulo VPC vendorizado em modules/vpc/vendor/terraform-aws-vpc
    # esta na v6.x e exige aws provider >= 6.28. Por isso a constraint aqui
    # e ">= 5.70, < 7.0" em vez do "~> 5.0" original do plano. Se o vendor
    # for rebaixado para a v5.5.x planejada, esta constraint pode voltar
    # para "~> 5.0".
    aws    = { source = "hashicorp/aws", version = ">= 5.70, < 7.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

provider "aws" {
  region = var.aws_region
}

module "vpc" {
  source      = "../../modules/vpc"
  environment = var.environment
}

module "secrets" {
  source      = "../../modules/secrets"
  environment = var.environment
}

module "rds" {
  source              = "../../modules/rds"
  environment         = var.environment
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnets
  db_password         = module.secrets.db_password_value

  depends_on = [module.vpc, module.secrets]
}
