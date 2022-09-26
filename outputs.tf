output "backend_registry_url" {
  value = aws_ecr_repository.backend.repository_url
}

output "backend_db_url" {
  value     = local.backend_postgres_url
  sensitive = true
}
