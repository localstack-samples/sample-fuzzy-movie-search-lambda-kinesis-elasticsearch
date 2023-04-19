variable "aws_region" {
	default = "eu-west-1"
}

resource "aws_iam_role" "lambda_role" {
  name = "lambdarole"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy" "lambda_role_policy" {
  name = "lambda_policy"
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        "Effect": "Allow",
        "Action": [
          "kinesis:*"
        ],
        "Resource": [
          aws_kinesis_stream.ingest_kinesis_stream.arn,
          "${aws_kinesis_stream.ingest_kinesis_stream.arn}/*"
        ]
      },
      {
        "Effect": "Allow",
        "Action": [
          "es:*"
        ],
        "Resource": [
          aws_elasticsearch_domain.movies_es_domain.arn,
          "${aws_elasticsearch_domain.movies_es_domain.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role" "firehose_role" {
  name = "firehose_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "firehose.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "firehose_role_policy" {
  name = "firehose_policy"
  role = aws_iam_role.firehose_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        "Effect": "Allow",
        "Action": [
          "kinesis:*"
        ],
        "Resource": [
          aws_kinesis_stream.ingest_kinesis_stream.arn,
          "${aws_kinesis_stream.ingest_kinesis_stream.arn}/*"
        ]
      },
      {
        "Effect": "Allow",
        "Action": [
          "s3:*"
        ],
        "Resource": [
          aws_s3_bucket.ingest_skipped_docs_bucket.arn,
          "${aws_s3_bucket.ingest_skipped_docs_bucket.arn}/*"
        ]
      },
      {
        "Effect": "Allow",
        "Action": [
          "es:*"
        ],
        "Resource": [
          aws_elasticsearch_domain.movies_es_domain.arn,
          "${aws_elasticsearch_domain.movies_es_domain.arn}/*"
        ]
      }
    ]
  })
}

data "archive_file" "ingest_lambda_archive" {
  type             = "zip"
  source_file      = "ingest/lambda.py"
  output_path      = "build/ingest_lambda.zip"
}

resource "aws_lambda_function" "ingest_lambda" {
  filename      = data.archive_file.ingest_lambda_archive.output_path
  function_name = "ingestlambda"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda.handler"

  source_code_hash = data.archive_file.ingest_lambda_archive.output_sha

  runtime = "python3.9"

  environment {
    variables = {
      STREAM_NAME = aws_kinesis_stream.ingest_kinesis_stream.name
    }
  }
}

resource "aws_lambda_function_url" "ingest_lambda_url" {
  function_name      = aws_lambda_function.ingest_lambda.function_name
  authorization_type = "NONE"
}

data "archive_file" "search_lambda_archive" {
  type             = "zip"
  source_file      = "search/lambda.py"
  output_path      = "build/search_lambda.zip"
}

resource "aws_lambda_function" "search_lambda" {
  filename      = data.archive_file.search_lambda_archive.output_path
  function_name = "searchlambda"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda.handler"

  source_code_hash = data.archive_file.search_lambda_archive.output_sha

  runtime = "python3.9"

  environment {
    variables = {
      ELASTICSEARCH_ENDPOINT = aws_elasticsearch_domain.movies_es_domain.endpoint
      ELASTICSEARCH_INDEX = "movies"
    }
  }
}

resource "aws_lambda_function_url" "search_lambda_url" {
  function_name      = aws_lambda_function.search_lambda.function_name
  authorization_type = "NONE"
  cors {
    allow_credentials = true
    allow_origins     = ["*"]
    allow_methods     = ["*"]
    allow_headers     = ["date", "keep-alive"]
    expose_headers    = ["keep-alive", "date"]
    max_age           = 86400
  }
}

resource "aws_elasticsearch_domain" "movies_es_domain" {
  domain_name           = "movie-search"
  elasticsearch_version = "7.10"

  cluster_config {
    instance_type = "m4.large.elasticsearch"
    instance_count = 1
    dedicated_master_enabled = false
    zone_awareness_enabled = false
    warm_enabled = false
  }

  ebs_options {
    ebs_enabled = true
    volume_type = "gp2"
    volume_size = 10
  }
}

resource "aws_kinesis_stream" "ingest_kinesis_stream" {
  name        = "ingest-kinesis-stream"
  shard_count = "1"
}

resource "aws_s3_bucket" "ingest_skipped_docs_bucket" {
  bucket = "ingest-skipped-docs-bucket"
}

resource "aws_kinesis_firehose_delivery_stream" "ingest_firehose_stream" {
  name        = "ingest-firehose-delivery-stream"
  destination = "elasticsearch"

  s3_configuration {
    role_arn           = aws_iam_role.firehose_role.arn
    bucket_arn         = aws_s3_bucket.ingest_skipped_docs_bucket.arn
  }

  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.ingest_kinesis_stream.arn
    role_arn = aws_iam_role.firehose_role.arn
  }

  elasticsearch_configuration {
    domain_arn = aws_elasticsearch_domain.movies_es_domain.arn
    role_arn   = aws_iam_role.firehose_role.arn
    index_name = "movies"
    buffering_interval = 60
    buffering_size = 1
  }
}

#
# S3 Website Config
#
resource "aws_s3_bucket" "website_bucket" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_website_configuration" "website_bucket" {
  bucket = aws_s3_bucket.website_bucket.id

  index_document {
    suffix = "index.html"
  }

}

resource "aws_s3_bucket_acl" "website_bucket" {
  bucket = aws_s3_bucket.website_bucket.id
  acl    = "public-read"
}

data "template_file" "data" {
  for_each = fileset("${path.root}/www_tpl", "**/*")
  template = "${file("${path.root}/www_tpl/${each.value}")}"
  vars = {
    search_lambda_url = aws_lambda_function_url.search_lambda_url.function_url
  }
}

resource "aws_s3_object" "object_www_templated" {
  depends_on   = [aws_s3_bucket.website_bucket]
  for_each     = fileset("${path.root}/www_tpl", "**/*")
  bucket       = aws_s3_bucket.website_bucket.bucket
  key          = each.value
  content      = data.template_file.data[each.value].rendered
  etag         = filemd5("${path.root}/www_tpl/${each.value}")
  # FIXME this should be auto-detected
  content_type = "text/html"
  acl          = "public-read"
}

locals {
  content_types = {
    css  = "text/css"
    html = "text/html"
    js   = "application/javascript"
    json = "application/json"
    txt  = "text/plain"
    png  = "image/png"
    ico  = "image/x-icon"
  }
}

resource "aws_s3_object" "object_www" {
  depends_on = [aws_s3_bucket.website_bucket]
  for_each   = fileset(path.root, "www/*")
  bucket     = var.bucket_name
  key        = basename(each.value)
  source     = each.value
  etag       = filemd5(each.value)
  acl        = "public-read"
  # FIXME this should be way easier?
  content_type     = lookup(local.content_types, element(split(".", each.value), length(split(".", each.value)) - 1), "text/plain")
  content_encoding = "utf-8"
}

resource "aws_s3_bucket_policy" "website_bucket" {
  bucket = aws_s3_bucket.website_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource = [
          aws_s3_bucket.website_bucket.arn,
          "${aws_s3_bucket.website_bucket.arn}/*",
        ]
      },
    ]
  })
}