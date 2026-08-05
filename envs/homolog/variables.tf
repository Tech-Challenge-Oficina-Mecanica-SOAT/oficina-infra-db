variable "aws_region" {
  description = "AWS region used by the provider"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "homolog"
}
