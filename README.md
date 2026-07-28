# christiansantiago.dev

Personal site and portfolio hub, built as a [Cloud Resume Challenge](https://cloudresumechallenge.dev/)
implementation. Static single page on S3 behind CloudFront, a visitor counter served by a Go Lambda,
every AWS resource in Terraform, every deploy through GitHub Actions with OIDC.

**Status: Phase 1, in progress. Not yet deployed.**

## Architecture

```
push to main ──▶ GitHub Actions (OIDC → AWS, no long-lived keys)
                   ├── terraform apply
                   └── sync client/ + CloudFront invalidation

Route53 ──▶ CloudFront (ACM cert, HTTPS, OAC) ──▶ S3 (private bucket)
               │ /api/*
               ▼
        API Gateway (HTTP API) ──▶ Lambda (Go, provided.al2023, arm64) ──▶ DynamoDB (on-demand)

CloudWatch alarms ──▶ SNS ──▶ email
```

Home region is `us-east-2`. CloudFront and Route53 are global. The ACM certificate is the one
exception: CloudFront only reads certificates from `us-east-1`, so Terraform declares a second
provider aliased to that region for the certificate alone.

## Layout

| Path | Contains |
|---|---|
| `client/` | HTML, CSS, vanilla JS, `resume.pdf`. No framework, no build step. |
| `infra/` | Terraform. One state, covering the site stack and the counter stack. |
| `resume/` | Typst source for `client/resume.pdf`. |
| `notes/` | Canonical copy (`brand-spine.md`, `resume-source.md`) and post fodder. |
| `.github/workflows/` | Path-filtered deploy workflows, one minimally scoped OIDC role each. |

## The resume

`client/resume.pdf` is generated, not hand-edited. Source is `resume/resume.typ`, built with
[Typst](https://typst.app/docs/):

```bash
typst compile resume/resume.typ client/resume.pdf
```

Typst rather than LaTeX because it is a single binary with no TeX distribution behind it, and it
bundles New Computer Modern, so the document keeps the LaTeX look without the install. The layout
mirrors the [Jake Gutierrez template](https://github.com/jakegut/resume).

The document is tuned to fit exactly one page with no slack. Adding a bullet pushes it to two, so
trim something else in the same edit and check the page count before committing.

Bullet wording is not owned by this file. `notes/resume-source.md` is canonical for the resume, the
site, and LinkedIn together; edit there first, then propagate.

The PDF must be uploaded with `Content-Type: application/pdf` so browsers render it inline rather
than downloading it, and the filename never changes, because external links point at it.

## Design decisions

These are the choices worth defending, and the reasons they were made.

**The S3 bucket is never public.** CloudFront reaches it through Origin Access Control, so the
bucket policy grants access to the distribution rather than to the world. A public bucket would work
and would be simpler; it would also mean the origin is reachable directly, bypassing CloudFront's
TLS, caching, and logging.

**The counter is a single `UpdateItem` with an atomic `ADD`.** Not a read, increment, and write.
Under concurrent visitors the read-modify-write version drops counts, because two requests can read
the same value before either writes. `ADD` pushes the increment into DynamoDB itself, where it is
applied atomically.

**The DynamoDB client sits behind a Go interface**, so the handler unit tests against a fake with no
AWS calls and no network.

**Go, not Python.** The challenge suggests Python and boto3. This uses `aws-sdk-go-v2` on the
`provided.al2023` runtime targeting arm64.

**Terraform, not SAM**, with remote state in S3.

**OIDC from the first commit.** No long-lived AWS access keys exist anywhere, including in GitHub
secrets. Each workflow assumes a role scoped to what that workflow actually touches.

**CORS is locked to this site's own origin**, never `*`.

## Roadmap

- **Phase 1** Front end live. HTML/CSS single pager, S3 + CloudFront + OAC + ACM + Route53 in
  Terraform, deploy workflow. Done when the site loads over HTTPS on the domain and the only way to
  deploy is `git push`.
- **Phase 2** Counter back end. DynamoDB, Go Lambda, API Gateway HTTP API, unit tests.
- **Phase 3** Integration. JS fetches and renders the count, CORS locked down, Playwright end to end
  test against production.
- **Phase 4** CI/CD hardening. Plan on PR, apply on merge, e2e gates the deploy, CloudWatch alarms
  to SNS.
- **Phase 5** Write-up published, with the architecture diagram.

## Cost

Roughly $2/month plus the domain. Route53 hosted zone is $0.50/month; S3, CloudFront, Lambda, API
Gateway, and DynamoDB at personal-site traffic land in or near the free tier. An AWS Budget alert is
set at $5.

## Related repositories

- [inference-gateway](https://github.com/Go-Santiago-Go/inference-gateway) LLM gateway in Go:
  streaming, rate limiting, cost metering
- [go-rag-api](https://github.com/Go-Santiago-Go/go-rag-api) hybrid-search RAG service on AWS
- [retrain-pipeline](https://github.com/Go-Santiago-Go/retrain-pipeline) training and governance
