# 1. The VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-${var.environment}-vpc"
  }
}

# 2a. The Public Subnet 1
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.100.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-${var.environment}-public-subnet-1"
  }
}

# 2b. The Public Subnet 2
resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.100.2.0/24" # Note the 2.0
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet-2"
  }
}

# 3. The Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-${var.environment}-igw"
  }
}

# 4. The Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-public-rt"
  }
}

#5a. Route Table Association
resource "aws_route_table_association" "public_rt_assoc_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public_rt.id
}

#5b. Route Table Association for the second public subnet
resource "aws_route_table_association" "public_rt_assoc_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public_rt.id
}


#7. Security Group for the application Host. 
resource "aws_security_group" "app_sg" {
  name        = "${var.project_name}-app-sg"
  description = "Allow inbound HTTP traffic on port 8000"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "FastAPI App Port"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id] # Allow traffic from ALB
  }

  egress {
    description = "Allow all outbound traffic for package updates"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-app-sg"
  }
}

########################################################
#8. EC2 Instance for the application
# resource "aws_instance" "app_server" {
#   ami                         = data.aws_ami.ubuntu.id
#   instance_type               = "t3.micro"
#   subnet_id                   = aws_subnet.public_1.id
#   vpc_security_group_ids      = [aws_security_group.app_sg.id]
#   associate_public_ip_address = true

#   #Bootstrap script to install Docker and run the test service
#   user_data = file("${path.module}/userdata.sh")

#   tags = {
#     Name = "${var.project_name}-app-server"
#   }
# }
########################################################

# 9. ALB Security Group. 
resource "aws_security_group" "alb_sg" {
  name        = "${var.project_name}-alb-sg"
  description = "Allow inbound HTTP traffic on port 80 for ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


#10. Application Load Balancer
resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  tags = {
    Name = "${var.project_name}-alb"
  }
}

#11. Target Group for the ALB
resource "aws_lb_target_group" "app_tg" {
  name        = "${var.project_name}-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/health"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200-299"
  }

  tags = {
    Name = "${var.project_name}-tg"
  }
}

#12. ALB Listener
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}


#15. Elastic Container Registry (ECR)
resource "aws_ecr_repository" "app_repo" {
  name                 = "${var.project_name}-repo"
  force_delete         = true # Force delete the repository when the Terraform state is destroyed
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.project_name}-repo"
  }
}

# ========================================
# ECS FARGATE RESOURCES
# ========================================

# 16. ECS Cluster — logical grouping for our services
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  # Enable Container Insights for monitoring (CPU, memory, network metrics)
  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "${var.project_name}-cluster"
  }
}

# 17. CloudWatch Log Group — centralized container logs
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-logs"
  }
}

# 18. ECS Task Execution Role — lets the ECS AGENT pull images and write logs
resource "aws_iam_role" "ecs_execution_role" {
  name = "${var.project_name}-ecs-execution-role"

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
    Name = "${var.project_name}-ecs-execution-role"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_execution_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}


# 19. ECS Task Definition — the container blueprint (replaces userdata.sh + docker run)
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project_name}-app"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "${var.project_name}-container"
      image     = "${aws_ecr_repository.app_repo.repository_url}:latest"
      essential = true

      portMappings = [
        {
          containerPort = 8000
          protocol      = "tcp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = {
    Name = "${var.project_name}-task-definition"
  }
}


# 20. ECS Service — maintains desired tasks, connects to ALB, handles deployments
resource "aws_ecs_service" "app" {
  name            = "${var.project_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  # Rolling deployment strategy — zero downtime
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = [aws_subnet.public_1.id, aws_subnet.public_2.id]
    security_groups  = [aws_security_group.app_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app_tg.arn
    container_name   = "${var.project_name}-container"
    container_port   = 8000
  }

  # Prevent Terraform from reverting image changes made by CI/CD pipeline
  lifecycle {
    ignore_changes = [task_definition]
  }

  tags = {
    Name = "${var.project_name}-service"
  }
}