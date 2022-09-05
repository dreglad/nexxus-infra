
# S3 Bucket to host transpiled frontend application
resource "aws_s3_bucket" "frontend" {
  bucket        = var.domain
  force_destroy = true
}

# S3 bucket ACL to allow public read access
resource "aws_s3_bucket_acl" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  acl = "public-read"
}

# S3 bucket policy to allow public read access to any object in the bucket
resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource = [
          aws_s3_bucket.frontend.arn,
          "${aws_s3_bucket.frontend.arn}/*",
        ]
      },
    ]
  })
}

# S3 website configuration to serve bucket contents as a website
resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

# DNS zone for the domain name
resource "aws_route53_zone" "frontend" {
  name = var.domain
}

# DNS Records for the frondend website (root and www)
resource "aws_route53_record" "frontend" {
  for_each = toset(["", "www"])

  zone_id = aws_route53_zone.frontend.zone_id

  name = each.key
  type = "A"

  alias {
    zone_id                = aws_s3_bucket.frontend.hosted_zone_id
    name                   = aws_s3_bucket_website_configuration.frontend.website_domain
    evaluate_target_health = false
  }
}

# index.html file
resource "aws_s3_object" "frontend_index" {
  bucket = aws_s3_bucket.frontend.id

  key          = "index.html"
  source       = "index.html"
  content_type = "text/html"
  etag         = filemd5("index.html")
}

# SSL Certificate for the frontend website
resource "aws_acm_certificate" "frontend" {
  domain_name       = var.domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}
