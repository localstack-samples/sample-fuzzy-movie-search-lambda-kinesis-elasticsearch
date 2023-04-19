# Output variable definitions

output "ingest_lambda_url" {
  value = aws_lambda_function_url.ingest_lambda_url.function_url
}

output "search_lambda_url" {
  value = aws_lambda_function_url.search_lambda_url.function_url
}

output "elasticsearch_endpoint" {
  value = aws_elasticsearch_domain.movies_es_domain.endpoint
}

output "website_bucket_arn" {
  description = "ARN of the bucket"
  value       = aws_s3_bucket.website_bucket.arn
}

output "website_bucket_name" {
  description = "Name (id) of the bucket"
  value       = aws_s3_bucket.website_bucket.id
}

output "website_bucket_domain" {
  description = "Domain name of the bucket"
  value       = aws_s3_bucket_website_configuration.website_bucket.website_domain
}

output "website_endpoint" {
  value = aws_s3_bucket_website_configuration.website_bucket.website_endpoint
}
