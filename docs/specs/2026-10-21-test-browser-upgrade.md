# Build spec: a newer test browser, so the checks run on today's runners (21 Oct 2026)

**Why:** on 20 Oct GitHub's `ubuntu-latest` became Ubuntu 26.04, where Playwright 1.56 can't install its browser's
system libraries. The checks were pinned to `ubuntu-24.04` (pull request #55) to keep them green. That pin is a
workaround: 24.04 will be retired in time, and the screenshots' browser falls further behind. Gitesh, 21 Oct: finish
the remaining builds.

**Outcome when done:**
- Both workflows (`checks.yml` and `database-rehearsal.yml`) run on `ubuntu-latest` again, with a Playwright version
  that installs there.
- Every check is green, and no saved answer moves because of the browser.

## The change
- **Find the oldest Playwright release** whose `playwright install --with-deps chromium` works on Ubuntu 26.04 (its
  release notes, or try it in the workflow). Pick an exact version at least two weeks old.
- **Pin it everywhere 1.56.0 is named:** both workflows, `tests/README.md` and `tests/run_all.sh`'s notes. Do the same
  for any Node Playwright the tests use (`NODE_PATH`, `package.json`), so Python and Node agree.
- **Remove the `ubuntu-24.04` pins and their comments.** Use `ubuntu-latest`.
- **If a newer Chromium renders a page differently enough to fail a check** (a screen's sideways scroll, a text
  match), fix the test or the page and say which in the pull request. Screenshots are for review only and don't need to
  match.
- **`tests/README.md`:** the versions, and a line in its history.

## Checks
- `checks` and `rehearse` green on `ubuntu-latest`.
- Cloudflare Pages green.

## Not in this build
- Any other dependency upgrade.
