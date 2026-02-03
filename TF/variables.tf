variable "aws_region" { type = string }
variable "ami_id" { type = string }
variable "key_name" { type = string }
variable "s3_bucket_name" { type = string }
variable "instance_type" { default = "t3.medium" }