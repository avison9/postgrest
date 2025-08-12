# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "mapper_log_group" {
  name              = "${var.environment}-mapper-service"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "postgrest_log_group" {
  count             = var.postgrest_service_count
  name              = "${var.environment}-postgrest-service-${count.index + 1}"
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
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    self        = true
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

# Security group for RDS access
resource "aws_security_group" "rds_sg" {
  vpc_id = var.vpc_id
  name   = "${var.environment}-postgrest-rds-sg"

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_sg.id, aws_security_group.postgrest_ecs_sg.id]
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

# IAM Role for ECS execution (unchanged)
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
        Resource = [var.rds_secret_arn, var.api_secret_arn, var.meta_secret_arn]
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
        { name = "META_HOST", value = var.rds_endpoint },
        { name = "ALB_DNS_NAME", value = aws_lb.main_alb.dns_name },
        { name = "POSTGREST_INTERNAL_ALB", value = aws_lb.postgrest_internal_alb.dns_name }
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

  network_configuration {
    subnets          = aws_subnet.postgres_subnet[*].id
    security_groups  = [aws_security_group.ecs_sg.id] # new SG above
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.mapper_tg.arn
    container_name   = "mapper"
    container_port   = 8000
  }

  depends_on = [aws_lb_listener.mapper_listener]
}

# PostgREST Task Definition
# resource "aws_ecs_task_definition" "postgrest_task" {
#   family                   = "${var.environment}-postgrest-task"
#   network_mode             = "awsvpc"
#   requires_compatibilities = ["FARGATE"]
#   cpu                      = var.postgrest_cpu
#   memory                   = var.postgrest_memory
#   execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
#   task_role_arn            = aws_iam_role.ecs_task_role.arn
#   count                    = var.postgrest_service_count

#   container_definitions = jsonencode([
#     {
#       name  = "postgrest",
#       image = "${aws_ecr_repository.app_repo.repository_url}:postgrest",
#       portMappings = [
#         {
#           containerPort = 3000,
#           hostPort      = 3000
#         }
#       ],
#       environment = [
#         { name = "MAPPER_API_URL", value = "http://${aws_lb.main_alb.dns_name}/db-url" },
#         { name = "API_SECRET_ARN", value = var.api_secret_arn },
#         { name = "CONFIG_URL", value = "http://${aws_lb.main_alb.dns_name}/config" }
#       ],
#       logConfiguration = {
#         logDriver = "awslogs",
#         options = {
#           "awslogs-group"         = "${var.environment}-postgrest-service-${count.index + 1}",
#           "awslogs-region"        = var.region,
#           "awslogs-stream-prefix" = "postgrest"
#         }
#       }
#     }
#   ])
# }

