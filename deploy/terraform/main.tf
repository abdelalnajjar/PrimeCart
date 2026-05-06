data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_subnet" "by_id" {
  for_each = toset(data.aws_subnets.default.ids)
  id       = each.value
}

locals {
  bootstrap_hash = filesha256("${path.module}/../bootstrap.sh")

  # One subnet per AZ among subnets that map a public IP (typical default-VPC public subnets).
  public_subnet_by_az = merge([
    for id in data.aws_subnets.default.ids :
    data.aws_subnet.by_id[id].map_public_ip_on_launch ? {
      (data.aws_subnet.by_id[id].availability_zone) = id
    } : {}
  ]...)

  # Fallback: any subnet per AZ if fewer than two public subnets (unusual).
  any_subnet_by_az = merge([
    for id in data.aws_subnets.default.ids :
    { (data.aws_subnet.by_id[id].availability_zone) = id }
  ]...)

  public_azs_sorted = sort(keys(local.public_subnet_by_az))
  any_azs_sorted    = sort(keys(local.any_subnet_by_az))

  alb_subnet_ids = length(local.public_azs_sorted) >= 2 ? [
    local.public_subnet_by_az[local.public_azs_sorted[0]],
    local.public_subnet_by_az[local.public_azs_sorted[1]],
    ] : (length(local.any_azs_sorted) >= 2 ? [
      local.any_subnet_by_az[local.any_azs_sorted[0]],
      local.any_subnet_by_az[local.any_azs_sorted[1]],
  ] : [])
}

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_dynamodb_table" "orders" {
  name         = "${var.environment}-orders"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "orderId"

  attribute {
    name = "orderId"
    type = "S"
  }
}

resource "aws_sqs_queue" "orders" {
  name = "${var.environment}-orders-queue"
}

resource "aws_s3_bucket" "app_artifacts" {
  bucket = "${var.environment}-app-${random_id.bucket_suffix.hex}"
}

resource "aws_s3_bucket_public_access_block" "app_artifacts" {
  bucket = aws_s3_bucket.app_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "archive_file" "app_zip" {
  type        = "zip"
  source_dir  = abspath("${path.module}/../..")
  output_path = "${path.module}/.build/app.zip"

  excludes = [
    "node_modules",
    ".git",
    ".terraform",
    "deploy/terraform/.build",
    ".cursor",
    "*.md",
  ]
}

resource "aws_s3_object" "app_zip" {
  bucket = aws_s3_bucket.app_artifacts.id
  key    = "releases/app.zip"
  source = data.archive_file.app_zip.output_path
  etag   = data.archive_file.app_zip.output_md5
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/${var.environment}/primecart-app"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "worker" {
  name              = "/${var.environment}/primecart-worker"
  retention_in_days = var.log_retention_days
}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name               = "${var.environment}-ec2-app"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

data "aws_iam_policy_document" "app_inline" {
  statement {
    sid = "ArtifactRead"
    actions = [
      "s3:GetObject",
    ]
    resources = ["${aws_s3_bucket.app_artifacts.arn}/${aws_s3_object.app_zip.key}"]
  }

  statement {
    sid = "OrdersTable"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:DescribeTable",
    ]
    resources = [aws_dynamodb_table.orders.arn]
  }

  statement {
    sid = "OrdersQueue"
    actions = [
      "sqs:SendMessage",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
    ]
    resources = [aws_sqs_queue.orders.arn]
  }

  statement {
    sid = "AppLogs"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = [
      "${aws_cloudwatch_log_group.app.arn}:*",
      "${aws_cloudwatch_log_group.worker.arn}:*",
    ]
  }
}

resource "aws_iam_role_policy" "app" {
  name   = "${var.environment}-app-inline"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.app_inline.json
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.environment}-ec2-profile"
  role = aws_iam_role.app.name
}

resource "aws_security_group" "alb" {
  name        = "${var.environment}-alb-sg"
  description = "ALB: HTTP from internet for PrimeCart"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "app" {
  name_prefix = "${var.environment}-app-"
  description = "ASG instances: HTTP from ALB only; egress all"
  vpc_id      = data.aws_vpc.default.id

  lifecycle {
    create_before_destroy = true
  }

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  dynamic "ingress" {
    for_each = length(var.ssh_ingress_cidrs) > 0 ? [1] : []
    content {
      description = "SSH optional Instance Connect or ssh client"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.ssh_ingress_cidrs
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "app" {
  name               = "${var.environment}-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = local.alb_subnet_ids

  idle_timeout = 60
}

resource "aws_lb_target_group" "app" {
  name     = "${var.environment}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    enabled             = true
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  deregistration_delay = 30
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_launch_template" "app" {
  name_prefix   = "${var.environment}-app-"
  image_id      = data.aws_ssm_parameter.al2023_ami.value
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.app.name
  }

  vpc_security_group_ids = [aws_security_group.app.id]

  user_data = base64encode(
    templatefile("${path.module}/../bootstrap.sh", {
      s3_bucket         = aws_s3_bucket.app_artifacts.bucket
      s3_key            = aws_s3_object.app_zip.key
      aws_region        = var.aws_region
      orders_table      = aws_dynamodb_table.orders.name
      orders_queue_url  = aws_sqs_queue.orders.url
      log_group_app    = aws_cloudwatch_log_group.app.name
      log_group_worker = aws_cloudwatch_log_group.worker.name
      # Use archive MD5 in user-data (stable within an apply). S3 etag can change mid-apply and break saved plans.
      app_zip_md5      = data.archive_file.app_zip.output_md5
      bootstrap_hash   = local.bootstrap_hash
    })
  )

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.environment}-app"
    }
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_s3_object.app_zip]
}

resource "aws_autoscaling_group" "app" {
  name                      = "${var.environment}-asg"
  vpc_zone_identifier       = local.alb_subnet_ids
  desired_capacity          = var.asg_desired_capacity
  min_size                  = var.asg_min_size
  max_size                  = var.asg_max_size
  health_check_type         = "ELB"
  health_check_grace_period = var.asg_health_check_grace_period
  default_cooldown          = 300

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.app.arn]

  tag {
    key                 = "Name"
    value               = "${var.environment}-app"
    propagate_at_launch = true
  }

  tag {
    key                 = "AppArtifactZipMd5"
    value               = data.archive_file.app_zip.output_md5
    propagate_at_launch = true
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = var.asg_instance_warmup
    }
    triggers = ["tag"]
  }

  lifecycle {
    precondition {
      condition     = length(local.alb_subnet_ids) >= 2
      error_message = "This stack needs at least two subnets in different Availability Zones (default VPC usually satisfies this). Add subnets or use a VPC with subnets per AZ."
    }

    precondition {
      condition     = var.asg_desired_capacity >= var.asg_min_size && var.asg_desired_capacity <= var.asg_max_size
      error_message = "asg_desired_capacity must be between asg_min_size and asg_max_size (inclusive)."
    }
  }

  depends_on = [aws_lb_listener.http]
}

resource "aws_cloudwatch_metric_alarm" "tg_unhealthy" {
  alarm_name          = "${var.environment}-unhealthy-targets"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_description   = "Fires when the ALB marks one or more targets unhealthy (good for demo: stop app, break health check)."

  dimensions = {
    LoadBalancer = aws_lb.app.arn_suffix
    TargetGroup = aws_lb_target_group.app.arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "asg_cpu_high" {
  alarm_name          = "${var.environment}-asg-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = var.asg_cpu_alarm_threshold
  treat_missing_data  = "notBreaching"
  alarm_description   = "Average CPU across ASG instances (use k6 or ab to stress for a load demo)."

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app.name
  }
}
