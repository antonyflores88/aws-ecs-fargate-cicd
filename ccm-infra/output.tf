output "alb_dns_name" {
  description = "URL to access the application via the load balancer"
  value       = "http://${aws_lb.main.dns_name}"
}

output "ecr_repository_url" {
  description = "The URL of the ECR repository for pushing Docker images"
  value       = aws_ecr_repository.app_repo.repository_url
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "Name of the ECS service (used by CI/CD for deployments)"
  value       = aws_ecs_service.app.name
}