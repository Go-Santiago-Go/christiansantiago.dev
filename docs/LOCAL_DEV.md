# Local development

The site has no build step, so the local loop is opening a file. The counter is a Lambda, so the
local loop for it is the test suite rather than a running process. Both are deliberate, and the
second one is the part worth explaining.

## What you need

| Tool | Version | Needed for |
|---|---|---|
| Go | 1.26 or newer, per `counter/go.mod` | Building and testing the counter |
| Terraform | 1.15.5 in CI, 1.10 or newer locally | `make plan`, `make apply` |
| Node | 22 | The Playwright suite in `e2e/` |
| AWS credentials | An account you own | Anything that touches AWS. Nothing local needs them. |

## Run it

```bash
git clone https://github.com/Go-Santiago-Go/christiansantiago.dev.git
cd christiansantiago.dev

make test                            # go test -race -cover ./... in counter/
python3 -m http.server -d client 8000  # the site, at http://localhost:8000
```

Any static server works, including opening `client/index.html` directly. The page is plain HTML, CSS,
and vanilla JavaScript, and nothing compiles it.

The counter will not resolve locally, and that is worth seeing once. `/api/count` exists only through
CloudFront, so the fetch fails, the console logs it, and the footer keeps the em dash the markup
ships with. That em dash is the designed failure state: the page stays complete, and the end to end
test in `e2e/` is what notices the number never arrived.

## Development commands

`make` with no target lists nothing; the targets are short enough to read in the
[Makefile](../Makefile).

| Command | What it does |
|---|---|
| `make test` | `go test -race -cover ./...`. `-race` is the point: the counter's whole claim is that concurrent visitors cannot corrupt it. |
| `make counter` | Cross compiles the Lambda binary to `counter/bin/bootstrap`. |
| `make fmt` | `go fmt` and `terraform fmt`. CI checks the Terraform half with `-check`. |
| `make plan` | Builds the binary, then `terraform plan`. |
| `make apply` | Builds the binary, then `terraform apply`. |
| `make e2e` | Playwright, against the deployed site. |
| `make destroy` | Tears the stack down. See [DEPLOYMENT.md](DEPLOYMENT.md#teardown). |

`plan` and `apply` depend on `counter` because Terraform packages the binary and cannot compile it.
The `archive_file` data source reads the file during plan, so a missing binary fails the plan rather
than surviving to the apply.

## Testing the counter

Two packages, both tested against fakes with no AWS client in the process.

```bash
make test
go test -C counter -cover ./internal/visits   # the write, in isolation
```

`internal/visits` is at 100% statement coverage, which is a small claim about a small package. The
tests worth reading are the two that make the design argument:

- `TestIncrementSendsOneAtomicAdd` asserts the update expression itself, so the atomicity cannot be
  refactored away by someone who does not know why it is there.
- `TestAtomicAddKeepsEveryVisit` and `TestReadModifyWriteLosesVisits` run 500 concurrent callers
  through the real counter and through a read modify write imitation of it. The first records 500 of
  500, the second records 2 of 500. Both are clean under `-race`, which is the uncomfortable part:
  the losing version locks each half of its own operation, so the detector has nothing to report
  while 99.6% of the writes disappear.

The handler cannot be run locally. `provided.al2023` supplies an OS and no language runtime, and the
function is started by the Lambda runtime API rather than by a `main` you can curl. Emulating that
locally is possible and buys nothing here: the handler is thin orchestration over an interface, and
its two tests cover the success path and the error path against a fake. The deployed path is verified
by the end to end test instead.

## The end to end test

```bash
npm --prefix e2e ci      # first run only
make e2e                 # runs against https://christiansantiago.dev
SITE_URL=https://staging.example.com make e2e
```

The suite holds no credentials and takes the site over its public URL the way a visitor does, which
is the whole point: it exercises CloudFront, the `/api/*` behaviour, API Gateway, and the Lambda
together. It asserts the shape of the count rather than a value, because its own page load increments
the counter and any exact number is stale before the assertion runs.

Chromium and the system libraries it links against are a separate install:

```bash
npx playwright install chromium
sudo npx playwright install-deps chromium
```

Under WSL, `sudo` resets `PATH` and finds the system Node rather than an nvm one, so the second
command wants `sudo env "PATH=$PATH"` in front of it.

`e2e/` carries its own `package.json`, and that does not give the site a build step. Nothing in that
directory is ever uploaded: the deploy is a byte for byte sync of `client/`.

## The resume PDF

`client/resume.pdf` is generated, not hand edited. The source is LaTeX, adapted from the
[Jake Gutierrez template](https://github.com/jakegut/resume), and builds with
[Tectonic](https://tectonic-typesetting.github.io/), which fetches only the packages the document
needs and caches them. The `.tex` source and its build script are kept outside this repository with
the other working notes, so the PDF is committed and the source is not.

Two things to know before editing it:

- **The spacing macros carry negative values that cancel LaTeX's list defaults rather than tightening
  them.** Remove the defaults and those negatives start eating real content. The build reports no
  error, the page count still says one page, and lines overlap.
- **Check the rendered page, not the page count.** "One page" is a proxy for "fits on one page
  legibly", and the proxy passes while the real property fails.

The filename never changes. LinkedIn and the site's own call to action both point at it, and the
deploy uploads it separately so its `Content-Type` is stated rather than guessed.

## A local gotcha

`terraform plan` will not run against a fresh clone until the Lambda binary exists, and the error
names the archive data source rather than the binary. `make plan` builds it first, which is why the
Makefile exists at all. Running `terraform -chdir=infra plan` by hand skips that step.
