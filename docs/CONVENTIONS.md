# Conventions

Rules for changing this repository's documentation and for the claims it makes. Code conventions are
the Go defaults plus `go vet`, and `terraform fmt -check` in CI; these are the ones a linter cannot
enforce and that have been gotten wrong before.

## Accuracy guards

Claims in the docs must match the code and the measurements.

**This is a static site with one small API, and the vocabulary has to stay that way.** It is not a
"web app", the counter is not a "microservice", and the Lambda is not a "backend service". The
architecture is a CDN in front of a private bucket plus one request driven function. Overselling it
invites interview questions the design cannot answer, which is a worse outcome than describing it
plainly.

**No number appears without a stated method.** Every figure in these docs carries where it came from:
a CloudWatch `REPORT` line, a `curl` loop with its sample size, a published price list. A number that
cannot be traced to one of those does not go in the README, the docs, the site, or a resume bullet.

**The cold start attribution is a hypothesis and must be labelled as one.** Measured: init is 91 ms
and the first invocation is 1,364 ms. Inferred: the remaining 1.3 seconds is spent inside the first
DynamoDB call, on DNS, the TLS handshake, and endpoint resolution. Nothing has isolated those phases,
so no sentence may state them as measured.

**The CloudFront hop is a local comparison, not a general one.** Roughly 80 ms at p50, n=15, from one
client location. The minimum through CloudFront was lower than the minimum direct, so a visitor
elsewhere may see the opposite. Any sentence claiming same origin routing is slower *in general* is
false.

**The end to end test asserts a shape, never a value.** Its own page load increments the counter, so
an exact number is stale before the assertion runs. Do not describe it as checking the count.

**The counter counts requests to `/api/count`.** Not visitors, not humans. Reloads, the end to end
test on every deploy, and any bot that runs JavaScript are all included.

**The plan role is read only, and that claim rests on two things together**: the AWS managed
`ReadOnlyAccess` policy, and the workflow running `plan` with `-lock=false`. Drop the flag and the
role needs write access to the lock object, and the sentence stops being true.

**The apply role is least service, not least privilege, and the docs say so out loud.** It permits
every action within eleven services, plus IAM confined to the `christiansantiago-dev-*` prefix. The
real control is the trust policy admitting exactly one ref. Softening this into "least privilege
throughout" would be the kind of claim an interviewer opens the file to check.

**`terraform destroy` does not remove the hosted zone or the OIDC provider.** Both are data sources,
owned elsewhere on purpose. Any teardown instruction implying a clean slate is wrong.

## Generated artifacts

**`client/resume.pdf` is generated, not hand edited.** The LaTeX source lives outside this repository
with the other working notes, so the PDF is committed and the source is not. The filename never
changes, because LinkedIn and the site's own call to action point at it. It is uploaded outside the
`aws s3 sync` step so its `Content-Type` is stated rather than guessed, and moving it back into the
sync silently turns "View Resume" into a download prompt.

**`docs/demo.png` is captured from the live site, never hand assembled.** A Playwright script drives
a real browser at the deployed page, waits for the counter to replace its em dash, and stacks the
hero shot over the footer shot. The visit count visible in it is that run's own, produced by the page
load that took the screenshot.

- Never hand edit it.
- Never describe it with numbers it does not show. The count in the README's alt text and caption
  comes from the run that produced the current file.
- The caption must keep saying the two panels are stitched. They are one page load and not one
  screenshot, and letting that drift turns an honest composite into a claim the page is short.
- A change to `client/` makes it stale, and nothing in the tree will say so.
- The script lives in `content/demo-capture/`, which is gitignored. If it is unavailable, flag the
  image as stale rather than editing the caption to match a layout the image no longer shows.

## Documentation layout

The docs are split by audience. **`README.md` is the overview and stays short.** Depth lives here:

| File | Scope |
|---|---|
| `docs/ARCHITECTURE.md` | The two request paths, the atomic write, the interface seam, why the counter is same origin, and what the shape rules out |
| `docs/API.md` | The counter endpoint, status codes, throttling, caching, and the static surface's two surprising behaviours |
| `docs/LOCAL_DEV.md` | Running the site and the tests locally, the Playwright suite, and building the resume PDF |
| `docs/DEPLOYMENT.md` | What Terraform provisions, the first apply, the three CI roles and their trust model, teardown, troubleshooting |
| `docs/OPERATIONS.md` | Verifying a deploy, the alarms, the cost model, measured performance, failure modes, honest constraints |
| `docs/CONVENTIONS.md` | This file |

**`docs/API.md` occupies the slot the sibling repos give to an HTTP service's reference.** The
surface here is one endpoint rather than a product, so the file also covers the static paths. The
slot's job is the same in all four repos: the complete surface a caller can touch.

