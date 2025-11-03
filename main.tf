provider "aws" {
  region = "us-east-1"
}
# --- S3 bucket for CodePipeline artifacts ---
resource "aws_s3_bucket" "artifact_bucket" {
  bucket_prefix = "tf-devops-artifacts-"
  force_destroy = true
}

# --- IAM Role for EC2 (CodeDeploy Agent Access) ---
resource "aws_iam_role" "ec2_role" {
  name = "tf-ec2-codedeploy-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_role_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforAWSCodeDeploy"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "tf-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# --- EC2 Instance for Deployment ---
resource "aws_instance" "app_server" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t2.micro"
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  vpc_security_group_ids = [aws_security_group.app_sg.id]
  user_data              = file("user_data.sh")

  tags = { Name = "tf-app-server" }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_security_group" "app_sg" {
  name        = "tf-app-sg"
  description = "Allow HTTP"
  ingress {
    from_port   = 8080
    to_port     = 8080
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

# --- CodeCommit Repo ---
# resource "aws_codecommit_repository" "repo" {
#   repository_name = "tf-simple-node-app"
#   description     = "Terraform DevOps Node.js app"
# }
data "aws_secretsmanager_secret" "github_token" {
  name = "github-token"
}

data "aws_secretsmanager_secret_version" "github_token" {
  secret_id = data.aws_secretsmanager_secret.github_token.id
}

# --- IAM Role for CodeBuild ---
resource "aws_iam_role" "codebuild_role" {
  name = "tf-codebuild-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "codebuild_policy" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeBuildDeveloperAccess"
}

# --- CodeBuild Project ---
resource "aws_codebuild_project" "build" {
  name         = "tf-nodejs-build"
  service_role = aws_iam_role.codebuild_role.arn
  artifacts {
    type = "CODEPIPELINE"
  }
  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    privileged_mode             = false
  }
  source {
    type      = "CODEPIPELINE"
    buildspec = file("buildspec.yml")
  }
}

# --- CodeDeploy Application ---
resource "aws_codedeploy_app" "app" {
  name = "tf-node-app"
  compute_platform = "Server"
}

# --- CodeDeploy IAM Role ---
resource "aws_iam_role" "codedeploy_role" {
  name = "tf-codedeploy-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "codedeploy.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "codedeploy_policy" {
  role       = aws_iam_role.codedeploy_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
}

# --- CodeDeploy Deployment Group ---
resource "aws_codedeploy_deployment_group" "dg" {
  app_name              = aws_codedeploy_app.app.name
  deployment_group_name = "tf-deploy-group"
  service_role_arn      = aws_iam_role.codedeploy_role.arn

  ec2_tag_filter {
    key   = "Name"
    value = "tf-app-server"
    type  = "KEY_AND_VALUE"
  }

  deployment_style {
    deployment_type   = "IN_PLACE"
    deployment_option = "WITHOUT_TRAFFIC_CONTROL"
  }
}

# --- IAM Role for CodePipeline ---
resource "aws_iam_role" "codepipeline_role" {
  name = "tf-codepipeline-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "codepipeline.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "codepipeline_policy" {
  role       = aws_iam_role.codepipeline_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodePipeline_FullAccess"
}

# --- CodePipeline ---
resource "aws_codepipeline" "pipeline" {
  name     = "tf-devops-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn
  artifact_store {
    location = aws_s3_bucket.artifact_bucket.bucket
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "ThirdParty"
      provider         = "GitHub"
      version          = "1"
      output_artifacts = ["source_output"]
      configuration = {
        Owner                = "myktiwari"
        Repo                 = "devops-cicd-sample-lab"
        Branch               = "main"
        OAuthToken           = data.aws_secretsmanager_secret_version.github_token.secret_string
      }
    }
  }

  stage {
    name = "Build"
    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      configuration = {
        ProjectName = aws_codebuild_project.build.name
      }
    }
  }

  stage {
    name = "Deploy"
    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeploy"
      version         = "1"
      input_artifacts = ["build_output"]
      configuration = {
        ApplicationName     = aws_codedeploy_app.app.name
        DeploymentGroupName = aws_codedeploy_deployment_group.dg.deployment_group_name
      }
    }
  }
}
