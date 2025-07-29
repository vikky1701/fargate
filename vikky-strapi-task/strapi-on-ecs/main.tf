provider "aws" {
  region = "us-east-2"
}

# Get Default VPC
data "aws_vpc" "default" {
  default = true
}

# Get Default Subnets (public subnets in default VPC)
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

# Get individual subnet details to check availability zones
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

# Security Group for RDS - FIXED
resource "aws_security_group" "rds_sg" {
  name        = "strapi-rds-sg-vivek"
  description = "Security group for Strapi RDS"
  vpc_id      = data.aws_vpc.default.id

  # Allow from ECS security group
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_sg.id]
  }

  # CRITICAL FIX: Allow from entire default VPC CIDR to fix pg_hba.conf issue
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]  # This covers 172.31.0.0/16
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

  # Enable Container Insights for enhanced monitoring
  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "strapi-cluster-vivek"
  }
}

# Application Load Balancer (using only 2 subnets in different AZs)
resource "aws_lb" "strapi_alb" {
  name               = "strapi-alb-vivek"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  
  # Use only the first 2 subnets to ensure different AZs
  subnets = slice(data.aws_subnets.default_public.ids, 0, 2)

  enable_deletion_protection = false

  tags = {
    Name = "strapi-alb-vivek"
  }
}

# Target Group
resource "aws_lb_target_group" "strapi_tg" {
  name        = "strapi-tg-vivek"
  port        = 1337
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 30
    interval            = 60
    path                = "/"
    matcher             = "200"
    port                = "traffic-port"
    protocol            = "HTTP"
  }

  tags = {
    Name = "strapi-tg-vivek"
  }
}

# ALB Listener
resource "aws_lb_listener" "strapi_listener" {
  load_balancer_arn = aws_lb.strapi_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.strapi_tg.arn
  }
}

# DB Subnet Group - FIXED to use default subnets
resource "aws_db_subnet_group" "strapi_db_subnet_group" {
  name       = "strapi-db-subnet-group-vivek"
  subnet_ids = data.aws_subnets.default_public.ids

  tags = {
    Name = "strapi-db-subnet-group-vivek"
  }
}

# IAM Role for ECS Task Execution - FIXED
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

# Attach the AWS managed policy for RDS enhanced monitoring
resource "aws_iam_role_policy_attachment" "rds_monitoring_policy" {
  role       = aws_iam_role.rds_monitoring_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Custom Parameter Group to configure PostgreSQL settings
resource "aws_db_parameter_group" "postgres_params" {
  family = "postgres15"
  name   = "strapi-postgres-params-vivek"

  # Enable logging for debugging
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
    value = "1000"  # Log queries taking more than 1 second
  }

  # Force SSL connections (this helps with pg_hba.conf)
  parameter {
    name  = "rds.force_ssl"
    value = "0"  # Set to 0 initially, we'll handle SSL in application
  }

  tags = {
    Name = "strapi-postgres-params-vivek"
  }
}

# RDS PostgreSQL Instance - FIXED for pg_hba.conf issues
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

  # CRITICAL: Enable SSL/TLS to fix pg_hba.conf authentication
  ca_cert_identifier = "rds-ca-rsa2048-g1"
  
  # Custom parameter group to modify pg_hba.conf behavior
  parameter_group_name = aws_db_parameter_group.postgres_params.name

  # Enable enhanced monitoring for RDS
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring_role.arn

  # Enable Performance Insights
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

# CloudWatch Log Group for ALB Access Logs
resource "aws_cloudwatch_log_group" "alb_logs" {
  name              = "/aws/loadbalancer/strapi-alb-vivek"
  retention_in_days = 7

  tags = {
    Name = "strapi-alb-logs-vivek"
  }
}

# ECS Task Definition - Updated with proper secrets and SSL handling
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

      # Add health check
      healthCheck = {
        command = ["CMD-SHELL", "curl -f http://localhost:1337/_health || exit 1"]
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
}

