#!/bin/bash
set -ex

# AL2023 uses dnf instead of apt
dnf update -y
dnf install -y docker

systemctl start docker
systemctl enable docker

# AWS CLI is already installed, go straight to authentication
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 387761228848.dkr.ecr.us-east-1.amazonaws.com

# Pull and run the immutable image
docker run -d \
  --name ccm-app \
  -p 8000:8000 \
  --restart always \
  387761228848.dkr.ecr.us-east-1.amazonaws.com/ccm-repo:v1