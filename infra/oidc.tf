# Read only, not created here. IAM permits one OIDC provider per issuer URL per
# account, and sibling repos already deploy through this one. Owning it here
# would mean a destroy in this project silently breaks their pipelines.
#
# Same rule as the hosted zone: Terraform ownership follows the lifecycle of the
# thing, not the convenience of whichever config happens to need it.
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# What GitHub Actions assumes instead of holding an access key. The workflow
# presents a short lived token GitHub signed for that specific run, trades it
# for temporary credentials, and nothing durable is ever stored in the repo.
resource "aws_iam_role" "deploy" {
  name        = "christiansantiago-dev-deploy"
  description = "Assumed by GitHub Actions on main to publish the site"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"

      # GitHub's issuer, which every repository on GitHub shares. Nothing about
      # this principal is specific to this account, so the Condition below is
      # the entire security boundary.
      Principal = {
        Federated = data.aws_iam_openid_connect_provider.github.arn
      }

      Action = "sts:AssumeRoleWithWebIdentity"

      Condition = {
        StringEquals = {
          # Who the token was minted for. Necessary, but every Actions run
          # targeting AWS carries the same value, so it filters out nothing.
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"

          # Who the caller is, and the only claim that narrows anything. Drop
          # this line and any workflow in any public repository on GitHub can
          # assume this role.
          #
          # Pinned to a branch, not just a repo. Matching on the repo alone
          # would let anything able to push a branch deploy to production, and
          # a wildcard across the account would trust repos not yet forked.
          "token.actions.githubusercontent.com:sub" = "repo:Go-Santiago-Go/christiansantiago.dev:ref:refs/heads/main"
        }
      }
    }]
  })
}

# What the role may do once assumed, as opposed to who may assume it. A role
# with no permissions policy can be assumed and then do nothing at all.
#
# Inline rather than a standalone managed policy: its lifecycle is bound to the
# role, so deleting the role takes it too and it can never be attached to
# another identity by accident. Managed policies are for permission sets shared
# across many identities.
#
# Derived from the two commands the workflow runs, and nothing wider: an s3 sync
# with --delete, then a CloudFront invalidation.
resource "aws_iam_role_policy" "deploy" {
  name = "publish-site"
  role = aws_iam_role.deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # sync lists the destination and compares sizes and timestamps before
        # uploading anything, so it cannot run without this. Note the bare
        # bucket ARN: ListBucket acts on the bucket, and giving it the /* form
        # silently never matches.
        Sid      = "ListForSyncDiff"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.site.arn
      },
      {
        # These act on objects, hence the /* suffix. DeleteObject is here only
        # because of --delete, which is what stops files removed from client/
        # living in the bucket forever.
        #
        # Deliberately no s3:GetObject. The deploy role can publish the site and
        # cannot read it back, because nothing in the workflow needs to.
        Sid    = "WriteObjects"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = "${aws_s3_bucket.site.arn}/*"
      },
      {
        # Scoped to this distribution. CloudFront has no resource level
        # alternative worth reaching for here, and a wildcard would let a
        # compromised workflow invalidate anything in the account.
        Sid      = "InvalidateCache"
        Effect   = "Allow"
        Action   = "cloudfront:CreateInvalidation"
        Resource = aws_cloudfront_distribution.site.arn
      },
    ]
  })
}
