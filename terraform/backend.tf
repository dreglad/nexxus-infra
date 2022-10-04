resource "aws_ecs_task_definition" "backend" {
  family = "backend"

  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"

  memory = var.backend_resources.memory
  cpu    = var.backend_resources.cpu

  execution_role_arn = aws_iam_role.ecs_role.arn
  task_role_arn      = aws_iam_role.ecs_role.arn
  depends_on         = [aws_iam_role.ecs_role]

  container_definitions = jsonencode([{
    name      = "backend"
    image     = aws_ecr_repository.backend.repository_url
    essential = true
    linuxParameters = {
      initProcessEnabled = true
    }
    environment = [
      {
        name  = "DATABASE_URL"
        value = local.backend_postgres_url
      },
      {
        name  = "NODE_ENV"
        value = "development"
      },
      {
        name  = "PORT"
        value = "80"
      },
      {
        name  = "JWT_SECRET"
        value = random_password.backend_jwt_secret.result
      },
      {
        name  = "SMTP_HOST"
        value = "email-smtp.${var.aws_region}.amazonaws.com"
      },
      {
        name  = "SMTP_PORT"
        value = "587"
      },
      {
        name  = "SMTP_USERNAME"
        value = aws_iam_access_key.smtp_user.id
      },
      {
        name  = "SMTP_PASSWORD"
        value = aws_iam_access_key.smtp_user.ses_smtp_password_v4
      },
      {
        name  = "EMAIL_FROM"
        value = "no-repply@${local.email_domain}"
      },
      {
        name  = "S3_BUCKET"
        value = aws_s3_bucket.data.bucket
      },
      {
        name  = "S3_REGION"
        value = var.aws_region
      },
      {
        name  = "S3_ACCESS_KEY_ID"
        value = aws_iam_access_key.backend_data.id
      },
      {
        name  = "S3_SECRET_ACCESS_KEY"
        value = aws_iam_access_key.backend_data.secret
      },
      {
        name  = "URL_APP"
        value = "https://${local.frontend_domain}"
      }
    ]
    portMappings = [{
      containerPort = 80
      hostPort      = 80
    }],
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.backend.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "backend"
      }
    }
  }])
}

resource "random_password" "backend_jwt_secret" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_cloudwatch_log_group" "backend" {
  name = "backend"
}

resource "aws_ecs_cluster" "backend" {
  name = "backend"
}

resource "aws_ecs_service" "backend" {
  name = "backend"

  cluster         = aws_ecs_cluster.backend.id
  task_definition = aws_ecs_task_definition.backend.arn

  launch_type   = "FARGATE"
  desired_count = var.backend_desired_count

  enable_execute_command = true

  network_configuration {
    subnets          = module.vpc.public_subnets
    security_groups  = [aws_security_group.backend_db.id, aws_security_group.backend.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_alb_target_group.backend.arn
    container_name   = "backend"
    container_port   = 80
  }
}

resource "aws_lb" "backend" {
  name = "backend"

  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.backend.id]
  subnets            = module.vpc.public_subnets

  enable_deletion_protection = false
}

resource "aws_alb_target_group" "backend" {
  name        = "backend"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    path = "/healthz"
  }
}

resource "aws_alb_listener" "http" {
  load_balancer_arn = aws_lb.backend.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = 443
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_alb_listener" "https" {
  load_balancer_arn = aws_lb.backend.arn
  port              = 443
  protocol          = "HTTPS"

  ssl_policy      = "ELBSecurityPolicy-2016-08"
  certificate_arn = aws_acm_certificate.backend.arn

  default_action {
    target_group_arn = aws_alb_target_group.backend.id
    type             = "forward"
  }
}

resource "aws_acm_certificate" "backend" {
  domain_name       = local.backend_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "backend" {
  name        = "backend"
  description = "Allow TLS inbound traffic on port 80 (http)"

  vpc_id                 = module.vpc.vpc_id
  revoke_rules_on_delete = true

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
}

resource "aws_route53_record" "api" {
  zone_id = aws_route53_zone.nexxus.zone_id

  name = local.backend_domain
  type = "A"

  alias {
    zone_id                = aws_lb.backend.zone_id
    name                   = aws_lb.backend.dns_name
    evaluate_target_health = false
  }
}

# DNS Records for the SSL certificate validation
resource "aws_route53_record" "backend_validation" {
  for_each = {
    for dvo in aws_acm_certificate.backend.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id = aws_route53_zone.nexxus.zone_id

  allow_overwrite = true
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.record]
}

# SSL certificate validation
resource "aws_acm_certificate_validation" "backend" {
  certificate_arn         = aws_acm_certificate.backend.arn
  validation_record_fqdns = [for record in aws_route53_record.backend_validation : record.fqdn]
}

# Create IAM role for ECS task execution
resource "aws_iam_role" "ecs_role" {
  name = "role_ecs_tasks"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "ecs_execute_role" {
  name = "ecs_execute_role"
  role = aws_iam_role.ecs_role.name

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel"
    ],
    "Resource": "*"
  }]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ecs_policy_attachment" {
  role = aws_iam_role.ecs_role.name

  # This policy adds logging + ECR permissions
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecr_repository" "backend" {
  name                 = "nexxus-backend"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository_policy" "backend" {
  repository = aws_ecr_repository.backend.name

  policy = <<EOF
  {
    "Version": "2008-10-17",
    "Statement": [
      {
        "Sid": "ECR Access",
        "Effect": "Allow",
        "Principal": "*",
        "Action": [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:GetDownloadUrlForLayer",
          "ecr:GetLifecyclePolicy",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart"
        ]
      }
    ]
  }
  EOF
}

output "backend_registry_url" {
  value = aws_ecr_repository.backend.repository_url
}

resource "aws_s3_bucket" "data" {
  bucket = "nexxus-data-${var.environment}"
}

resource "aws_s3_bucket_policy" "data" {
  bucket = aws_s3_bucket.data.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource = [
          aws_s3_bucket.data.arn,
          "${aws_s3_bucket.data.arn}/*",
        ]
      },
    ]
  })
}

resource "aws_s3_bucket_acl" "data" {
  bucket = aws_s3_bucket.data.id
  acl    = "public-read"
}

data "aws_iam_policy_document" "backend_data" {
  statement {
    effect = "Allow"
    actions = [
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:PutObject",
      "s3:PutObjectAcl"
    ]
    resources = ["${aws_s3_bucket.data.arn}/*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.data.arn]
  }
}

resource "aws_iam_user" "backend_data" {
  name = "backend-data-user"
}

resource "aws_iam_access_key" "backend_data" {
  user = aws_iam_user.backend_data.name
}

resource "aws_iam_policy" "backend_data" {
  name        = "backend-data-policy"
  description = "Allows operations on the backend data bucket"
  policy      = data.aws_iam_policy_document.backend_data.json
}

resource "aws_iam_user_policy_attachment" "backend_data" {
  user       = aws_iam_user.backend_data.name
  policy_arn = aws_iam_policy.backend_data.arn
}

output "data_access_key_id" {
  value = aws_iam_access_key.backend_data.id
}

output "data_access_key_secret" {
  value     = aws_iam_access_key.backend_data.secret
  sensitive = true
}
