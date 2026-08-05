terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.70, < 7.0" }
  }
}

module "vpc" {
  source  = "./vendor/terraform-aws-vpc"

  name = "oficina-vpc-${var.environment}"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b"]
  private_subnets = ["10.0.10.0/24", "10.0.20.0/24"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb"                               = 1
    "kubernetes.io/cluster/oficina-eks-${var.environment}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"                      = 1
    "kubernetes.io/cluster/oficina-eks-${var.environment}" = "shared"
  }

  tags = {
    Project     = "oficina-mecanica"
    Environment = var.environment
    ManagedBy   = "terraform"
    Repository  = "oficina-infra-db"
  }
}

resource "aws_ssm_parameter" "vpc_id" {
  name  = "/oficina/${var.environment}/network/vpc-id"
  type  = "String"
  value = module.vpc.vpc_id
  overwrite = true
}

resource "aws_ssm_parameter" "vpc_cidr" {
  name  = "/oficina/${var.environment}/network/vpc-cidr"
  type  = "String"
  value = module.vpc.vpc_cidr_block
  overwrite = true
}

resource "aws_ssm_parameter" "public_subnet_ids" {
  name  = "/oficina/${var.environment}/network/public-subnet-ids"
  type  = "StringList"
  value = join(",", module.vpc.public_subnets)
  overwrite = true
}

resource "aws_ssm_parameter" "private_subnet_ids" {
  name  = "/oficina/${var.environment}/network/private-subnet-ids"
  type  = "StringList"
  value = join(",", module.vpc.private_subnets)
  overwrite = true
}
