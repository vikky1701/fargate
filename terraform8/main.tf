provider "aws" {
  region = "us-east-2"
}

# Get Default VPC
data "aws_vpc" "default" {
  default = true
}

# Get Default Subnets
data "aws_subnets" "default_public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# Get individual subnet details
data "aws_subnet" "default_subnets" {
  for_each = toset(data.aws_subnets.default_public.ids)
  id       = each.value
}

# Get availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Security Group for ALB
resource "aws_security_group" "alb_sg" {
  name        = "strapi-alb-sg-vivek"
  description = "Security group for Strapi ALB"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "strapi-alb-sg-vivek"
  }
}

# Security Group for ECS Tasks
resource "aws_security_group" "ecs_sg" {
  name        = "strapi-ecs-sg-vivek"
  description = "Security group for Strapi ECS tasks"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = 1337
    to_port         = 1337
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "strapi-ecs-sg-vivek"
  }
}

# Security Group for RDS
resource "aws_security_group" "rds_sg" {
  name        = "strapi-rds-sg-vivek"
  description = "Security group for Strapi RDS"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_sg.id]
  }

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
    description = "PostgreSQL from default VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "strapi-rds-sg-vivek"
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "strapi_cluster" {
  name = "strapi-cluster-vivek"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "strapi-cluster-vivek"
  }
}

# Application Load Balancer
resource "aws_lb" "strapi_alb" {
  name               = "strapi-alb-vivek"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  
  subnets = slice(data.aws_subnets.default_public.ids, 0, 2)

  enable_deletion_protection = false

  tags = {
    Name = "strapi-alb-vivek"
  }
}

# Blue Target Group
resource "aws_lb_target_group" "strapi_blue_tg" {
  name        = "strapi-blue-tg-vivek"
  port        = 1337
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 10
    interval            = 30
    path                = "/"
    matcher             = "200,302"
    port                = "traffic-port"
    protocol            = "HTTP"
  }

  tags = {
    Name = "strapi-blue-tg-vivek"
  }
}

# Green Target Group
resource "aws_lb_target_group" "strapi_green_tg" {
  name        = "strapi-green-tg-vivek"
  port        = 1337
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 10
    interval            = 30
    path                = "/"
    matcher             = "200,302"
    port                = "traffic-port"
    protocol            = "HTTP"
  }

  tags = {
    Name = "strapi-green-tg-vivek"
  }
}

# ALB Listener (starts with Blue target group)
resource "aws_lb_listener" "strapi_listener" {
  load_balancer_arn = aws_lb.strapi_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.strapi_blue_tg.arn
  }

  lifecycle {
    ignore_changes = [default_action]
  }
}

# Test Listener for Green deployments (port 8080)
resource "aws_lb_listener" "strapi_test_listener" {
  load_balancer_arn = aws_lb.strapi_alb.arn
  port              = "8080"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.strapi_green_tg.arn
  }

  lifecycle {
    ignore_changes = [default_action]
  }
}

# DB Subnet Group
resource "aws_db_subnet_group" "strapi_db_subnet_group" {
  name       = "strapi-db-subnet-group-vivek"
  subnet_ids = data.aws_subnets.default_public.ids

  tags = {
    Name = "strapi-db-subnet-group-vivek"
  }
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "strapi-ecs-task-execution-role-vivek"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "strapi-ecs-task-execution-role-vivek"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# IAM Role for CodeDeploy
resource "aws_iam_role" "codedeploy_role" {
  name = "strapi-codedeploy-role-vivek"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codedeploy.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "strapi-codedeploy-role-vivek"
  }
}

resource "aws_iam_role_policy_attachment" "codedeploy_role_policy" {
  role       = aws_iam_role.codedeploy_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
}

# IAM Role for RDS Enhanced Monitoring
resource "aws_iam_role" "rds_monitoring_role" {
  name = "strapi-rds-monitoring-role-vivek"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "strapi-rds-monitoring-role-vivek"
  }
}

