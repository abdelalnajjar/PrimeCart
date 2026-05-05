output "app_url" {
  description = "Open in a browser after user-data finishes (often 2–5 minutes). Uses port 80."
  value       = "http://${aws_instance.app.public_dns}"
}

output "app_public_ip" {
  description = "EC2 public IPv4 (same target as app_url)."
  value       = aws_instance.app.public_ip
}

output "orders_table_name" {
  description = "DynamoDB orders table; set ORDERS_TABLE_NAME for local runs against this environment."
  value       = aws_dynamodb_table.orders.name
}

output "app_artifact_bucket" {
  description = "Private S3 bucket holding the deployment zip (not product images)."
  value       = aws_s3_bucket.app_artifacts.bucket
}

output "app_artifact_key" {
  description = "S3 object key for the uploaded app zip."
  value       = aws_s3_object.app_zip.key
}
