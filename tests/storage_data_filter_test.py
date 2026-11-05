"""database/storage_data_filter.py: storage tables the copy lacks are left out; the copy's own and public's are kept.

The rehearsal's restore stopped on 4 Nov 2026 at storage.bucket_lifecycle_states, a table Supabase added on live that the
pinned CLI's local storage doesn't have.
"""
import pathlib, subprocess, sys, tempfile

DATA = '''SET statement_timeout = 0;
COPY "storage"."buckets" ("id", "name") FROM stdin;
site-photos\tsite-photos
\\.
COPY "storage"."bucket_lifecycle_states" ("bucket_id") FROM stdin;
site-photos
\\.
COPY storage.vector_indexes (id) FROM stdin;
\\.
COPY "public"."settings" ("key") FROM stdin;
storage is a word here
\\.
'''

with tempfile.TemporaryDirectory() as d:
    d = pathlib.Path(d)
    (d / "data.sql").write_text(DATA)
    (d / "have.txt").write_text("buckets\nobjects\n")
    r = subprocess.run([sys.executable, "database/storage_data_filter.py", d / "data.sql", d / "have.txt", d / "out.sql"],
                       capture_output=True, text=True, check=True)
    out = (d / "out.sql").read_text()
    assert 'COPY "storage"."buckets"' in out and "site-photos\tsite-photos" in out, "a storage table the copy has was left out"
    assert 'COPY "public"."settings"' in out and "storage is a word here" in out, "public's data was touched"
    assert "bucket_lifecycle_states" not in out and "vector_indexes" not in out, "a storage table the copy lacks was kept"
    assert out.count("\\.\n") == 2, "a COPY block's end went missing"
    assert "bucket_lifecycle_states: its data left out (1 row(s)" in r.stdout, r.stdout
    assert "vector_indexes: its data left out (0 row(s)" in r.stdout, r.stdout
print("storage data filter: lacking tables left out (2), the copy's and public's kept")
