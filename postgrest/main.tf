# # CloudWatch Log Groups
# resource "aws_cloudwatch_log_group" "mapper_log_group" {
#   name              = "${var.environment}-mapper-service"
#   retention_in_days = var.log_retention_days
# }

# resource "aws_cloudwatch_log_group" "supavisor_log_group" {
#   count             = var.postgrest_service_count
#   name              = "${var.environment}-supavisor-service-${count.index + 1}"
#   retention_in_days = var.log_retention_days
# }

# # ECR Repository
# resource "aws_ecr_repository" "app_repo" {
#   name = "${var.environment}-postgrest-app-repo"
# }

# # ECS Cluster
# resource "aws_ecs_cluster" "postgrest_cluster" {
#   name = "${var.environment}-postgrest-cluster"
# }

# # Security group for ECS services and ALB
# resource "aws_security_group" "ecs_sg" {
#   vpc_id = var.vpc_id
#   name   = "${var.environment}-ecs-main-sg"

#   ingress {
#     from_port   = 80
#     to_port     = 80
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   ingress {
#     from_port   = 8000
#     to_port     = 8000
#     protocol    = "tcp"
#     self        = true
#   }

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
# }

# # Security group for Supavisor access
# resource "aws_security_group" "supavisor_sg" {
#   vpc_id = var.vpc_id
#   name   = "${var.environment}-supavisor-sg"

#   ingress {
#     from_port   = 5433
#     to_port     = 5433
#     protocol    = "tcp"
#     cidr_blocks = ["172.31.0.0/16"]  # For NLB health checks and internal access
#   }

#   ingress {
#     from_port   = 4000
#     to_port     = 4000
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0.0/0"]  # Allow external access to port 4000
#   }

#   ingress {
#     from_port       = 5433
#     to_port         = 5433
#     protocol        = "tcp"
#     security_groups = [aws_security_group.ecs_sg.id]  # For mapper_service
#   }

#   ingress {
#     from_port       = 4000
#     to_port         = 4000
#     protocol        = "tcp"
#     security_groups = [aws_security_group.ecs_sg.id]  # For mapper_service
#   }

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
# }

# # Security group for RDS access
# resource "aws_security_group" "rds_sg" {
#   vpc_id = var.vpc_id
#   name   = "${var.environment}-postgrest-rds-sg"

#   ingress {
#     from_port       = 5432
#     to_port         = 5432
#     protocol        = "tcp"
#     security_groups = [aws_security_group.ecs_sg.id, aws_security_group.supavisor_sg.id]
#   }

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
# }

# # Subnets for PostgreSQL
# resource "aws_subnet" "postgres_subnet" {
#   count             = var.az_count
#   vpc_id            = var.vpc_id
#   cidr_block        = var.postgres_subnet_cidrs[count.index]
#   availability_zone = var.availability_zones[count.index]
#   tags = {
#     Name = "${var.environment}-postgrest-subnet-${count.index + 1}"
#   }
# }

# # Data source for existing internet gateway
# data "aws_internet_gateway" "existing_igw" {
#   filter {
#     name   = "attachment.vpc-id"
#     values = [var.vpc_id]
#   }
# }

# # Route table for postgres subnets to ensure RDS connectivity
# resource "aws_route_table" "postgres_route_table" {
#   vpc_id = var.vpc_id
#   route {
#     cidr_block = "0.0.0.0/0"
#     gateway_id = data.aws_internet_gateway.existing_igw.internet_gateway_id
#   }
#   tags = {
#     Name = "${var.environment}-postgres-route-table"
#   }
# }

# resource "aws_route_table_association" "postgres_subnet_association" {
#   count          = var.az_count
#   subnet_id      = aws_subnet.postgres_subnet[count.index].id
#   route_table_id = aws_route_table.postgres_route_table.id
# }

# # Subnet group for existing RDS
# resource "aws_db_subnet_group" "postgres_subnet_group" {
#   name       = "${var.environment}-postgres-subnet-group"
#   subnet_ids = aws_subnet.postgres_subnet[*].id
#   tags = {
#     Name = "${var.environment}-postgres-subnet-group"
#   }
# }

# # IAM Role for ECS execution
# resource "aws_iam_role" "ecs_task_execution_role" {
#   name = "${var.environment}-postgrest-ecs-task-execution-role"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect = "Allow",
#         Principal = {
#           Service = "ecs-tasks.amazonaws.com"
#         },
#         Action = "sts:AssumeRole"
#       }
#     ]
#   })
# }

# resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
#   role       = aws_iam_role.ecs_task_execution_role.name
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
# }

# # Task Role for ECS containers to access secrets
# resource "aws_iam_role" "ecs_task_role" {
#   name = "${var.environment}-postgrest-ecs-task-role"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect = "Allow",
#         Principal = {
#           Service = "ecs-tasks.amazonaws.com"
#         },
#         Action = "sts:AssumeRole"
#       }
#     ]
#   })
# }

# resource "aws_iam_role_policy" "ecs_task_secrets_policy" {
#   name = "${var.environment}-ecs-task-secrets-policy"
#   role = aws_iam_role.ecs_task_role.id

#   policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect = "Allow",
#         Action = ["secretsmanager:GetSecretValue"],
#         Resource = [var.rds_secret_arn, var.api_secret_arn, var.meta_secret_arn, var.meta_hash_arn, var.supa_secret_arn]
#       },
#       {
#         Effect = "Allow",
#         Action = [
#           "ecr:GetDownloadUrlForLayer",
#           "ecr:BatchGetImage",
#           "ecr:GetAuthorizationToken"
#         ],
#         Resource = "*"
#       },
#       {
#         Effect = "Allow",
#         Action = [
#           "logs:CreateLogStream",
#           "logs:PutLogEvents"
#         ],
#         Resource = "*"
#       }
#     ]
#   })
# }

# resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
#   name = "${var.environment}-ecs-execution-secrets-policy"
#   role = aws_iam_role.ecs_task_execution_role.id

#   policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect = "Allow",
#         Action = ["secretsmanager:GetSecretValue"],
#         Resource = [
#           var.rds_secret_arn,
#           var.api_secret_arn,
#           var.meta_secret_arn,
#           var.supa_secret_arn,
#           var.meta_hash_arn
#         ]
#       }
#     ]
#   })
# }

# resource "aws_iam_role_policy_attachment" "ecs_exec_ssm" {
#   role       = aws_iam_role.ecs_task_execution_role.name
#   policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
# }

# # Supavisor Task Definition
# resource "aws_ecs_task_definition" "supavisor_task" {
#   count                    = var.postgrest_service_count
#   family                   = "${var.environment}-supavisor-task-${count.index + 1}"
#   network_mode             = "awsvpc"
#   requires_compatibilities = ["FARGATE"]
#   cpu                      = var.postgrest_cpu
#   memory                   = var.postgrest_memory
#   execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
#   task_role_arn            = aws_iam_role.ecs_task_role.arn

#   container_definitions = jsonencode([
#     {
#       name  = "supavisor",
#       image = "${aws_ecr_repository.app_repo.repository_url}:supavisor",
#       essential = true,
#       portMappings = [
#         { containerPort = 5433, hostPort = 5433, protocol = "tcp" },
#         { containerPort = 4000, hostPort = 4000, protocol = "tcp" },
#         { containerPort = 5000, hostPort = 5000, protocol = "tcp" },
#         { containerPort = 5001, hostPort = 5001, protocol = "tcp" },
#         { containerPort = 6543, hostPort = 6543, protocol = "tcp" }
#       ],
#       environment = [
#         { name = "API_ENABLED", value = "true" },
#         { name = "API_PORT", value = "4000" },
#         { name = "POOLER_MODE", value = "transaction" },
#         { name = "RDS_ENDPOINT", value = var.rds_endpoint },
#         { name = "DEFAULT_POOL_SIZE", value = "20" },
#         { name = "DEFAULT_MAX_CLIENTS", value = "100" },
#         { name = "VAULT_ENC_KEY", value = "${var.meta_hash_arn}:meta_hash::" },
#         { name = "SECRET_KEY_BASE", value = "${var.supa_secret_arn}:sec_key::" },
#         { name = "API_JWT_SECRET", value = "${var.supa_secret_arn}:sec_key::" },
#         { name = "METRICS_JWT_SECRET", value = "${var.supa_secret_arn}:sec_key::" }
#       ],
#       secrets = [
#         { name = "META_USER", valueFrom = "${var.meta_secret_arn}:username::" },
#         { name = "META_PASS", valueFrom = "${var.meta_secret_arn}:password::" },
#         { name = "DATABASE_URL", valueFrom = "${var.meta_secret_arn}:db_url::" }
#       ],
#       logConfiguration = {
#         logDriver = "awslogs",
#         options = {
#           "awslogs-group"         = aws_cloudwatch_log_group.supavisor_log_group[count.index].name,
#           "awslogs-region"        = var.region,
#           "awslogs-stream-prefix" = "supavisor"
#         }
#       },
#       healthCheck = {
#         command     = ["CMD-SHELL", "nc -z localhost 5433 || exit 1"],
#         interval    = 30,
#         timeout     = 5,
#         retries     = 3,
#         startPeriod = 10
#       }
#     }
#   ])
# }

# # Supavisor Service
# resource "aws_ecs_service" "supavisor_service" {
#   count           = var.postgrest_service_count
#   name            = "${var.environment}-supavisor-service-${count.index + 1}"
#   cluster         = aws_ecs_cluster.postgrest_cluster.id
#   task_definition = aws_ecs_task_definition.supavisor_task[count.index].arn
#   desired_count   = element(var.postgrest_task_counts, count.index)
#   launch_type     = "FARGATE"
#   enable_execute_command = true

#   network_configuration {
#     subnets          = aws_subnet.postgres_subnet[*].id
#     security_groups  = [aws_security_group.supavisor_sg.id]
#     assign_public_ip = true
#   }

#   load_balancer {
#     target_group_arn = aws_lb_target_group.supavisor_tg.arn
#     container_name   = "supavisor"
#     container_port   = 5433
#   }

#   load_balancer {
#     target_group_arn = aws_lb_target_group.supavisor_admin_tg.arn
#     container_name   = "supavisor"
#     container_port   = 4000
#   }

#   depends_on = [
#     aws_lb_listener.supavisor_listener,
#     aws_lb_listener.supavisor_admin_listener
#   ]
# }

# # Network Load Balancer for Supavisor
# resource "aws_lb" "supavisor_nlb" {
#   name               = "${var.environment}-supavisor-nlb"
#   internal           = true
#   load_balancer_type = "network"
#   subnets            = aws_subnet.postgres_subnet[*].id
# }

# resource "aws_lb_target_group" "supavisor_tg" {
#   name        = "${var.environment}-supavisor-tg"
#   port        = 5433
#   protocol    = "TCP"
#   vpc_id      = var.vpc_id
#   target_type = "ip"

#   health_check {
#     enabled  = true
#     protocol = "TCP"
#     port     = "5433"
#     interval = 30
#     timeout  = 10
#     healthy_threshold   = 3
#     unhealthy_threshold = 3
#   }
# }

# resource "aws_lb_listener" "supavisor_listener" {
#   load_balancer_arn = aws_lb.supavisor_nlb.arn
#   port              = 5433
#   protocol          = "TCP"

#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.supavisor_tg.arn
#   }
# }

# # Mapper Task Definition
# resource "aws_ecs_task_definition" "mapper_task" {
#   family                   = "${var.environment}-mapper-task"
#   network_mode             = "awsvpc"
#   requires_compatibilities = ["FARGATE"]
#   cpu                      = var.mapper_cpu
#   memory                   = var.mapper_memory
#   execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
#   task_role_arn            = aws_iam_role.ecs_task_role.arn

#   container_definitions = jsonencode([
#     {
#       name  = "mapper",
#       image = "${aws_ecr_repository.app_repo.repository_url}:mapper",
#       portMappings = [
#         {
#           containerPort = 8000,
#           hostPort      = 8000
#         }
#       ],
#       environment = [
#         { name = "RDS_HOST", value = var.rds_endpoint },
#         { name = "RDS_SECRET_ARN", value = var.rds_secret_arn },
#         { name = "API_SECRET_ARN", value = var.api_secret_arn },
#         { name = "META_SECRET_ARN", value = var.meta_secret_arn },
#         { name = "META_HARSH_ARN", value = var.meta_hash_arn },
#         { name = "SUPA_KEY_ARN", value = var.supa_secret_arn },
#         { name = "META_HOST", value = var.rds_endpoint },
#         { name = "ALB_DNS_NAME", value = aws_lb.main_alb.dns_name },
#         { name = "SUPAVISOR_HOST", value = aws_lb.supavisor_nlb.dns_name }
#       ],
#       logConfiguration = {
#         logDriver = "awslogs",
#         options = {
#           "awslogs-group"         = aws_cloudwatch_log_group.mapper_log_group.name,
#           "awslogs-region"        = var.region,
#           "awslogs-stream-prefix" = "mapper"
#         }
#       }
#     }
#   ])
# }

# # Mapper Service
# resource "aws_ecs_service" "mapper_service" {
#   name            = "${var.environment}-mapper-service"
#   cluster         = aws_ecs_cluster.postgrest_cluster.id
#   task_definition = aws_ecs_task_definition.mapper_task.arn
#   desired_count   = 1
#   launch_type     = "FARGATE"
#   enable_execute_command = true

#   network_configuration {
#     subnets          = aws_subnet.postgres_subnet[*].id
#     security_groups  = [aws_security_group.ecs_sg.id]
#     assign_public_ip = true
#   }

#   load_balancer {
#     target_group_arn = aws_lb_target_group.mapper_tg.arn
#     container_name   = "mapper"
#     container_port   = 8000
#   }

#   depends_on = [aws_lb_listener.mapper_listener]
# }

# # Application Load Balancer
# resource "aws_lb" "main_alb" {
#   name               = "${var.environment}-mapper-alb"
#   internal           = false
#   load_balancer_type = "application"
#   security_groups    = [aws_security_group.ecs_sg.id]
#   subnets            = aws_subnet.postgres_subnet[*].id
# }

# # Target Group for Mapper
# resource "aws_lb_target_group" "mapper_tg" {
#   name        = "${var.environment}-mapper-tg"
#   port        = 8000
#   protocol    = "HTTP"
#   vpc_id      = var.vpc_id
#   target_type = "ip"

#   health_check {
#     path = "/health"
#     port = "8000"
#   }
# }

# # ALB Listener for Mapper
# resource "aws_lb_listener" "mapper_listener" {
#   load_balancer_arn = aws_lb.main_alb.arn
#   port              = 80
#   protocol          = "HTTP"

#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.mapper_tg.arn
#   }
# }

# # Target Group for Supavisor Admin (Port 4000)
# resource "aws_lb_target_group" "supavisor_admin_tg" {
#   name        = "${var.environment}-supavisor-admin-tg"
#   port        = 4000
#   protocol    = "TCP"
#   vpc_id      = var.vpc_id
#   target_type = "ip"

#   health_check {
#     enabled  = true
#     protocol = "TCP"
#     port     = "4000"
#     interval = 30
#     timeout  = 10
#     healthy_threshold   = 3
#     unhealthy_threshold = 3
#   }
# }

# # Listener for Port 4000
# resource "aws_lb_listener" "supavisor_admin_listener" {
#   load_balancer_arn = aws_lb.supavisor_nlb.arn
#   port              = 4000
#   protocol          = "TCP"

#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.supavisor_admin_tg.arn
#   }
# }


# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "mapper_log_group" {
  name              = "${var.environment}-mapper-service"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "supavisor_log_group" {
  count             = var.postgrest_service_count
  name              = "${var.environment}-supavisor-service-${count.index + 1}"
  retention_in_days = var.log_retention_days
}

# ECR Repository
resource "aws_ecr_repository" "app_repo" {
  name = "${var.environment}-postgrest-app-repo"
}

# ECS Cluster
resource "aws_ecs_cluster" "postgrest_cluster" {
  name = "${var.environment}-postgrest-cluster"
}

# Security group for ECS services and ALB
resource "aws_security_group" "ecs_sg" {
  vpc_id = var.vpc_id
  name   = "${var.environment}-ecs-main-sg"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security group for Supavisor access
resource "aws_security_group" "supavisor_sg" {
  vpc_id = var.vpc_id
  name   = "${var.environment}-supavisor-sg"

  ingress {
    from_port   = 6543
    to_port     = 6543
    protocol    = "tcp"
    cidr_blocks = ["172.31.0.0/16"]  # For NLB health checks and internal access
  }

  ingress {
    from_port   = 4000
    to_port     = 4000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allow external access to API port 4000
  }

  ingress {
    from_port       = 6543
    to_port         = 6543
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_sg.id]  # For mapper_service
  }

  ingress {
    from_port       = 4000
    to_port         = 4000
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_sg.id]  # For mapper_service to API
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security group for RDS access
resource "aws_security_group" "rds_sg" {
  vpc_id = var.vpc_id
  name   = "${var.environment}-postgrest-rds-sg"

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_sg.id, aws_security_group.supavisor_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Subnets for PostgreSQL
resource "aws_subnet" "postgres_subnet" {
  count             = var.az_count
  vpc_id            = var.vpc_id
  cidr_block        = var.postgres_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "${var.environment}-postgrest-subnet-${count.index + 1}"
  }
}

# Data source for existing internet gateway
data "aws_internet_gateway" "existing_igw" {
  filter {
    name   = "attachment.vpc-id"
    values = [var.vpc_id]
  }
}

# Route table for postgres subnets to ensure RDS connectivity
resource "aws_route_table" "postgres_route_table" {
  vpc_id = var.vpc_id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = data.aws_internet_gateway.existing_igw.internet_gateway_id
  }
  tags = {
    Name = "${var.environment}-postgres-route-table"
  }
}

resource "aws_route_table_association" "postgres_subnet_association" {
  count          = var.az_count
  subnet_id      = aws_subnet.postgres_subnet[count.index].id
  route_table_id = aws_route_table.postgres_route_table.id
}

# Subnet group for existing RDS
resource "aws_db_subnet_group" "postgres_subnet_group" {
  name       = "${var.environment}-postgres-subnet-group"
  subnet_ids = aws_subnet.postgres_subnet[*].id
  tags = {
    Name = "${var.environment}-postgres-subnet-group"
  }
}

# IAM Role for ECS execution
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.environment}-postgrest-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Task Role for ECS containers to access secrets
resource "aws_iam_role" "ecs_task_role" {
  name = "${var.environment}-postgrest-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "ecs_task_secrets_policy" {
  name = "${var.environment}-ecs-task-secrets-policy"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["secretsmanager:GetSecretValue"],
        Resource = [var.rds_secret_arn, var.api_secret_arn, var.meta_secret_arn, var.meta_hash_arn, var.supa_secret_arn]
      },
      {
        Effect = "Allow",
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:GetAuthorizationToken"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  name = "${var.environment}-ecs-execution-secrets-policy"
  role = aws_iam_role.ecs_task_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["secretsmanager:GetSecretValue"],
        Resource = [
          var.rds_secret_arn,
          var.api_secret_arn,
          var.meta_secret_arn,
          var.supa_secret_arn,
          var.meta_hash_arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_exec_ssm" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Supavisor Task Definition
resource "aws_ecs_task_definition" "supavisor_task" {
  count                    = var.postgrest_service_count
  family                   = "${var.environment}-supavisor-task-${count.index + 1}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.postgrest_cpu
  memory                   = var.postgrest_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name  = "supavisor",
      image = "${aws_ecr_repository.app_repo.repository_url}:supavisor",
      essential = true,
      portMappings = [
        { containerPort = 6543, hostPort = 6543, protocol = "tcp" },
        { containerPort = 4000, hostPort = 4000, protocol = "tcp" },  # Management API
        { containerPort = 5000, hostPort = 5000, protocol = "tcp" },
        { containerPort = 5001, hostPort = 5001, protocol = "tcp" },
        { containerPort = 5434, hostPort = 5434, protocol = "tcp" },  # Session proxy
        { containerPort = 5435, hostPort = 5435, protocol = "tcp" },   # General proxy
        { containerPort = 5433, hostPort = 5433, protocol = "tcp" },
      ],
      environment = [
        { name = "API_ENABLED", value = "true" },
        { name = "API_PORT", value = "4000" },  # Management API on default port
        { name = "POOLER_MODE", value = "transaction" },
        { name = "RDS_ENDPOINT", value = var.rds_endpoint },
        { name = "DEFAULT_POOL_SIZE", value = "2" },
        { name = "DEFAULT_MAX_CLIENTS", value = "20" },
        { name = "POOLER_MODE", value = "transaction" },
        { name = "LOG_LEVEL", value = "debug" },
        { name = "LOG_REQUESTS", value = "true" }

      ],
      secrets = [
        { name = "META_USER", valueFrom = "${var.meta_secret_arn}:username::" },
        { name = "META_PASS", valueFrom = "${var.meta_secret_arn}:password::" },
        { name = "DATABASE_URL", valueFrom = "${var.meta_secret_arn}:db_url::" },
        { name = "VAULT_ENC_KEY", valueFrom = "${var.meta_hash_arn}:meta_hash::" },
        { name = "SECRET_KEY_BASE", valueFrom = "${var.supa_secret_arn}:sec_key::" },
        { name = "API_JWT_SECRET", valueFrom = "${var.supa_secret_arn}:jwt_32_bits::" },
        { name = "METRICS_JWT_SECRET", valueFrom = "${var.supa_secret_arn}:jwt_32_bits::" }
      ],
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.supavisor_log_group[count.index].name,
          "awslogs-region"        = var.region,
          "awslogs-stream-prefix" = "supavisor"
        }
      },
      healthCheck = {
        command     = ["CMD-SHELL", "nc -z localhost 6543 || exit 1"],
        interval    = 30,
        timeout     = 5,
        retries     = 3,
        startPeriod = 10
      }
    }
  ])
}

