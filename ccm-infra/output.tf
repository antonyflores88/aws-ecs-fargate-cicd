# output "instance_public_ip" {
#   description = "Public IP address of the EC2 node"
#   value       = aws_instance.app_server.public_ip
# }

# output "health_check_url" {
#   description = "Target URL for the FastAPI health check"
#   value       = "http://${aws_instance.app_server.public_ip}:8000/health"
# }

output "alb_dns_name" {
  value = "http://${aws_lb.main.dns_name}"
}


output "ecr_repository_url" {
  description = "The URL of the ECR repository"
  value       = aws_ecr_repository.app_repo.repository_url
}