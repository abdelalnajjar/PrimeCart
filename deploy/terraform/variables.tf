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
  default     = 35

  validation {
    condition     = var.asg_cpu_alarm_threshold > 0 && var.asg_cpu_alarm_threshold <= 100
    error_message = "asg_cpu_alarm_threshold must be between 1 and 100."
  }
}

variable "asg_cpu_alarm_period" {
  type        = number
  description = "CloudWatch period in seconds for the ASG CPU demo alarm (shorter = faster to ALARM during load tests)."
  default     = 60
}

variable "asg_cpu_alarm_evaluation_periods" {
  type        = number
  description = "Consecutive breaching periods before the ASG CPU alarm goes to ALARM."
  default     = 1

  validation {
    condition     = var.asg_cpu_alarm_evaluation_periods >= 1
    error_message = "asg_cpu_alarm_evaluation_periods must be at least 1."
  }
}

variable "enable_asg_cpu_target_tracking" {
  type        = bool
  description = "Enable target-tracking scaling based on ASG average CPU utilization."
  default     = true
}

variable "asg_cpu_target_value" {
  type        = number
  description = "Target CPUUtilization percentage for ASG target-tracking policy. Lower = scale out sooner (good for coursework demos on t2.micro)."
  default     = 12

  validation {
    condition     = var.asg_cpu_target_value > 0 && var.asg_cpu_target_value <= 100
    error_message = "asg_cpu_target_value must be between 1 and 100."
  }
}

variable "enable_alb_request_target_tracking" {
  type        = bool
  description = "Enable target-tracking scaling based on ALB RequestCountPerTarget (scales on light HTTP load without waiting for high CPU)."
  default     = true
}

variable "alb_request_target_value" {
  type        = number
  description = "Target requests per target (per minute) for ALB RequestCountPerTarget scaling policy. Lower = scale out with modest k6 traffic."
  default     = 60

  validation {
    condition     = var.alb_request_target_value > 0
    error_message = "alb_request_target_value must be greater than 0."
  }
}

variable "asg_default_cooldown" {
  type        = number
  description = "ASG default cooldown between scaling activities (seconds). Target-tracking policies use the group default; lower = faster successive scaling steps in demos."
  default     = 90
}

variable "alb_idle_timeout" {
  type        = number
  description = "ALB idle timeout in seconds (HTTP keep-alive / long requests)."
  default     = 60
}

variable "tg_health_check_interval" {
  type        = number
  description = "Target group health check interval in seconds (min 5 for ALB). Lower = faster unhealthy detection for failure demos."
  default     = 10

  validation {
    condition     = var.tg_health_check_interval >= 5 && var.tg_health_check_interval <= 300
    error_message = "tg_health_check_interval must be between 5 and 300 (ALB)."
  }
}

variable "tg_health_check_timeout" {
  type        = number
  description = "Target group health check timeout in seconds (must be below interval)."
  default     = 5
}

variable "tg_health_check_healthy_threshold" {
  type        = number
  description = "Consecutive successes to mark healthy."
  default     = 2
}

variable "tg_health_check_unhealthy_threshold" {
  type        = number
  description = "Consecutive failures to mark unhealthy (lower = faster removal during crash demo)."
  default     = 2
}

variable "tg_health_check_matcher" {
  type        = string
  description = "HTTP status codes the ALB treats as healthy for /health (e.g. 200)."
  default     = "200"
}

