/*
Simple Email Service (SES)
*/

locals {
  email_domain = "app.${var.domain}"
}
resource "aws_ses_domain_identity" "email" {
  domain = local.email_domain
}

resource "aws_ses_domain_mail_from" "email" {
  domain           = aws_ses_domain_identity.email.domain
  mail_from_domain = "bounce.${aws_ses_domain_identity.email.domain}"
}

resource "aws_ses_domain_dkim" "email" {
  domain = aws_ses_domain_identity.email.domain
}

resource "aws_route53_record" "ses_dkim" {
  count   = 3
  zone_id = aws_route53_zone.nexxus.zone_id
  name    = "${element(aws_ses_domain_dkim.email.dkim_tokens, count.index)}._domainkey"
  type    = "CNAME"
  ttl     = "600"
  records = ["${element(aws_ses_domain_dkim.email.dkim_tokens, count.index)}.dkim.amazonses.com"]
}

resource "aws_route53_record" "email_validation" {
  zone_id = aws_route53_zone.nexxus.zone_id
  name    = "_amazonses.${local.email_domain}"
  type    = "TXT"
  ttl     = "600"
  records = [aws_ses_domain_identity.email.verification_token]
}

resource "aws_ses_domain_identity_verification" "email" {
  domain = aws_ses_domain_identity.email.id

  depends_on = [aws_route53_record.email_validation]
}

# Example Route53 MX record
resource "aws_route53_record" "email_from_mx" {
  zone_id = aws_route53_zone.nexxus.id
  name    = aws_ses_domain_mail_from.email.mail_from_domain
  type    = "MX"
  ttl     = "600"
  records = ["10 feedback-smtp.${var.aws_region}.amazonses.com"]
}

# Example Route53 TXT record for SPF
resource "aws_route53_record" "email_from_txt" {
  zone_id = aws_route53_zone.nexxus.id
  name    = aws_ses_domain_mail_from.email.mail_from_domain
  type    = "TXT"
  ttl     = "600"
  records = ["v=spf1 include:amazonses.com -all"]
}

data "aws_iam_policy_document" "email" {
  statement {
    actions   = ["SES:SendEmail", "SES:SendRawEmail"]
    resources = [aws_ses_domain_identity.email.arn]

    principals {
      identifiers = ["*"]
      type        = "AWS"
    }
  }
}

resource "aws_ses_identity_policy" "email" {
  name = "email"

  identity = aws_ses_domain_identity.email.arn
  policy   = data.aws_iam_policy_document.email.json
}

resource "aws_iam_user" "smtp_user" {
  name = "smtp_user"
}

resource "aws_iam_access_key" "smtp_user" {
  user = aws_iam_user.smtp_user.name
}

data "aws_iam_policy_document" "ses_sender" {
  statement {
    actions   = ["ses:SendRawEmail"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "ses_sender" {
  name        = "ses_sender"
  description = "Allows sending of e-mails via Simple Email Service"
  policy      = data.aws_iam_policy_document.ses_sender.json
}

resource "aws_iam_user_policy_attachment" "test-attach" {
  user       = aws_iam_user.smtp_user.name
  policy_arn = aws_iam_policy.ses_sender.arn
}

output "smtp_username" {
  value = aws_iam_access_key.smtp_user.id
}

output "smtp_password" {
  value     = aws_iam_access_key.smtp_user.ses_smtp_password_v4
  sensitive = true
}
