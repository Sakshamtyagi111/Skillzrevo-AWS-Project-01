# CloudEdge: Private S3 + CloudFront Static Website (AWS Console Edition)

Build a fast, secure website on AWS using only the **AWS Management Console** (plus an optional CloudShell for tests).

**What you will have at the end**

- A website that lives in a **private S3 bucket** (nobody can open the bucket directly).
- **CloudFront** (AWS's CDN) serving it worldwide over **HTTPS** with your own domain.
- **HTML never cached**, while CSS/JS/images/video **are cached** at the edge.
- A **Lambda function** that automatically refreshes (invalidates) CloudFront when you upload a changed file.
- **S3 versioning + a rollback script** so you can undo a bad deploy.
- **Test scripts** that prove everything works, and a screenshot checklist for your report/portfolio.

> **Time:** 2 to 3 hours the first time. **Cost:** almost free (see [Cost](#2-cost-read-this-first)).
> Read each step fully **before** clicking. Most errors in this project come from skipping a detail.

---

## Table of contents

1. [How it works](#1-how-it-works)
2. [Cost (read this first)](#2-cost-read-this-first)
3. [Before you start](#3-before-you-start)
4. [Project folder layout (do this first)](#4-project-folder-layout-do-this-first)
5. [Your values cheat-sheet](#5-your-values-cheat-sheet)
6. [Step-by-step build](#6-step-by-step-build)
7. [Testing](#7-testing)
8. [Day-to-day: deploy an update and roll back](#8-day-to-day-deploy-an-update-and-roll-back)
9. [Screenshots for your report](#9-screenshots-for-your-report)
10. [Troubleshooting](#10-troubleshooting)
11. [Cleanup (avoid surprise bills)](#11-cleanup-avoid-surprise-bills)
12. [Glossary](#12-glossary)

---

## 1. How it works

```
 Visitor's browser
       │  https://yourdomain.com
       ▼
 Route 53 (DNS)  ── "yourdomain.com" points to CloudFront (Alias record)
       │
       ▼
 CloudFront (CDN, 400+ edge locations)  ← ACM certificate (HTTPS, issued in us-east-1)
       │  cache miss only
       │  (signed request using OAC = Origin Access Control)
       ▼
 S3 bucket (PRIVATE, Block Public Access ON, Versioning ON)
       │
       │  ObjectCreated event (when you upload .html/.css/.js)
       ▼
 Lambda  ──►  CloudFront CreateInvalidation  (edge cache refreshed)
```

| Piece | Why it exists |
|---|---|
| **S3 (private)** | Stores the files cheaply. Public access is blocked, so the only way in is through CloudFront. |
| **OAC** | Lets *only your* CloudFront distribution read the bucket (via the bucket policy). |
| **CloudFront** | Caches files near visitors, adds HTTPS, HTTP/2, HTTP/3, compression, security headers. |
| **ACM** | Free HTTPS certificate. **Must be created in `us-east-1` (N. Virginia)** for CloudFront. |
| **Route 53** | DNS: points your domain to CloudFront. |
| **Lambda** | Runs `invalidate.py` after uploads so visitors never see stale files. |
| **S3 Versioning** | Keeps every old copy of every file, so rollback is possible. |

**Caching rules used in this project**

| Files | Browser/edge caching | Why |
|---|---|---|
| `index.html`, `error.html` | **Never cached** (`no-cache`) | Visitors always get the latest page. |
| `/css/*`, `/js/*`, `/images/*`, `/fonts/*`, `/videos/*` | **Cached long** (1 year) | Fast. New versions are picked up through `?v=v1`, `?v=v2`... in the HTML and through Lambda invalidation. |

---

## 2. Cost (read this first)

| Service | Cost for this project |
|---|---|
| S3, CloudFront (free tier: 1 TB out/month), ACM, Lambda, CloudShell | Free or a few cents |
| **Route 53 hosted zone** | **about $0.50 per month** (charged even if idle) |
| **Domain name** | Around $3 to $15 per year, depending on the domain (the only real cost) |
| CloudFront invalidations | First 1,000 paths per month free |

Set up a **budget alert** so nothing surprises you: *Billing → Budgets → Create budget → Zero spend budget*.

When you finish learning, follow [Cleanup](#11-cleanup-avoid-surprise-bills).

> **No domain? You can still do most of the project.** Skip Steps 3, 4 and 8. In CloudFront, leave the default
> `dxxxxxxxx.cloudfront.net` certificate and use that address as your site URL. In `test.sh`, the DNS, ACM/TLS and
> some protocol checks will fail. That is expected without a custom domain.

---

## 3. Before you start

You need:

1. An **AWS account** (with billing/MFA set up). Sign in as a normal admin user, not as the root user if possible.
2. A **domain name** (buy one in Route 53 or any registrar). Below we call it `example.com`. **Replace it with yours everywhere.**
3. A laptop with a modern browser and a text editor (**VS Code** is recommended because it has easy Find & Replace across files).
4. The project files from this folder.

**Region to use:** the guide uses **Asia Pacific (Mumbai) `ap-south-1`** for S3 and Lambda. (`test.sh` defaults to this.) The *certificate* must be in **`us-east-1`**. Route 53 and CloudFront are global, so they have no region.

> ⚠ **The #1 beginner mistake is working in the wrong region.** Look at the region name in the top-right corner of the console before every step.

---

## 4. Project folder layout (do this first)

The files you received are all in **one flat folder**. The website and scripts expect a **specific folder structure**
(for example, `index.html` links to `/css/style.css` and `/images/hero.svg`). If the structure is wrong, you get broken CSS or images.

Create this structure on your computer and move the files in:

```
cloudedge/
├── README.md                    (this file)
├── website/
│   ├── index.html
│   ├── error.html
│   ├── css/
│   │   └── style.css
│   ├── js/
│   │   └── app.js
│   ├── images/
│   │   ├── hero.svg
│   │   └── favicon.svg
│   ├── videos/
│   │   └── demo.mp4
│   └── fonts/
│       ├── README.txt           (the file named "README (1).txt")
│       └── inter-var.woff2      (optional, see below)
├── lambda/
│   └── invalidate.py
├── scripts/
│   └── rollback.sh
├── tests/
│   ├── test.sh
│   ├── invalidation-test.sh
│   └── latency.sh
└── docs/
    └── screenshots/
        └── CHECKLIST.md
```

**Where each uploaded file goes**

| File | Goes to |
|---|---|
| `index.html`, `error.html` | `website/` |
| `style.css` | `website/css/` |
| `app.js` | `website/js/` |
| `hero.svg`, `favicon.svg` | `website/images/` |
| `demo.mp4` | `website/videos/` |
| `README (1).txt` | `website/fonts/README.txt` |
| `invalidate.py` | `lambda/` |
| `rollback.sh` | `scripts/` |
| `test.sh`, `invalidation-test.sh`, `latency.sh` | `tests/` |
| `CHECKLIST.md` | `docs/screenshots/` |
| old file index `README.txt` | not needed (replaced by this README) |

**Optional font:** download the *Inter* variable font from <https://rsms.me/inter/>, rename it to exactly
`inter-var.woff2` and put it in `website/fonts/`. If you skip it, the site simply uses your system font. Nothing breaks.

**Important rules**

- File and folder names are **case-sensitive** in S3: `css/style.css` is not `CSS/Style.css`.
- Don't put spaces in names.

---

## 5. Your values cheat-sheet

Write these in a notepad. You will use them many times. Keep this table updated as you create things.

| Placeholder | Meaning | Example | Your value |
|---|---|---|---|
| `DOMAIN` | Your domain | `example.com` | |
| `BUCKET` | S3 bucket name (globally unique, lowercase) | `cloudedge-yourname-2026` | |
| `REGION` | Region for S3 + Lambda | `ap-south-1` | |
| `ACCOUNT_ID` | Your 12-digit AWS account number (top-right menu) | `123456789012` | |
| `DIST_ID` | CloudFront distribution ID (starts with `E`) | `E1ABCDEF234XYZ` | *(after Step 5)* |
| `DIST_DOMAIN` | CloudFront domain | `d111111abcdef8.cloudfront.net` | *(after Step 5)* |
| `VERSION` | Deploy label | `v1`, `v2`, ... | `v1` |

---

## 6. Step-by-step build

> Follow the steps **in order**. Each step ends with a ✅ **Checkpoint**. Do not continue if the checkpoint fails.

### Step 1: Create the private S3 bucket

1. Console → **S3** → **Create bucket**. Region: **`ap-south-1`**.
2. **Bucket name:** your `BUCKET` value.
3. **Object Ownership:** *ACLs disabled (recommended)*.
4. **Block Public Access:** keep **"Block *all* public access" ticked** (all four boxes).
5. **Bucket Versioning:** **Enable**.
6. **Default encryption:** leave *SSE-S3* (default).
7. **Create bucket.**

> ❌ Do **NOT** turn on "Static website hosting". CloudFront will use the normal (private) S3 endpoint, not the website endpoint.

✅ **Checkpoint:** *Bucket → Permissions* shows "Block all public access: **On**", and *Properties → Bucket Versioning* shows **Enabled**.
(Screenshots #1 and #2.)

---

### Step 2: Prepare and upload the website

#### 2A. Build a copy with the version label

`index.html` contains the text `__VERSION__` **5 times** and `error.html` **once**. They must be replaced with a real label such as `v1`.
Never edit the original. Work on a copy:

1. Copy the whole `website/` folder and name the copy **`build/`**.
2. In **VS Code**: *File → Open Folder → `build`*. Press **Ctrl+Shift+H** (Find in Files).
   Find: `__VERSION__`  Replace with: `v1`  → **Replace All**.
3. Search for `__VERSION__` again. You must get **0 results**.

(Or in CloudShell/Linux: `sed -i 's/__VERSION__/v1/g' build/index.html build/error.html`. On macOS use `sed -i '' ...`.)

> If you forget this, your site loads `/css/style.css?v=__VERSION__` and the "Build" badge shows `__VERSION__`.

#### 2B. Upload the assets first, then the HTML

Console → your bucket → **Upload**. Do it in **two rounds** because HTML and assets need *different* Cache-Control values.

**Round 1: assets (long cache)**

1. Click **Add folder** and add each of these folders from `build/`: `css`, `js`, `images`, `videos` (and `fonts` if you have the font).
   Folder upload keeps the folder names, which is exactly what we need.
2. Expand **Properties → Metadata → Add metadata**:
   - Type: **System defined**, Key: **Cache-Control**, Value: `public, max-age=31536000, immutable`
3. **Upload.**

**Round 2: HTML (never cached)**

1. **Add files:** `build/index.html` and `build/error.html` (they go in the bucket **root**, not inside a folder).
2. **Properties → Metadata → Add metadata:**
   - Key **Cache-Control**, Value: `no-cache, no-store, must-revalidate, max-age=0`
   - Key **Content-Type**, Value: `text/html; charset=utf-8`
3. **Upload.**

> Alternative with CloudShell/CLI (after uploading the `build` folder there):
> ```bash
> aws s3 sync build/ s3://BUCKET/ --exclude "*.html" \
>   --cache-control "public, max-age=31536000, immutable"
> aws s3 cp build/index.html s3://BUCKET/index.html \
>   --cache-control "no-cache, no-store, must-revalidate, max-age=0" --content-type "text/html; charset=utf-8"
> aws s3 cp build/error.html s3://BUCKET/error.html \
>   --cache-control "no-cache, no-store, must-revalidate, max-age=0" --content-type "text/html; charset=utf-8"
> ```

✅ **Checkpoint:** Bucket root shows `index.html`, `error.html`, and folders `css/ js/ images/ videos/`.
Click `index.html` → **Properties → Metadata** shows the `no-cache` Cache-Control (Screenshot #5).
Click `images/hero.svg` and confirm *Content-Type* is `image/svg+xml`.

---

### Step 3: Route 53 hosted zone (DNS)

> Skip Steps 3, 4 and 8 if you have no domain.

1. Console → **Route 53 → Hosted zones → Create hosted zone**.
2. Domain name: `example.com`, Type: **Public hosted zone** → **Create**.
3. Open the zone. You'll see **NS** and **SOA** records. Note the **4 name servers** (`ns-xxx.awsdns-xx.org`, ...).
4. **If you bought the domain in Route 53:** it creates its own zone. Either use that one, or set the domain's name servers to match your new zone (*Registered domains → your domain → Add/edit name servers*).
5. **If you bought the domain elsewhere** (GoDaddy, Namecheap, ...): log in there and replace the domain's name servers with the **4 AWS name servers**.

✅ **Checkpoint:** after some minutes (up to a few hours), `dig NS example.com +short` (or <https://dnschecker.org>) shows `awsdns` servers.
**Do not continue to Step 4 until this works**, or certificate validation will hang forever.

---

### Step 4: Request the HTTPS certificate (ACM)

1. In the top-right region menu choose **US East (N. Virginia) `us-east-1`**.
   🚨 **CloudFront can only see certificates from `us-east-1`.** In any other region, the certificate will not appear in the dropdown later.
2. Console → **Certificate Manager → Request → Request a public certificate**.
3. Domain names: add **both** `example.com` and `www.example.com`.
4. Validation method: **DNS validation**. Key algorithm: RSA 2048 (default). **Request.**
5. Open the certificate → under *Domains* click **Create records in Route 53** → **Create records**.
6. Wait 2 to 10 minutes and refresh until Status = **Issued**.

✅ **Checkpoint:** Status **Issued**, both names listed (Screenshot #6). Then switch your region back to **`ap-south-1`**.

---

### Step 5: Create the CloudFront distribution

CloudFront settings take a few minutes to deploy, so prepare the policies first.

#### 5A. Create a cache policy for assets

*CloudFront → Policies → Cache → Create cache policy*

| Setting | Value |
|---|---|
| Name | `cloudedge-assets` |
| Minimum TTL | `0` |
| Default TTL | `86400` |
| Maximum TTL | `31536000` |
| Compression support | ✅ **Gzip** and ✅ **Brotli** |
| Headers | None |
| Query strings | **None** |
| Cookies | None |

> Why "Query strings: None"? Our Lambda invalidates plain paths such as `/css/style.css`. Ignoring the query string in the cache key makes sure that invalidation clears the file.
> The `?v=v1` label is still useful because it makes *browsers* fetch a fresh copy.

(Screenshot #9 later.)

#### 5B. Create an Origin Access Control (OAC)

*CloudFront → Security → Origin access → Create control setting*
Name `cloudedge-oac`, Origin type **S3**, Signing behavior **Sign requests (recommended)** → **Create**.
(Or let the distribution wizard create it for you in the next step.)

#### 5C. Create the distribution

*CloudFront → Distributions → Create distribution*

**Origin**

| Setting | Value |
|---|---|
| Origin domain | Pick **your bucket** from the list: it looks like `BUCKET.s3.ap-south-1.amazonaws.com` (**not** the website endpoint) |
| Origin access | **Origin access control settings (recommended)** → choose `cloudedge-oac` |
| Origin path | leave empty |

**Default cache behavior** (this one serves your HTML)

| Setting | Value |
|---|---|
| Viewer protocol policy | **Redirect HTTP to HTTPS** |
| Allowed HTTP methods | GET, HEAD |
| Cache policy | Managed: **CachingDisabled** |
| Response headers policy | Managed: **SecurityHeadersPolicy** |

**Settings**

| Setting | Value |
|---|---|
| Alternate domain names (CNAMEs) | `example.com` and `www.example.com` |
| Custom SSL certificate | Choose your **ACM certificate** (visible only if it was created in `us-east-1`) |
| Security policy | **TLSv1.2_2021** (this blocks old TLS versions) |
| Supported HTTP versions | HTTP/2 ✅ and **HTTP/3** ✅ |
| Default root object | **`index.html`** (exact spelling, no slash) |
| IPv6 | **On** (needed for AAAA records) |
| Price class | Any (choose "Use all edge locations" for the best latency tests) |
| WAF | **Do not enable security protections** (avoids extra cost) |

**Create distribution.** Then:

1. Copy the **bucket policy** the console offers (a banner says *"The S3 bucket policy needs to be updated"* → **Copy policy**). You need it in Step 6.
2. Write down the **Distribution ID** (`DIST_ID`) and **Distribution domain name** (`DIST_DOMAIN`).

#### 5D. Add the extra behaviors for assets

Open the distribution → **Behaviors → Create behavior**. Create **five** behaviors. They are all identical except for the path pattern:

| Path pattern |
|---|
| `/css/*` |
| `/js/*` |
| `/images/*` |
| `/fonts/*` |
| `/videos/*` |

Use these settings in all five:

| Setting | Value |
|---|---|
| Origin | your S3 origin |
| Viewer protocol policy | Redirect HTTP to HTTPS |
| Allowed methods | GET, HEAD |
| Cache policy | **`cloudedge-assets`** (your custom one) |
| Response headers policy | **SecurityHeadersPolicy** |
| Compress objects automatically | **Yes** |

> The patterns are case-sensitive and need the leading `/` and trailing `/*`.

#### 5E. Custom error page (404)

Distribution → **Error pages → Create custom error response**. Create **two**:

| HTTP error code | Response page path | HTTP response code | Error caching min TTL |
|---|---|---|---|
| **403** | `/error.html` | **404** | `10` |
| **404** | `/error.html` | **404** | `10` |

> Why 403 too? The bucket is private and CloudFront has no "list" permission. S3 therefore answers **403** (not 404) for a file that does not exist. Mapping both codes gives visitors a proper 404 page.

✅ **Checkpoint:** Status changes from *Deploying* to a **Last modified date** (about 3 to 10 minutes). Note that the site does **not** work yet (it returns AccessDenied) because the bucket policy is missing. That's Step 6.
(Screenshots #7, #8 and #9.)

---

### Step 6: Add the bucket policy (allow only CloudFront)

S3 → your bucket → **Permissions → Bucket policy → Edit**, paste this, replacing the three placeholders:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCloudFrontServicePrincipalReadOnly",
      "Effect": "Allow",
      "Principal": { "Service": "cloudfront.amazonaws.com" },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::BUCKET/*",
      "Condition": {
        "StringEquals": {
          "AWS:SourceArn": "arn:aws:cloudfront::ACCOUNT_ID:distribution/DIST_ID"
        }
      }
    }
  ]
}
```

(Or paste the policy copied from CloudFront in Step 5C. It's the same thing.)

Common mistakes: wrong account ID, `/*` missing after the bucket name, or JSON copied with curly "smart quotes".

✅ **Checkpoint:** Open `https://DIST_DOMAIN/` in your browser. You should see the CloudEdge page, with CSS, hero image and a "Build v1" badge.
Then open `https://BUCKET.s3.ap-south-1.amazonaws.com/index.html` and you must get **AccessDenied** (Screenshots #3 and #13).

---

### Step 7: Point your domain to CloudFront (Route 53 records)

> Skip if you have no domain.

In your **hosted zone → Create record** (use *Switch to wizard* if needed). Create these:

| Record name | Type | Value |
|---|---|---|
| *(empty, the apex)* | **A**, Alias ✅ | Alias to **CloudFront distribution** → choose yours |
| *(empty)* | **AAAA**, Alias ✅ | Alias to the same distribution |
| `www` | **A**, Alias ✅ | Alias to the same distribution |
| `www` | **AAAA**, Alias ✅ | Alias to the same distribution |
| *(empty)* | **TXT** | `"CloudEdge demo project"` (include the quotes) |
| *(empty)* | **CAA** | `0 issue "amazon.com"` |

Already present: **NS**, **SOA** and the **ACM validation CNAME** (don't delete the CNAME; ACM uses it to renew the certificate).

✅ **Checkpoint:** `https://example.com` and `https://www.example.com` load your site with a padlock 🔒 (Screenshots #11 and #12).
If you get "site can't be reached", wait 5 to 15 minutes for DNS to update.

---

### Step 8: Auto-invalidation with Lambda

Goal: every time you upload `.html`, `.css` or `.js` to S3, CloudFront's cached copy is cleared automatically.

#### 8A. Create the function

*Lambda → Create function* (**region `ap-south-1`**, the same as the bucket)

| Setting | Value |
|---|---|
| Author from scratch | ✅ |
| Name | `cloudedge-invalidate` |
| Runtime | **Python 3.12** (or newer Python) |
| Architecture | x86_64 |
| Permissions | Create a new role with basic Lambda permissions |

#### 8B. Paste the code

1. Open the **Code** tab → file **`lambda_function.py`** → delete everything → paste the full content of `lambda/invalidate.py`.
2. Click **Deploy**. 🚨 *(If you forget, Lambda keeps running the empty sample code.)*
3. **Runtime settings → Edit → Handler:** `lambda_function.handler`
   (The file is `lambda_function.py`, the function is `handler`, so you write `lambda_function.handler`. The default `lambda_function.lambda_handler` will cause *"Handler 'lambda_handler' missing"*.)

#### 8C. Environment variable and timeout

- **Configuration → Environment variables → Edit → Add:** Key `DIST_ID`, Value = your distribution ID (e.g. `E1ABCDEF234XYZ`).
- **Configuration → General configuration → Edit:** Timeout **10 sec**.

#### 8D. Permission to invalidate

**Configuration → Permissions →** click the **role name** → **Add permissions → Create inline policy → JSON**:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "cloudfront:CreateInvalidation",
      "Resource": "arn:aws:cloudfront::ACCOUNT_ID:distribution/DIST_ID"
    }
  ]
}
```

Name it `AllowInvalidate` → **Create policy**.

#### 8E. Connect S3 to Lambda (three triggers)

Add **three** triggers with different file endings. In **Lambda → Add trigger → S3** (or S3 → bucket → *Properties → Event notifications*):

| # | Bucket | Event type | Suffix |
|---|---|---|---|
| 1 | your bucket | **All object create events** | `.html` |
| 2 | your bucket | **All object create events** | `.css` |
| 3 | your bucket | **All object create events** | `.js` |

Tick the "Recursive invocation" acknowledgement. This function never writes to S3, so there is no loop.

> Always use **suffixes**. Two rules with the same event type that overlap (for example both with *no* suffix) are rejected by S3 with *"Configurations overlap"*.

✅ **Checkpoint:** Re-upload `index.html` (same file, same metadata as Step 2B), wait 10 seconds, then check:

- **Lambda → Monitor → View CloudWatch logs:** you see `Invalidated: ['/', '/index.html']`.
- **CloudFront → Invalidations:** a new entry reaches **Completed** (Screenshot #10).

---

## 7. Testing

### 7A. Browser test (Edge Inspector built into the site)

1. Open your site → scroll to **Edge Inspector** → click **Run test**, then click it again.
2. Expected results:

| File | X-Cache (2nd click) |
|---|---|
| `/index.html` | **Miss from cloudfront** (never *Hit*) |
| `/css/style.css`, `/js/app.js`, `/images/hero.svg` | **Hit from cloudfront**, with an `Age` value > 0 |

3. Also see it in **DevTools → Network** (F12): click a file → *Response headers → x-cache* (Screenshots #14 and #15).

### 7B. Script tests in AWS CloudShell

1. Open **CloudShell** (the `>_` icon at the top of the console). Use a region where you have your resources, e.g. Mumbai.
2. **Actions → Upload file**: upload `test.sh`, `invalidation-test.sh`, `latency.sh`, `rollback.sh`.
3. Arrange them and make them runnable:

```bash
mkdir -p tests scripts
mv test.sh invalidation-test.sh latency.sh tests/
mv rollback.sh scripts/
chmod +x tests/*.sh scripts/*.sh
sudo dnf install -y bind-utils      # gives you the 'dig' command used by test.sh
```

> If you edited the scripts on **Windows**, line endings can break them (`bad interpreter: /usr/bin/env bash^M`). Fix with: `sed -i 's/\r$//' tests/*.sh scripts/*.sh`

#### Main test (11 sections)

```bash
DOMAIN=example.com BUCKET=your-bucket-name REGION=ap-south-1 ./tests/test.sh
```

It checks: DNS records, HTTP→HTTPS redirect, ACM certificate, TLS version, HTTP/2 and HTTP/3, "index.html not cached", "assets cached", compression, video Range requests, security headers, S3 privacy + versioning, and the custom 404.
At the end you get `Result: N passed, M failed`. Aim for 0 failed.

**Known harmless "failures"**

| Message | Why | What to do |
|---|---|---|
| `HTTP/3 not testable` | The `curl` in CloudShell has no HTTP/3 support | Ignore; verify HTTP/3 in browser DevTools (Protocol column `h3`) |
| `TLS 1.1 accepted?` | Newer OpenSSL no longer supports the `-tls1_1` option, so the test cannot run | Check that your CloudFront security policy is `TLSv1.2_2021`. That's what matters |
| An asset says `not a Hit` | First request after upload was a Miss | Run the test again |
| `CAA` / `TXT` missing | Record not created yet or DNS not updated | Recheck Step 7 |

#### Invalidation test

```bash
DOMAIN=example.com BUCKET=your-bucket-name DIST_ID=E1ABCDEF234XYZ ./tests/invalidation-test.sh
```

It adds a hidden `<!-- TEST-... -->` comment to your live `index.html`, uploads it, invalidates, and waits until the change is visible. Expected: `✅ Change visible after ~Ns`.

> ⚠ **This test leaves the test comment in your live `index.html`.** It is harmless, but clean up by re-uploading your clean `build/index.html` (Step 2B, Round 2) or by rolling back (Section 8).

#### Latency test (compare regions)

```bash
./tests/latency.sh https://example.com 10
```

Run it from CloudShell in **3 different regions** (use the region menu → CloudShell restarts there), e.g. Mumbai, Frankfurt and N. Virginia. Compare the `ttfb_ms` averages.
Notice how the second and later requests are fast (`Hit`) and show different `pop` codes (edge city codes) in different regions. Screenshot #16.

---

## 8. Day-to-day: deploy an update and roll back

### Deploy an update

1. Edit files in `website/`.
2. Create a **new build** with the **next version label** (`v2`, `v3`, ...): copy `website/` → `build/`, replace `__VERSION__` with `v2`.
3. Upload as in Step 2B (assets with long cache, HTML with `no-cache`).
4. Lambda invalidates automatically. Check with the Edge Inspector. The Build badge should show `v2`.

> Always **increase the version label** when CSS/JS/images change. Browsers cache assets for a year and only fetch a new copy if the URL (`?v=v2`) changes.

### Roll back a bad deploy

CloudShell:

```bash
# 1. Find the version you want
BUCKET=your-bucket-name ./scripts/rollback.sh list index.html

# 2. Restore it (this copies the old version on top as the NEW current version, history is kept)
BUCKET=your-bucket-name DIST_ID=E1ABCDEF234XYZ ./scripts/rollback.sh restore index.html <VersionId>
```

Pick the `VersionId` of the earlier, good version from the table. The script restores the file and invalidates CloudFront.

In the console you can see versions too: *S3 → bucket → Objects → toggle **List versions*** (Screenshot #4).

---

## 9. Screenshots for your report

Take the 16 screenshots listed in `docs/screenshots/CHECKLIST.md` as you go, and save them in `docs/screenshots/` using the file names given there. Screenshot numbers are mentioned in the steps above so you know when to take them.

Tips: zoom in so the key setting is readable, and **hide/blur your account ID and the Distribution ID if you publish the report online.**

---

## 10. Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| **`AccessDenied` XML page** at your CloudFront or domain URL | Bucket policy missing/wrong, or wrong account/distribution ID in it | Redo Step 6 (copy the policy from CloudFront); check there's `/*` after the bucket name |
| `AccessDenied` for `/` but `/index.html` works | Default root object not set | CloudFront → General → Settings → Default root object = `index.html` |
| ACM certificate not in the CloudFront dropdown | Certificate was not created in **us-east-1** | Request a new certificate in N. Virginia |
| ACM stuck on **Pending validation** | Name servers not switched (Step 3) or validation CNAME missing | Fix NS first, then *Create records in Route 53* |
| `CNAMEAlreadyExists` when saving the distribution | The domain is already attached to another distribution | Remove it from the other one, or use a different domain |
| Page loads but **no CSS / no images** | Wrong folder structure, or you uploaded the `build` folder itself instead of its *contents* | Check keys in S3 are exactly `css/style.css`, `images/hero.svg`... not `build/css/...` |
| Build badge shows **`__VERSION__`** or `-` | You didn't replace `__VERSION__` or JS didn't load | Redo 2A, re-upload, check `/js/app.js` loads in DevTools |
| Site shows **old content** after upload | Lambda trigger missing / invalidation not done / browser cache | Check Lambda logs and CloudFront Invalidations; hard-refresh (Ctrl+Shift+R) |
| Lambda error: `Unable to import module 'lambda_function'` | File name wrong or code not pasted | File must be `lambda_function.py`, then **Deploy** |
| Lambda error: `Handler 'handler' missing` / `lambda_handler` | Handler setting wrong | Set handler to `lambda_function.handler` |
| Lambda error: `KeyError: 'DIST_ID'` | Environment variable missing | Step 8C |
| Lambda error: `AccessDenied ... cloudfront:CreateInvalidation` | Missing IAM policy | Step 8D (check the distribution ARN) |
| Lambda never runs | Trigger missing, wrong suffix, or Lambda is in a different region than the bucket | Step 8E; Lambda and bucket must be in the same region |
| S3 error "Configurations overlap" | Two triggers with the same event and overlapping prefix/suffix | Use separate `.html`, `.css`, `.js` suffixes |
| HTML downloads instead of displaying | Wrong `Content-Type` metadata | Set `Content-Type: text/html; charset=utf-8` on the object |
| `index.html` shows **Hit** in tests | Default behavior isn't using **CachingDisabled** | Step 5C |
| `x-cache` missing in Edge Inspector | Cross-origin/CDN header filtering or an old cached copy | Use DevTools instead; hard-refresh |
| Video can't seek / test 8 fails | `/videos/*` behavior missing or video file not uploaded | Step 5D; confirm `videos/demo.mp4` exists |
| Direct S3 URL opens the file (not 403) | Block Public Access is off or a public policy exists | Step 1: turn **Block all public access** back on |
| Missing page gives 403 instead of the 404 page | Error responses not set | Step 5E (both 403 and 404 → `/error.html` → 404) |
| `dig: command not found` in CloudShell | Tool not installed | `sudo dnf install -y bind-utils` |
| `bad interpreter: ^M` | Windows line endings | `sed -i 's/\r$//' tests/*.sh scripts/*.sh` |
| `Permission denied` when running a script | Not executable | `chmod +x tests/*.sh scripts/*.sh` |
| Changes in CloudFront "don't work" right away | Distribution still deploying | Wait until the status shows a date, not *Deploying* |
| Browser console: 404 for `/fonts/inter-var.woff2` | Optional font not uploaded | Harmless. The site falls back to system fonts. Or add the font |

**Useful debugging commands**

```bash
curl -I https://example.com/                 # look at status, x-cache, cache-control
curl -I https://example.com/css/style.css    # 2nd run should say Hit
dig example.com +short                       # does DNS resolve?
aws cloudfront list-invalidations --distribution-id DIST_ID
aws logs tail /aws/lambda/cloudedge-invalidate --since 10m
```

---

## 11. Cleanup (avoid surprise bills)

When you're done (take your screenshots first!), delete in **this order**:

1. **CloudFront:** *Distributions → select → Disable*. Wait until it shows deployed, then **Delete**. Later delete the **cache policy**, **OAC** and any leftover custom items.
2. **Route 53:** delete all your records except NS and SOA, then **Delete hosted zone**. (If you don't want to renew the domain, turn off auto-renew in *Registered domains*.)
3. **ACM (us-east-1):** delete the certificate (only possible after the distribution is gone).
4. **Lambda:** delete the function, its IAM role, and the CloudWatch log group `/aws/lambda/cloudedge-invalidate`.
5. **S3:** the bucket has versioning on, so a normal delete fails. Use **Empty** first (it removes all versions), then **Delete** the bucket.
6. Check *Billing → Bills* a day later to confirm costs have stopped.

---

## 12. Glossary

| Term | Meaning |
|---|---|
| **CDN** | Network of servers around the world that keeps copies of your files close to visitors. |
| **Edge location / POP** | One of CloudFront's local servers (identified in the `x-amz-cf-pop` header, e.g. `BOM52-C1`). |
| **Cache Hit / Miss** | *Hit*: edge already had the file. *Miss*: edge had to get it from S3. |
| **TTL** | How long a cached file is considered fresh. |
| **Invalidation** | Telling CloudFront to throw away its cached copy of a path. |
| **OAC** | Origin Access Control: a secure identity that lets CloudFront (and only CloudFront) read a private bucket. |
| **ACM** | AWS Certificate Manager: free HTTPS certificates. |
| **Alias record** | A Route 53 record type that points a domain name at an AWS resource such as CloudFront. |
| **CAA record** | DNS record that says which companies may issue certificates for your domain. |
| **Versioning (S3)** | S3 keeps every older copy of an object when you overwrite it. |
| **Range request** | Lets a video player ask for part of a file (needed for seeking). Reply code `206 Partial Content`. |

---

**You're done when:** the browser shows the padlock on your domain, `test.sh` ends with `0 failed` (apart from the known harmless items), `index.html` is never a *Hit*, static files are a *Hit*, the direct S3 URL gives *AccessDenied*, and your 16 screenshots are saved. 🎉
