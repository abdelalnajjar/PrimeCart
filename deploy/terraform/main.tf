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
  # Prefer a subnet that maps a public IP by default (typical default-VPC public subnets).
  public_subnet_candidates = [
    for id in data.aws_subnets.default.ids : id
    if data.aws_subnet.by_id[id].map_public_ip_on_launch
  ]
  instance_subnet_id = length(local.public_subnet_candidates) > 0 ? local.public_subnet_candidates[0] : sort(tolist(data.aws_subnets.default.ids))[0]
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
}

resource "aws_iam_role_policy" "app" {
  name   = "${var.environment}-app-inline"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.app_inline.json
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.environment}-ec2-profile"
  role = aws_iam_role.app.name
}

resource "aws_security_group" "app" {
  name        = "${var.environment}-app-sg"
  description = "Single EC2: HTTP for PrimeCart (free-tier friendly, no ALB)"
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

resource "aws_instance" "app" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.instance_type
  subnet_id                   = local.instance_subnet_id
  vpc_security_group_ids      = [aws_security_group.app.id]
  iam_instance_profile        = aws_iam_instance_profile.app.name
  associate_public_ip_address = true

  user_data = base64encode(
    templatefile("${path.module}/../bootstrap.sh", {
      s3_bucket    = aws_s3_bucket.app_artifacts.bucket
      s3_key       = aws_s3_object.app_zip.key
      aws_region   = var.aws_region
      orders_table = aws_dynamodb_table.orders.name
    })
  )

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  depends_on = [aws_s3_object.app_zip]

  tags = {
    Name = "${var.environment}-app"
  }

  lifecycle {
    replace_triggered_by = [aws_s3_object.app_zip.etag]
  }
}
