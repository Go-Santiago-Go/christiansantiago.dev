# Operations

What this stack costs, what it tells you when it breaks, and what has actually been measured on it.

## Verifying a deploy is healthy

The pipeline already does this: both deploy workflows end in the Playwright job, and a deploy that
fails it is a failed deploy. By hand, the same three checks:

```bash
curl -sI https://christiansantiago.dev | head -1          # 200, over HTTPS
curl -s  https://christiansantiago.dev/api/count          # {"count":N}, N larger than last time
make e2e                                                  # the number reached the page
```

The third is the only one that proves the feature works. The count exists in the DOM only after
JavaScript has run, so a `curl` against the API can succeed while the page still shows the em dash it
ships with.

Checking that the resume renders rather than downloads is worth doing after any change to the deploy
workflow:

```bash
curl -sI https://christiansantiago.dev/resume.pdf | grep -i content-type
# content-type: application/pdf
```

`binary/octet-stream` here means the sync picked the file up instead of the explicit `aws s3 cp`
step, and browsers will download the resume rather than open it.

## Alarms

Three CloudWatch alarms on the counter, all reporting to one SNS topic and from there to email.

| Alarm | Fires when | Why that threshold |
|---|---|---|
| `-errors` | Any error in five minutes | The handler's only failure path is DynamoDB, so one is already news. This is the only alarm with an OK action, because it is the only one that means the site is currently broken. |
| `-latency-p95` | API p95 over 2s across two windows | A cold start is 1,364 ms and healthy. One window would alarm on it. |
| `-invocation-spike` | Over 500 invocations in five minutes | An order of magnitude under the stage throttle's ceiling, well above anything a shared LinkedIn post produces. |

All three set `treat_missing_data = "notBreaching"`, and that is the setting worth understanding. A
five minute window with no visitors produces no datapoint rather than a zero, and CloudWatch's default
for a gap is to hold the alarm's previous state. On a site this quiet, the default leaves an alarm
reporting something it decided hours ago.

The latency alarm reads `Latency` rather than `IntegrationLatency`, because it includes API Gateway's
own overhead and is therefore what the visitor actually waits.

The email subscription is confirmed out of band. Terraform creates it and reports success, and it
delivers nothing until the link AWS sends is clicked.

## Cost

About fifty cents a month at rest, which is the Route 53 hosted zone. S3, CloudFront, and the
certificate round to nothing at this traffic, and alias record queries to AWS targets are not billed.
The domain is roughly $17 a year.

Nothing in the counter bills while idle: on demand DynamoDB, a Lambda that scales to zero, an HTTP
API charged per request, and a log group with 14 day retention.

At list prices checked in July 2026 for `us-east-2`, ignoring free tiers, one visit costs about
**$3.03 per million requests**:

| Component | Rate | Per request |
|---|---|---|
| CloudFront HTTPS request | $0.0100 per 10,000 | $1.000e-6 |
| API Gateway HTTP API | $1.00 per million | $1.000e-6 |
| DynamoDB write request unit | $0.625 per million | $0.625e-6 |
| Lambda request | $0.20 per million | $0.200e-6 |
| CloudWatch Logs ingestion, about 0.4 KB | $0.50 per GB | $0.200e-6 |
| Lambda duration, 128 MB, 5 ms billed, arm64 | $0.0000133334 per GB-s | $0.008e-6 |
| **Total** | | **$3.03e-6** |

Three things that table says, and each one changed a decision here:

- **Running the code is 0.27% of the cost of serving the request.** The rest is transport, routing,
  storage, and logging. Optimising the handler would be optimising the cheapest line.
- **CloudWatch ingestion costs 24 times the Lambda duration**, on Lambda's automatic `START`, `END`,
  and `REPORT` lines alone. The 14 day retention on the log group is a cost control, not
  housekeeping.
- **CloudFront and API Gateway together are 65% of the bill**, and neither does anything but move
  bytes.

Two earlier decisions are visible in it. The HTTP API over a REST API saves $2.50 per million.
DynamoDB's on demand price was cut 50% in November 2024, so the write row would read $1.25 under the
old rates.

The alarms are free: CloudWatch bills standard alarms past the first ten, and there are three.

An AWS Budget is set at $5 a month, account wide and unfiltered, alerting at 80% of actual spend and
100% of forecast. It is deliberately not scoped to this project's services, since a budget's job is
to catch what you did not anticipate. The known cost of that choice is the annual domain renewal
tripping it once a year.

## Performance

Every number here comes from a named measurement rather than an estimate. Lambda figures are read
from the CloudWatch `REPORT` line, client figures from `curl -w %{time_total}`.

| | Measured |
|---|---|
| Init duration, cold | **91 ms** (n=2) |
| Invocation duration, cold | **1,364 ms** and 1,273 ms (n=2) |
| Invocation duration, warm | **p50 5 ms**, p95 19 ms, min 3.9 ms (n=41) |
| Max memory used | 34 to 36 MB of 128 MB |
| Deployment package, stripped | **4.5 MB**, from a 13.4 MB binary |
| Counter latency through CloudFront | p50 241 ms, p95 379 ms (n=15) |
| Counter latency direct to `execute-api` | p50 162 ms, p95 265 ms (n=15) |

