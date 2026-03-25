provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

# ---------------------------------------------------------------------------
# Look up the default VPC and one of its subnets automatically
# ---------------------------------------------------------------------------

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ---------------------------------------------------------------------------
# Key Pair
# ---------------------------------------------------------------------------

resource "tls_private_key" "cdb_chronicle_log_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "cdb_chronicle_log_key_pair" {
  key_name   = "cdb-chronicle-log-key-pair"
  public_key = tls_private_key.cdb_chronicle_log_key.public_key_openssh
}

resource "local_file" "cdb_chronicle_log_private_key" {
  content         = tls_private_key.cdb_chronicle_log_key.private_key_pem
  filename        = "${path.module}/cdb-chronicle-log-key.pem"
  file_permission = "0400"
}

# ---------------------------------------------------------------------------
# Security Group
# ---------------------------------------------------------------------------

resource "aws_security_group" "cdb_chronicle_log_sg" {
  name        = "cdb-chronicle-log-sg"
  description = "Allow Kafka and SSH traffic"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Kafka broker"
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }

  ingress {
    description = "SSH"
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

  tags = {
    Name = "cdb-chronicle-log-sg"
  }
}

# ---------------------------------------------------------------------------
# EC2 Instance
# ---------------------------------------------------------------------------

resource "aws_instance" "cdb_chronicle_log" {
  ami                         = "ami-0ec10929233384c7f"
  instance_type               = "t3.small"
  key_name                    = aws_key_pair.cdb_chronicle_log_key_pair.key_name
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.cdb_chronicle_log_sg.id]
  associate_public_ip_address = true

  tags = {
    Name = "cdb-chronicle-log"
  }

  provisioner "file" {
    source      = "docker-compose.yml"
    destination = "/home/ubuntu/docker-compose.yml"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.cdb_chronicle_log_key.private_key_pem
      host        = self.public_ip
    }
  }

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.cdb_chronicle_log_key.private_key_pem
      host        = self.public_ip
    }

    inline = [
      "sudo apt-get update -y",
      "sudo apt-get install -y docker.io",
      "sudo systemctl start docker",
      "sudo usermod -aG docker ubuntu",
      "sudo mkdir -p /usr/local/lib/docker/cli-plugins",
      "sudo curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 -o /usr/local/lib/docker/cli-plugins/docker-compose",
      "sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose",
      "cd /home/ubuntu && sudo EC2_PRIVATE_IP=${self.private_ip} docker compose up -d"
    ]
  }
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

output "cdb_chronicle_log_private_ip" {
  value       = aws_instance.cdb_chronicle_log.private_ip
}

output "cdb_chronicle_log_bootstrap_server" {
  value       = "${aws_instance.cdb_chronicle_log.private_ip}:9092"
}

output "cdb_chronicle_log_ssh_command" {
  value       = "ssh -i cdb-chronicle-log-key.pem ubuntu@${aws_instance.cdb_chronicle_log.public_ip}"
}