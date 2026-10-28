"""S3 ObjectCreated -> CloudFront invalidation for changed html/css/js files."""
import os
import time
import urllib.parse

import boto3

cf = boto3.client("cloudfront")


def handler(event, context):
    paths = set()
    for rec in event.get("Records", []):
        key = urllib.parse.unquote_plus(rec["s3"]["object"]["key"])
        paths.add("/" + key)
        if key == "index.html":
            paths.add("/")  # root URL maps to index.html

    if not paths:
        return {"invalidated": []}

    items = sorted(paths)
    cf.create_invalidation(
        DistributionId=os.environ["DIST_ID"],
        InvalidationBatch={
            "Paths": {"Quantity": len(items), "Items": items},
            "CallerReference": str(time.time()),
        },
    )
    print("Invalidated:", items)
    return {"invalidated": items}
