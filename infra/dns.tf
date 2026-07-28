# Created by the Route53 registrar at domain registration, and the .dev
# registry delegates to its nameservers. Read only on purpose: declaring it as
# a resource would create a second zone with different nameservers, and 
# importing it would put the live delegation inside destroy's blast radius.
data "aws_route53_zone" "main" {
  name = var.domain_name
}

# What actually points the domain at the distribution. Two resources rather than
# four blocks, each creating one record for the apex and one for www.
#
# These are Route 53 alias records, not CNAMEs. A CNAME is illegal at an apex,
# because DNS forbids a name carrying a CNAME from carrying any other record and
# an apex must carry its own SOA and NS. An alias resolves to the target at query
# time while looking like an ordinary address record to the client, so it is
# legal at the apex, follows CloudFront's changing edge IPs with no action here,
# and is not billed per query the way a normal lookup is.
resource "aws_route53_record" "site_ipv4" {
  # A set rather than the map built for the certificate records: there is no
  # per name data to carry, so each.value is the name itself.
  for_each = toset([var.domain_name, "www.${var.domain_name}"])

  zone_id = data.aws_route53_zone.main.zone_id
  name    = each.value
  type    = "A"

  alias {
    name = aws_cloudfront_distribution.site.domain_name

    # CloudFront's own hosted zone, not this domain's. It is a fixed AWS
    # constant, read from the distribution rather than pasted as a literal.
    zone_id = aws_cloudfront_distribution.site.hosted_zone_id

    # CloudFront does not support Route 53 health evaluation. Setting this true
    # fails the apply.
    evaluate_target_health = false
  }
}

# The IPv6 half. Clients use whichever address family they have, so a site
# publishes both and the distribution has is_ipv6_enabled set to match.
resource "aws_route53_record" "site_ipv6" {
  for_each = toset([var.domain_name, "www.${var.domain_name}"])

  zone_id = data.aws_route53_zone.main.zone_id
  name    = each.value
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = false
  }
}