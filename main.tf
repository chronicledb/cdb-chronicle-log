provider "aws" {
  region = var.region
}

# ---------------------------------------------------------------------------
# Backend
# ---------------------------------------------------------------------------

terraform {
  backend "s3" {}
}

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------

variable "region" {
  description = "AWS region to deploy into"
  type        = string
}

variable "ami" {
  description = "AMI for the EC2 instance"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

# ---------------------------------------------------------------------------
# Shared infrastructure (VPC, subnet) from cdb-shared-infra
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

data "terraform_remote_state" "shared_infra" {
  backend = "s3"

  config = {
    bucket = "cdb-tf-state-${data.aws_caller_identity.current.account_id}"
    key    = "shared-infra/terraform.tfstate"
    region = var.region
  }
}

# ---------------------------------------------------------------------------
# Security Group
# ---------------------------------------------------------------------------

resource "aws_security_group" "cdb_chronicle_log_sg" {
  name        = "cdb-chronicle-log-sg"
  description = "Allow Kafka traffic within VPC"
  vpc_id      = data.terraform_remote_state.shared_infra.outputs.cdb_vpc_id

  ingress {
    description = "Kafka broker"
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = [data.terraform_remote_state.shared_infra.outputs.cdb_vpc_cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "cdb-chronicle-log-sg"
  }
}

# ---------------------------------------------------------------------------
# EC2 Instance
# ---------------------------------------------------------------------------

resource "aws_instance" "cdb_chronicle_log" {
  ami                         = var.ami
  instance_type               = var.instance_type
  subnet_id                   = data.terraform_remote_state.shared_infra.outputs.cdb_public_subnet_id
  vpc_security_group_ids      = [aws_security_group.cdb_chronicle_log_sg.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.cdb_chronicle_log.name

  user_data = <<-EOF
    #!/bin/bash
    set -e

    # Install Docker
    apt-get update -y
    apt-get install -y docker.io
    systemctl enable docker
    systemctl start docker

    # Install Docker Compose
    mkdir -p /usr/local/lib/docker/cli-plugins
    curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
      -o /usr/local/lib/docker/cli-plugins/docker-compose
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

    # Write docker-compose.yml
    echo "${base64encode(file("docker-compose.yml"))}" | base64 -d > /home/ubuntu/docker-compose.template.yml

    # Substitute private IP
    TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
      -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    export EC2_PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
      http://169.254.169.254/latest/meta-data/local-ipv4)
    envsubst '$${EC2_PRIVATE_IP}' < /home/ubuntu/docker-compose.template.yml > /home/ubuntu/docker-compose.yml
    chown ubuntu:ubuntu /home/ubuntu/docker-compose.yml

    # Start Kafka
    cd /home/ubuntu && docker compose up -d
  EOF

  tags = {
    Name = "cdb-chronicle-log"
  }
}

resource "aws_iam_role" "cdb_chronicle_log" {
  name = "cdb-chronicle-log-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cdb_chronicle_log_ssm" {
  role       = aws_iam_role.cdb_chronicle_log.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "cdb_chronicle_log" {
  name = "cdb-chronicle-log-profile"
  role = aws_iam_role.cdb_chronicle_log.name
}

# ---------------------------------------------------------------------------
# Outputs (written into remote state, readable by other repos)
# ---------------------------------------------------------------------------

output "cdb_chronicle_log_private_ip" {
  value = aws_instance.cdb_chronicle_log.private_ip
}

output "cdb_chronicle_log_kafka_bootstrap_server" {
  value = "${aws_instance.cdb_chronicle_log.private_ip}:9092"
}