resource "aws_iam_role_policy_attachment" "rds_monitoring_policy" {
  role       = aws_iam_role.rds_monitoring_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Custom Parameter Group
resource "aws_db_parameter_group" "postgres_params" {
  family = "postgres15"
  name   = "strapi-postgres-params-vivek"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  parameter {
    name  = "log_statement"
    value = "all"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  parameter {
    name  = "rds.force_ssl"
    value = "0"
  }

  tags = {
    Name = "strapi-postgres-params-vivek"
  }
}

# RDS PostgreSQL Instance
resource "aws_db_instance" "strapi_postgres" {
  identifier             = "strapi-postgres-db-vivek"
  engine                 = "postgres"
  engine_version         = "15.8"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  storage_type           = "gp2"
  db_name                = var.db_name
  username               = var.db_user
  password               = var.db_password
  port                   = 5432
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.strapi_db_subnet_group.name
  publicly_accessible    = false
  skip_final_snapshot    = true
  backup_retention_period = 0

  ca_cert_identifier = "rds-ca-rsa2048-g1"
  parameter_group_name = aws_db_parameter_group.postgres_params.name
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring_role.arn
  performance_insights_enabled = true
  performance_insights_retention_period = 7

  tags = {
    Name = "strapi-postgres-db-vivek"
  }
}

# CloudWatch Log Group for ECS
resource "aws_cloudwatch_log_group" "strapi_logs" {
  name              = "/ecs/strapi-task-vivek"
  retention_in_days = 7

  tags = {
    Name = "strapi-logs-vivek"
  }
}

# ECS Task Definition (Placeholder - will be updated by CodeDeploy)
resource "aws_ecs_task_definition" "strapi_task" {
  family                   = "strapi-task-vivek"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "strapi"
      image     = var.ecr_image_url
      essential = true
      
      portMappings = [
        {
          containerPort = 1337
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "DATABASE_CLIENT"
          value = "postgres"
        },
        {
          name  = "DATABASE_HOST"
          value = aws_db_instance.strapi_postgres.address
        },
        {
          name  = "DATABASE_PORT"
          value = "5432"
        },
        {
          name  = "DATABASE_NAME"
          value = var.db_name
        },
        {
          name  = "DATABASE_USERNAME"
          value = var.db_user
        },
        {
          name  = "DATABASE_PASSWORD"
          value = var.db_password
        },
        {
          name  = "NODE_ENV"
          value = "production"
        },
        {
          name  = "HOST"
          value = "0.0.0.0"
        },
        {
          name  = "PORT"
          value = "1337"
        },
        {
          name  = "DATABASE_SSL"
          value = "false"
        },
        {
          name  = "DATABASE_SSL_SELF"
          value = "true"
        },
        {
          name  = "DATABASE_SSL_REJECT_UNAUTHORIZED"
          value = "false"
        },
        {
          name  = "APP_KEYS"
          value = var.app_keys
        },
        {
          name  = "API_TOKEN_SALT"
          value = var.api_token_salt
        },
        {
          name  = "ADMIN_JWT_SECRET"
          value = var.admin_jwt_secret
        },
        {
          name  = "TRANSFER_TOKEN_SALT"
          value = var.transfer_token_salt
        },
        {
          name  = "DATABASE_URL"
          value = "postgres://${var.db_user}:${var.db_password}@${aws_db_instance.strapi_postgres.address}:5432/${var.db_name}"
        },
        {
          name = "JWT_SECRET"
          value = var.jwt_secret
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.strapi_logs.name
          "awslogs-region"        = "us-east-2"
          "awslogs-stream-prefix" = "ecs"
        }
      }

       healthCheck = {
        command = ["CMD-SHELL", "wget --quiet --tries=1 --spider http://localhost:1337/ || exit 1"]
        interval = 30
        timeout = 5
        retries = 3
        startPeriod = 60
      }
    }
  ])

  tags = {
    Name = "strapi-task-vivek"
  }

  lifecycle {
    ignore_changes = [container_definitions]
  }
}

# ECS Service (configured for Blue-Green deployment)
resource "aws_ecs_service" "strapi_service" {
  name            = "strapi-service-vivek"
  cluster         = aws_ecs_cluster.strapi_cluster.id
  task_definition = aws_ecs_task_definition.strapi_task.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = slice(data.aws_subnets.default_public.ids, 0, 2)
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.strapi_blue_tg.arn
    container_name   = "strapi"
    container_port   = 1337
  }

  # Enable CodeDeploy
  deployment_controller {
    type = "CODE_DEPLOY"
  }

  depends_on = [
    aws_lb_listener.strapi_listener,
    aws_db_instance.strapi_postgres
  ]

  tags = {
    Name = "strapi-service-vivek"
  }

  lifecycle {
    ignore_changes = [task_definition, load_balancer]
  }
}

# CodeDeploy Application
resource "aws_codedeploy_app" "strapi_app" {
  compute_platform = "ECS"
  name             = "strapi-app-vivek"

  tags = {
    Name = "strapi-app-vivek"
  }
}

