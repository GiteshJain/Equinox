#!/usr/bin/env python3
"""Leaves out the data of storage tables the rehearsal's local copy lacks (database/rehearse.sh, step 1).

Supabase adds its own storage tables on live before the pinned CLI's local storage has them (storage.buckets_vectors and
storage.vector_indexes in October, storage.bucket_lifecycle_states on 4 Nov 2026). The backup's schema holds public only,
so their data has no table on the copy and the restore stops. This copies data.sql without the COPY blocks of storage
tables not listed in the second file, and prints which it left out and how many rows (Supabase's own, never ours).

Usage: storage_data_filter.py <data.sql> <file listing the copy's storage tables> <out.sql>
"""
import re, sys
src, have, out = sys.argv[1], set(open(sys.argv[2]).read().split()), sys.argv[3]
skip, dropped = None, {}
with open(src) as f, open(out, "w") as o:
    for line in f:
        if skip is not None:
            if line.rstrip("\n") == "\\.":
                skip = None
            else:
                dropped[skip] += 1
            continue
        m = re.match(r'COPY "?storage"?\."?([A-Za-z0-9_]+)"? ', line)
        if m and m.group(1) not in have:
            skip = m.group(1); dropped[skip] = 0
            continue
        o.write(line)
for t, n in dropped.items():
    print(f"the copy's storage has no table {t}: its data left out ({n} row(s); Supabase's own, not ours)")
