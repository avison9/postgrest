# outputs.tf
output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.postgrest.alb_dns_name
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.postgrest.ecs_cluster_name
}

output "mapper_service_name" {
  description = "Name of the mapper service"
  value       = module.postgrest.mapper_service_name
}

# output "postgrest_service_names" {
#   description = "Names of the PostgREST services"
#   value       = module.postgrest.postgrest_service_names
# }

output "postgres_subnet_ids" {
  description = "IDs of the PostgreSQL subnets"
  value       = module.postgrest.postgres_subnet_ids
}

output "rds_secret_arn" {
  description = "ARN of the Secrets Manager secret for RDS credentials"
  value       = module.postgrest.rds_secret_arn
}

output "api_secret_arn" {
  description = "ARN of the Secrets Manager secret for API key"
  value       = module.postgrest.api_secret_arn
}
