/* Route53 */

resource "aws_route53_zone" "nexxus" {
  name = var.domain
}
