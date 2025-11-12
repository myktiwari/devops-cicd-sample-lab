provider "aws" {
  region = "us-east-1"
}

# --- S3 bucket for CodePipeline artifacts ---
resource "aws_s3_bucket" "artifact_bucket" {
  bucket_prefix = "tf-devops-artifacts-"
  force_destroy = true
}

# --- IAM Role for EC2 (CodeDeploy + SSM Access) ---
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

# Attach policies for EC2 instance (CodeDeploy + SSM)
resource "aws_iam_role_policy_attachment" "ec2_codedeploy_access" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforAWSCodeDeploy"
}

resource "aws_iam_role_policy_attachment" "ec2_ssm_full_access" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMFullAccess"
}

resource "aws_iam_role_policy_attachment" "ec2_ssm_managed_core" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# --- EC2 Instance Profile ---
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "tf-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# --- Security Group ---
resource "aws_security_group" "app_sg" {
  name        = "tf-app-sg"
  description = "Allow HTTP and SSH access"
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
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

# --- Amazon Linux 2 AMI ---
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# --- EC2 Instance for Deployment ---
resource "aws_instance" "app_server" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3a.micro"
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  vpc_security_group_ids = [aws_security_group.app_sg.id]
  user_data              = file("user_data.sh")

  tags = {
    Name = "tf-app-server"
  }
}

# --- Wait for EC2 to initialize ---
resource "null_resource" "wait_for_ec2_ready" {
  depends_on = [aws_instance.app_server]

  provisioner "local-exec" {
    command = "sleep 90"
  }
}

# --- CodeDeploy Application ---
resource "aws_codedeploy_app" "app" {
  name              = "tf-node-app"
  compute_platform  = "Server"
}

# --- IAM Role for CodeDeploy ---
resource "aws_iam_role" "codedeploy_role" {
  name = "tf-codedeploy-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [ {
      Effect = "Allow"
      Principal = { Service = "codedeploy.amazonaws.com" }
      Action = "sts:AssumeRole"
    } ]
  })
}

resource "aws_iam_role_policy_attachment" "codedeploy_policy" {
  role       = aws_iam_role.codedeploy_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
}

# --- CodeDeploy Deployment Group ---
resource "aws_codedeploy_deployment_group" "dg" {
  depends_on           = [null_resource.wait_for_ec2_ready]
  app_name             = aws_codedeploy_app.app.name
  deployment_group_name = "tf-deploy-group"
  service_role_arn     = aws_iam_role.codedeploy_role.arn

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

resource "aws_iam_role_policy" "codepipeline_codebuild_access" {
  name = "tf-codepipeline-codebuild-access"
  role = aws_iam_role.codepipeline_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild"
        ]
        Resource = "arn:aws:codebuild:us-east-1:${data.aws_caller_identity.current.account_id}:project/tf-nodejs-build"
      }
    ]
  })
}

# --- Give CodePipeline access to S3 artifact bucket ---
resource "aws_iam_role_policy" "codepipeline_s3_access" {
  name = "tf-codepipeline-s3-access"
  role = aws_iam_role.codepipeline_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:GetBucketVersioning"
        ]
        Resource = [
          "${aws_s3_bucket.artifact_bucket.arn}",
          "${aws_s3_bucket.artifact_bucket.arn}/*"
        ]
      }
    ]
  })
}


# --- CodeBuild Role ---
resource "aws_iam_role" "codebuild_role" {
  name = "tf-codebuild-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [ {
      Effect = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action = "sts:AssumeRole"
    } ]
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
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:7.0"
    type         = "LINUX_CONTAINER"
  }
  source {
    type      = "CODEPIPELINE"
    buildspec = file("buildspec.yml")
  }
}

# --- CodePipeline Role ---
resource "aws_iam_role" "codepipeline_role" {
  name = "tf-codepipeline-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [ {
      Effect = "Allow"
      Principal = { Service = "codepipeline.amazonaws.com" }
      Action = "sts:AssumeRole"
    } ]
  })
}

resource "aws_iam_role_policy_attachment" "codepipeline_policy" {
  role       = aws_iam_role.codepipeline_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodePipeline_FullAccess"
}

# --- Secrets Manager (GitHub Token) ---
data "aws_secretsmanager_secret" "github_token" {
  name = "github-token"
}

data "aws_secretsmanager_secret_version" "github_token" {
  secret_id = data.aws_secretsmanager_secret.github_token.id
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
        Owner      = "myktiwari"
        Repo       = "devops-cicd-sample-lab"
        Branch     = "main"
        OAuthToken = data.aws_secretsmanager_secret_version.github_token.secret_string
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

# --- Allow CodeBuild to write to CloudWatch Logs ---
resource "aws_iam_role_policy" "codebuild_logs_access" {
  name = "tf-codebuild-logs-access"
  role = aws_iam_role.codebuild_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:logs:us-east-1:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "codebuild_s3_access" {
  name = "tf-codebuild-s3-access"
  role = aws_iam_role.codebuild_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:GetBucketVersioning"
        ]
        Resource = [
          "${aws_s3_bucket.artifact_bucket.arn}",
          "${aws_s3_bucket.artifact_bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "codepipeline_codedeploy_access" {
  name = "tf-codepipeline-codedeploy-access"
  role = aws_iam_role.codepipeline_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "codedeploy:CreateDeployment",
          "codedeploy:GetApplication",
          "codedeploy:GetDeployment",
          "codedeploy:GetDeploymentConfig",
          "codedeploy:RegisterApplicationRevision",
          "codedeploy:GetDeploymentGroup",
          "codedeploy:GetApplicationRevision"
        ]
        Resource = "*"
      }
    ]
  })
}

# --- Data for Account ID ---
data "aws_caller_identity" "current" {}