resource "aws_ecs_task_definition" "postgrest_task" {
  count                    = var.postgrest_service_count
  family                   = "${var.environment}-postgrest-task-${count.index + 1}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.postgrest_cpu
  memory                   = var.postgrest_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name  = "supavisor",
      image = "supabase/supavisor:1.1.21",  # Latest stable
      essential = true,
      portMappings = [
        { containerPort = 6543, hostPort = 6543, protocol = "tcp" }
      ],
      environment = [
        { name = "POOLER_MODE", value = "transaction" },
        { name = "DATABASE_URL", value = "postgresql://$(META_USER):$(META_PASS)@${var.rds_endpoint}:5432/supavisor_meta" },
        { name = "DEFAULT_POOL_SIZE", value = "20" },  # Per tenant
        { name = "DEFAULT_MAX_CLIENTS", value = "100" },
        { name = "VAULT_ENC_KEY", value = "${var.meta_hash_arn}:meta_hash::" }  # Generate: openssl rand -hex 16
      ],
      secrets = [
        { name = "META_USER", valueFrom = "${var.meta_secret_arn}:username::" },
        { name = "META_PASS", valueFrom = "${var.meta_secret_arn}:password::" }
      ],
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.supavisor_log_group[count.index].name,
          "awslogs-region"        = var.region,
          "awslogs-stream-prefix" = "supavisor"
        }
      }
      healthCheck = {
      command     = ["CMD-SHELL", "pg_isready -h 127.0.0.1 -p 6543 || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 10
      }
    },
    {
      name  = "postgrest",
      image = "${aws_ecr_repository.app_repo.repository_url}:postgrest",
      essential = true,
      portMappings = [
        { containerPort = 3000, hostPort = 3000 }
      ],
      environment = [
        { name = "PGRST_DB_URI", value = "postgresql://postgrest:$(PGRST_DB_PASS)@127.0.0.1:6543/postgres" },  # Fixed to Supavisor
        { name = "PGRST_DB_SCHEMAS", value = "*" },  # Allow all schemas
        { name = "PGRST_DB_ANON_ROLE", value = "web_anon" }
      ],
      secrets = [
        { name = "PGRST_JWT_SECRET", valueFrom = "${var.api_secret_arn}:api_key::" },
        { name = "PGRST_DB_PASS", valueFrom = "${var.rds_secret_arn}:password::" }
      ],
      dependsOn = [{ containerName = "supavisor", condition = "HEALTHY" }],
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          "awslogs-group"         = "${var.environment}-postgrest-service-${count.index + 1}",
          "awslogs-region"        = var.region,
          "awslogs-stream-prefix" = "postgrest"
        }
      }
    }
  ])
}

# PostgREST Services
resource "aws_ecs_service" "postgrest_service" {
  count           = var.postgrest_service_count
  name            = "${var.environment}-postgrest-service-${count.index + 1}"
  cluster         = aws_ecs_cluster.postgrest_cluster.id
  task_definition = aws_ecs_task_definition.postgrest_task[count.index].arn
  desired_count   = element(var.postgrest_task_counts, count.index)
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.postgres_subnet[*].id
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.postgrest_tg_internal.arn
    container_name   = "postgrest"
    container_port   = 3000
  }

  depends_on = [aws_lb_listener.postgrest_internal_listener]
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

# Target Group for PostgREST
resource "aws_lb_target_group" "postgrest_tg" {
  name        = "${var.environment}-postgrest-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path = "/health"
    port = "3000"
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

# ALB Listener Rule for PostgREST
# resource "aws_lb_listener_rule" "postgrest_rule" {
#   listener_arn = aws_lb_listener.mapper_listener.arn
#   priority     = 100

#   action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.postgrest_tg.arn
#   }

#   condition {
#     path_pattern {
#       values = ["/postgrest/*"]
#     }
#   }
# }

# Allow Mapper (current ecs_sg) -> Internal ALB
resource "aws_security_group" "postgrest_internal_alb_sg" {
  vpc_id = var.vpc_id
  name   = "${var.environment}-postgrest-internal-alb-sg"

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_sg.id] # existing ecs_sg (mapper currently uses this)
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Allow Internal ALB -> PostgREST tasks (container port 3000)
resource "aws_security_group" "postgrest_ecs_sg" {
  vpc_id = var.vpc_id
  name   = "${var.environment}-postgrest-backend-sg"

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.postgrest_internal_alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


# Internal Application Load Balancer for PostgREST
resource "aws_lb" "postgrest_internal_alb" {
  name               = "${var.environment}-postgrest-internal-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.postgrest_internal_alb_sg.id]
  subnets            = aws_subnet.postgres_subnet[*].id
}

# Internal target group which forwards to container port 3000
resource "aws_lb_target_group" "postgrest_tg_internal" {
  name        = "${var.environment}-postgrest-tg-internal"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path = "/health"
    port = "3000"
  }
}

resource "aws_lb_listener" "postgrest_internal_listener" {
  load_balancer_arn = aws_lb.postgrest_internal_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.postgrest_tg_internal.arn
  }
}



