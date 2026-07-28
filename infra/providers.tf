locals {
  # Applied by both providers below. Defined once so the aliased provider
  # cannot drift from the default one.
  common_tags = {
    Project   = "personal-site"
    ManagedBy = "Terraform"
    Repo      = "Go-Santiago-Go/christiansantiago.dev"
  }
}

provider "aws" {
  region = "us-east-2"

  default_tags {
    tags = local.common_tags
  }
}

# CloudFront reads its TLS certificate only from us-east-1, so the 
# certificate and its validation live behind this alias. Nothing else uses it.
provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"

  default_tags {
    tags = local.common_tags
  }
}