# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Current state

**No code exists yet.** This directory contains only the build plan (`build-plan.md`) and is not a git
repository. Phase 1 has not started.

`build-plan.md` is the authoritative spec — read it before making changes. It is phased, and the phases
are a deliberate cut line, not a wish list: **v1 ends at Phase 5 (the blog post)**. Phase 6 ("Ask my
resume" Bedrock Q&A) is explicitly deferred and must not be built before Phase 5 ships.

## What this is

A Cloud Resume Challenge build: a single-page personal site (Hero → About → Experience → Projects →
Resume → Contact) on S3 + CloudFront + Route53, with a serverless visitor counter, all Terraform, all
deployed by GitHub Actions with OIDC. It is the hub that ties the sibling portfolio repos together —
`../inference-gateway`, `../go-rag-api`, `../retrain-pipeline` — each of which gets a project card
that **leads with its headline metric**.

Ship the cards with honest current descriptions rather than blocking the launch on metrics that don't
exist yet; update them as numbers land. `retrain-pipeline` gets a card only once it has working code.

## Design reference

The site mirrors **https://www.johnjudge.me/** — treat it as the structural and visual source of truth
and re-check it before layout work. As of the last look, that site is a single page with anchor nav:

- Nav/section order: **About → Experience → Education → Projects → Resume → Contact**, preceded by a
  hero (name, title, short description, CTA buttons) and closed by a footer with copyright and repeated
  social links.
- **Experience** items: title, company, location, date range, then impact-focused bullets.
- **Project** cards: title, date range, description paragraph, a `Stack:`-labeled tech list, and links
  (GitHub, live demo where one exists).
- **Resume** section: a highlights block plus view/download options.
- Resume CTA appears in **three** places — header, hero, and footer.

**Decided: the Education section is in**, between Experience and Projects, matching the reference site.
`build-plan.md` omits it and places the resume CTA in the hero and nav only — the plan doc is stale on
both counts; follow the reference structure above.

The one intentional divergence from johnjudge.me: project cards **lead with the headline metric**.

## Planned structure

**Decided: one repo, not two.** `build-plan.md` inherits a frontend/backend repo split from the Cloud
Resume Challenge book; this project deliberately does not follow it. A split would mean two Terraform
states, two workflows, and a cross-repo step to feed the API URL into the front end — all overhead for
a single personal site, with no added interview signal. Treat the plan doc as stale on this point.

Layout: `frontend/` (HTML/CSS/JS, resume PDF) and `backend/` (Go Lambda) subtrees, with Terraform in
one state covering S3/CloudFront/Route53/ACM *and* API Gateway/Lambda/DynamoDB/CloudWatch.

Sibling repos share a convention worth matching: `cmd/` + `internal/` for Go, `infra/` or `terraform/`
for Terraform, `content/` for publishable write-ups, and a `CLAUDE.local.md` holding per-repo working
style that takes precedence for *how* to collaborate.

## Commands

None yet — nothing is scaffolded. The plan's per-phase acceptance checks define what the commands must
eventually satisfy:

```bash
go test ./...                        # Phase 2: covers the counter handler
curl https://api.yourdomain/count    # Phase 2: returns an incrementing JSON count
```

Terraform is the only way infrastructure gets created (see below), and deploys happen via `git push`,
not local `aws s3 sync`.

## Architecture (the big picture)

```
push to main ──▶ GitHub Actions (OIDC → AWS, no long-lived keys)
                   ├── terraform apply
                   └── sync site/ + CloudFront invalidation

Route53 ──▶ CloudFront (ACM cert, HTTPS, OAC) ──▶ S3 (private bucket)
                │ /api/*
                ▼
         API Gateway (HTTP API) ──▶ Lambda (Go, provided.al2023, arm64) ──▶ DynamoDB (on-demand)

CloudWatch alarms ──▶ SNS ──▶ email/Slack
```

**The bucket is never public.** CloudFront reaches S3 through Origin Access Control. "Public bucket vs.
OAC" is one of the blog post's talking points — don't shortcut it.

**The counter is a single atomic `UpdateItem` with `ADD`**, not read-modify-write. That's what makes it
idempotent and race-free under concurrent visitors, and it's the reason DynamoDB is the right store here.

**The DynamoDB client sits behind a Go interface** so the handler unit-tests against a fake with no AWS
calls — the same dependency-inversion pattern used in `../go-rag-api`.

## Key design decisions to preserve

- **Go, not Python** (the book suggests Python/boto3). `aws-sdk-go-v2` on `provided.al2023`/arm64. The
  Go custom-runtime cold-start story is a deliberate interview talking point.
- **Terraform, not SAM**, with remote state (S3 + lockfile).
- **OIDC from the first commit** — zero long-lived AWS keys, ever.
- **IaC and the deploy workflow land in Phase 1**, not as a retrofit ("Automation Nation" mod).
- **ACM cert for CloudFront must live in `us-east-1`** regardless of where everything else is. This is
  the single most common CRC failure.
- **CORS is locked to the site's own domain**, never `*`.
- **`resume.pdf` must be served with `Content-Type: application/pdf`** (set it in the Terraform/upload
  step) so browsers render it inline instead of downloading it. Keep the filename stable — external
  links (LinkedIn) depend on it.
- **No framework, no build step** for the front end — plain HTML/CSS/JS.
- **The site stays blog-free by design.** The Phase 5 write-up publishes to dev.to or Hashnode and is
  linked from the site.

## Cost discipline

Target is ≈$1.50–2/mo plus the domain. Set an AWS Budget alert at $5. Tear down billable experiments
after each session.
