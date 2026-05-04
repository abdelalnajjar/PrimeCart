variable "aws_region" {
  type        = string
  description = "AWS region (must match app default if you do not override in env)."
  default     = "us-west-1"
}

variable "environment" {
  type        = string
  description = "Name prefix for resources."
  default     = "primecart"
}

variable "instance_type" {
  type        = string
  description = "EC2 type. t2.micro is the usual 12-month Free Tier size (750 hrs/mo); t3.micro is also often included—confirm in your account’s Free Tier page."
  default     = "t2.micro"
}
