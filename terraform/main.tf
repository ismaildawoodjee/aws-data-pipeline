# 0.a Configure Terraform version and specify provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "3.70.0"
    }
  }
  required_version = ">= 0.14.9"
}

# 0.b Configure secret variables for AWS authentication
# Actual keys are defined in `terraform.tfvars` and kept out of git
variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "redshift_username" {}
variable "redshift_password" {}
variable "redshift_database" {}
variable "redshift_elastic_ip" {}
variable "my_ip" {}
variable "path_to_pem" {}
variable "supersetdb_password" {}
variable "superset_password" {}

# 1. Configure the AWS provider
provider "aws" {
  profile = "ismaildawoodjee"
  region  = "ap-southeast-1"
}

# 2. Create S3 bucket for storing object data 
# The syntax is `resource "aws_resource_name" "nickname_used_in_main.tf"`
resource "aws_s3_bucket" "malware_detection_s3" {
  bucket = "malware-detection-bucket"
  acl    = "public-read-write"

  tags = {
    "s3" = "malware-detection-data"
  }
}

# 3.a Create IAM roles for deploying an EMR cluster
# The JSON to string multiline variables are kept in the variables.tf file
# 3.a.i. The IAM role for using the EMR cluster:
resource "aws_iam_role" "iam_emr_service_role" {
  name               = "iam_emr_service_role"
  assume_role_policy = var.emr_role
}

# 3.a.ii. The IAM policy for the EMR cluster 
# => permissions for the EMR role to do stuff with other AWS resources
# e.g. permissions to access EC2, S3, Lambda resources
resource "aws_iam_role_policy" "iam_emr_service_policy" {
  name   = "iam_emr_service_policy"
  role   = aws_iam_role.iam_emr_service_role.id
  policy = var.emr_policy
}

# 3.b.i. EC2 instances must be assigned a profile, which contains a role
resource "aws_iam_role" "iam_emr_profile_role" {
  name               = "iam_emr_profile_role"
  assume_role_policy = var.emr_ec2_profile_role
}

# 3.b.ii. The IAM profile for the EC2 instances that are part of EMR
resource "aws_iam_instance_profile" "iam_emr_profile" {
  name = "iam_emr_profile"
  role = aws_iam_role.iam_emr_profile_role.name
}

# 3.b.iii. The IAM policy for the EC2 instances
# => permissions for the EC2 instances' (that are part of EMR) profile to interact with other AWS resources
resource "aws_iam_role_policy" "iam_emr_profile_policy" {
  name   = "iam_emr_profile_policy"
  role   = aws_iam_role.iam_emr_profile_role.id
  policy = var.emr_ec2_profile_policy
}

# 3.c Create the EMR cluster using the roles and policies defined above
# This cluster will have 1 master node and 2 core/compute node running Hadoop + Spark
resource "aws_emr_cluster" "malware_detection_emr" {
 name                = "malware-detection-cluster"
 log_uri             = "s3://malware-detection-bucket/emr_logs/"
 service_role        = aws_iam_role.iam_emr_service_role.arn
 applications        = ["Hadoop", "Spark"]
 release_label       = "emr-6.4.0"
 configurations_json = var.emr_spark_env_config

 step {
   action_on_failure = "CANCEL_AND_WAIT"
   name              = "Setup Hadoop Debugging"
   hadoop_jar_step {
     jar  = "command-runner.jar"
     args = ["state-pusher-script"]
   }
 }

 lifecycle {
   ignore_changes = [step]
 }
 auto_termination_policy {
   idle_timeout = 60 # this doesn't terminate EMR after 60 seconds! takes 5 minutes
 }
 ec2_attributes {
   instance_profile = aws_iam_instance_profile.iam_emr_profile.arn
 }

 # specifying bid_price automatically implies that I'm using a spot instance
 master_instance_group {
   name           = "Master Node - 1"
   instance_type  = "m5.xlarge"
   instance_count = 1
   bid_price      = "0.1" # in DOLLARS, NOT percentages
 }
 core_instance_group {
   name           = "Core Nodes - 2"
   instance_type  = "m5.xlarge"
   instance_count = 2
   bid_price      = "0.1"
 }
}

# 4.a.i Create role for Redshift to perform operations
resource "aws_iam_role" "redshift_role" {
  name               = "redshift_role"
  assume_role_policy = var.redshift_role
}