# Supavisor Service
resource "aws_ecs_service" "supavisor_service" {
  count           = var.postgrest_service_count
  name            = "${var.environment}-supavisor-service-${count.index + 1}"
  cluster         = aws_ecs_cluster.postgrest_cluster.id
  task_definition = aws_ecs_task_definition.supavisor_task[count.index].arn
  desired_count   = element(var.postgrest_task_counts, count.index)
  launch_type     = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets          = aws_subnet.postgres_subnet[*].id
    security_groups  = [aws_security_group.supavisor_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.supavisor_tg.arn
    container_name   = "supavisor"
    container_port   = 6543
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.supavisor_admin_tg.arn
    container_name   = "supavisor"
    container_port   = 4000  # Admin API port
  }

  depends_on = [
    aws_lb_listener.supavisor_listener,
    aws_lb_listener.supavisor_admin_listener
  ]
}

# Network Load Balancer for Supavisor
resource "aws_lb" "supavisor_nlb" {
  name               = "${var.environment}-supavisor-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = aws_subnet.postgres_subnet[*].id
}

resource "aws_lb_target_group" "supavisor_tg" {
  name        = "${var.environment}-supavisor-tg"
  port        = 6543
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled  = true
    protocol = "TCP"
    port     = "6543"
    interval = 30
    timeout  = 10
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "supavisor_listener" {
  load_balancer_arn = aws_lb.supavisor_nlb.arn
  port              = 6543
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.supavisor_tg.arn
  }
}

