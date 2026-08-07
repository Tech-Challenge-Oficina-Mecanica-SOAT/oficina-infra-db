# Architecture Overview

This repository manages shared AWS infrastructure for the oficina project:

- VPC with public and private subnets in two AZs
- NAT Gateway for internet outbound access from private subnets
- RDS PostgreSQL instance in private subnets
- Secrets Manager for the RDS password and JWT secret key
- Parameter Store for published non-sensitive infrastructure values

## Diagrama de rede

```mermaid
flowchart TB
    subgraph VPC["VPC 10.0.0.0/16 (us-east-1)"]
        subgraph AZ1["us-east-1a"]
            PUB1["Subnet publica<br/>10.0.1.0/24"]
            PRIV1["Subnet privada<br/>10.0.10.0/24"]
        end
        subgraph AZ2["us-east-1b"]
            PUB2["Subnet publica<br/>10.0.2.0/24"]
            PRIV2["Subnet privada<br/>10.0.20.0/24"]
        end
        IGW["Internet Gateway"]
        NAT["NAT Gateway<br/>(single_nat_gateway)"]
        RDS["RDS PostgreSQL 15.7<br/>db.t3.micro Single-AZ"]
        SG["Security Group<br/>porta 5432 (VPC)"]

        IGW --- PUB1
        IGW --- PUB2
        PUB1 --- NAT
        NAT --- PRIV1
        NAT --- PRIV2
        PRIV1 --- RDS
        PRIV2 --- RDS
        SG -.protege.- RDS
    end

    SM["Secrets Manager<br/>db-password / jwt-secret-key"]
    SSM["Parameter Store<br/>contratos de rede e db"]

    RDS -. senha .-> SM
    VPC -. publica IDs .-> SSM

    EKS["EKS (P3)"] -. consome subnets .-> SSM
    LAMBDA["Lambda auth-cpf (P2)"] -. consome JWT key .-> SM
    API["API .NET (P1)"] -. consome db + JWT .-> SSM
    API -. consome db + JWT .-> SM
```

## Logical components

- `modules/vpc` — creates shared networking, publishes VPC and subnet IDs to SSM Parameter Store
- `modules/secrets` — creates Secrets Manager secrets for `db-password` and `jwt-secret-key`
- `modules/rds` — creates PostgreSQL instance in private subnets and publishes db endpoint/credentials metadata to SSM Parameter Store

## Environments

Each environment has its own Terraform workspace under `envs/`:

- `envs/homolog`
- `envs/prod`

Each environment contains:

- `main.tf`
- `backend.tf`
- `variables.tf`
- `terraform.tfvars.example`

## Deployment flow

1. Initialize `envs/<environment>` with `terraform init`
2. Validate with `terraform validate`
3. Plan with `terraform plan`
4. Apply with `terraform apply` (manual dispatch on GitHub Actions or local)

## Contracts

Published to SSM Parameter Store:

- `/oficina/{env}/network/vpc-id`
- `/oficina/{env}/network/vpc-cidr`
- `/oficina/{env}/network/public-subnet-ids`
- `/oficina/{env}/network/private-subnet-ids`
- `/oficina/{env}/db/endpoint`
- `/oficina/{env}/db/port`
- `/oficina/{env}/db/name`
- `/oficina/{env}/db/username`
- `/oficina/{env}/db/security-group-id`

Published to Secrets Manager:

- `oficina/{env}/db-password`
- `oficina/{env}/jwt-secret-key`
