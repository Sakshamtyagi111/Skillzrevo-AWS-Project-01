CloudEdge - Console Edition: files you need
===========================================

Follow the guide "CloudEdge: Console Edition (Student Guide)". These are the files it refers to.

website/                 The site. Upload its CONTENTS to the S3 bucket root (Step 7).
                         index.html and error.html contain __VERSION__ (5 times / once):
                         copy the folder to "build", Find & Replace __VERSION__ -> v1, then upload.
                         fonts/ : optionally add inter-var.woff2 (see fonts/README.txt).
lambda/invalidate.py     Paste into the Lambda function's lambda_function.py (Step 6C).
                         Handler must be: lambda_function.handler
tests/                   Optional: upload to CloudShell and run (Step 11).
scripts/rollback.sh      Optional: CloudShell rollback that keeps version history (Step 10C).
docs/screenshots/        Screenshot checklist (also in section 14 of the guide).
