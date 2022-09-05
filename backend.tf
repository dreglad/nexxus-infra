# PostgreSQL database instance
resource "aws_db_instance" "backend" {
  # Engine
  engine         = "postgres"
  engine_version = "13"

  # Instance type
  instance_class = var.database_instance_class

  # Allocated storage
  allocated_storage     = var.database_storage.allocated
  max_allocated_storage = var.database_storage.max_allocated

  # DB Access
  db_name  = "postgres"
  username = "postgres"
  password = "postgres"

  skip_final_snapshot = true
}

// Fargate task definition 
resource "aws_ecs_task_definition" "backend" {
  family = "nexxus_backend"

  // Fargate is a type of ECS that requires awsvpc network_mode
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"

  // Valid sizes are shown here: https://aws.amazon.com/fargate/pricing/
  memory = var.backend_resources.memory
  cpu    = var.backend_resources.cpu

  // Fargate requires task definitions to have an execution role ARN to support ECR images
  execution_role_arn = aws_iam_role.ecs_role.arn

  // Container definition
  container_definitions = <<EOT
[
    {
        "name": "nexxus_backend",
        "image": "nginx:latest",
        "memory": ${var.backend_resources.memory},
        "essential": true,
        "portMappings": [
            {
                "containerPort": 80,
                "hostPort": 80
            }
        ]
    }
]
EOT
}

resource "aws_ecs_cluster" "backend" {
  name = "backend_cluster"
}

resource "aws_ecs_service" "backend" {
  name = "backend_service"

  cluster         = aws_ecs_cluster.backend.id
  task_definition = aws_ecs_task_definition.backend.arn

  launch_type   = "FARGATE"
  desired_count = var.backend_desired_count

  network_configuration {
    subnets          = ["${aws_subnet.public_a.id}", "${aws_subnet.public_b.id}"]
    security_groups  = ["${aws_security_group.backend.id}"]
    assign_public_ip = true
  }
}

resource "aws_acm_certificate" "backend" {
  domain_name       = "api.${var.domain}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}
