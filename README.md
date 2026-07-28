# christiansantiago.dev

Live at **[christiansantiago.dev](https://christiansantiago.dev)**.

A single page personal site on AWS, built the [Cloud Resume Challenge](https://cloudresumechallenge.dev/)
way. Static files on S3 behind CloudFront, every AWS resource declared in Terraform, and deploys that
happen by pushing to `main` with no long lived AWS credentials anywhere.

**Status: Phase 1 complete.** The site is live over HTTPS on the apex and `www`, the bucket is
private, and the only way to publish is `git push`. The visitor counter is Phase 2 and is not built
yet.

## Architecture

What exists today:

```
push to main ──▶ GitHub Actions
                   │  OIDC → AWS, no stored keys
                   └── sync client/ → S3, then invalidate CloudFront

Route 53 ──▶ CloudFront ──▶ S3 (private bucket)
             ACM cert       reachable only through
             HTTPS, OAC     Origin Access Control
```

Planned, in phase order:

```
CloudFront /api/* ──▶ API Gateway (HTTP API)
                        └──▶ Lambda (Go, provided.al2023, arm64)
                               └──▶ DynamoDB (on demand, atomic ADD)

CloudWatch alarms ──▶ SNS ──▶ email
```

Home region is `us-east-2`. Route 53 and CloudFront are global. The ACM certificate is the one
exception: CloudFront reads certificates only from `us-east-1`, so Terraform declares a second
provider aliased to that region, used by the certificate and nothing else.

`terraform apply` runs locally, not in CI. A second workflow with permission to change
infrastructure buys little on a repo with one committer, and it would need a far broader role than
the deploy uses. That moves to CI in Phase 4, where the back end pipeline needs it anyway.

## Layout

| Path | Contains |
|---|---|
| `client/` | HTML, CSS, vanilla JS, `resume.pdf`, OG card. No framework, no build step. |
| `infra/` | Terraform. One state, remote in S3, covering the site stack and later the counter. |
| `.github/workflows/` | `deploy-site.yml`, path filtered to `client/**`. |

## Design decisions

The choices worth defending, and why.

**The S3 bucket is never public.** CloudFront signs its origin requests through Origin Access
Control, and the bucket policy grants read access to the CloudFront service principal with an
`AWS:SourceArn` condition pinning it to this one distribution. Without that condition the policy
would let any distribution in any AWS account read the bucket. A public bucket would be simpler and
would mean anyone who learns the bucket name bypasses the CDN entirely: no caching, no HTTPS
enforcement, no access logs, and an origin reachable directly.

**The policy grants `GetObject` and not `ListBucket`.** Nobody can enumerate the bucket through
CloudFront. The visible cost is that a mistyped URL returns 403 rather than 404, because S3 will not
confirm that an object is absent to a caller who cannot list.

**The hosted zone is a data source, not a resource.** Route 53 created it at registration and the
`.dev` registry delegates to its nameservers. Declaring it would create a second zone, with
different nameservers, that nothing on the internet points at. Terraform would report success and
the site would resolve to nothing.

**The OIDC provider is also read only.** IAM allows one provider per issuer URL per account and
sibling repos already deploy through it, so owning it here would mean a `terraform destroy` in this
project silently breaking their pipelines. Terraform ownership follows the lifecycle of the thing,
not the convenience of whichever config needs it.

**The deploy role's trust policy pins the `sub` claim to this repository and the `main` branch.**
Omit it and any workflow in any public repository on GitHub can assume the role. The claim uses
GitHub's immutable form, which embeds the numeric owner and repository IDs, so it keeps working
across a rename and cannot be inherited by whoever claims the old name.

**The role can publish the site and cannot read it back.** No `s3:GetObject`, because nothing in the
workflow needs it.

**`resume.pdf` is uploaded separately with an explicit `Content-Type`.** `aws s3 sync` applies one
type to every object it touches, so a per file type is impossible inside the sync. Left to guess,
the type comes from the runner's mimetypes database rather than from anything in this repo, and a
wrong guess turns "View Resume" into a download prompt.

**Terraform, not SAM**, with remote state in S3 and native state locking.

Planned, and stated here because they shape the design already:

**The counter will be a single `UpdateItem` with an atomic `ADD`**, not a read followed by a write.
Under concurrent visitors the read modify write version drops counts, because two requests can read
the same value before either writes.

**The DynamoDB client will sit behind a Go interface**, so the handler unit tests against a fake with
no AWS calls and no network.

**Go rather than Python**, using `aws-sdk-go-v2` on the `provided.al2023` runtime targeting arm64.

**CORS will be locked to this site's own origin**, never `*`.

## Deploying

Pushing to `main` with changes under `client/**` deploys the site. There is nothing to run locally.

Infrastructure changes are applied by hand:

```bash
cd infra
terraform init      # once
terraform plan -out=tfplan
terraform apply tfplan
```

Expect a first apply to take 10 to 25 minutes. Certificate validation waits on DNS propagation, and
a CloudFront distribution takes about ten minutes on its own to reach every edge location.

## The resume

`client/resume.pdf` is generated, not hand edited. The source is LaTeX, adapted from the
[Jake Gutierrez template](https://github.com/jakegut/resume), and builds with
[Tectonic](https://tectonic-typesetting.github.io/), which fetches only the packages the document
needs and caches them.

The document is tuned to fit exactly one page with no slack, and the spacing macros carry negative
values that cancel LaTeX's list defaults rather than tightening them. Removing the defaults makes
those negatives eat real content, and the build reports no error while lines overlap. Check the
rendered page, not the page count.

The filename never changes. LinkedIn and the site's own CTA both point at it.

## Cost

About fifty cents a month at rest, which is the Route 53 hosted zone. S3, CloudFront, and the
certificate round to nothing at this traffic, and alias record queries to AWS targets are not
billed. The domain is roughly $17 a year.

An AWS Budget is set at $5 a month, account wide and unfiltered, alerting at 80% of actual spend and
100% of forecast. It is deliberately not scoped to this project's services, since a budget's job is
to catch what you did not anticipate. The known cost of that choice is the annual domain renewal
tripping it once a year.

## Roadmap

- **Phase 1** — *complete.* Single page front end, S3 + CloudFront + OAC + ACM + Route 53 in
  Terraform, deploy workflow on OIDC.
- **Phase 2** Counter back end. DynamoDB, Go Lambda, API Gateway HTTP API, unit tests against a fake.
- **Phase 3** Integration. JS fetches and renders the count, CORS locked down, Playwright end to end
  test against production.
- **Phase 4** CI/CD hardening. Plan on PR, apply on merge, e2e gating the deploy, CloudWatch alarms
  to SNS.
- **Phase 5** Write up published, with the architecture diagram.

## Related repositories

- [inference-gateway](https://github.com/Go-Santiago-Go/inference-gateway) — LLM gateway in Go:
  streaming, rate limiting, cost metering
- [go-rag-api](https://github.com/Go-Santiago-Go/go-rag-api) — hybrid search RAG service on AWS
- [retrain-pipeline](https://github.com/Go-Santiago-Go/retrain-pipeline) — training and governance
