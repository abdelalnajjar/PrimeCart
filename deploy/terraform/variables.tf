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

variable "ssh_ingress_cidrs" {
  type        = list(string)
  description = "Optional CIDRs allowed on TCP 22 (SSH). Required for EC2 Instance Connect in the browser unless you use Session Manager. Example: [\"203.0.113.10/32\"] (your public IP). Empty = no SSH ingress."
  default     = []
}

variable "asg_min_size" {
  type        = number
  description = "Minimum instances in the Auto Scaling group (use 2+ for AZ redundancy behind the ALB)."
  default     = 2
}

variable "asg_max_size" {
  type        = number
  description = "Maximum instances the ASG can scale out to."
  default     = 6
}

variable "asg_desired_capacity" {
  type        = number
  description = "Desired instance count after apply (must satisfy min_size <= desired <= max_size)."
  default     = 2
}

variable "asg_health_check_grace_period" {
  type        = number
  description = "Seconds before ELB health checks count for new instances (bootstrap + npm ci can be slow on t2.micro)."
  default     = 600
}

variable "asg_instance_warmup" {
  type        = number
  description = "Instance warmup seconds for ASG instance refresh (should cover cold start)."
  default     = 300
}

variable "log_retention_days" {
  type        = number
  description = "CloudWatch Logs retention for application and worker log groups."
  default     = 14
}

variable "asg_cpu_alarm_threshold" {
  type        = number
  description = "CPU percent (average over ASG) above which the demo CPU alarm goes to ALARM — lower for easier k6 demos."
  default     = 50

  validation {
    condition     = var.asg_cpu_alarm_threshold > 0 && var.asg_cpu_alarm_threshold <= 100
    error_message = "asg_cpu_alarm_threshold must be between 1 and 100."
  }
}

