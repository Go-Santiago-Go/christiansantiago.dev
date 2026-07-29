# christiansantiago.dev

Live at **[christiansantiago.dev](https://christiansantiago.dev)**.

A single page personal site on AWS, built the [Cloud Resume Challenge](https://cloudresumechallenge.dev/)
way. Static files on S3 behind CloudFront, every AWS resource declared in Terraform, and deploys that
happen by pushing to `main` with no long lived AWS credentials anywhere.

**Status: Phase 2 complete.** The site is live over HTTPS on the apex and `www`, the bucket is
private, and the only way to publish is `git push`. The counter API is deployed and returns an
incrementing count. It is not yet reachable from the site's own domain, and the page does not call
it yet: both are Phase 3.

## Architecture

What exists today:

```
push to main ──▶ GitHub Actions
                   │  OIDC → AWS, no stored keys
                   └── sync client/ → S3, then invalidate CloudFront

Route 53 ──▶ CloudFront ──▶ S3 (private bucket)
             ACM cert       reachable only through
             HTTPS, OAC     Origin Access Control

CloudFront /api/* ──▶ API Gateway (HTTP API)
  caching disabled      GET /api/count
                          └──▶ Lambda (Go, provided.al2023, arm64)
                                 └──▶ DynamoDB (on demand, atomic ADD)
```

Planned, in phase order:

```
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
| `counter/` | The Go Lambda. `cmd/counter` is the Lambda entry point, `internal/visits` the DynamoDB logic. |
| `infra/` | Terraform. One state, remote in S3, covering the site stack and the counter. |
| `.github/workflows/` | `deploy-site.yml`, path filtered to `client/**`. |
| `Makefile` | Builds the Lambda binary, which Terraform packages but cannot compile. |

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

**The counter is a single `UpdateItem` with an atomic `ADD`**, not a read followed by a write.
`UpdateItem` sends an instruction rather than a value and DynamoDB evaluates it under a lock, so
concurrent callers queue instead of interleaving. The read modify write version drops counts because
two requests can read the same value before either writes, and it does so silently: nothing errors
and the number still goes up. A test asserts the update expression, so the design cannot be
refactored away by accident.

**The table holds one item and every write lands on one partition.** That caps throughput at roughly
1,000 writes per second. Write sharding across `site#0` to `site#9` would lift it and would cost a
ten item fan out on every read, forever, for headroom a personal site will never touch.

**The DynamoDB client sits behind a Go interface** declared in the package that consumes it, not the
one that implements it. Go interfaces are structural, so `*dynamodb.Client` satisfies a one method
interface without knowing it exists, and the handler tests against a fake with no AWS calls and no
network.

**Go rather than Python**, using `aws-sdk-go-v2` on the `provided.al2023` runtime targeting arm64.
Measured, init is 91 ms and the first invocation is 1,364 ms, so the language accounts for under 7%
of the cold path. The rest is the first DynamoDB call setting up a connection. Warm invocations
return in 5 ms.

**An HTTP API, not a REST API.** $1.00 against $3.50 per million requests, and none of the REST
features (usage plans, API keys, request validators) are used.

**Handler failures are returned as responses, not as Go errors.** Returning a non nil `error`
surrenders control of the status code and the body to API Gateway. The error detail goes to the log
and the caller gets a generic message, because DynamoDB errors carry table names and this endpoint
is public.

**The Lambda log group is declared in Terraform.** Left implicit, Lambda creates it on first
invocation with no expiry and outside Terraform's state, so the logs bill forever and survive a
`destroy`. Retention is 14 days, which is a cost control: CloudWatch ingestion costs about 24 times
the Lambda duration on this workload.

**The managed `AWSLambdaBasicExecutionRole` policy is not attached.** It grants
`logs:CreateLogGroup` across the account. Since Terraform creates the group, the function only needs
to write streams into its own.

**The counter is served from this domain through a CloudFront `/api/*` behaviour**, so the browser
makes no cross origin request and CORS is designed out rather than configured. Two settings carry
that behaviour. `Managed-CachingDisabled`, because under the site's caching policy the edge would
serve one frozen count to everyone while DynamoDB incremented correctly behind it. And
`Managed-AllViewerExceptHostHeader`, because `execute-api` routes on `Host` and rejects the site's
domain as unknown.

The honest cost is a hop. Measured from one location, the counter is about 80 ms slower at p50
through CloudFront than direct to `execute-api`, since the behaviour is uncacheable and the edge
therefore never saves a round trip. What it buys is no CORS policy, no second certificate, and no
custom domain on the API.

## Deploying

Pushing to `main` with changes under `client/**` deploys the site. There is nothing to run locally.

Infrastructure changes are applied by hand, through the Makefile. Terraform packages the Lambda
binary but cannot compile it, so anything reading the archive builds it first:

```bash
make test      # go test -race -cover ./...
make plan      # build the binary, then terraform plan
make apply     # build the binary, then terraform apply
```

Expect a first apply to take 10 to 25 minutes. Certificate validation waits on DNS propagation, and
a CloudFront distribution takes about ten minutes on its own to reach every edge location. The
counter resources are quick by comparison: all ten came up in under a minute.

The binary is cross compiled to a static arm64 executable named `bootstrap`, which is the filename
`provided.al2023` requires. `-trimpath -ldflags="-s -w"` halves the deployment package, and package
size gates cold start because the package is pulled before the process can start.

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

Nothing in the counter bills while idle. On demand DynamoDB, a Lambda that scales to zero, an HTTP
API charged per request, and a log group with 14 day retention. At list price a single visit costs
about $3.03 per million requests, of which the Lambda duration is 0.27%. The expensive parts are
CloudFront and API Gateway moving bytes, and CloudWatch storing log lines.

An AWS Budget is set at $5 a month, account wide and unfiltered, alerting at 80% of actual spend and
100% of forecast. It is deliberately not scoped to this project's services, since a budget's job is
to catch what you did not anticipate. The known cost of that choice is the annual domain renewal
tripping it once a year.

## Roadmap

- **Phase 1** — *complete.* Single page front end, S3 + CloudFront + OAC + ACM + Route 53 in
  Terraform, deploy workflow on OIDC.
- **Phase 2** — *complete.* Counter back end. DynamoDB, Go Lambda, API Gateway HTTP API, unit tests
  against a fake.
- **Phase 3** Integration. JS fetches and renders the count, Playwright end to end test against
  production.
- **Phase 4** CI/CD hardening. Plan on PR, apply on merge, e2e gating the deploy, CloudWatch alarms
  to SNS.
- **Phase 5** Write up published, with the architecture diagram.

## Related repositories

- [inference-gateway](https://github.com/Go-Santiago-Go/inference-gateway) — LLM gateway in Go:
  streaming, rate limiting, cost metering
- [go-rag-api](https://github.com/Go-Santiago-Go/go-rag-api) — hybrid search RAG service on AWS
- [retrain-pipeline](https://github.com/Go-Santiago-Go/retrain-pipeline) — training and governance
