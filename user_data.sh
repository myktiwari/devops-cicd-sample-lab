#!/bin/bash
yum update -y
yum install -y ruby wget
REGION="us-east-1"
cd /home/ec2-user
wget https://aws-codedeploy-${REGION}.s3.${REGION}.amazonaws.com/latest/install
chmod +x install
./install auto
service codedeploy-agent start