Reproduce the Lambda side by invoking the endpoint and reading the log group:

```bash
curl -s https://christiansantiago.dev/api/count
aws logs tail /aws/lambda/christiansantiago-dev-counter --since 5m | grep REPORT
```

Four readings out of that table are worth stating plainly.

**The Go runtime is 6.7% of the cold path.** Init is 91 ms against a first invocation of 1,364 ms.
Whatever a cold start costs here, it is almost entirely not the language, which is the opposite of
what the runtime choice is usually argued about.

**What the remaining 1.3 seconds is spent on is a hypothesis, not a measurement.** It is inside the
handler's first DynamoDB call. Likely causes are DNS, the TLS handshake to the regional endpoint, and
SDK endpoint resolution, none of which has been isolated. Timing the call's phases would settle it.

**Same origin costs about 80 ms at p50.** The `/api/*` behaviour is uncacheable by design, so the
edge adds a hop and can never save one. The minimum through CloudFront is *lower* than the minimum
direct, which is the edge being nearer the client on a warm connection, so a visitor far from
`us-east-2` may see the opposite result. Measured from one location, so it is a local comparison
rather than a general one.

**Memory is already at the floor.** 36 MB used against a 128 MB allocation, and 128 MB is the
smallest setting Lambda offers. There is nothing to tune downward.

## Failure modes

### The counter shows an em dash

The page is fine and the number never arrived. Work outward:

```bash
curl -s https://christiansantiago.dev/api/count                       # through CloudFront
curl -s "$(terraform -chdir=infra output -raw counter_url)"           # direct to the API
aws logs tail /aws/lambda/christiansantiago-dev-counter --since 15m
```

If the direct URL works and the site URL does not, it is the `/api/*` behaviour: check that the
origin request policy is still `Managed-AllViewerExceptHostHeader`, since `execute-api` rejects the
site's domain in `Host` as an unknown host.

If both fail with a `500`, the handler logged the cause. The response deliberately does not carry it.

### The counter is stuck at one number

The edge is caching it. The behaviour on `/api/*` must use `Managed-CachingDisabled`; under the
site's optimised policy the first response is held and served to everyone while DynamoDB increments
correctly behind it.

```bash
curl -sI https://christiansantiago.dev/api/count | grep -i x-cache
# x-cache: Miss from cloudfront
```

Anything other than a miss on this path is the bug.

### Everything returns 403

Origin access is broken rather than the site being down. Either the bucket policy lost its
`AWS:SourceArn` condition, or the Origin Access Control stopped signing. A 403 on one specific path
is different and usually correct: a missing object returns 403 rather than 404 because the policy
grants no `ListBucket`.

### The site serves an old page

The invalidation returns as soon as CloudFront accepts it, not once every edge has caught up. The
Playwright suite retries twice in CI for this reason. If it persists past a few minutes, check that
the deploy job actually ran: a commit touching only `infra/**` does not republish the site.

### Alarms are silent during a real outage

Check the SNS subscription is `Confirmed` rather than `PendingConfirmation`.

```bash
aws sns list-subscriptions-by-topic \
  --topic-arn "$(aws sns list-topics --query "Topics[?contains(TopicArn,'christiansantiago-dev-alerts')].TopicArn" --output text)"
```

## Honest constraints

**The counter counts requests, not people.** Reloads count again, the end to end test counts itself
on every deploy, and any bot that executes JavaScript is included. It is a Cloud Resume Challenge
tradition rather than an analytics product, and reading it as traffic would be wrong.

**Counting unique visitors was declined on privacy grounds, not on difficulty.** Deduplication needs
something that identifies a returning person: a cookie, a device fingerprint, or a hashed IP address.
All three are personal data under GDPR and the CPRA regardless of how the value is stored, so doing
it properly means a lawful basis, a consent banner for a site that currently sets no cookies, a
stated retention period, and a way to honour a deletion request. That is a real obligation, and it
buys a vanity number. The counter stores one integer and nothing about who incremented it, which is
the version of this feature that needs no privacy policy to be honest.

**One item, one partition, roughly 1,000 writes per second.** The ceiling is accepted rather than
sharded, and it is several orders of magnitude above anything this site will see.

**There is no staging environment.** `main` deploys to production, and the end to end test runs
after the deploy rather than before it, so it catches a broken deploy rather than preventing one. The
window is the minute or two between the sync and the assertion. A staging distribution would close it
and would double the infrastructure for a single page site.

**The end to end suite is one assertion.** It proves the counter rendered, which is the one thing
that no other test in the repository can see. It does not check layout, links, or the resume.

**CloudFront access logs are off**, so there is no request level view of static traffic and no
measured cache hit ratio. Turning them on means an S3 bucket that grows and bills forever, for a site
whose traffic question is answered by the counter.

**No WAF, and no bot filtering.** The stage throttle is the only rate control, and it is a cost
ceiling rather than a security control. WAF starts at roughly $5 a month, which is ten times what
this stack costs at rest.
