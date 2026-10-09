"""No keys or passwords in the repository (operating manual §1; decision #9).

Scans every tracked file, and the inside of the compressed test samples, for things that look like real keys:
database keys other than the public "anon" key, Supabase secret keys, database addresses with a password, GitHub,
Anthropic, OpenAI and AWS keys, private keys, and a capture key filled in where the placeholder belongs.
Prints each finding with its file and line, never the key itself. Exit code 1 if anything is found.

Usage: python3 tests/check_secrets.py
"""
import base64, gzip, json, re, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

JWT = re.compile(r"eyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}")
PATTERNS = [
    ("Supabase secret key", re.compile(r"sb_secret_[A-Za-z0-9_-]{10,}")),
    ("database address with a password", re.compile(r"postgres(?:ql)?://[^:\s/'\"]+:(?!postgres@127\.0\.0\.1)(?!\[)(?!<)[^@\s'\"]{3,}@")),
    ("GitHub token", re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})")),
    ("private key", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("Anthropic key", re.compile(r"sk-ant-[A-Za-z0-9_-]{20,}")),
    ("OpenAI-style key", re.compile(r"\bsk-(?:proj-)?[A-Za-z0-9]{32,}")),
    ("AWS key", re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    ("capture key filled in", re.compile(r"\bKEY\s*=\s*\"(?!__CAPTURE_KEY__\")[^\"]{12,}\"")),
]


def jwt_role(token):
    try:
        part = token.split(".")[1]
        return json.loads(base64.urlsafe_b64decode(part + "=" * (-len(part) % 4))).get("role")
    except Exception:
        return None


def scan(name, text):
    found = []
    for n, line in enumerate(text.splitlines(), 1):
        for m in JWT.finditer(line):
            role = jwt_role(m.group(0))
            if role != "anon":   # the anon key is public by design; anything else (service_role, a user's session) isn't
                found.append(f"{name}:{n}: database key with role {role!r}")
        for label, rx in PATTERNS:
            if rx.search(line):
                found.append(f"{name}:{n}: {label}")
    return found


def main():
    files = subprocess.run(["git", "ls-files", "-z"], cwd=ROOT, capture_output=True, check=True).stdout.decode().split("\0")
    files += [str(p.relative_to(ROOT)) for p in (ROOT / "tests" / "fixtures").glob("*.gz")]   # new samples, tracked or not
    findings, scanned = [], 0
    for f in sorted(set(filter(None, files))):
        p = ROOT / f
        if not p.is_file() or f == "tests/check_secrets.py":
            continue
        raw = p.read_bytes()
        if f.endswith(".gz"):
            raw = gzip.decompress(raw)
        if b"\0" in raw[:4096]:
            continue   # binary (images)
        findings += scan(f, raw.decode("utf-8", "replace"))
        scanned += 1
    if findings:
        print(f"Keys or passwords found ({len(findings)}):")
        print("\n".join("  " + x for x in findings))
        sys.exit(1)
    print(f"No keys or passwords in {scanned} files.")


if __name__ == "__main__":
    main()
