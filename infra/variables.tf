variable "domain_name" {
  description = "Apex domain the site is served from. Appears in the certificate, the CloudFront aliases, and the Route 53 records"
  type        = string
  default     = "christiansantiago.dev"
}

# ------------------------------------------------------------------------------
# GitHub identity
#
# Names the one repository allowed to assume the CI roles via OIDC. Split into four
# variables rather than one string so the immutable subject claim is assembled in a
# single place and cannot be mistyped per role.
# ------------------------------------------------------------------------------

variable "github_org" {
  description = "GitHub owner of the repository permitted to assume the CI roles via OIDC."
  type        = string
  default     = "Go-Santiago-Go"
}

variable "github_repo" {
  description = "Repository permitted to assume the CI roles via OIDC."
  type        = string
  default     = "christiansantiago.dev"
}

# Repos created after 2026-07-15 use immutable subject claims, which embed numeric
# IDs that survive a rename.

variable "github_owner_id" {
  description = "Numeric GitHub owner ID, from `gh api repos/OWNER/REPO --jq .owner.id`."
  type        = string
  default     = "85260356"
}

variable "github_repo_id" {
  description = "Numeric GitHub repository ID, from `gh api repos/OWNER/REPO --jq .id`."
  type        = string
  default     = "1315366323"
}

variable "alert_email" {
  description = "Where budget notifications are sent. Defaulted rather than kept in a tfvars file because this address is already published in the site's contact section, so hiding it here would protect nothing"
  type        = string
  default     = "santiagothedeveloper@gmail.com"
}