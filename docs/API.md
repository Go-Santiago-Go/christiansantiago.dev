# API reference

One endpoint, served from the site's own domain. There is no authentication, no request body, and no
versioning: the surface is a single counter that the page fetches on load.

| Surface | Origin | Notes |
|---|---|---|
| `GET /api/count` | API Gateway HTTP API, then Lambda | The counter. Never cached at the edge. |
| `GET /` and every other path | S3, private, through Origin Access Control | Static objects. Cached under `Managed-CachingOptimized`. |
| `GET /resume.pdf` | Same bucket | Uploaded separately so `Content-Type: application/pdf` is stated rather than guessed. |

## `GET /api/count`

Increments the site's visit count and returns the new value. There is no read only variant: asking
for the number is what increments it.

```bash
curl -s https://christiansantiago.dev/api/count
# {"count":1284}
```

### Request

No parameters, no headers, no body. Anything sent is ignored: the integration is `AWS_PROXY` with
payload format 2.0, and the handler unmarshals the request without reading a field from it.

### Response

```json
{ "count": 1284 }
```

`count` is a JSON number, and it is the value after this request's increment. It is `int64` in Go,
parsed from the decimal string DynamoDB returns.

`Content-Type: application/json` is set by the handler rather than by API Gateway.

### Status codes

| Code | Body | When |
|---|---|---|
| `200` | `{"count":N}` | The write succeeded. |
| `403` | CloudFront error page | A method other than `GET` or `HEAD`. The behaviour on `/api/*` allows those two and refuses the rest at the edge, so they never reach API Gateway. |
| `404` | `{"message":"Not Found"}` | Any path under `/api/` that is not `/api/count`. This is API Gateway's own response for an unmatched route, not the handler's. |
| `429` | `{"message":"Too Many Requests"}` | The stage throttle, 20 requests per second with a burst of 40. |
| `500` | `{"error":"could not record visit"}` | The DynamoDB call failed or timed out. The cause is in CloudWatch Logs and deliberately not in the response. |

The `500` body never carries the underlying error. DynamoDB failures name the table, and this
endpoint is public. `TestHandlerDoesNotLeakInternalErrors` asserts it.

### Throttling

The `$default` stage sets `throttling_rate_limit = 20` and `throttling_burst_limit = 40`. This is a
cost ceiling rather than a rate policy: the endpoint writes to DynamoDB on every hit, and the
throttle caps what an abusive caller can spend. Real traffic on a personal site is orders of
magnitude below it, so a `429` here means something is wrong rather than something is popular. The
invocation spike alarm fires well under the same ceiling. See [OPERATIONS.md](OPERATIONS.md#alarms).

### Caching

Never cached, by design. The behaviour uses `Managed-CachingDisabled`, so every request reaches the
origin and the response carries `x-cache: Miss from cloudfront`. A cached counter would serve one
frozen number to everyone while the table incremented correctly behind it.

The cost of that decision is a measured hop. See [OPERATIONS.md](OPERATIONS.md#performance).

### The direct URL

The function is also reachable at its `execute-api` hostname, which `terraform output counter_url`
prints. It is useful for isolating the API from CloudFront when something breaks, and it is not what
visitors use:

```bash
curl -s "$(terraform -chdir=infra output -raw counter_url)"
```

Requests through that URL increment the same counter. There is no separate environment.

## The static surface

Everything not under `/api/` is an object in the site bucket, reached only through CloudFront. Two
behaviours are worth knowing.

**A missing object returns `403`, not `404`.** The bucket policy grants `s3:GetObject` and not
`s3:ListBucket`, so nobody can enumerate the bucket through the CDN, and S3 will not confirm that an
object is absent to a caller who cannot list. The trade is a less helpful status code for a typo.

**`/` resolves to `index.html` at CloudFront, not at S3.** Keeping the bucket private meant giving up
S3 website hosting and its index document resolution, so the distribution's `default_root_object`
supplies the key instead. This applies to the root only: CloudFront does not resolve index documents
in subdirectories, which is fine for a single page site and would need a function for anything
deeper.

**`resume.pdf` is stable and typed.** The filename never changes, because LinkedIn and the site's own
call to action both point at it. It is uploaded outside the `aws s3 sync` step so its `Content-Type`
can be stated explicitly; left to the sync, the type comes from the runner's mimetypes database, and
a wrong guess turns "View Resume" into a download prompt.
