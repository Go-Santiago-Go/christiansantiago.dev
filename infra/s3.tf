resource "aws_s3_bucket" "site" {
  bucket = "christiansantiago-dev-site"
}

# Two mechanisms can expose a bucket, ACLs and the bucket policy, and each
# needs guarding in two phases: refuse to create new public grants, and ignore
# any that already exist. That is what the four settings are, and why turning
# on only half of them still leaves an inherited bucket open.
#
# This is a backstop above policy evaluation, not the access control itself.
# The bucket policy is the access control; these exist so a mistake in it
# cannot become an open bucket.
resource "aws_s3_bucket_public_access_block" "site" {
  bucket = aws_s3_bucket.site.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# The authorization half of Origin Access Control. The OAC makes CloudFront sign
# its origin requests, which only identifies the caller; this is what makes that
# caller allowed to read. Without it every origin fetch returns 403.
#
# Not circular despite appearances: this reads the distribution's ARN, and the
# distribution reads the bucket's domain name. Terraform orders them bucket,
# distribution, policy.
resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id

  policy = jsonencode({
    # The policy language version, not a date to keep current. Omitting it
    # selects the 2008 grammar, which has no support for conditions.
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowCloudFrontRead"
      Effect = "Allow"

      # The service itself is the caller. This is the identity CloudFront signs
      # as once the origin access control is attached.
      Principal = {
        Service = "cloudfront.amazonaws.com"
      }

      # Read objects, and nothing else. Deliberately not s3:ListBucket: granting
      # it would let anyone enumerate the bucket through CloudFront. The cost is
      # that a missing key returns 403 rather than 404, because S3 will not
      # confirm an object is absent to a caller who cannot list.
      Action = "s3:GetObject"

      # GetObject acts on objects, so the ARN needs the /* suffix. Bucket level
      # actions would use the bare bucket ARN.
      Resource = "${aws_s3_bucket.site.arn}/*"

      # The security control. Without it this reads "any CloudFront
      # distribution, in any AWS account, may read this bucket", and anyone
      # could serve this site from their own domain.
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.site.arn
        }
      }
    }]
  })
}