# Mapper Task Definition
resource "aws_ecs_task_definition" "mapper_task" {
  family                   = "${var.environment}-mapper-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.mapper_cpu
  memory                   = var.mapper_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name  = "mapper",
      image = "${aws_ecr_repository.app_repo.repository_url}:mapper",
      portMappings = [
        {
          containerPort = 8000,
          hostPort      = 8000
        }
      ],
      environment = [
        { name = "RDS_HOST", value = var.rds_endpoint },
        { name = "RDS_SECRET_ARN", value = var.rds_secret_arn },
        { name = "API_SECRET_ARN", value = var.api_secret_arn },
        { name = "META_SECRET_ARN", value = var.meta_secret_arn },
        { name = "META_HARSH_ARN", value = var.meta_hash_arn },
        { name = "SUPA_KEY_ARN", value = var.supa_secret_arn },
        { name = "META_HOST", value = var.rds_endpoint },
        { name = "ALB_DNS_NAME", value = aws_lb.main_alb.dns_name },
        { name = "SUPAVISOR_HOST", value = "${aws_lb.supavisor_nlb.dns_name}" }  # Use port 4000 for API
      ],
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.mapper_log_group.name,
          "awslogs-region"        = var.region,
          "awslogs-stream-prefix" = "mapper"
        }
      }
    }
  ])
}

