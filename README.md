# cdb-chronicle-log

Kafka broker for ChronicleDB, deployed on AWS EC2 using Docker and Terraform.

## Overview

Runs a single-node Kafka cluster (KRaft mode, no Zookeeper) on an EC2 instance. Port 9092 is only accessible from within the same VPC — intended for other EC2 instances in the same network.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install)
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) configured with credentials

## Deploy

Create a `terraform.tfvars` file:
```hcl
region        = "us-east-1"
ami           = "ami-0ec10929233384c7f"  # Ubuntu 24.04 LTS, us-east-1
instance_type = "t3.small"
```

Then:
```bash
terraform init
terraform apply -auto-approve
```

Terraform will:
1. Create a security group that allows Kafka (port 9092) from within the VPC only
2. Launch an Ubuntu EC2 instance in the shared VPC
3. Install Docker and Docker Compose on the instance
4. Start the Kafka container

## Outputs

After `terraform apply`, the following are printed:

| Output | Description |
|---|---|
| `cdb_chronicle_log_private_ip` | Private IP of the EC2 instance |
| `cdb_chronicle_log_kafka_bootstrap_server` | Kafka bootstrap server address (`<private_ip>:9092`) |

## Connecting to Kafka

Only EC2 instances within the same VPC can reach the broker. Use the private IP:
```
bootstrap-server: <cdb_chronicle_log_private_ip>:9092
```

## Teardown
```bash
terraform destroy -auto-approve
```

## A Note on Infrastructure

Yes, this is a single-node Kafka cluster on the smallest viable instance type. No redundancy, no replication, no fault tolerance. If it goes down, it goes down. In fact, it probably will go down. This is a poverty deployment and I am fully aware.