terraform {
  # use_lockfile requires 1.10 or newer
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.56"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
  backend "s3" {
    bucket       = "christiansantiago-dev-tfstate-646278323015"
    key          = "site/terraform.tfstate"
    region       = "us-east-2"
    use_lockfile = true
  }
}
