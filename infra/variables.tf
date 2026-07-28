variable "domain_name" {
  description = "Apex domain the site is served from. Appears in the certificate, the CloudFront aliases, and the Route 53 records"
  type        = string
  default     = "christiansantiago.dev"
}

variable "alert_email" {
  description = "Where budget notifications are sent. Defaulted rather than kept in a tfvars file because this address is already published in the site's contact section, so hiding it here would protect nothing"
  type        = string
  default     = "santiagothedeveloper@gmail.com"
}