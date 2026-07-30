# ------------------------------------------------------------------------------
# GitHub OIDC identity provider
#
# Account-global: exactly one per account, keyed by URL. It is shared across the
# portfolio repos, all of which authenticate GitHub Actions the same way, so a
# sibling project owns it and this config only references it for the ARN its trust
# policies need. Owning it here would let this repo's destroy break the siblings.
# ------------------------------------------------------------------------------

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

locals {
  # Assembled once and shared by all three trust policies, so a typo cannot quietly
  # widen one of them. The plain repo:owner/name form never matches here, and STS
  # denies with a message that says nothing about why.
  github_subject = "repo:${var.github_org}@${var.github_owner_id}/${var.github_repo}@${var.github_repo_id}"
}

# ------------------------------------------------------------------------------
# Site deploy role
#
# Three CI roles rather than one, because they answer to different trust. This role
# and the apply role are pinned to main. The plan role answers to pull requests,
# which are unreviewed code, so it gets read access and nothing more. Sharing one
# role across both would hand every pull request the reach to rewrite DNS.
# ------------------------------------------------------------------------------

data "aws_iam_policy_document" "deploy_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    # Who the token was minted for. Necessary, but every Actions run targeting AWS
    # carries the same value, so it filters out nothing on its own.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Pinned to a branch, not just a repo. Matching on the repo alone would let
    # anything able to push a branch deploy to production.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.github_subject}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name               = "christiansantiago-dev-deploy"
  description        = "Assumed by GitHub Actions on main to publish the site"
  assume_role_policy = data.aws_iam_policy_document.deploy_assume_role.json
}

# Derived from the two commands the workflow runs, and nothing wider: an s3 sync
# with --delete, then a CloudFront invalidation.
data "aws_iam_policy_document" "deploy" {
  # sync lists the destination and compares sizes and timestamps before uploading.
  # Note the bare bucket ARN: ListBucket acts on the bucket, and the /* form
  # silently never matches.
  statement {
    sid       = "ListForSyncDiff"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.site.arn]
  }

  # Deliberately no s3:GetObject. The deploy role can publish the site and cannot
  # read it back, because nothing in the workflow needs to.
  statement {
    sid       = "WriteObjects"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]
  }

  statement {
    sid       = "InvalidateCache"
    actions   = ["cloudfront:CreateInvalidation"]
    resources = [aws_cloudfront_distribution.site.arn]
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "publish-site"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy.json
}

# ------------------------------------------------------------------------------
# Terraform plan role
#
# Answers to pull requests so a reviewer sees the diff before it lands. Read only,
# and the workflow runs plan with -lock=false: a plan takes a state lock by default,
# which would need write access to the lock object for no benefit here, since
# nothing a plan does can corrupt state.
#
# Fork pull requests cannot reach this role at all. GitHub refuses them the
# id-token: write permission, so they never obtain a token to trade.
# ------------------------------------------------------------------------------

data "aws_iam_policy_document" "plan_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # The pull_request selector, not a ref. StringEquals rather than StringLike is
    # the boundary: a wildcard over the last segment would also match
    # ref:refs/heads/main and give pull requests the apply role's reach.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.github_subject}:pull_request"]
    }
  }
}

resource "aws_iam_role" "plan" {
  name               = "christiansantiago-dev-plan"
  description        = "Assumed by GitHub Actions on pull requests to run terraform plan"
  assume_role_policy = data.aws_iam_policy_document.plan_assume_role.json
}

# Broad on purpose. Plan refreshes every resource in the config, so enumerating the
# reads per service would break on each resource added and buys nothing while the
# role cannot mutate anything. The honest cost is that it can read any object in the
# account, which is acceptable in an account that hosts only this project.
resource "aws_iam_role_policy_attachment" "plan_read_only" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# ------------------------------------------------------------------------------
# Terraform apply role
#
# The one role in this config that is not least privilege, and worth saying so out
# loud: it can create IAM roles, and creating IAM roles is a path to admin. The name
# prefix narrows that reach without closing it. The real control is the trust
# policy, which admits exactly one ref.
# ------------------------------------------------------------------------------

data "aws_iam_policy_document" "apply_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.github_subject}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "apply" {
  name               = "christiansantiago-dev-apply"
  description        = "Assumed by GitHub Actions on main to run terraform apply"
  assume_role_policy = data.aws_iam_policy_document.apply_assume_role.json
}

# An allowlist of the eleven services this stack creates, replacing the
# PowerUserAccess this used to attach. That policy is written as NotAction, so it
# allowed everything but IAM, and every service AWS launches from now on along with
# it. The expensive failure it left open was a leaked token starting compute.
#
# Honest about what this is: least service, not least privilege. It still permits
# every action within these eleven, including deleting the state bucket. Enumerating
# per action would break on each resource added, since apply needs the reads a
# refresh performs as well as the writes.
data "aws_iam_policy_document" "apply" {
  statement {
    sid = "ManageProjectServices"
    actions = [
      "acm:*",
      "apigateway:*",
      "budgets:*",
      "cloudfront:*",
      "cloudwatch:*",
      "dynamodb:*",
      "lambda:*",
      "logs:*",
      "route53:*",
      "s3:*",
      "sns:*",
    ]
    resources = ["*"]
  }

  # Read by the account ID data source, which every role ARN in this file is built
  # from.
  statement {
    sid       = "IdentifySelf"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "apply" {
  name   = "manage-project-services"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.apply.json
}

data "aws_iam_policy_document" "apply_iam" {
  # Confined to this project's name prefix, so the role cannot touch roles belonging
  # to the sibling projects sharing this account.
  statement {
    sid = "ManageProjectRoles"
    actions = [
      "iam:AttachRolePolicy",
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:DeleteRolePolicy",
      "iam:DetachRolePolicy",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListRolePolicies",
      "iam:PutRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:UpdateRole",
    ]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/christiansantiago-dev-*"]
  }

  # The escalation guard. Scoped to one role and one service, so apply can hand
  # Lambda exactly the counter's execution role and nothing else.
  statement {
    sid       = "PassCounterExecutionRole"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.counter.arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["lambda.amazonaws.com"]
    }
  }

  # Read only, for the provider data source at the top of this file. PowerUserAccess
  # excludes all of IAM, so without this the very first refresh fails.
  statement {
    sid       = "ReadSharedOidcProvider"
    actions   = ["iam:GetOpenIDConnectProvider"]
    resources = [data.aws_iam_openid_connect_provider.github.arn]
  }
}

resource "aws_iam_role_policy" "apply_iam" {
  name   = "manage-project-iam"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.apply_iam.json
}