# Mapper Service
resource "aws_ecs_service" "mapper_service" {
  name            = "${var.environment}-mapper-service"
  cluster         = aws_ecs_cluster.postgrest_cluster.id
  task_definition = aws_ecs_task_definition.mapper_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets          = aws_subnet.postgres_subnet[*].id
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.mapper_tg.arn
    container_name   = "mapper"
    container_port   = 8000
  }

  depends_on = [aws_lb_listener.mapper_listener]
}

# Application Load Balancer
resource "aws_lb" "main_alb" {
  name               = "${var.environment}-mapper-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ecs_sg.id]
  subnets            = aws_subnet.postgres_subnet[*].id
}

# Target Group for Mapper
resource "aws_lb_target_group" "mapper_tg" {
  name        = "${var.environment}-mapper-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path = "/health"
    port = "8000"
  }
}

# ALB Listener for Mapper
resource "aws_lb_listener" "mapper_listener" {
  load_balancer_arn = aws_lb.main_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.mapper_tg.arn
  }
}

# Target Group for Supavisor Admin (Port 4000)
resource "aws_lb_target_group" "supavisor_admin_tg" {
  name        = "${var.environment}-supavisor-admin-tg"
  port        = 4000
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    protocol            = "HTTP"
    port                = "4000"
    path                = "/swaggerui"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 3
    unhealthy_threshold = 3
    matcher             = "200-399"
  }
}

# Listener for Port 4000
resource "aws_lb_listener" "supavisor_admin_listener" {
  load_balancer_arn = aws_lb.supavisor_nlb.arn
  port              = 4000
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.supavisor_admin_tg.arn
  }
}
