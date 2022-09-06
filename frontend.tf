
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

# index.html file (will be ignores after first run)
resource "aws_s3_object" "frontend_index" {
  bucket = aws_s3_bucket.frontend.id

  key          = "index.html"
  source       = "index.html"
  content_type = "text/html"
  etag         = filemd5("index.html")

  lifecycle {
    ignore_changes = [etag, tags_all]
  }
}

# SSL Certificate for the frontend website
resource "aws_acm_certificate" "frontend" {
  domain_name               = var.domain
  subject_alternative_names = ["www.${var.domain}"]

  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
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
    zone_id                = aws_cloudfront_distribution.frontend.hosted_zone_id
    name                   = aws_cloudfront_distribution.frontend.domain_name
    evaluate_target_health = false
  }
}

# DNS Records for the SSL certificate validation
resource "aws_route53_record" "frontend_validation" {
  for_each = {
    for dvo in aws_acm_certificate.frontend.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id = aws_route53_zone.frontend.zone_id

  allow_overwrite = true
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.record]
}

# SSL certificate validation
resource "aws_acm_certificate_validation" "frontend" {
  certificate_arn         = aws_acm_certificate.frontend.arn
  validation_record_fqdns = [for record in aws_route53_record.frontend_validation : record.fqdn]
}

resource "aws_cloudfront_origin_access_identity" "frontend" {
  comment = "Frontend website"
}

locals {
  s3_origin_id = "s3-${aws_s3_bucket.frontend.id}"
}

resource "aws_cloudfront_distribution" "frontend" {
  origin {
    domain_name = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id   = local.s3_origin_id

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.frontend.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  custom_error_response {
    error_caching_min_ttl = 0
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
  }

  aliases = [var.domain, "www.${var.domain}"]

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = true

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.frontend.arn
    ssl_support_method  = "sni-only"
  }
}
