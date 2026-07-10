terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }

  # Local backend on purpose: this is a short-lived, single-operator take-home
  # exercise, not a long-running shared environment. A remote backend
  # (S3 + DynamoDB lock table) would add infrastructure the grader has to
  # provision before they can even run `terraform init`, which works against
  # the "must execute flawlessly on the first run" constraint. See
  # docs/DECISIONS.md for the full rationale.
}