# 4.a.ii Create Redshift and S3 full access policies to allow Redshift to 
# read from S3
resource "aws_iam_role_policy" "redshift_s3_full_access_policy" {
  name   = "redshift_s3_policy"
  role   = aws_iam_role.redshift_role.id
  policy = var.redshift_s3_full_access_policy
}

# 4.b Create Redshift cluster using the roles and policies defined in 4.a
# 1-node cluster for development, at least 2 nodes for production
resource "aws_redshift_cluster" "malware_detection_redshift" {
  cluster_identifier  = "malware-files-datawarehouse"
  master_username     = var.redshift_username
  master_password     = var.redshift_password
  database_name       = var.redshift_database
  node_type           = "dc2.large"
  cluster_type        = "multi-node"
  number_of_nodes     = 2
  iam_roles           = [aws_iam_role.redshift_role.arn]
  publicly_accessible = true
  elastic_ip          = var.redshift_elastic_ip
}

# 5.a.i Create security group for an EC2 instance that will host the Superset dashboard
# Allow ingress from Redshift and from my IP address, and allow egress to the internet
resource "aws_security_group" "superset_dashboard_ec2_sg" {
  name        = "superset_sg"
  description = "Allow TLS traffic to EC2 instance hosting a Superset dashboard"

  # allow traffic from Redshift cluster (given that it is assigned an elastic IP)
  ingress {
    from_port   = 5439
    to_port     = 5439
    protocol    = "tcp"
    cidr_blocks = ["${var.redshift_elastic_ip}/32"]
  }
  # allow traffic from my IP (SSH, TCP or otherwise)
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["${var.my_ip}/32"]
  }
  # allow traffic from the internet, but only on the Superset port
  ingress {
    from_port        = 8080
    to_port          = 8080
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  # allow traffic to the internet 
  # need to allow both IPV4 and IPV6 in order to `sudo apt update/upgrade` etc.
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "tls_private_key" "kp" {
  algorithm = "RSA"
}
resource "aws_key_pair" "terraform_generated_keypair" {
  key_name   = "superset_ec2_keypair"
  public_key = tls_private_key.kp.public_key_openssh
  # the private key will be inside the terraform.tfstate
  # copy it into a superset_ec2_keypair.pem file and `chmod 400 superset_ec2_keypair.pem` 
}

resource "aws_instance" "superset_dashboard_ec2" {
  # ubuntu 20.04 (64-bit) instance in ap-southeast-1 region
  ami                         = "ami-055d15d9cfddf7bd3"
  instance_type               = "t2.micro"
  associate_public_ip_address = true
  key_name                    = aws_key_pair.terraform_generated_keypair.key_name
  security_groups             = [aws_security_group.superset_dashboard_ec2_sg.name]
  # user_data                   = var.script_to_execute
  tags = {
    Name = "superset-dashboard"
  }

  # this bootstraps the EC2 instance by remotely executing the code below using SSH
  # user_data doesn't work because you have to wait for cloud-init
  # https://stackoverflow.com/questions/47713519/issue-using-terraform-ec2-userdata?rq=1
  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("${var.path_to_pem}")
    host        = self.public_ip
  }
  # install Docker and spin up a Postgres container. then spin up a Superset container
  # by following the instructions from here: https://hub.docker.com/r/apache/superset
  provisioner "remote-exec" {
    inline = [
      "#!/bin/bash",
      "set -x",
      "sudo apt update -y && sudo apt upgrade -y",
      "sudo apt install docker.io -y",
      "sudo apt update -y && sudo apt upgrade -y",
      "sudo docker run -d --name supersetdb -e POSTGRES_PASSWORD=${var.supersetdb_password} -p 5432:5432 postgres:latest",
      "sudo docker run -d --name superset -p 8080:8088 apache/superset:latest",
      "sudo docker exec -it superset superset fab create-admin --username admin --firstname Ismail --lastname Dawoodjee --email admin@admin.com --password ${var.superset_password}",
      "sudo docker exec -it superset superset db upgrade",
      "sudo docker exec -it superset superset init"
    ]
    # to connect to the Postgres container, use the address "172.17.0.1:5432", where the IP
    # is found from the docker0 inet connection using `ifconfig` or `ip addr show`
  }
}
