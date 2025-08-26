# variables.tf
variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-north-1"
}

variable "environment" {
  description = "Environment name (e.g., dev, prod)"
  type        = string
}

variable "vpc_id" {
  description = "ID of the existing VPC"
  type        = string
}

variable "rds_endpoint" {
  description = "Endpoint of the existing RDS instance"
  type        = string
}

variable "rds_secret_arn" {
  description = "ARN of the existing Secrets Manager secret for RDS credentials"
  type        = string
}

variable "api_secret_arn" {
  description = "ARN of the existing Secrets Manager secret for API key"
  type        = string
}

variable "config_url" {
  description = "URL to fetch PostgREST configuration (db_name, schema_name)"
  type        = string
  default     = ""
}

variable "az_count" {
  description = "Number of availability zones to use"
  type        = number
  default     = 3
  validation {
    condition     = var.az_count >= 2
    error_message = "At least 2 availability zones are required for ALB high availability"
  }
}

variable "postgres_subnet_cidrs" {
  description = "List of CIDR blocks for PostgreSQL subnets"
  type        = list(string)
  default     = ["172.31.1.0/24", "172.31.2.0/24", "172.31.3.0/24"]
  validation {
    condition     = length(var.postgres_subnet_cidrs) >= var.az_count
    error_message = "Length of postgres_subnet_cidrs must be at least az_count"
  }
}

variable "availability_zones" {
  description = "List of availability zones for PostgreSQL subnets"
  type        = list(string)
  default     = ["eu-north-1a", "eu-north-1b", "eu-north-1c"]
  validation {
    condition     = length(var.availability_zones) >= var.az_count
    error_message = "Length of availability_zones must be at least az_count"
  }
}

variable "mapper_image_tag" {
  description = "Tag for the mapper image in ECR"
  type        = string
  default     = "mapper"
}

variable "postgrest_image_tag" {
  description = "Tag for the PostgREST image in ECR"
  type        = string
  default     = "postgrest"
}

variable "postgrest_service_count" {
  description = "Number of PostgREST services"
  type        = number
  default     = 1
}

variable "postgrest_task_counts" {
  description = "List of task counts for each PostgREST service"
  type        = list(number)
  default     = [4]
  validation {
    condition     = length(var.postgrest_task_counts) >= var.postgrest_service_count
    error_message = "Length of postgrest_task_counts must be at least postgrest_service_count"
  }
}

variable "mapper_cpu" {
  description = "CPU units for the mapper task"
  type        = string
  default     = "256"
}

variable "mapper_memory" {
  description = "Memory (MB) for the mapper task"
  type        = string
  default     = "512"
}

variable "postgrest_cpu" {
  description = "CPU units for the PostgREST task"
  type        = string
  default     = "256"
}

variable "postgrest_memory" {
  description = "Memory (MB) for the PostgREST task"
  type        = string
  default     = "512"
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
}

variable "meta_secret_arn" {
  description = "ARN of Secrets Manager secret for Supavisor meta DB"
  type        = string
}

variable "meta_hash_arn" {
  description = "ARN of the existing Secrets Manager secret for password Hash"
  type        = string
}

variable "supa_secret_arn" {
  description = "ARN of the existing Secrets Manager secret for password Hash"
  type        = string
}

