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

# variable "today" {
#   type    = string
#   default = formatdate("YYYY-MM-DD", timestamp()) # this doesn't work
# }

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
# This cluster will have 1 master node and 1 core/compute node running Hadoop + Spark
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
  # havent tried out this step - may not work
  # step { 
  #   action_on_failure = "CANCEL_AND_WAIT"
  #   name              = "Analyse Malware Files Data"
  #   hadoop_jar_step {
  #     jar = "command-runner.jar"
  #     args = [
  #       "spark-submit",
  #       "--deploy-mode",
  #       "client",
  #       "s3://malware-detection-bucket/scripts/spark/malware_file_detection.py",
  #       "s3://malware-detection-bucket/raw/malware_file_detection/${var.today}/malware_files.csv",
  #       "s3://malware-detection-bucket/stage/malware_file_detection/${var.today}/"
  #     ]
  #   }
  # }

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
    name           = "Core Nodes - 1"
    instance_type  = "m5.xlarge"
    instance_count = 1
    bid_price      = "0.1"
  }
}
