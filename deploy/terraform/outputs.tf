output "app_url" {
  description = "Open in a browser after user-data finishes (often 2–5 minutes). Uses port 80."
  value       = "http://${aws_instance.app.public_dns}"
}

output "app_public_ip" {
  value = aws_instance.app.public_ip
}

output "orders_table_name" {
  value = aws_dynamodb_table.orders.name
}

output "app_artifact_bucket" {
  value = aws_s3_bucket.app_artifacts.bucket
}

output "app_artifact_key" {
  value = aws_s3_object.app_zip.key
}
