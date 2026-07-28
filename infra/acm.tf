# CloudFront is a global service and looks for its TLS certificate in exactly
# one place, so this resource uses the aliased provider while the rest of the
# build stays in us-east-2. A certificate issued anywhere else is invisible to
# the distribution, and the resulting error does not mention the region.
resource "aws_acm_certificate" "site" {
  provider = aws.us-east-1

  # The apex is the canonical name. The www SAN exists so the redirect added
  # later terminates TLS rather than failing on a name mismatch first.
  domain_name               = var.domain_name
  subject_alternative_names = ["www.${var.domain_name}"]

  # DNS validation is the only method ACM can re-run unattended, so renewals
  # need no human. Email validation expires the certificate every 13 months
  # unless someone clicks a link.
  validation_method = "DNS"
}

# ACM emits one validation CNAME per name on the certificate. Publishing them
# in the zone is the proof of control, since only the zone's owner can write
# there. ACM polls until it sees them, then issues.
#
# No provider alias: Route 53 is global and belongs to the default provider.
# Where the certificate lives has no bearing on where the proof is published.
resource "aws_route53_record" "cert_validation" {
  # domain_validation_options is a set; for_each needs a map. Keying on the
  # domain name rather than a position means dropping the www SAN later
  # destroys only that record instead of renumbering the rest.
  for_each = {
    for dvo in aws_acm_certificate.site.domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = data.aws_route53_zone.main.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]

  # Short TTL so a corrected record propagates in a minute. These are read by
  # ACM at issuance and again at each renewal, never by site visitors.
  ttl = 60

  # Replacing the certificate reissues the same record names. Without this the
  # apply fails on a record Terraform believes it already owns.
  allow_overwrite = true
}

# Creates nothing in AWS. It blocks the apply until ACM reports ISSUED, which
# is the only thing standing between CloudFront and a certificate still in
# PENDING_VALIDATION. Downstream resources must depend on this rather than on
# the certificate directly, or Terraform sees no reason to wait.
resource "aws_acm_certificate_validation" "site" {
  provider = aws.us-east-1

  certificate_arn         = aws_acm_certificate.site.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}