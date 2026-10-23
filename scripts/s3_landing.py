"""Copy the bronze CSV files to / from an Amazon S3 bucket (the "landing zone" of the cloud version).

    python scripts/s3_landing.py upload   raw_private/bronze_csv
    python scripts/s3_landing.py download raw_private/from_s3

Settings come from environment variables, never from files in the repository:
    S3_BUCKET   (required)  bucket name
    S3_PREFIX   (optional)  folder inside the bucket, default "bronze"
    AWS credentials and region: the normal AWS mechanisms (aws configure, AWS_PROFILE, AWS_ACCESS_KEY_ID, ...)

Design: object key = <prefix>/<file name>. The file names are stable and every file carries its own SHA-256 in
the `_file_sha256` column, so uploading twice overwrites with the same bytes (safe to repeat).
Every object is encrypted at rest (AES-256, server side). The synthetic demo data is the only data this repo has.
"""
import os
import sys
from pathlib import Path


def make_client():
    import boto3  # imported here so the rest of the project does not need boto3
    return boto3.client("s3")


def key_for(prefix: str, name: str) -> str:
    prefix = prefix.strip("/")
    return f"{prefix}/{name}" if prefix else name


def upload_folder(folder, bucket, prefix="bronze", client=None):
    """Upload every *.csv in `folder`. Returns the list of keys written."""
    client = client or make_client()
    files = sorted(Path(folder).glob("*.csv"))
    if not files:
        raise FileNotFoundError(f"no .csv files in {folder}")
    keys = []
    for path in files:
        key = key_for(prefix, path.name)
        client.upload_file(str(path), bucket, key, ExtraArgs={"ServerSideEncryption": "AES256"})
        keys.append(key)
    return keys


def download_folder(bucket, prefix, dest, client=None):
    """Download every *.csv under the prefix into `dest`. Returns the list of local paths."""
    client = client or make_client()
    dest = Path(dest)
    dest.mkdir(parents=True, exist_ok=True)
    wanted = prefix.strip("/") + "/" if prefix.strip("/") else ""
    out = []
    for page in client.get_paginator("list_objects_v2").paginate(Bucket=bucket, Prefix=wanted):
        for obj in page.get("Contents", []):
            key = obj["Key"]
            if not key.endswith(".csv"):
                continue
            local = dest / key[len(wanted):]
            client.download_file(bucket, key, str(local))
            out.append(local)
    return sorted(out)


def main(argv) -> int:
    if len(argv) != 2 or argv[0] not in ("upload", "download"):
        print(__doc__)
        return 1
    bucket = os.environ.get("S3_BUCKET")
    if not bucket:
        print("Set S3_BUCKET first, e.g.  export S3_BUCKET=my-bucket-name", file=sys.stderr)
        return 1
    prefix = os.environ.get("S3_PREFIX", "bronze")
    if argv[0] == "upload":
        keys = upload_folder(argv[1], bucket, prefix)
        print(f"uploaded {len(keys)} files to s3://{bucket}/{prefix}/")
    else:
        files = download_folder(bucket, prefix, argv[1])
        print(f"downloaded {len(files)} files from s3://{bucket}/{prefix}/ to {argv[1]}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
