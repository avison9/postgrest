// Dagster module sets up the Dagster platform and its ECS services
// It connects to the client’s database and uses network infrastructure configured by the networking module
module "postgrest" {
  source                          = "../postgrest"
  environment                     = var.environment                     # Deployment environment
  region                          = var.region
  vpc_id                  = var.vpc_id
  rds_endpoint            = var.rds_endpoint
  rds_secret_arn          = var.rds_secret_arn
  api_secret_arn          = var.api_secret_arn
  az_count                = var.az_count
  postgres_subnet_cidrs   = var.postgres_subnet_cidrs
  availability_zones      = var.availability_zones
  postgrest_service_count = var.postgrest_service_count
  postgrest_task_counts   = var.postgrest_task_counts
  mapper_cpu              = var.mapper_cpu
  mapper_memory           = var.mapper_memory
  postgrest_cpu           = var.postgrest_cpu
  postgrest_memory        = var.postgrest_memory
  log_retention_days      = var.log_retention_days
  mapper_image_tag        = var.mapper_image_tag
  postgrest_image_tag     = var.postgrest_image_tag
  config_url              = var.config_url
  meta_secret_arn         = var.meta_secret_arn
  meta_hash_arn           = var.meta_hash_arn
  supa_secret_arn         = var.supa_secret_arn
}
