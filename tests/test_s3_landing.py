"""S3 landing module, tested with a fake S3 client (no AWS account, no network)."""
import pytest

from helpers import load_script

s3 = load_script("s3_landing.py")


class FakeS3:
    """Just enough of the boto3 S3 client: a dict of key -> bytes."""

    def __init__(self):
        self.objects = {}
        self.extra = {}

    def upload_file(self, Filename, Bucket, Key, ExtraArgs=None):
        self.objects[(Bucket, Key)] = open(Filename, "rb").read()
        self.extra[(Bucket, Key)] = ExtraArgs

    def download_file(self, Bucket, Key, Filename):
        open(Filename, "wb").write(self.objects[(Bucket, Key)])

    def get_paginator(self, name):
        assert name == "list_objects_v2"
        outer = self

        class P:
            def paginate(self, Bucket, Prefix):
                keys = sorted(k for (b, k) in outer.objects if b == Bucket and k.startswith(Prefix))
                yield {"Contents": [{"Key": k} for k in keys]}
                yield {}                     # a last empty page must not break the loop
        return P()


def _folder(tmp_path):
    d = tmp_path / "csv"
    d.mkdir()
    (d / "a.csv").write_text("x,y\n1,2\n")
    (d / "b.csv").write_text("x\n9\n")
    (d / "notes.txt").write_text("not a csv")
    return d


def test_key_for():
    assert s3.key_for("bronze", "a.csv") == "bronze/a.csv"
    assert s3.key_for("/bronze/", "a.csv") == "bronze/a.csv"
    assert s3.key_for("", "a.csv") == "a.csv"


def test_upload_sends_only_csv_and_encrypts(tmp_path):
    fake = FakeS3()
    keys = s3.upload_folder(_folder(tmp_path), "bkt", "bronze", client=fake)
    assert keys == ["bronze/a.csv", "bronze/b.csv"]
    assert ("bkt", "bronze/notes.txt") not in fake.objects
    assert all(v == {"ServerSideEncryption": "AES256"} for v in fake.extra.values())


def test_upload_twice_gives_same_result(tmp_path):
    fake = FakeS3()
    folder = _folder(tmp_path)
    s3.upload_folder(folder, "bkt", "bronze", client=fake)
    first = dict(fake.objects)
    s3.upload_folder(folder, "bkt", "bronze", client=fake)
    assert fake.objects == first


def test_upload_empty_folder_fails_loudly(tmp_path):
    empty = tmp_path / "empty"
    empty.mkdir()
    with pytest.raises(FileNotFoundError):
        s3.upload_folder(empty, "bkt", client=FakeS3())


def test_roundtrip_upload_then_download(tmp_path):
    fake = FakeS3()
    folder = _folder(tmp_path)
    s3.upload_folder(folder, "bkt", "bronze", client=fake)
    fake.objects[("bkt", "other/c.csv")] = b"z\n"          # a different prefix must be ignored
    files = s3.download_folder("bkt", "bronze", tmp_path / "back", client=fake)
    assert [p.name for p in files] == ["a.csv", "b.csv"]
    assert (tmp_path / "back" / "a.csv").read_bytes() == (folder / "a.csv").read_bytes()


def test_main_requires_bucket(tmp_path, monkeypatch, capsys):
    monkeypatch.delenv("S3_BUCKET", raising=False)
    assert s3.main(["upload", str(tmp_path)]) == 1
    assert s3.main([]) == 1
