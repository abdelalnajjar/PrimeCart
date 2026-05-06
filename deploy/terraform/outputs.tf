output "app_url" {
  description = "Open in a browser after instances pass ALB health checks (often several minutes on first boot)."
  value       = "http://${aws_lb.app.dns_name}"
}

output "alb_dns_name" {
  description = "ALB DNS name (same host as app_url without scheme)."
  value       = aws_lb.app.dns_name
}

output "autoscaling_group_name" {
  description = "ASG name (for CLI instance refresh, scaling, or demos)."
  value       = aws_autoscaling_group.app.name
}

output "cloudwatch_log_group_app" {
  description = "Log group for PrimeCart web app stdout (via CloudWatch agent)."
  value       = aws_cloudwatch_log_group.app.name
}

output "cloudwatch_log_group_worker" {
  description = "Log group for PrimeCart SQS worker stdout."
  value       = aws_cloudwatch_log_group.worker.name
}

output "orders_table_name" {
  description = "DynamoDB orders table; set ORDERS_TABLE_NAME for local runs against this environment."
  value       = aws_dynamodb_table.orders.name
}

output "orders_queue_url" {
  description = "SQS queue URL; set ORDERS_QUEUE_URL locally if you want to use the same queue as the deployed stack."
  value       = aws_sqs_queue.orders.url
}

output "app_artifact_bucket" {
  description = "Private S3 bucket holding the deployment zip (not product images)."
  value       = aws_s3_bucket.app_artifacts.bucket
}

output "app_artifact_key" {
  description = "S3 object key for the uploaded app zip."
  value       = aws_s3_object.app_zip.key
}