# CodeDeploy Deployment Group - CORRECTED for ECS Fargate
resource "aws_codedeploy_deployment_group" "strapi_deployment_group" {
  app_name              = aws_codedeploy_app.strapi_app.name
  deployment_group_name = "strapi-deployment-group-vivek"
  service_role_arn      = aws_iam_role.codedeploy_role.arn

  # Required for ECS Blue/Green deployments
  deployment_style {
    deployment_type   = "BLUE_GREEN"
    deployment_option = "WITH_TRAFFIC_CONTROL"
  }

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }

  blue_green_deployment_config {
    terminate_blue_instances_on_deployment_success {
      action                          = "TERMINATE"
      termination_wait_time_in_minutes = 5
    }

    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }
  }

  deployment_config_name = "CodeDeployDefault.ECSCanary10Percent5Minutes"

  ecs_service {
    cluster_name = aws_ecs_cluster.strapi_cluster.name
    service_name = aws_ecs_service.strapi_service.name
  }

  # Load balancer configuration for ECS
  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [aws_lb_listener.strapi_listener.arn]
      }

      test_traffic_route {
        listener_arns = [aws_lb_listener.strapi_test_listener.arn]
      }

      target_group {
        name = aws_lb_target_group.strapi_blue_tg.name
      }

      target_group {
        name = aws_lb_target_group.strapi_green_tg.name
      }
    }
  }

  tags = {
    Name = "strapi-deployment-group-vivek"
  }
}

# SNS Topic for Alerts
resource "aws_sns_topic" "strapi_alerts" {
  name = "strapi-alerts-vivek"

  tags = {
    Name = "strapi-alerts-vivek"
  }
}

# SNS Topic Subscription
resource "aws_sns_topic_subscription" "email_alerts" {
  topic_arn = aws_sns_topic.strapi_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "ecs_high_cpu" {
  alarm_name          = "strapi-ecs-high-cpu-vivek"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ECS CPU utilization"
  alarm_actions       = [aws_sns_topic.strapi_alerts.arn]

  dimensions = {
    ServiceName = aws_ecs_service.strapi_service.name
    ClusterName = aws_ecs_cluster.strapi_cluster.name
  }

  tags = {
    Name = "strapi-ecs-high-cpu-vivek"
  }
}

resource "aws_cloudwatch_metric_alarm" "ecs_high_memory" {
  alarm_name          = "strapi-ecs-high-memory-vivek"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ECS Memory utilization"
  alarm_actions       = [aws_sns_topic.strapi_alerts.arn]

  dimensions = {
    ServiceName = aws_ecs_service.strapi_service.name
    ClusterName = aws_ecs_cluster.strapi_cluster.name
  }

  tags = {
    Name = "strapi-ecs-high-memory-vivek"
  }
}

# Variables
variable "db_name" {
  description = "Database name"
  type        = string
  default     = "mydb"
}

variable "db_user" {
  description = "Database username"
  type        = string
  default     = "myuser"
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

variable "ecr_image_url" {
  description = "ECR image URL for Strapi"
  type        = string
}

variable "alert_email" {
  description = "Email for alerts"
  type        = string
}

variable "app_keys" {
  description = "Strapi APP_KEYS"
  type        = string
  sensitive   = true
}

variable "jwt_secret" {
  description = "Jwt_Secret"
  type        = string
  sensitive   = true
}

variable "api_token_salt" {
  description = "Strapi API_TOKEN_SALT"
  type        = string
  sensitive   = true
}

variable "admin_jwt_secret" {
  description = "Strapi ADMIN_JWT_SECRET"
  type        = string
  sensitive   = true
}

variable "transfer_token_salt" {
  description = "Strapi TRANSFER_TOKEN_SALT"
  type        = string
  sensitive   = true
}

# Outputs
output "alb_dns_name" {
  description = "DNS name of the load balancer"
  value       = aws_lb.strapi_alb.dns_name
}

output "alb_test_url" {
  description = "Test URL for Green deployments (port 8080)"
  value       = "http://${aws_lb.strapi_alb.dns_name}:8080"
}

output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.strapi_postgres.endpoint
}

output "codedeploy_app_name" {
  description = "CodeDeploy application name"
  value       = aws_codedeploy_app.strapi_app.name
}

output "codedeploy_deployment_group_name" {
  description = "CodeDeploy deployment group name"
  value       = aws_codedeploy_deployment_group.strapi_deployment_group.deployment_group_name
}

output "blue_target_group_name" {
  description = "Blue target group name"
  value       = aws_lb_target_group.strapi_blue_tg.name
}

output "green_target_group_name" {
  description = "Green target group name"
  value       = aws_lb_target_group.strapi_green_tg.name
}