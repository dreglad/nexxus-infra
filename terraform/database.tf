resource "aws_db_instance" "backend" {
  identifier = "nexxus-backend-${var.environment}"

  # Engine
  engine               = "postgres"
  engine_version       = "14"
  parameter_group_name = aws_db_parameter_group.backend.name

  # Resources
  instance_class        = var.database_instance_class
  allocated_storage     = var.database_storage.allocated
  max_allocated_storage = var.database_storage.max_allocated

  # DB Access
  db_name  = "postgres"
  username = "postgres"
  password = random_password.database_password.result

  # Network
  publicly_accessible    = true
  db_subnet_group_name   = aws_db_subnet_group.backend_db.name
  vpc_security_group_ids = [aws_security_group.backend_db.id]

  # Backup
  backup_retention_period = 30
  backup_window           = "02:01-03:00"

  # Termination
  skip_final_snapshot       = false
  final_snapshot_identifier = "nexxus-backend-${var.environment}-final-snapshot"
  delete_automated_backups  = false

  apply_immediately = true
}

resource "aws_db_subnet_group" "backend_db" {
  name = "nexxus-backend-db-${var.environment}"

  subnet_ids = module.vpc.public_subnets
}

resource "aws_security_group" "backend_db" {
  name = "nexxus-backend-db-${var.environment}"

  vpc_id = module.vpc.vpc_id

  revoke_rules_on_delete = false

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_parameter_group" "backend" {
  name = "nexxus-backend-db-${var.environment}"

  family = "postgres14"

  parameter {
    name  = "log_connections"
    value = "1"
  }
}

resource "random_password" "database_password" {
  length  = 16
  special = false
}

locals {
  backend_postgres_url = "postgres://${aws_db_instance.backend.username}:${aws_db_instance.backend.password}@${aws_db_instance.backend.endpoint}/${aws_db_instance.backend.db_name}"
}

output "backend_db_url" {
  value     = local.backend_postgres_url
  sensitive = true
}
