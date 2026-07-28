# Created by the Route53 registrar at domain registration, and the .dev
# registry delegates to its nameservers. Read only on purpose: declaring it as
# a resource would create a second zone with different nameservers, and 
# importing it would put the live delegation inside destroy's blast radius.
data "aws_route53_zone" "main" {
    name = var.domain_name
}