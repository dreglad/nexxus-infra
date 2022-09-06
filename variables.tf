variable "domain" {
  description = "Domain name to use for the application. It requires setting nameservers to Route53 at registrar."
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "Dev"
}

variable "aws_region" {
  description = "AWS region to deploy the application"
  type        = string
  default     = "us-east-1"
}

variable "database_instance_class" {
  description = "AWS profile to use for DB instance"
  type        = string
  default     = "db.t3.micro"
}

variable "backend_resources" {
  type        = map(string)
  description = "CPU and Memory to allocate to the backend application container"
  default = {
    "cpu"    = "256"
    "memory" = "512"
  }
}

variable "backend_desired_count" {
  description = "Number of backend container replicas to run"
  type        = number
  default     = 1
}

variable "database_storage" {
  type = map(string)
  default = {
    "allocated"     = "20"
    "max_allocated" = "60"
  }
}
