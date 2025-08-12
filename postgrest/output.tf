# outputs.tf
output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main_alb.dns_name
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.postgrest_cluster.name
}

output "mapper_service_name" {
  description = "Name of the mapper service"
  value       = aws_ecs_service.mapper_service.name
}

output "postgrest_service_names" {
  description = "Names of the PostgREST services"
  value       = aws_ecs_service.postgrest_service[*].name
}

output "postgres_subnet_ids" {
  description = "IDs of the PostgreSQL subnets"
  value       = aws_subnet.postgres_subnet[*].id
}

output "rds_secret_arn" {
  description = "ARN of the Secrets Manager secret for RDS credentials"
  value       = var.rds_secret_arn
}

output "api_secret_arn" {
  description = "ARN of the Secrets Manager secret for API key"
  value       = var.api_secret_arn
}