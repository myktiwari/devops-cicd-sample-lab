output "codecommit_repo_clone_url" {
  value = aws_codecommit_repository.repo.clone_url_http
}

output "ec2_public_ip" {
  value = aws_instance.app_server.public_ip
}
