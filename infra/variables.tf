variable "domain_name" {
    description = "Apex domain the site is served from. Appears in the certificate, the CloudFront aliases, and the Route 53 records"
    type = string
    default = "christiansantiago.dev"
}