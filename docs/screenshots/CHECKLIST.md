# Console screenshot checklist

Take these while following the README and save them here with the filenames below.
They are proof-of-work for your project report/portfolio.

| # | Filename | Where in the AWS console | What must be visible |
|---|----------|--------------------------|----------------------|
| 1 | 01-s3-block-public-access.png | S3 → bucket → Permissions | "Block all public access: On" |
| 2 | 02-s3-versioning-enabled.png | S3 → bucket → Properties | Bucket Versioning: Enabled |
| 3 | 03-s3-bucket-policy.png | S3 → Permissions → Bucket policy | `cloudfront.amazonaws.com` + `AWS:SourceArn` |
| 4 | 04-s3-show-versions.png | S3 → Objects → toggle "List versions" | Multiple version IDs of index.html |
| 5 | 05-s3-object-metadata.png | S3 → index.html → Properties → Metadata | Cache-Control: no-cache… |
| 6 | 06-acm-issued.png | ACM (us-east-1) → Certificates | Status: Issued, both names |
| 7 | 07-cf-origin-oac.png | CloudFront → Origins | Origin access: OAC, S3 regional domain |
| 8 | 08-cf-behaviors.png | CloudFront → Behaviors | Default + /css /js /fonts /images /videos |
| 9 | 09-cf-cache-policies.png | CloudFront → Policies → Cache | assets policy TTL 0 / 86400 / 31536000 |
| 10 | 10-cf-invalidation.png | CloudFront → Invalidations | Status Completed |
| 11 | 11-r53-records.png | Route 53 → Hosted zone | A, AAAA, TXT, CAA, NS, SOA, ACM CNAME |
| 12 | 12-browser-lock.png | Browser | Padlock + certificate details |
| 13 | 13-s3-direct-403.png | Browser | Direct S3 URL shows AccessDenied |
| 14 | 14-devtools-xcache.png | DevTools → Network | x-cache: Hit from cloudfront on css/img |
| 15 | 15-index-miss.png | DevTools → Network | index.html: Miss/RefreshHit never Hit |
| 16 | 16-latency-results.png | Terminal / WebPageTest | Multi-region latency numbers |