# ECS Service
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
    target_group_arn = aws_lb_target_group.strapi_tg.arn
    container_name   = "strapi"
    container_port   = 1337
  }

  depends_on = [
    aws_lb_listener.strapi_listener,
    aws_db_instance.strapi_postgres
  ]

  tags = {
    Name = "strapi-service-vivek"
  }
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "strapi_dashboard" {
  dashboard_name = "strapi-dashboard-vivek"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ServiceName", aws_ecs_service.strapi_service.name, "ClusterName", aws_ecs_cluster.strapi_cluster.name],
            [".", "MemoryUtilization", ".", ".", ".", "."],
          ]
          view    = "timeSeries"
          stacked = false
          region  = "us-east-2"
          title   = "ECS CPU and Memory Utilization"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/ECS", "RunningTaskCount", "ServiceName", aws_ecs_service.strapi_service.name, "ClusterName", aws_ecs_cluster.strapi_cluster.name],
          ]
          view    = "timeSeries"
          stacked = false
          region  = "us-east-2"
          title   = "ECS Running Task Count"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.strapi_alb.arn_suffix],
            [".", "RequestCount", ".", "."],
          ]
          view    = "timeSeries"
          stacked = false
          region  = "us-east-2"
          title   = "ALB Response Time and Request Count"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 18
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", aws_db_instance.strapi_postgres.id],
            [".", "DatabaseConnections", ".", "."],
          ]
          view    = "timeSeries"
          stacked = false
          region  = "us-east-2"
          title   = "RDS CPU and Database Connections"
          period  = 300
        }
      }
    ]
  })
}

# CloudWatch Alarms

# ECS High CPU Alarm
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

# ECS High Memory Alarm
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

# ECS Task Count Alarm
resource "aws_cloudwatch_metric_alarm" "ecs_task_count" {
  alarm_name          = "strapi-ecs-task-count-vivek"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "RunningTaskCount"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "This metric monitors ECS running task count"
  alarm_actions       = [aws_sns_topic.strapi_alerts.arn]

  dimensions = {
    ServiceName = aws_ecs_service.strapi_service.name
    ClusterName = aws_ecs_cluster.strapi_cluster.name
  }

  tags = {
    Name = "strapi-ecs-task-count-vivek"
  }
}

# ALB Target Health Alarm
resource "aws_cloudwatch_metric_alarm" "alb_target_health" {
  alarm_name          = "strapi-alb-unhealthy-targets-vivek"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "This metric monitors ALB healthy target count"
  alarm_actions       = [aws_sns_topic.strapi_alerts.arn]

  dimensions = {
    TargetGroup  = aws_lb_target_group.strapi_tg.arn_suffix
    LoadBalancer = aws_lb.strapi_alb.arn_suffix
  }

  tags = {
    Name = "strapi-alb-unhealthy-targets-vivek"
  }
}

# ALB Response Time Alarm
resource "aws_cloudwatch_metric_alarm" "alb_response_time" {
  alarm_name          = "strapi-alb-high-response-time-vivek"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Average"
  threshold           = "5"
  alarm_description   = "This metric monitors ALB response time"
  alarm_actions       = [aws_sns_topic.strapi_alerts.arn]

  dimensions = {
    LoadBalancer = aws_lb.strapi_alb.arn_suffix
  }

  tags = {
    Name = "strapi-alb-high-response-time-vivek"
  }
}

# RDS High CPU Alarm
resource "aws_cloudwatch_metric_alarm" "rds_high_cpu" {
  alarm_name          = "strapi-rds-high-cpu-vivek"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors RDS CPU utilization"
  alarm_actions       = [aws_sns_topic.strapi_alerts.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.strapi_postgres.id
  }

  tags = {
    Name = "strapi-rds-high-cpu-vivek"
  }
}

# RDS Database Connections Alarm
resource "aws_cloudwatch_metric_alarm" "rds_connections" {
  alarm_name          = "strapi-rds-high-connections-vivek"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "15"
  alarm_description   = "This metric monitors RDS database connections"
  alarm_actions       = [aws_sns_topic.strapi_alerts.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.strapi_postgres.id
  }

  tags = {
    Name = "strapi-rds-high-connections-vivek"
  }
}

