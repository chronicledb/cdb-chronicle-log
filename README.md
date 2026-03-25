# cdb-chronicle-log

Kafka broker for ChronicleDB, deployed on AWS EC2 using Docker and Terraform.

## Overview

Runs a single-node Kafka cluster (KRaft mode, no Zookeeper) on a `t3.small` EC2 instance. Port 9092 is only accessible from within the same VPC — intended for other EC2 instances in the same network.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install)
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) configured with credentials

## Deploy

```bash
terraform init
terraform apply -auto-approve
```

Terraform will:
1. Generate an RSA key pair and register it with AWS
2. Save the private key as `cdb-chronicle-log-key.pem` in the project directory
3. Create a security group that allows Kafka (port 9092) from within the VPC only, and SSH (port 22) from anywhere
4. Launch an Ubuntu EC2 instance (`t3.small`) in the default VPC
5. Install Docker and Docker Compose on the instance
6. Start the Kafka container

## Outputs

After `terraform apply`, the following are printed:

| Output | Description |
|---|---|
| `cdb_chronicle_log_private_ip` | Private IP of the EC2 instance |
| `cdb_chronicle_log_bootstrap_server` | Kafka bootstrap server address (`<private_ip>:9092`) |
| `cdb_chronicle_log_ssh_command` | SSH command to connect to the instance |

## Connecting to Kafka

Only EC2 instances within the same VPC can reach the broker. Use the private IP:

```
bootstrap-server: <cdb_chronicle_log_private_ip>:9092
```

## Teardown

```bash
terraform destroy -auto-approve
```

## SSH Access

> **WSL users:** The `.pem` file is saved to the Windows filesystem where `chmod` does not work. Copy it to your WSL home directory first:
> ```bash
> cp cdb-chronicle-log-key.pem ~/cdb-chronicle-log-key.pem
> chmod 400 ~/cdb-chronicle-log-key.pem
> ssh -i ~/cdb-chronicle-log-key.pem ubuntu@<public_ip>
> ```

## A Note on Infrastructure

Yes, this is a single-node Kafka cluster on the smallest viable instance type. No redundancy, no replication, no fault tolerance. If it goes down, it goes down. In fact, it probably will go down. This is a poverty deployment and I am fully aware.