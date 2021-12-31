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

# 3. Create EMR cluster for complex data processing