**Architecture is the request path; deployment is the cloud.** What Terraform provisions belongs in
`DEPLOYMENT.md`, not in `ARCHITECTURE.md`, even though both describe AWS resources.

**When a README section grows past a few paragraphs, move it into the matching file above and leave a
link.** Do not let the README reabsorb depth. The alarm table, the cost model, and the resume build
notes all lived in the README once and all belong in `docs/`.

## The README spine

`README.md` follows a fixed section order, shared across the portfolio repos so they read as one body
of work. Do not rename or reorder these, and do not insert new top-level sections between them:

```
title + badges + what it is → Contents → Demo → The problem → How it works → Quickstart
→ Trade-offs → Results → What I'd do differently → Known gaps and next steps
→ Repo layout → Documentation → License
```

The narrative arc under those names is **problem → approach → trade-offs → results → hindsight**. A
section that does not advance that arc belongs in `docs/`. The phase roadmap and the sibling
repository links were both cut for that reason: the phases live in the build plan, and the site
itself is where the portfolio links belong.

Rules specific to the spine:

- **`Results` ships only if it contains a number a reader could reproduce.** Here that is `make test`
  for the concurrency figures, and an invocation plus `aws logs tail` for the runtime ones. Prices
  and derived arithmetic are prose or a clearly labelled cost table, never rows in the measured
  table.
- **`What I'd do differently` is hindsight; `Known gaps and next steps` is scope.** They are
  different claims and must not be merged. Folding a deliberate scoping call into the hindsight
  section turns a defensible decision into an apparent regret, and the reverse hides a real mistake
  behind "out of scope".
- **`Repo layout` is a table, not an ASCII tree**, and ends at the table with no trailing prose.
- **`Trade-offs` is a four column table: `Decision`, `Choice`, `Why`, `Also considered`.** `Decision`
  names the *concern* rather than the answer, so the column reads as a list of questions a reviewer
  could ask. A `Why` cell is one sentence; if the reasoning needs a paragraph it belongs in `docs/`
  with the cell pointing there. The `Also considered` column is not optional, because a decision with
  no stated alternative has not been shown to be a decision.
- **Section shape is shared across the portfolio repos, not just section names.** `The problem` ends
  in a bulleted list of requirements, each naming what it costs to get wrong. `How it works` opens
  the diagram, then bolded lead-ins, then the interface table, then the deployed shape. `Trade-offs`
  closes with the pattern under the decisions and a one sentence stack summary. `Results` leads with
  a measured table and how to reproduce it. `What I'd do differently` opens by stating how many
  things and that they are hindsight rather than parked work. **`Known gaps and next steps` is bolded
  lead-in paragraphs, never a bullet list**, and closes with a single `Also parked:` sentence
  sweeping up the items too small for their own paragraph.
- **Tables whose first column is a label, not a category, take an empty header row (`| | |`).** The
  `Contents` table and the `Results` measured table both do this.

## Writing rules

- **Never link the README or `docs/` to anything in `content/` or `notes/`.** Both directories are
  gitignored, so those links 404 for anyone reading the repo on GitHub. They hold unpublished drafts,
  measurement logs, and personal career notes, and none of it is staged or committed.
- **Diagrams are Mermaid, single-direction, with no back edges.** If a diagram needs to show two
  concerns, make it two diagrams. ASCII art was replaced for a reason: it does not survive being
  edited.
- **No `classDef`, `style`, or `linkStyle` blocks in any diagram, without exception.** Mermaid on
  GitHub inherits the reader's light or dark theme; hardcoded fills do not, so a palette tuned on a
  white background renders as glaring white boxes in dark mode. Meaning goes in the shape and the
  edge, not the colour.
- **A diagram's edges carry what crosses them.** A signed origin request, a path forwarded unchanged,
  an update expression. An unlabelled arrow has said only that two boxes are adjacent.
- **No em dashes as sentence breaks**, and no hyphenation except in compound words. Prose here uses
  commas and full stops, and the site's own markup is the only place an em dash belongs.
- **British spellings, because the existing prose and the Terraform comments already use them**:
  behaviour, optimised, recognises. Consistency matters more than the choice.
- **The name is `christiansantiago.dev` everywhere**: repo, Go module path, README title, doc titles,
  and the AWS resource prefix `christiansantiago-dev-`. The site is never "the portfolio site" in
  prose that a stranger will read.
- **Badges point at workflows that exist.** This repo has `deploy-site.yml` and `infra.yml`. The
  `e2e.yml` workflow is `workflow_call` only, so it has no status of its own and gets no badge.
- **Verify fast-moving service shapes against live documentation** rather than memory, then write
  what you verified. CloudFront managed policy names, the API Gateway payload format versions, and
  GitHub's immutable OIDC subject claims have all moved under this project.
