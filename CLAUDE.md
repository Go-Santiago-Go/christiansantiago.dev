# CLAUDE.md

How to get this repository running and how to verify a change. Everything else lives in `docs/`; see
the map at the bottom.

`christiansantiago.dev` is a [Cloud Resume Challenge](https://cloudresumechallenge.dev/) build: a
single page static site on S3, served only through CloudFront with Origin Access Control, plus one
request driven API. That API is `GET /api/count`, an HTTP API in front of a Go Lambda that increments
a visit count with a single atomic DynamoDB `ADD` and returns the new value. Every AWS resource is
Terraform in one state, and `git push` is the only way anything reaches production. It is a static
site with one small API, and the docs deliberately never call it a web app or the counter a
microservice.

## Run it

There is no build step and no local server for the counter. Needs Go for the tests and any static
server for the page.

```bash
make test                              # go test -race -cover ./... in counter/
python3 -m http.server -d client 8000  # the site, at http://localhost:8000
```

The counter will not resolve locally. `/api/count` exists only through CloudFront, so the fetch
fails, the console logs it, and the footer keeps the em dash the markup ships with. That is the
designed failure state, not a bug to fix.

`make` targets are short enough to read in the [Makefile](Makefile). The verbs (`test`, `plan`,
`apply`, `destroy`) are the same in every repo in this portfolio.

## Verify a change

What CI runs, and what should pass before any commit:

```bash
make test                            # -race is the point: the counter's claim is concurrency safety
terraform -chdir=infra fmt -check -recursive
make plan                            # builds the Lambda binary, then plans
```

The Go tests need no cloud access. `internal/visits` runs against a fake `Updater` and the handler
against a fake counter, which is the payoff of the interface boundaries in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

Narrower loops while working:

```bash
go test -C counter ./internal/visits
go test -C counter -run TestAtomicAddKeepsEveryVisit ./internal/visits
```

Anything touching the deployed page needs the smoke test, because the count exists in the DOM only
after JavaScript has run:

```bash
make e2e     # Playwright, against https://christiansantiago.dev
```

## Things that will waste your time

- **`terraform plan` fails on a fresh clone, and the error names the archive data source.** The
  Lambda binary does not exist yet. Terraform packages it and cannot compile it, which is why
  `make plan` and `make apply` build it first. Running `terraform -chdir=infra plan` by hand skips
  that step.
- **Never declare the Route 53 hosted zone as a resource.** The registrar created it and the `.dev`
  registry delegates to its nameservers. Declaring it creates a *second* zone with different
  nameservers: the apply succeeds, records land in the new zone, and the site resolves to nothing.
  The symptom points at CloudFront rather than at DNS bookkeeping.
- **The ACM certificate must stay in `us-east-1`.** CloudFront reads certificates from that region
  only, the home region here is `us-east-2`, and the error when it cannot find one does not mention
  regions. That is what the `aws.us-east-1` provider alias exists for, and nothing else uses it.
- **`resume.pdf` is uploaded outside the `aws s3 sync` step on purpose.** `sync` applies one
  `Content-Type` to everything it touches, so folding the PDF back in leaves the type to the runner's
  mimetypes database and turns "View Resume" into a download prompt. The filename never changes:
  LinkedIn points at it.
- **The `/api/*` behaviour needs both managed policies it has.** `Managed-CachingDisabled`, or the
  edge serves one frozen number to everyone while DynamoDB increments correctly behind it. And
  `Managed-AllViewerExceptHostHeader`, because `execute-api` routes on `Host` and rejects the site's
  domain as unknown.
- **Do not replace the atomic `ADD` with a read then a write.** It drops counts silently, and it does
  so while passing `-race`: `TestReadModifyWriteLosesVisits` records 2 of 500 concurrent visits with
  no data race reported. `TestIncrementSendsOneAtomicAdd` asserts the update expression so the design
  cannot be refactored away by accident.
- **A green `make test` has not seen the counter work.** The number only reaches the page through
  JavaScript, so neither the Go tests nor a `curl` against the API can see a dead counter. Only
  `make e2e` can.
- **`make e2e` needs Chromium and its system libraries.** `npx playwright install chromium`, then
  `sudo npx playwright install-deps chromium`. Under WSL, `sudo` resets `PATH` and finds the system
  Node rather than an nvm one, so the second command wants `sudo env "PATH=$PATH"` in front of it.
- **The CloudFront distribution ID is hardcoded in `deploy-site.yml`.** It is the one value that does
  not come from a Terraform output, so a deploy pointed at a new account invalidates the wrong
  distribution until it is changed. This is a known wart, named in the README.
- **`terraform destroy` leaves the hosted zone and the OIDC provider standing.** Both are data
  sources, owned elsewhere on purpose, and the bucket must be emptied before it will delete.
- **If you forked this, several identities are still mine.** The `module` line in `counter/go.mod`,
  the OIDC `sub` claim built from my numeric GitHub owner and repo IDs in `infra/variables.tf`, the
  `christiansantiago-dev-*` resource names, and the state bucket in `infra/versions.tf`.
- **Before writing docs, read [docs/CONVENTIONS.md](docs/CONVENTIONS.md).** It carries the accuracy
  guards, the README spine, and the rules for the generated artifacts, and each one is there because
  it was gotten wrong.

## Scope

- **v1 ends at the write-up.** The phased plan is a local working doc and is not committed. The
  phases are a cut line rather than a wish list, and the "ask my resume" question answering feature
  is deferred: do not start it, scaffold for it, or suggest starting it.
- **The site stays blog free by design.** The Cloud Resume Challenge write-up publishes to dev.to and
  is linked from the site. Any "add a blog" impulse is a stretch item.
- **Nothing may bill while idle.** The target is roughly $2 a month plus the domain, and at rest this
  stack is about fifty cents, which is the hosted zone. No provisioned throughput, no NAT gateways,
  no always on compute. Flag any resource with idle cost before creating it. An account wide AWS
  Budget alerts at $5.
- **No claim gets a number that has not been measured.** Not in the README, the docs, the site, or a
  resume bullet. See the accuracy guards in [docs/CONVENTIONS.md](docs/CONVENTIONS.md).

## The site itself

`client/` is plain HTML, CSS, and vanilla JavaScript with no framework and no build step, deployed as
a byte for byte sync. Single page, anchor nav, sections in this order: hero, About, Experience,
Education, Projects, Resume, Contact, footer. The resume call to action appears three times, in the
header, the hero, and the footer, and always opens `/resume.pdf` in a new tab.

The structure follows a reference site (`https://www.johnjudge.me/`) with one intentional divergence:
**project cards lead with their headline metric.** The cards point at the sibling portfolio repos,
`inference-gateway`, `go-rag-api`, and `retrain-pipeline`, and a card ships with an honest current
description rather than waiting on a metric that does not exist yet.

`client/main.js` is progressive enhancement throughout. The page is complete and readable with that
file blocked, and nothing in it creates content. Keep it that way: the reveal animation, the nav
state, and the counter all degrade to a plain, finished page.

## Where everything is

| Doc | Scope |
|---|---|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | The two request paths, why the count comes back from the write, the interface seam, same origin routing, what the shape rules out |
| [docs/API.md](docs/API.md) | The counter endpoint, status codes, throttling, caching, and the static surface's two surprising behaviours |
| [docs/LOCAL_DEV.md](docs/LOCAL_DEV.md) | Running the site and the tests locally, the Playwright suite, how the resume PDF is built |
| [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) | What Terraform provisions, the first apply, the three CI roles and their trust model, teardown, troubleshooting |
| [docs/OPERATIONS.md](docs/OPERATIONS.md) | Verifying a deploy, the alarms, the cost model, measured performance, failure modes, honest constraints |
| [docs/CONVENTIONS.md](docs/CONVENTIONS.md) | Documentation rules, the README spine, accuracy guards, generated artifacts |

| Path | Contents |
|---|---|
| `client/` | The site. HTML, CSS, vanilla JS, `resume.pdf`, and the OG card. Synced to S3 as is. |
| `counter/cmd/counter/` | The Lambda entry point. Response shaping, the request timeout, and the error path that logs rather than leaks. |
| `counter/internal/visits/` | The atomic `ADD`, the `Updater` interface it depends on, and the tests that make the concurrency argument. |
| `infra/` | Terraform, one state, remote in S3. Delivery, DNS and TLS, the counter, alarms and budget, and the three CI roles. |
| `e2e/` | The Playwright smoke test that runs against production. Development tooling, never uploaded with the site. |
| `.github/workflows/` | `deploy-site.yml` for `client/**`, `infra.yml` for the stack, `e2e.yml` called by both. |
| `Makefile` | Task runner. Builds the Lambda binary, which Terraform packages but cannot compile. |
