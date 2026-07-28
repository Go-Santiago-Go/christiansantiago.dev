# The identity CloudFront presents to S3. It grants nothing on its own: it only
# makes CloudFront sign its origin requests, so the bucket policy has a named
# principal to authorize. Signing gets an identified caller, the policy makes it
# an authorized one, and both halves are required.
#
# This replaces Origin Access Identity, which cannot read SSE-KMS encrypted
# objects, does not work in regions launched after 2022, and only handles GET.
resource "aws_cloudfront_origin_access_control" "site" {
  name        = "christiansantiago-dev-site"
  description = "Signs CloudFront origin requests to the private site bucket"

  origin_access_control_origin_type = "s3"

  # Sign every origin request. The alternative, no-override, signs only when the
  # viewer request already carried an Authorization header, which for anonymous
  # visitors means never signing and every origin fetch returning 403.
  signing_behavior = "always"
  signing_protocol = "sigv4"
}

# AWS maintains this policy, so its TTLs and compression handling track
# CloudFront's defaults instead of a copy that rots here. Its cache key is the
# path alone, which is the right key for a site where nothing varies by query
# string, cookie, or header. Referenced by name rather than pasted as a UUID.
data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

resource "aws_cloudfront_distribution" "site" {
  # Where CloudFront fetches from on a cache miss.
  origin {
    # The regional endpoint, not the global one. The global form answers with a
    # 307 redirect for buckets outside us-east-1, and a SigV4 signature covers
    # the Host header, so a signed request does not survive being redirected.
    domain_name = aws_s3_bucket.site.bucket_regional_domain_name

    # A label with meaning only inside this distribution. Terraform does not
    # check it against the behavior below; a mismatch surfaces as an API error
    # minutes into the apply.
    origin_id = "site-bucket"

    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  default_cache_behavior {
    target_origin_id = "site-bucket"

    # Plain HTTP gets a 301 rather than a response. A .dev domain is HSTS
    # preloaded so browsers refuse HTTP before they ask, but this covers
    # everything that is not a browser.
    viewer_protocol_policy = "redirect-to-https"

    # A read only site has nothing to write to, so anything else is refused at
    # the edge and never reaches the bucket. This is a security control rather
    # than a caching one.
    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]

    # Gzip and Brotli at the edge, applied to the HTML, CSS, and JS.
    compress = true

    cache_policy_id = data.aws_cloudfront_cache_policy.optimized.id
  }

  enabled = true

  # Required for the AAAA alias record that points at this distribution.
  is_ipv6_enabled = true

  comment = "christiansantiago.dev static site"

  # Keeping the bucket private meant giving up S3 website hosting, and index
  # document resolution went with it. A request for / arrives here with no
  # object key, so CloudFront supplies one.
  default_root_object = "index.html"

  # Every name here must also appear on the certificate below. CloudFront
  # refuses to create a distribution that would have no certificate to present
  # for one of its own aliases.
  aliases = [var.domain_name, "www.${var.domain_name}"]

  # US, Canada, and Europe. The cheapest tier, and the audience is US
  # recruiters. Widening it later is a one line change.
  price_class = "PriceClass_100"

  # Required even when nothing is restricted.
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    # The validation resource, not the certificate. Both yield the same ARN, but
    # the certificate's ARN is known while it is still PENDING_VALIDATION, so
    # referencing it directly would let Terraform build this too early.
    acm_certificate_arn = aws_acm_certificate_validation.site.certificate_arn

    # The client names the host it wants during the TLS handshake, so one edge
    # IP serves many certificates. The alternative is a dedicated IP at roughly
    # $600 a month, for clients too old to do SNI.
    ssl_support_method = "sni-only"

    minimum_protocol_version = "TLSv1.2_2021"
  }
}