# SNS Topic for Alerts
resource "aws_sns_topic" "strapi_alerts" {
  name = "strapi-alerts-vivek"

  tags = {
    Name = "strapi-alerts-vivek"
  }
}

# SNS Topic Subscription (Email)
resource "aws_sns_topic_subscription" "email_alerts" {
  topic_arn = aws_sns_topic.strapi_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Enhanced CloudWatch Log Metric Filters for better error detection
resource "aws_cloudwatch_log_metric_filter" "error_count" {
  name           = "strapi-error-count-vivek"
  log_group_name = aws_cloudwatch_log_group.strapi_logs.name
  
  # Enhanced pattern to catch various error types
  pattern = "?ERROR ?error ?Error ?failed ?Failed ?exception ?Exception ?FATAL ?Fatal ?\"no pg_hba.conf entry\""

  metric_transformation {
    name      = "ErrorCount"
    namespace = "Strapi/Application"
    value     = "1"
  }
}

# Database Connection Error Metric Filter
resource "aws_cloudwatch_log_metric_filter" "db_connection_errors" {
  name           = "strapi-db-errors-vivek"
  log_group_name = aws_cloudwatch_log_group.strapi_logs.name
  
  pattern = "?\"FATAL\" ?\"no pg_hba.conf entry\" ?\"password authentication failed\" ?\"database does not exist\" ?\"connection refused\" ?\"timeout expired\""
  
  metric_transformation {
    name      = "DatabaseErrors"
    namespace = "Strapi/Database"
    value     = "1"
  }
}

# Application Startup/Shutdown Events
resource "aws_cloudwatch_log_metric_filter" "startup_events" {
  name           = "strapi-startup-vivek"
  log_group_name = aws_cloudwatch_log_group.strapi_logs.name
  
  pattern = "?\"Server started\" ?\"Shutting down Strapi\" ?\"Starting\" ?\"started\""
  
  metric_transformation {
    name      = "StartupEvents"
    namespace = "Strapi/Application"
    value     = "1"
  }
}

# Alarm for Application Errors
resource "aws_cloudwatch_metric_alarm" "application_errors" {
  alarm_name          = "strapi-application-errors-vivek"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ErrorCount"
  namespace           = "Strapi/Application"
  period              = "300"
  statistic           = "Sum"
  threshold           = "3"
  alarm_description   = "This metric monitors application errors in logs"
  alarm_actions       = [aws_sns_topic.strapi_alerts.arn]
  treat_missing_data  = "notBreaching"

  tags = {
    Name = "strapi-application-errors-vivek"
  }
}

# Database Connection Errors Alarm
resource "aws_cloudwatch_metric_alarm" "database_errors" {
  alarm_name          = "strapi-database-errors-vivek"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "DatabaseErrors"
  namespace           = "Strapi/Database"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors database connection errors"
  alarm_actions       = [aws_sns_topic.strapi_alerts.arn]
  treat_missing_data  = "notBreaching"
  
  tags = {
    Name = "strapi-database-errors-vivek"
  }
}

# Task Health Check - No logs for extended period
resource "aws_cloudwatch_metric_alarm" "no_logs_alarm" {
  alarm_name          = "strapi-no-logs-vivek"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "IncomingLogEvents"
  namespace           = "AWS/Logs"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "Alert when no logs are being generated (possible application crash)"
  alarm_actions       = [aws_sns_topic.strapi_alerts.arn]
  treat_missing_data  = "breaching"
  
  dimensions = {
    LogGroupName = aws_cloudwatch_log_group.strapi_logs.name
  }
  
  tags = {
    Name = "strapi-no-logs-vivek"
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

# Add Strapi secrets as variables
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

output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.strapi_postgres.endpoint
}

output "default_vpc_id" {
  description = "Default VPC ID"
  value       = data.aws_vpc.default.id
}

output "default_vpc_cidr" {
  description = "Default VPC CIDR block"
  value       = data.aws_vpc.default.cidr_block
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = aws_sns_topic.strapi_alerts.arn
}