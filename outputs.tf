output "github_repo_clone_url" {
  description = "GitHub repo clone URL for CodePipeline source"
  value       = "https://github.com/${var.github_owner}/${var.github_repo}.git"
}

output "ec2_public_ip" {
  value = aws_instance.app_server.public_ip
}
