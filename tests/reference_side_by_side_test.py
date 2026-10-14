"""The new planner's Interline, Photos and Reference, and its header search, side by side with the old planner's on the
rehearsal's copy (decision #18, build pull request 12, spec docs/specs/2026-10-14-interline-photos-reference.md,
"Checks"): the pull request's own new planner (built into web/app/) and the old planner (web/planner/), both at their live
addresses, signed in as the same test staff user, at the same frozen moment, reading a full local copy of Supabase restored
from last night's backup.

Run by database/rehearse.sh, after the Review side by side. Like tests/review_side_by_side_test.py it uses
tests/real_saves_test.py's helpers and request mapping, needs the copy, so it isn't part of tests/run_all.sh, and nothing
goes outside. The copy has no storage service, so each browser answers the photo bucket itself (the upload is kept in the
test, never sent anywhere).

1. Both planners open at the moment (the old one from a copy of web/ with the test's hook; web/planner/ is unchanged).
   Opening them writes nothing.
2. Interline, in both: the agreements board (every airline–country row with its airports, round trips a day, status,
   partner, date and notes), its airline and status filters (all, the first airline, still to sign, signed), the interline
   countries with their partners, and the notes.
3. Photos, in both: the logos, and the destinations missing a photo and then all of them (their photos, flights a week,
   credits and buttons).
4. Reference, in both: every section (its title and note, every table with every box's value, the words around them).
5. The header search: sample queries made from the copy (a flight with and without its airline's code, a number, part of
   a registration, an aircraft on order, two airports, an airport, the start of a city, nothing) give the old planner's
   results; Enter opens the new screen for a flight, an aircraft and an airport.
6. Reference's Export flights (CSV) gives the old planner's file; Export backup (JSON) gives every planner table.
7. Edits, each in the new planner and then in the old one from the same copy (the copy put back after each): Interline (a
   status set on a row with no agreement, a note on one), Reference (a hub's bank time, a constant, an aircraft type's
   field, Add config, a night ban added, a removed route restored, a time zone on an airport no flight touches), and a
   destination photo uploaded (a small test image). Each writes exactly the old planner's rows (for the photo: the same
   file sent to the bucket and the same website row), logged as planner with the tab's ID, and the old planner, opened
   again after the new one's edit, shows it.
8. A preview address (127.0.0.1) shows the three screens, and an upload, an interline status and a constant there send
   nothing (no write, no upload).
9. At 380 px wide the three screens (Reference with every section open) have no sideways scroll and no errors.
   Screenshots of the new screens and the old at 380 and 1280 px go to REFERENCE_SCREENS_DIR (the run's reference-screens
   artifact).
10. Nothing went outside.

A difference fails and names the screen, the row and both values, unless it is a known difference (KNOWN below, each with
its rule), printed with how often it was used and examples. Prints codes, registrations, counts and the screens' words,
never anything else from the rows, since the log is posted on the pull request; never the local keys or the test password.

Environment, set by database/rehearse.sh: LOCAL_SUPABASE_ENV, LOCAL_DB_URL, SECRET_TABLES and REFERENCE_SCREENS_DIR.
Usage: python3 tests/reference_side_by_side_test.py
"""
import asyncio, csv, json, os, re, secrets, shutil, struct, sys, tempfile, time, zlib
from collections import Counter
from pathlib import Path
from urllib.parse import urlsplit
from harness import serve, settle
from playwright.async_api import async_playwright
import real_saves_test as rs
from real_saves_test import count_changes, counts, is_planner_user, library, local_env, log_since, make_user, marks, planner_facts, psql, token_for, why
import planner_next_test as pn
from captured_figures_test import ms
from home_side_by_side_test import web_copy
from review_side_by_side_test import OldReview, refresh, until_quiet

SCREENS_DIR = os.environ.get("REFERENCE_SCREENS_DIR")
WORLD = "(select w.id from public.worlds w order by w.is_default desc, w.id limit 1)"
failures = []
started = time.monotonic()
COPY = {}

KNOWN = {
    "undefined box": {
        "rule": "the old Reference put a missing figure into its box as the word \"undefined\" (a hub's MCT where the airport has "
                "none, the load leeway and pattern window at their defaults, which the old planner's copy leaves out); the new box "
                "shows the figure or nothing. Only a box where the old one says \"undefined\": every other word the same.",
        "used": 0, "where": []},
    "learned speeds": {
        "rule": "manual §4 and the library (#19): block estimates are the block allowance plus the distance at the type's cruise "
                "speed, so the Aircraft table's \"Learned from your schedule\" column and the section's note say that; the old "
                "planner fitted speeds to the times typed (M.calibration, retired). Only that column and that note.",
        "used": 0, "where": []},
    "storage words": {
        "rule": "design §14: the new planner keeps nothing on the device, so Storage's first line names the cloud store's state "
                "only; the old one named its last writes and the device's copy. Only those words: the counts (frequencies, "
                "tails, route edits, markets, service profiles) must be the same.",
        "used": 0, "where": []},
    "import and clear": {
        "rule": "design §14 (choice 2): importing a backup and clearing everything went with the tables, so Data keeps the two "
                "exports and says why; the old one had Import backup, Clear everything and the paste box. Only those.",
        "used": 0, "where": []},
    "rule notes": {
        "rule": "the new Constants says the figures are rule numbers kept in settings (manual §1); the old had no note there. Only "
                "that note.",
        "used": 0, "where": []},
    "logo order": {
        "rule": "Photos lists the logos in the airlines' own order (airlines.position, as every new screen); the old one had its "
                "own list in its code. Only the order: the same cards with the same words.",
        "used": 0, "where": []},
    "order on a tie": {
        "rule": "the search goes through the routes in the planner's order: the old one in the research's order (planner_data), "
                "the new one by id (as the Routes side by side allows). Only routes' and airports' results, and only their "
                "order: the same results.",
        "used": 0, "where": []},
    "block estimates": {
        "rule": "an arrival left empty takes the estimate (manual §4, as the Routes side by side allows): in Export flights only "
                "the arrival, its day, the duration and the bank of a flight with an estimated time.",
        "used": 0, "where": []},
}


def step(ok, name, problems=()):
    print(("ok    " if ok else "FAIL  ") + name, flush=True)
    for p in ([] if ok else list(problems)[:30]):
        print("      " + p, flush=True)
    if not ok:
        failures.append(name)


def known(name, where):
    KNOWN[name]["used"] += 1
    if len(KNOWN[name]["where"]) < 12:
        KNOWN[name]["where"].append(where)


# ---------- reading either planner: the new screens draw the old ones' markup, so one reader serves both (root: the
# old #view, the new main[data-screen=...])
READ = r"""(sel) => {
  const R = document.querySelector(sel);
  if (!R) return null;
  const T = e => (e ? e.textContent.replace(/\s+/g, " ").trim() : "");
  // a copy with each box, list and tick box replaced by {its value} (an empty box by its hint)
  function plain(el) {
    const c = el.cloneNode(true);
    const src = [...el.querySelectorAll("input, select, textarea")], dst = [...c.querySelectorAll("input, select, textarea")];
    dst.forEach((d, i) => { const s = src[i]; let v;
      if (s.tagName === "SELECT") v = s.selectedOptions[0] ? T(s.selectedOptions[0]) : "";
      else if (s.type === "checkbox") v = s.checked ? "x" : " ";
      else if (s.type === "file") v = "file";
      else v = s.value === "" && s.placeholder ? "(" + s.placeholder + ")" : s.value;
      d.replaceWith(document.createTextNode(" {" + v + "} ")); });
    return c;
  }
  const rowsOf = t => [...t.querySelectorAll("tr")].map(tr => [...tr.children].map(T).join(" | "));
  function readInterline() {
    const b = R.querySelector(".board");
    if (!b) return null;
    const il = b.querySelector("table.il");
    const rows = il ? [...il.querySelectorAll("tr")].slice(1).map(tr => { const td = [...tr.children], img = td[0] && td[0].querySelector("img");
      return { cls: tr.className.trim(), first: img ? img.alt : T(td[0]), cells: [...plain(tr).children].slice(1).map(T) }; }) : [];
    const other = [...b.querySelectorAll("table.tbl:not(.il)")][0];
    return { heads: [...b.querySelectorAll("h3.rh")].map(T), chips: [...b.querySelectorAll(".chips .chip")].map(c => (c.classList.contains("on") ? "*" : "") + T(c)),
      rows, countries: other ? [...other.querySelectorAll("tr")].map(tr => [...tr.children].map(td => T(td) + [...td.querySelectorAll("a")].map(a => " <" + a.getAttribute("href") + ">").join("")).join(" | ")) : [],
      notes: [...b.querySelectorAll("div.note")].map(T), empty: [...b.querySelectorAll("div.dim")].filter(e => !e.closest("table")).map(T) };
  }
  function readPhotos() {
    const r = R.querySelector("#ph-root");
    if (!r) return null;
    const card = c => { const img = c.querySelector(".ph-img img"), box = c.querySelector(".ph-img").cloneNode(true);
      box.querySelectorAll(".tag, img").forEach(x => x.remove());
      return [c.dataset.lg || c.dataset.ph, img ? "photo" : "no photo: " + T(box), T(c.querySelector(".ph-img .tag")), T(c.querySelector(".ph-body b")),
              T(c.querySelector(".ph-body .small")), T(c.querySelector(".ph-acts")), c.querySelector("[data-ph-credit]") ? "credit box" : ""].join(" | "); };
    return { note: T(r.querySelector(".ph-note")), heads: [...r.querySelectorAll("h3.rh")].map(T), intro: T(r.querySelector("p.note")),
      logos: [...r.querySelectorAll("[data-lg]")].map(card), tools: T(r.querySelector(".ph-tools")), missing: !!(r.querySelector("#ph-missing") || {}).checked,
      cards: [...r.querySelectorAll("[data-ph]")].map(card), empty: T(r.querySelector(".ph-grid > .empty")) };
  }
  function readRef() {
    return [...R.querySelectorAll("details.rsec")].map(d => {
      const s = d.querySelector("summary"), p = plain(d.querySelector(".rsb"));
      const tables = [...p.querySelectorAll("table")].map(rowsOf);
      p.querySelectorAll("table").forEach(t => t.remove());
      const notes = [...p.querySelectorAll("div.note")].map(T);
      p.querySelectorAll("div.note").forEach(t => t.remove());
      return { key: d.dataset.rsec, title: T(s.querySelector(".rst")), note: T(s.querySelector(".note")), tables, notes, rest: T(p) };
    });
  }
"""
READ_INTERLINE = READ + "return readInterline(); }"
READ_PHOTOS = READ + "return readPhotos(); }"
READ_REF = READ + "return readRef(); }"
NEW_ROOT = {"interline": "main[data-screen=interline]", "photos": "main[data-screen=photos]", "reference": "main[data-screen=reference]"}
OLD_ROOT = "#view"


# ---------- the two planners
class OldPlanner(OldReview):
    """The old planner (real_saves_test.py's, as the Review side by side opens it): its clock frozen, with the hook."""

    async def show(self, view, extra=""):
        await self.run(f"Object.assign(ui, {{view: {json.dumps(view)}, modal: null}}); {extra}; render(); true")
        await settle(self.pg, 250)

    async def photos(self):
        await self.show("photos")
        await self.pg.wait_for_function("() => window.__eqOld('!!EQM')", timeout=30000)
        await self.run("eqRefresh(); true")
        await settle(self.pg, 250)

    async def ref(self):
        await self.show("ref")
        await self.pg.evaluate("document.querySelectorAll('#view details.rsec').forEach(d => { d.open = true; })")
        await settle(self.pg, 250)


async def new_go(pl, to, ready, extra=None):
    """The new planner at one of its addresses (inside the router, as a click would take it), once it has read everything."""
    await pl.pg.evaluate("t => window.__eqPlanner.go(t)", to)
    await pl.pg.wait_for_selector(ready, timeout=90000)
    if extra:
        await pl.pg.wait_for_function(extra, timeout=30000)
    await settle(pl.pg, 250)


INTERLINE_READY = "main[data-screen=interline][data-interline-ready=yes]"
PHOTOS_READY = "main[data-screen=photos][data-photos-ready=yes]"
REF_READY = "main[data-screen=reference][data-reference-ready=yes]"


async def new_interline(pl, search=""):
    await new_go(pl, "/interline" + search, INTERLINE_READY,
                 f"() => (document.querySelector('main[data-screen=interline]') || {{dataset: {{}}}}).dataset.interlineView === {json.dumps(search)}")


async def new_ref(pl, slug):
    await new_go(pl, "/reference/" + slug, REF_READY, f"() => !!document.querySelector('details.rsec[data-section={slug}][open]')")


# ---------- the photo bucket, answered in the browser (the copy has no storage service)
def hook_storage(pl):
    """Answers the planner's requests for the photo bucket in its own browser: an upload is kept (what it sent) and
    answered as the bucket would, a removal answered, a picture asked for is not there."""
    pl.uploads, pl.pictures = [], 0

    async def handle(r):
        req = r.request
        path = urlsplit(req.url).path.split("/storage/v1/", 1)[-1]
        if req.method == "GET":
            pl.pictures += 1
            await r.fulfill(status=404, content_type="application/json", body='{"error":"not in the test"}')
            return
        body = req.post_data_buffer or b""
        headers = await req.all_headers()
        part = re.search(rb"Content-Type: (image/[\w.+-]+)", body)
        cache = re.search(rb'name="cacheControl"\r\n\r\n([^\r\n]*)', body)
        pl.uploads.append({"method": req.method, "object": path.split("object/", 1)[-1],
                           "type": part[1].decode() if part else headers.get("content-type", "").split(";")[0],
                           "cache": cache[1].decode() if cache else headers.get("cache-control", ""),
                           "upsert": headers.get("x-upsert", ""), "image": image_facts(body)})
        if req.method == "DELETE":
            await r.fulfill(status=200, content_type="application/json", body="[]")
        else:
            key = path.split("object/", 1)[-1]
            await r.fulfill(status=200, content_type="application/json", body=json.dumps({"Key": key, "Id": "test"}))
    return handle


def image_facts(body):
    """What picture a request carries: JPEG or PNG and its size, read from the bytes."""
    i = body.find(b"\xff\xd8\xff")
    if i >= 0:
        j = i + 2
        while j < len(body) - 9:
            if body[j] != 0xFF:
                j += 1
                continue
            m = body[j + 1]
            if m in (0xC0, 0xC1, 0xC2):
                h, w = struct.unpack(">HH", body[j + 5:j + 9])
                return f"JPEG {w}x{h}"
            if m == 0xD8 or m == 0x01 or 0xD0 <= m <= 0xD7 or m == 0xFF:
                j += 2 if m != 0xFF else 1
                continue
            j += 2 + struct.unpack(">H", body[j + 2:j + 4])[0]
        return "JPEG"
    i = body.find(b"\x89PNG\r\n\x1a\n")
    if i >= 0:
        w, h = struct.unpack(">II", body[i + 16:i + 24])
        return f"PNG {w}x{h}"
    return "no picture" if body else ""


def test_png(w=320, h=200):
    """A small picture made here (a colour ramp), so nothing is read from outside."""
    rows = b"".join(b"\x00" + bytes(v for x in range(w) for v in (x * 255 // (w - 1), y * 255 // (h - 1), 160)) for y in range(h))

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b"")


# ---------- comparing
def undefined_ok(o, n):
    """True when the old words differ from the new only where the old box says "undefined"."""
    if "{undefined}" not in o:
        return False
    pat = "".join(r"\{[^}]*\}" if part == "{undefined}" else re.escape(part) for part in re.split(r"(\{undefined\})", o))
    return re.fullmatch(pat, n) is not None


def same_words(label, o, n, p):
    if o == n:
        return
    if undefined_ok(o, n):
        known("undefined box", f"{label}: old {o[:90]!r}, new {n[:90]!r}")
    else:
        p.append(f"{label}: old {o!r}, new {n!r}"[:700])


def compare_interline(label, o, n):
    p = []
    if o is None or n is None:
        return [f"{label}: the {'old' if o is None else 'new'} board isn't there"]
    for k in ("heads", "chips", "countries", "notes", "empty"):
        if o[k] != n[k]:
            p.append(f"{label}: {k}: old {o[k]!r}, new {n[k]!r}"[:900])
    if len(o["rows"]) != len(n["rows"]):
        p.append(f"{label}: old {len(o['rows'])} rows, new {len(n['rows'])}: old {[r['cells'][:1] for r in o['rows']][:20]}, new {[r['cells'][:1] for r in n['rows']][:20]}"[:900])
    for a, b in zip(o["rows"], n["rows"]):
        if a != b:
            p.append(f"{label} {a['first'] or ''} {(a['cells'] or ['?'])[0]}: old {a}, new {b}"[:700])
    return p


def compare_photos(label, o, n):
    p = []
    if o is None or n is None:
        return [f"{label}: the {'old' if o is None else 'new'} screen isn't there"]
    for k in ("note", "heads", "intro", "tools", "missing", "cards", "empty"):
        if o[k] != n[k]:
            p.append(f"{label}: {k}: old {o[k]!r}, new {n[k]!r}"[:900])
    if o["logos"] != n["logos"]:
        if sorted(o["logos"]) == sorted(n["logos"]):
            known("logo order", f"old {[x.split(' | ')[0] for x in o['logos']]}, new {[x.split(' | ')[0] for x in n['logos']]}")
        else:
            p.append(f"{label}: logos: old {o['logos']!r}, new {n['logos']!r}"[:900])
    return p


COUNTS = re.compile(r"\d+ frequencies, \d+ tails, \d+ route edits, \d+ markets, \d+ service profiles")


def compare_ref(o, n):
    p = []
    if not o or not n:
        return [f"the {'old' if not o else 'new'} Reference has no sections"]
    if [s["title"] for s in o] != [s["title"] for s in n]:
        p.append(f"the sections: old {[s['title'] for s in o]}, new {[s['title'] for s in n]}")
    news = {s["title"]: s for s in n}
    for a in o:
        b = news.get(a["title"])
        t = a["title"]
        if not b:
            continue
        if a["key"] != b["key"]:
            p.append(f"{t}: its key: old {a['key']!r}, new {b['key']!r}")
        if a["note"] != b["note"]:
            if t == "Aircraft":
                known("learned speeds", f"the note: old {a['note'][:80]!r}, new {b['note'][:80]!r}")
            else:
                p.append(f"{t}: the note: old {a['note']!r}, new {b['note']!r}")
        if len(a["tables"]) != len(b["tables"]):
            p.append(f"{t}: old {len(a['tables'])} tables, new {len(b['tables'])}")
        for i, (ta, tb) in enumerate(zip(a["tables"], b["tables"])):
            if len(ta) != len(tb):
                p.append(f"{t}: old {len(ta)} rows, new {len(tb)}: old {[r.split(' | ')[0] for r in ta][:12]}, new {[r.split(' | ')[0] for r in tb][:12]}"[:700])
            for ra, rb in zip(ta, tb):
                if ra == rb:
                    continue
                ca, cb = ra.split(" | "), rb.split(" | ")
                if t == "Aircraft" and len(ca) == len(cb) == 8 and ca[6] != cb[6]:
                    known("learned speeds", f"{ca[0][:30]}: old {ca[6]!r}, new {cb[6]!r}")
                    ca[6] = cb[6] = ""
                    ra, rb = " | ".join(ca), " | ".join(cb)
                    if ra == rb:
                        continue
                same_words(f"{t}: {ra.split(' | ')[0][:30]}", ra, rb, p)
        if b["notes"] and not a["notes"] and t in ("Constants", "Data"):
            known("rule notes" if t == "Constants" else "import and clear", f"{t}: {b['notes'][0][:80]!r}")
        elif a["notes"] != b["notes"]:
            p.append(f"{t}: notes: old {a['notes']!r}, new {b['notes']!r}"[:700])
        if a["rest"] != b["rest"]:
            if t == "Storage":
                ca, cb = COUNTS.search(a["rest"]), COUNTS.search(b["rest"])
                if ca and cb and ca[0] == cb[0]:
                    known("storage words", f"old {a['rest'][:70]!r}, new {b['rest'][:70]!r}")
                else:
                    p.append(f"Storage: old {a['rest']!r}, new {b['rest']!r}"[:700])
            elif t == "Data" and all(x in a["rest"] and x in b["rest"] for x in ("Export backup (JSON)", "Export flights (CSV)")):
                known("import and clear", f"old {a['rest'][:90]!r}, new {b['rest'][:90]!r}")
            else:
                same_words(f"{t}: the words around the tables", a["rest"], b["rest"], p)
    return p


# ---------- 2. Interline, 3. Photos, 4. Reference
async def interline_screens(old, new):
    p, views = [], []
    COPY["il_rows"] = await interline_rows(new)
    names = {x["code"]: x["name"] for x in COPY["airlines"]}
    first = next((r["code"] for r in COPY["il_rows"] if r["code"] in names), None)
    al = {"code": first, "name": names[first]} if first else None
    for label, ilf, search in (("all", {}, ""), (f"airline {al['code'] if al else '-'}", {"al": al["name"]} if al else None, f"?airline={al['code']}" if al else None),
                               ("still to sign", {"status": "open"}, "?status=open"), ("signed", {"status": "signed"}, "?status=signed")):
        if ilf is None:
            continue
        await old.show("interline", f"ui.ilf = {json.dumps(ilf)}")
        o = await old.pg.evaluate(READ_INTERLINE, OLD_ROOT)
        await new_interline(new, search)
        n = await new.pg.evaluate(READ_INTERLINE, NEW_ROOT["interline"])
        p += compare_interline(f"Interline ({label})", o, n)
        views.append(f"{label}: {len((n or {}).get('rows', []))} rows")
    await old.show("interline", "ui.ilf = {}")
    n = await new.pg.evaluate(READ_INTERLINE, NEW_ROOT["interline"])
    return (f"Interline equals the old one: the agreements board ({'; '.join(views)}), its filters in the address, the "
            f"{max(0, len((n or {}).get('countries', [])) - 1)} interline countries with their partners, and the notes"), p


async def photos_screens(old, new):
    p = []
    await old.photos()
    o = await old.pg.evaluate(READ_PHOTOS, OLD_ROOT)
    await new_go(new, "/photos", PHOTOS_READY)
    n = await new.pg.evaluate(READ_PHOTOS, NEW_ROOT["photos"])
    p += compare_photos("Photos (missing a photo)", o, n)
    await old.pg.click("#view #ph-missing")
    await new.pg.click("main[data-screen=photos] #ph-missing")
    await settle(old.pg, 300)
    await settle(new.pg, 300)
    o2 = await old.pg.evaluate(READ_PHOTOS, OLD_ROOT)
    n2 = await new.pg.evaluate(READ_PHOTOS, NEW_ROOT["photos"])
    p += compare_photos("Photos (all)", o2, n2)
    await old.pg.click("#view #ph-missing")
    await new.pg.click("main[data-screen=photos] #ph-missing")
    return (f"Photos equals the old one: {len((n or {}).get('logos', []))} logos, {len((n or {}).get('cards', []))} destinations missing a photo "
            f"and all {len((n2 or {}).get('cards', []))}, with their photos, flights a week, credits and buttons"), p


async def reference_screens(old, new):
    await old.ref()
    o = await old.pg.evaluate(READ_REF, OLD_ROOT)
    await new_go(new, "/reference", REF_READY)
    folded = await new.pg.evaluate("[...document.querySelectorAll('main[data-screen=reference] details.rsec')].every(d => !d.open)")
    n = await new.pg.evaluate(READ_REF, NEW_ROOT["reference"])
    p = compare_ref(o, n)
    if not folded:
        p.append("the new Reference's sections aren't all folded on arrival")
    # a section's address opens it, and opening another puts that one in the address
    await new_ref(new, "night-bans")
    await new.pg.click("details.rsec[data-section=constants] > summary")
    await new.pg.wait_for_function("() => location.pathname.endsWith('/reference/constants')", timeout=10000)
    rows = sum(len(t) for s in (n or []) for t in s["tables"])
    return (f"Reference equals the old one: {len(n or [])} sections ({', '.join(s['title'] for s in (n or []))}), {rows} table rows with "
            "every box's value, the words around them; folded on arrival, a section's address opening it"), p


# ---------- 5. the header search
async def new_search(new, q):
    await new.pg.fill("#gsearch", q)
    await new.pg.wait_for_function("() => (document.querySelector('.gs') || {dataset: {}}).dataset.searchReady === 'yes'", timeout=60000)
    await settle(new.pg, 120)
    return await new.pg.evaluate("""() => { const b = document.querySelector('#gsr'); if (!b || b.style.display === 'none') return [];
        return [...b.querySelectorAll('.gsi')].map(x => { const k = x.querySelector('.gsk'), kind = k ? k.textContent : '';
          return kind + ': ' + x.textContent.slice(kind.length).replace(/\\s+/g, ' ').trim(); })
          .concat([...b.querySelectorAll('.gse')].map(e => 'empty: ' + e.textContent.trim())); }""")


def search_queries():
    c = COPY["search"]
    qs = []
    if c.get("flight"):
        code, no = c["flight"]
        qs += [f"{code} {no}", f"{code}{no}", str(no), str(no)[:2]]
    if c.get("reg"):
        qs.append(c["reg"].replace("-", "")[-3:])
    if c.get("order"):
        qs.append(c["order"])
    if c.get("planned"):
        qs.append(str(c["planned"]))
    if c.get("pair"):
        h, d = c["pair"]
        qs += [f"{h}-{d}", f"{d} {h}"]
    if c.get("airport"):
        qs.append(c["airport"])
    if c.get("city"):
        qs.append(c["city"])
    return qs + ["QQZZ"]


async def search(old, new):
    p, n_hits = [], 0
    qs = search_queries()
    await new_go(new, "/", "main[data-screen=home][data-home-ready=yes]")
    for q in qs:
        o = json.loads(await old.run(f"""JSON.stringify((() => {{ const r = searchAll({json.dumps(q)});
            return r.map(x => x.kind + ': ' + x.label).concat(!r.length && {json.dumps(q)}.trim().length >= 2 ? ['empty: Nothing found'] : []); }})())"""))
        n = await new_search(new, q)
        n_hits += len(n)
        if o == n:
            continue
        loose = lambda xs: [x for x in xs if not x.startswith(("Airport:", "Route:"))]
        if sorted(o) == sorted(n) and loose(o) == loose(n):
            known("order on a tie", f"{q!r}: {len(o)} results")
        else:
            p.append(f"{q!r}: old {o}, new {n}"[:900])
    # Enter opens the first result's new screen: a flight or a route its route, an aircraft its page, an aircraft on order
    # or a planned flight its card on Tails, an airport the airline's routes there
    opened = []
    c = COPY["search"]
    for q in (f"{c['flight'][0]} {c['flight'][1]}" if c.get("flight") else None, c.get("reg"), c.get("airport"), c.get("order")):
        if not q:
            continue
        hits = await new_search(new, q)
        if not hits or hits[0].startswith("empty:"):
            continue
        kind, label = hits[0].split(": ", 1)
        await new.pg.press("#gsearch", "Enter")
        await settle(new.pg, 500)
        path, s = await new.pg.evaluate("[location.pathname, location.search]")
        first = label.split(" ")[0]
        ok = {"Flight": lambda: re.fullmatch(r"/planner/next/routes/[^/]+/[A-Z0-9]{3}-[A-Z0-9]{3}", path),
              "Route": lambda: re.fullmatch(r"/planner/next/routes/[^/]+/" + re.escape(label.split(" ")[0].replace("–", "-")), path),
              "Aircraft": lambda: path == f"/planner/next/tails/{first}",
              "On order": lambda: path == "/planner/next/tails" and f"card={first}" in s,
              "Planned": lambda: path == "/planner/next/tails" and "card=" in s,
              "Airport": lambda: path == "/planner/next/routes" and f"q={first}" in s}.get(kind, lambda: False)()
        if not ok:
            p.append(f"Enter on {q!r} (first result {hits[0]!r}) opened {path}{s}")
        else:
            opened.append(f"{q!r} ({kind.lower()})")
        await new_go(new, "/", "main[data-screen=home][data-home-ready=yes]")
    return (f"the header search gives the old planner's results for {len(qs)} queries made from the copy ({', '.join(repr(q) for q in qs)}; "
            f"{n_hits} results in all), and Enter opens the first result's new screen for {', '.join(opened) or 'none'}"), p


# ---------- 6. the exports
async def exports(old, new):
    p = []
    o = (await old.run("flightsCsv()")).split("\n")
    await new_ref(new, "data")
    async with new.pg.expect_download(timeout=60000) as d:
        await new.pg.click("#expcsv")
    n = Path(await (await d.value).path()).read_text().split("\n")
    est = COPY["est_flights"]
    if len(o) != len(n):
        p.append(f"Export flights: old {len(o)} lines, new {len(n)}")
    for a, b in zip(o, n):
        if a == b:
            continue
        ca, cb = next(csv.reader([a]), []), next(csv.reader([b]), [])
        if len(ca) == len(cb) == 17 and ca[0] in est and [x for i, x in enumerate(ca) if i not in (6, 7, 8, 16)] == [x for i, x in enumerate(cb) if i not in (6, 7, 8, 16)]:
            known("block estimates", f"Export flights {ca[0]}: old {ca[6:9] + ca[16:]}, new {cb[6:9] + cb[16:]}")
        else:
            p.append(f"Export flights: old {a}, new {b}"[:500])
    async with new.pg.expect_download(timeout=60000) as d:
        await new.pg.click("#exp")
    j = json.loads(Path(await (await d.value).path()).read_text())
    have = {t: len(v) for t, v in (j.get("tables") or {}).items()}
    want = {t: int(psql(f"select count(*) from public.{t} where world_id = {WORLD}").strip()) for t in ("routes", "rotations", "flight_legs", "aircraft", "airline_bases")}
    for t, k in want.items():
        if have.get(t) != k:
            p.append(f"Export backup: {t}: {have.get(t)} rows, the copy has {k}")
    return (f"Export flights (CSV) gives the old planner's file ({len(n) - 1} flights), and Export backup (JSON) every planner table "
            f"({len(have)} tables; {', '.join(f'{t} {k}' for t, k in want.items())} rows as the copy has)"), p


# ---------- 7. edits in both
def table_columns(table):
    return [r for r in psql("""select column_name from information_schema.columns where table_schema = 'public' and table_name = :'t'
                                and is_generated = 'NEVER' order by ordinal_position""", t=table).split() if r]


def raw(table, where):
    return psql(f"select coalesce(json_agg(t), '[]') from public.{table} t where {where}").strip()


def snapshot(table, where):
    """The rows as JSON without their ids and times (each side writes its own), in a fixed order."""
    rows = json.loads(raw(table, where))
    for r in rows:
        for c in ("id", "created_at", "updated_at", "at"):
            r.pop(c, None)
    return sorted(rows, key=lambda r: json.dumps(r, sort_keys=True))


def put_back(table, where, rows_json, pk=("id",)):
    """The table's rows for the key as they were: a row added taken out, a row changed set back (in place, so nothing that
    points at it is touched), a row taken out put back with its key (the change log off for the test's own moves)."""
    cols = table_columns(table)
    rest = [c for c in cols if c not in pk]
    match = " and ".join(f"t.{c} = r.{c}" for c in pk)
    ident = "overriding system value" if "id" in pk else ""
    psql(f"""set equinox.change_log = 'off';
        delete from public.{table} t where {where} and not exists (select 1 from json_populate_recordset(null::public.{table}, :'rows'::json) r where {match});
        update public.{table} t set ({', '.join(rest)}) = row({', '.join('r.' + c for c in rest)})
          from json_populate_recordset(null::public.{table}, :'rows'::json) r
         where {match} and (to_jsonb(t) - 'updated_at') is distinct from (to_jsonb(r) - 'updated_at');
        insert into public.{table} ({', '.join(cols)}) {ident}
        select {', '.join('r.' + c for c in cols)} from json_populate_recordset(null::public.{table}, :'rows'::json) r
         where not exists (select 1 from public.{table} t where {match});""", rows=rows_json)


def kinds(rows):
    return Counter((r["table"], r["op"]) for r in rows)


async def both(name, old, new, tables, acts_new, acts_old, view):
    """Edits in the new planner, the copy put back, then the same in the old one: the same rows and kinds of change, logged
    as planner with the tab's ID; view(): what the old planner, opened again, shows, the same after either."""
    problems = []
    before = {t: raw(t, k) for t, (k, pk) in tables.items()}

    def put_back_all():
        for t, (k, pk) in tables.items():
            put_back(t, k, before[t], pk)
    new_log = old_log = []
    new_rows = old_rows = {}
    shown_new = shown_old = None
    try:
        await refresh(new)
        client = await new.pg.evaluate("window.__eqPlanner.client")
        mark = marks()
        for act in acts_new:
            m = marks()
            await act()
            got = await rs.wait_for(lambda: log_since(m), lambda got: len(got) >= 1, seconds=20)
            if not got:
                problems.append(f"the new planner wrote nothing for {act.__doc__ or act.__name__}")
        await until_quiet()
        new_log = log_since(mark)
        new_rows = {t: snapshot(t, k) for t, (k, pk) in tables.items()}
        problems += [f"a change-log row names {r['actor']} ({r['detail']}), not planner with the tab's ID" for r in new_log
                     if r["actor"] != "planner" or r["detail"] != client]
        await old.reopen()
        shown_new = await view()
        put_back_all()
        await old.reopen()
        mark2 = marks()
        for act in acts_old:
            m = marks()
            await act()
            got = await rs.wait_for(lambda: log_since(m), lambda got: len(got) >= 1, seconds=20)
            if not got:
                problems.append(f"the old planner wrote nothing for {act.__doc__ or act.__name__}")
        await until_quiet()
        old_log = log_since(mark2)
        old_rows = {t: snapshot(t, k) for t, (k, pk) in tables.items()}
        await old.reopen()
        shown_old = await view()
    finally:
        put_back_all()
    if shown_new != shown_old:
        problems.append(f"the old planner, opened again, shows {shown_new} after the new planner's edits and {shown_old} after its own"[:900])
    if kinds(new_log) != kinds(old_log):
        problems.append(f"the new planner changed {dict(kinds(new_log))}, the old {dict(kinds(old_log))}")
    for t in tables:
        if new_rows.get(t) != old_rows.get(t):
            problems.append(f"{t} after the new planner's edits differs from the old's: new {new_rows.get(t)}, old {old_rows.get(t)}"[:1200])
    late = [t for t, (k, pk) in tables.items() if snapshot(t, k) != sorted((dict((c, v) for c, v in r.items() if c not in ("id", "created_at", "updated_at", "at")) for r in json.loads(before[t])), key=lambda r: json.dumps(r, sort_keys=True))]
    if late:
        problems.append(f"{', '.join(late)} not as they were after putting back")
    return (f"{name}: {dict(kinds(new_log))}, the same rows as the old planner's, logged as planner with the tab's ID; the old "
            f"planner, opened again, shows it"), problems


async def old_fill(old, sel, v):
    await old.pg.fill(sel, v)
    await old.pg.dispatch_event(sel, "change")


async def new_fill(new, sel, v):
    await new.pg.fill(sel, v)
    await new.pg.press(sel, "Enter")


async def interline_edits(old, new):
    il = COPY["il_rows"]
    if not il:
        return "Interline edits: the copy has no airline–country row", []
    a = next((r for r in il if r["status"] == "none"), None)
    b = next((r for r in il if r["status"] != "none" and r is not a), None) or a
    if not a:
        a = b
    names = {x["code"]: x["name"] for x in COPY["airlines"]}
    old_key = lambda r: f"{names[r['code']]}|{r['cc']}"
    new_key = lambda r: f"{r['code']}|{r['cc']}"
    sel = lambda k, f: f"[data-il={json.dumps(k)}][data-ilk={f}]"
    note = "rehearsal note " + secrets.token_hex(2)

    async def new_status():
        "a status"
        await new_interline(new)
        await new.pg.select_option(sel(new_key(a), "status"), "requested" if a["status"] == "none" else "none")

    async def new_note():
        "a note"
        await new_interline(new)
        await new_fill(new, sel(new_key(b), "notes"), note)

    async def old_status():
        await old.show("interline", "ui.ilf = {}")
        await old.pg.select_option(sel(old_key(a), "status"), "requested" if a["status"] == "none" else "none")

    async def old_note():
        await old.show("interline", "ui.ilf = {}")
        await old_fill(old, sel(old_key(b), "notes"), note)

    async def view():
        return json.loads(await old.run(f"JSON.stringify([{json.dumps(old_key(a))}, {json.dumps(old_key(b))}].map(k => (state.interline || {{}})[k] || null))"))
    w = COPY["world"]
    label, problems = await both(f"Interline: {a['code']} {a['cc']}'s status ({a['status']} → {'requested' if a['status'] == 'none' else 'none'}) and a note on "
                                 f"{b['code']} {b['cc']}", old, new, {"interline_agreements": (f"world_id = {w}", ("id",))},
                                 [new_status, new_note], [old_status, old_note], view)
    return label, problems


async def reference_edits(old, new):
    c, w = COPY["ref"], COPY["world"]
    acts_new, acts_old, tables, what, views = [], [], {}, [], []
    hb = c.get("hub")
    if hb:
        i, t = hb["i"], hb["bank1"]
        h, m = divmod(int(t[:2]) * 60 + int(t[3:5]) + 5, 60)
        v = f"{h % 24:02d}:{m:02d}"
        s = f"[data-ref='hubs.{i}.banks.0']"

        async def n1():
            "a bank time"
            await new_ref(new, "hubs")
            await new_fill(new, s, v)

        async def o1():
            await old.ref()
            await old_fill(old, s, v)
        acts_new.append(n1)
        acts_old.append(o1)
        tables["airline_bases"] = (f"id = {hb['id']}", ("id",))
        what.append(f"{hb['code']}'s bank 1 {t} → {v}")
        views.append(f"state.ref.hubs[{i}].banks")
    if c.get("buf") is not None:
        v = str(int(c["buf"]) + 1)

        async def n2():
            "a constant"
            await new_ref(new, "constants")
            await new_fill(new, "[data-ref='consts.buf']", v)

        async def o2():
            await old.ref()
            await old_fill(old, "[data-ref='consts.buf']", v)
        acts_new.append(n2)
        acts_old.append(o2)
        tables["settings"] = (f"world_id = {w} and airline_id is null and key = 'bank_buffer_min'", ("id",))
        what.append(f"the bank buffer {c['buf']} → {v}")
        views.append("state.ref.consts.buf")
    tp = c.get("type")
    if tp:
        v = str(int(tp["min_turn"] or 0) + 5)

        async def n3():
            "a type's minimum turn"
            await new_ref(new, "aircraft")
            await new_fill(new, "[data-ref='types.0.minTurn']", v)

        async def o3():
            await old.ref()
            await old_fill(old, "[data-ref='types.0.minTurn']", v)
        acts_new.append(n3)
        acts_old.append(o3)
        tables["aircraft_types"] = (f"id = {tp['id']}", ("id",))
        what.append(f"{tp['name']}'s minimum turn {tp['min_turn']} → {v}")
        views.append("state.ref.types[0]")

    async def n4():
        "Add config"
        await new_ref(new, "configs")
        await new.pg.click("main[data-screen=reference] [data-addrow=configs]")

    async def o4():
        await old.ref()
        await old.pg.click("#view [data-addrow=configs]")
    acts_new.append(n4)
    acts_old.append(o4)
    tables["cabin_configs"] = (f"world_id = {w} and id > {c['max_config']}", ("id",))
    what.append("Add config")
    views.append("state.ref.configs.slice(-1)")
    ban = c.get("ban")
    if ban:
        async def n5():
            "a night ban"
            await new_ref(new, "night-bans")
            await new.pg.fill("#cf-code", ban)
            await new.pg.fill("#cf-val", "00:30-05:30")
            await new.pg.click("#cf-add")

        async def o5():
            await old.ref()
            await old.pg.fill("#cf-code", ban)
            await old.pg.fill("#cf-val", "00:30-05:30")
            await old.pg.click("#cf-add")
        acts_new.append(n5)
        acts_old.append(o5)
        what.append(f"a night ban at {ban}")
        views.append(f"(state.ref.curfews || {{}})[{json.dumps(ban)}]")
    rm = c.get("removed")
    if rm:
        async def n6():
            "a route restored"
            await new_ref(new, "removed")
            await new.pg.click(f"[data-restore={json.dumps(rm['key'])}]")

        async def o6():
            await old.ref()
            await old.pg.click(f"#view [data-restore={json.dumps(rm['key'])}]")
        acts_new.append(n6)
        acts_old.append(o6)
        tables["routes"] = (f"id = {rm['id']}", ("id",))
        what.append(f"{rm['key'].split('|', 1)[1].replace('|', '–')} restored")
        views.append(f"(state.routeEdits[{json.dumps(rm['key'])}] || {{}}).removed || false")
    tz = c.get("tz")
    if tz:
        v = f"{float(tz['offset']) + 1:g}"

        async def n7():
            "a time zone"
            await new_ref(new, "time-zones")
            await new.pg.fill("#utc-code", tz["code"])
            await new.pg.fill("#utc-val", v)
            await new.pg.click("#utc-set")
            await new.pg.click("[data-confirm-yes]", timeout=20000)

        async def o7():
            await old.ref()
            await old.pg.fill("#utc-code", tz["code"])
            await old.pg.fill("#utc-val", v)
            await old.pg.click("#utc-set")
        acts_new.append(n7)
        acts_old.append(o7)
        what.append(f"{tz['code']}'s UTC offset {tz['offset']} → {v}")
        views.append(f"state.ref.utcOverrides[{json.dumps(tz['code'])}]")
    wa = [x for x in (ban, tz and tz["code"]) if x]
    if wa:
        tables["world_airports"] = (f"world_id = {w} and airport_code in ({', '.join(repr(x) for x in wa)})", ("world_id", "airport_code"))

    async def view():
        return json.loads(await old.run(f"JSON.stringify([{', '.join(views)}])"))
    return await both("Reference: " + "; ".join(what), old, new, tables, acts_new, acts_old, view)


async def photo_upload(old, new):
    code = COPY.get("photo_code")
    if not code:
        return "a photo upload: every destination has a photo", []
    picture = {"name": "test.png", "mimeType": "image/png", "buffer": test_png()}
    credit = "Rehearsal test"
    media = psql("select coalesce((select value::text from public.site_content where key = 'media'), '')").strip()
    entry = f"select coalesce((select value -> 'airports' -> :'c' from public.site_content where key = 'media'), 'null'::jsonb)::text"
    gone = json.loads(psql(entry, c=code).strip()) is None
    problems = [] if gone else [f"{code} has a photo already"]

    def put_back_media():
        if media:
            psql("update public.site_content set value = :'v'::jsonb where key = 'media'", v=media)
        else:
            psql("delete from public.site_content where key = 'media'")

    async def wait_entry():
        for _ in range(80):
            got = json.loads(psql(entry, c=code).strip())
            if got:
                return got
            await asyncio.sleep(0.25)
        return None
    shown_new = shown_old = None
    try:
        new.uploads.clear()
        await new_go(new, "/photos", PHOTOS_READY)
        await new.pg.fill(f"[data-ph-credit={code}]", credit)
        await new.pg.set_input_files(f"[data-ph-up={code}]", picture)
        e_new = await wait_entry()
        await new.pg.wait_for_function("() => (document.querySelector('main[data-screen=photos]') || {dataset: {}}).dataset.photosBusy === ''", timeout=30000)
        await settle(new.pg, 600)
        card_new = await new.pg.evaluate(READ_PHOTOS, NEW_ROOT["photos"])
        up_new = list(new.uploads)
        await old.reopen()
        await old.photos()
        shown_new = await old.run(f"JSON.stringify(eqPhotoOf({json.dumps(code)}))")
        put_back_media()
        await old.reopen()
        old.uploads.clear()
        await old.photos()
        await old.pg.fill(f"#view [data-ph-credit={code}]", credit)
        await old.pg.set_input_files(f"#view [data-ph-up={code}]", picture)
        e_old = await wait_entry()
        await settle(old.pg, 800)
        card_old = await old.pg.evaluate(READ_PHOTOS, OLD_ROOT)
        up_old = list(old.uploads)
        await old.reopen()
        await old.photos()
        shown_old = await old.run(f"JSON.stringify(eqPhotoOf({json.dumps(code)}))")
    finally:
        put_back_media()
    strip = lambda e: {k: v for k, v in (e or {}).items() if k != "at"}
    if not e_new:
        problems.append("the new planner's upload didn't reach the website's row")
    if strip(e_new) != strip(e_old):
        problems.append(f"the website's row for {code}: new {strip(e_new)}, old {strip(e_old)}")
    if up_new != up_old:
        problems.append(f"sent to the bucket: new {up_new}, old {up_old}")
    if not up_new or up_new[0].get("image") != "JPEG 320x200" or up_new[0].get("type") != "image/jpeg":
        problems.append(f"the new planner sent {up_new}, not the picture as a 320×200 JPEG")
    for k in ("note", "cards"):
        if (card_new or {}).get(k) != (card_old or {}).get(k):
            problems.append(f"after the upload the screen's {k}: new {(card_new or {}).get(k)!r}, old {(card_old or {}).get(k)!r}"[:700])
    if shown_new != shown_old:
        problems.append(f"the old planner, opened again, shows {shown_new} after the new planner's upload and {shown_old} after its own")
    if json.loads(psql(entry, c=code).strip()) is not None:
        problems.append("the website's row wasn't put back")
    u = up_new[0] if up_new else {}
    return (f"a destination photo uploaded ({code}, a 320×200 test picture with a credit) in the new Photos and in the old: the "
            f"same file sent to the bucket ({u.get('method')} {re.sub(r'-[0-9]+[.]', '-<time>.', u.get('object', ''))}, {u.get('type')}, "
            f"{u.get('image')}, cache {u.get('cache')}), the same website row (site_set_airport_photo), the same words on the "
            "card; the old planner, opened again, shows it"), problems


# ---------- 8. a preview, 9. a phone and the screenshots
async def preview(p, port, env, facts, staff, moment, seen):
    pv = pn.Planner(p, port, env, facts)
    seen.append(pv)
    problems, did = [], []
    try:
        await pv.open(host="127.0.0.1", moment=moment)
        await pv.ctx.route("**/storage/v1/**", hook_storage(pv))
        await pv.sign_in(*staff)
        n0, mark = counts(), marks()
        await new_go(pv, "/photos", PHOTOS_READY)
        up = await pv.pg.evaluate("(document.querySelector('[data-ph-up]') || {dataset: {}}).dataset.phUp || ''")
        if up:
            await pv.pg.set_input_files(f"[data-ph-up={up}]", {"name": "test.png", "mimeType": "image/png", "buffer": test_png(64, 40)})
            did.append("an upload")
            await settle(pv.pg, 800)
        await new_interline(pv)
        sel = await pv.pg.evaluate("(document.querySelector('select[data-ilk=status]') || {dataset: {}}).dataset.il || ''")
        if sel:
            await pv.pg.select_option(f"select[data-il={json.dumps(sel)}][data-ilk=status]", "declined")
            did.append("an interline status")
            await settle(pv.pg, 800)
        await new_ref(pv, "constants")
        await new_fill(pv, "[data-ref='consts.buf']", "99")
        did.append("a constant")
        await settle(pv.pg, 800)
        state = await pv.pg.evaluate("(document.querySelector('[data-save-state]') || {}).textContent")
        if state != "preview · not saved":
            problems.append(f"the header says {state!r}, not \"preview · not saved\"")
        for fn in ("planner_save", "site_set_airport_photo", "site_set_airline_logo"):
            if fn in pv.rpcs:
                problems.append(f"the preview sent {fn}() to the copy")
        if pv.uploads:
            problems.append(f"the preview sent {len(pv.uploads)} request(s) to the photo bucket")
        if log_since(mark):
            problems.append("the tables changed")
        problems += count_changes(n0, counts()) + pv.errors
    finally:
        await pv.close()
    return (f"a preview address (127.0.0.1) shows Interline, Photos and Reference, and {', '.join(did) or 'nothing'} there send nothing "
            f"(no write, no upload; it called {', '.join(sorted(set(pv.rpcs))) or 'nothing'})"), problems


SCROLL = "Math.max(document.documentElement.scrollWidth, document.body.scrollWidth) - window.innerWidth"


async def phone(p, port, env, facts, staff, moment, seen):
    ph = pn.Planner(p, port, env, facts, width=380, height=800)
    seen.append(ph)
    problems = []
    if SCREENS_DIR:
        Path(SCREENS_DIR).mkdir(parents=True, exist_ok=True)
    try:
        await ph.open(moment=moment)
        await ph.pg.emulate_media(reduced_motion="reduce")
        await ph.sign_in(*staff)
        for sid, go in (("interline", lambda: new_interline(ph)), ("photos", lambda: new_go(ph, "/photos", PHOTOS_READY)), ("reference", lambda: new_go(ph, "/reference", REF_READY))):
            await go()
            if sid == "reference":
                await ph.pg.evaluate("document.querySelectorAll('main[data-screen=reference] details.rsec').forEach(d => { d.open = true; })")
            await settle(ph.pg, 400)
            if (over := await ph.pg.evaluate(SCROLL)) > 0:
                wide = await ph.pg.evaluate(f"""() => [...document.querySelectorAll('{NEW_ROOT[sid]} *')].filter(e => e.getBoundingClientRect().right > window.innerWidth + 1
                    && !e.closest('.tblwrap, .tscroll')).slice(0, 4).map(e => e.tagName + '.' + [...e.classList].join('.'))""")
                problems.append(f"{sid} scrolls sideways by {over} px at 380 px wide (too wide: {wide})")
            if SCREENS_DIR:
                await ph.pg.screenshot(path=str(Path(SCREENS_DIR) / f"{sid}-380.png"), full_page=True, timeout=90000)
        problems += ph.errors
    finally:
        await ph.close()
    return "at 380 px wide Interline, Photos and Reference (every section open) have no sideways scroll and no errors; wide tables scroll in their own box", problems


async def screenshots(old, new):
    if not SCREENS_DIR:
        return
    Path(SCREENS_DIR).mkdir(parents=True, exist_ok=True)
    for width, height in ((1280, 900), (380, 800)):
        await old.pg.set_viewport_size({"width": width, "height": height})
        for sid, show in (("interline", lambda: old.show("interline", "ui.ilf = {}")), ("photos", old.photos), ("reference", old.ref)):
            await show()
            await settle(old.pg, 300)
            await old.pg.screenshot(path=str(Path(SCREENS_DIR) / f"old-{sid}-{width}.png"), full_page=True, timeout=90000)
    await old.pg.set_viewport_size({"width": 1440, "height": 1000})
    for sid, go in (("interline", lambda: new_interline(new)), ("photos", lambda: new_go(new, "/photos", PHOTOS_READY)), ("reference", lambda: new_go(new, "/reference", REF_READY))):
        await go()
        if sid == "reference":
            await new.pg.evaluate("document.querySelectorAll('main[data-screen=reference] details.rsec').forEach(d => { d.open = true; })")
        await settle(new.pg, 400)
        await new.pg.screenshot(path=str(Path(SCREENS_DIR) / f"{sid}-1280.png"), full_page=True, timeout=90000)


# ---------- what the copy holds
def one(sql, **v):
    return json.loads(psql(f"select coalesce(({sql}), 'null')", **v).strip())


def read_copy():
    w = int(psql(f"select {WORLD}").strip())
    airlines = json.loads(psql(f"""select coalesce(json_agg(json_build_object('id', a.id, 'code', a.iata_code, 'name', coalesce(a.planner_name, a.public_name, a.game_name))
              order by a.position nulls last, a.id), '[]') from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
              where g.kind = 'ours' and a.world_id = {w}""").strip())
    ref = {
        "hub": one(f"""select json_build_object('i', x.i, 'id', x.id, 'code', x.airport_code, 'bank1', x.bank1) from (
                 select row_number() over (order by b.position, b.id) - 1 as i, b.id, b.airport_code, b.role, to_char(b.bank_times[1], 'HH24:MI') as bank1
                   from public.airline_bases b where b.world_id = {w}) x where x.role = 'hub' and x.bank1 is not null order by x.i limit 1"""),
        "buf": one(f"select to_json(s.value) from public.settings s where s.world_id = {w} and s.airline_id is null and s.key = 'bank_buffer_min'"),
        "type": one(f"select json_build_object('id', t.id, 'name', t.name, 'min_turn', t.min_turn_min) from public.aircraft_types t where t.world_id = {w} order by t.id limit 1"),
        "max_config": int(psql(f"select coalesce(max(id), 0) from public.cabin_configs").strip()),
        # a destination with no night ban: one the world already describes, else any
        "ban": one(f"""select to_json(coalesce(
                  (select r.dest_code from public.routes r join public.world_airports wa on wa.world_id = r.world_id and wa.airport_code = r.dest_code
                    where r.world_id = {w} and not r.removed and wa.night_ban_from is null order by r.id limit 1),
                  (select r.dest_code from public.routes r where r.world_id = {w} and not r.removed
                      and not exists (select 1 from public.world_airports wa where wa.world_id = r.world_id and wa.airport_code = r.dest_code) order by r.id limit 1)))"""),
        "removed": one(f"""select json_build_object('id', r.id, 'key', coalesce(a.planner_name, a.public_name) || '|' || r.hub_code || '|' || r.dest_code)
                  from public.routes r join public.airlines a on a.id = r.airline_id where r.world_id = {w} and r.removed order by r.id limit 1"""),
        "tz": one(f"""select json_build_object('code', wa.airport_code, 'offset', ap.utc_offset) from public.world_airports wa join public.airports ap on ap.code = wa.airport_code
                  where wa.world_id = {w} and wa.utc_offset_override is null and ap.utc_offset is not null
                    and not exists (select 1 from public.flight_legs l where l.world_id = {w} and (l.origin_code = wa.airport_code or l.dest_code = wa.airport_code))
                    and not exists (select 1 from public.plan_card_legs l where l.world_id = {w} and (l.origin_code = wa.airport_code or l.dest_code = wa.airport_code))
                  order by wa.airport_code limit 1"""),
    }
    if ref["ban"] and ref["tz"] and ref["ban"] == ref["tz"]["code"]:
        ref["tz"] = None
    flight = one(f"""select json_build_array(a.iata_code, l.flight_no) from public.flight_legs l join public.airlines a on a.id = l.airline_id
              where l.world_id = {w} and l.rotation_id is not null and l.leg_no = 1 and l.flight_no >= 1000 order by l.rotation_id limit 1""")
    srch = {
        "flight": flight,
        "reg": one(f"select to_json(a.registration) from public.aircraft a where a.world_id = {w} and a.extra ? 'tails_index' order by (a.extra ->> 'tails_index')::int limit 1"),
        "order": one(f"""select to_json(a.registration) from public.aircraft a where a.world_id = {w} and a.extra ? 'deliveries_index' and not a.extra ? 'tails_index'
                  order by (a.extra ->> 'deliveries_index')::int limit 1"""),
        "planned": one(f"""select to_json(l.flight_no) from public.plan_card_legs l join public.plan_cards c on c.id = l.plan_card_id join public.aircraft a on a.id = c.aircraft_id
                  where l.world_id = {w} and a.extra ? 'deliveries_index' and not a.extra ? 'tails_index' and l.flight_no is not null order by l.plan_card_id, l.position limit 1"""),
        "pair": one(f"""select json_build_array(r.hub_code, r.dest_code) from public.routes r join public.rotations o on o.route_id = r.id
                  where r.world_id = {w} and not r.removed order by r.id limit 1"""),
        "airport": one(f"""select to_json(x.c) from (select r.dest_code c, count(*) n from public.routes r where r.world_id = {w} and not r.removed
                  group by r.dest_code having count(*) between 2 and 4 order by r.dest_code limit 1) x"""),
        "city": one(f"""select to_json(upper(left(ap.city, 4))) from public.routes r join public.airports ap on ap.code = r.dest_code
                  where r.world_id = {w} and not r.removed and length(ap.city) >= 5 and ap.city ~ '^[A-Za-z]{{4}}'
                    and (select count(*) from public.routes r2 join public.airports a2 on a2.code = r2.dest_code or a2.code = r2.hub_code
                          where r2.world_id = {w} and not r2.removed and upper(a2.city) like upper(left(ap.city, 4)) || '%') between 1 and 6
                  order by r.id limit 1"""),
    }
    est = set(json.loads(psql(f"""select coalesce(json_agg(distinct l.flight_no::text), '[]') from public.flight_legs l
              where l.world_id = {w} and l.dep_utc_min is not null and l.block_min is null""").strip()))
    COPY.update(world=w, airlines=airlines, ref=ref, search=srch, est_flights=est)
    return airlines


async def interline_rows(new):
    """The new Interline's rows (code, country, status), from its own board: which rows the edits use."""
    await new_interline(new)
    return await new.pg.evaluate("""[...document.querySelectorAll('tr[data-il-row]')].map(tr => { const [code, cc] = tr.dataset.ilRow.split('|');
        return { code, cc, status: tr.className.trim() || 'none' }; })""")


async def main():
    facts, nfacts = planner_facts(), pn.planner_facts()
    if not facts or not nfacts:
        step(False, "both planners name their Supabase address and public key", ["not found in web/planner/index.html or app/planner/src/data/config.ts"])
        sys.exit(1)
    if not pn.PAGE.is_file():
        step(False, "the new planner is built", ["web/app/index.html is missing: run npm ci && npm run build first"])
        sys.exit(1)
    try:
        env = local_env()
        lib_js = library(facts["lib_version"])
    except Exception as e:
        step(False, "set up: the copy's address and the old planner's Supabase library", [why(e)])
        sys.exit(1)

    moment = psql("select to_char((max(captured_at) + interval '1 hour') at time zone 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS.MS\"Z\"') from public.game_capture_raw").strip()
    try:
        airlines = read_copy()
        problems = [] if airlines else ["the copy has none of our airlines"]
    except Exception as e:
        airlines, problems = [], [why(e)]
    step(not problems, f"the moment: {moment} (the copy's latest capture plus one hour); the copy: {len(airlines)} of our airlines", problems)
    if problems:
        sys.exit(1)

    tag = secrets.token_hex(4)
    staff = (f"reference-staff-{tag}@example.com", secrets.token_urlsafe(18))
    try:
        make_user(env, *staff)
        psql("insert into public.planner_users (email) values (:'email')", email=staff[0])
        problems = [] if is_planner_user(env, token_for(env, *staff)) else ["public.is_planner_user() isn't true for the staff user"]
    except Exception as e:
        problems = [why(e)]
    if problems:
        step(False, "a test staff user, made through the copy's sign-in", problems)
        sys.exit(1)

    work = Path(tempfile.mkdtemp(prefix="reference-side-by-side-"))
    seen = []
    try:
        root = web_copy(work)
        with serve(root) as port:
            async with async_playwright() as p:
                old = OldPlanner(p, port, env, facts, lib_js, moment=moment)
                new = pn.Planner(p, port, env, nfacts, width=1280, height=900)
                seen += [old, new]
                try:
                    n0, mark = counts(), marks()
                    await old.open()
                    await old.ctx.route("**/storage/v1/**", hook_storage(old))
                    await old.sign_in(*staff)
                    await old.ready()
                    await new.open(moment=moment)
                    await new.ctx.route("**/storage/v1/**", hook_storage(new))
                    await new.pg.emulate_media(reduced_motion="reduce")
                    await new.sign_in(*staff)
                    problems = list(old.errors) + list(new.errors)
                    if log_since(mark):
                        problems.append("opening the planners changed the tables")
                    problems += count_changes(n0, counts())
                    if abs(await new.pg.evaluate("Date.now()") - ms(moment)) > 1000:
                        problems.append("the new planner's clock isn't frozen at the moment")
                    for sid in ("interline", "photos", "reference"):
                        await new.pg.click(f"[data-screen-link={sid}]")
                        await new.pg.wait_for_selector(f"main[data-screen={sid}]", timeout=60000)
                        if await new.pg.evaluate(f"!!document.querySelector('main[data-screen={sid}] [data-not-built]')"):
                            problems.append(f"{sid} is still a placeholder")
                except Exception as e:
                    problems = [why(e)] + old.errors[:3] + new.errors[:3]
                step(not problems, "both planners opened at the moment, signed in as test staff; Interline, Photos and Reference are built; opening them wrote nothing", problems)
                if problems:
                    sys.exit(1)

                for check in (interline_screens, photos_screens, reference_screens, search, exports):
                    t = time.monotonic()
                    try:
                        label, problems = await check(old, new)
                    except Exception as e:
                        label, problems = check.__name__, [why(e)]
                    step(not problems, label + f" ({time.monotonic() - t:.0f} s)", problems + new.errors[:3] + old.errors[:3])
                try:
                    await screenshots(old, new)
                except Exception as e:
                    print(f"      the screenshots: {why(e)}", flush=True)
                for k, v in KNOWN.items():
                    where = f" (e.g. {'; '.join(v['where'][:4])})" if v["where"] else ""
                    print(f"      known difference \"{k}\": used {v['used']} time(s){where}. {v['rule']}"[:1800], flush=True)

                # the rows the edits use, and a destination with no photo
                try:
                    if not COPY.get("il_rows"):
                        COPY["il_rows"] = await interline_rows(new)
                    await new_go(new, "/photos", PHOTOS_READY)
                    COPY["photo_code"] = await new.pg.evaluate("(document.querySelector('main[data-screen=photos] [data-ph]') || {dataset: {}}).dataset.ph || null")
                except Exception as e:
                    COPY.setdefault("il_rows", [])
                    print(f"      the rows for the edits: {why(e)}", flush=True)
                for edit in (interline_edits, reference_edits, photo_upload):
                    t = time.monotonic()
                    try:
                        label, problems = await edit(old, new)
                    except Exception as e:
                        label, problems = edit.__name__, [why(e)]
                    step(not problems, label + f" ({time.monotonic() - t:.0f} s)", problems + new.errors[:3] + old.errors[:3])
                await old.close()
                await new.close()

                for check in (preview, phone):
                    try:
                        label, problems = await check(p, port, env, nfacts, staff, moment, seen)
                    except Exception as e:
                        label, problems = check.__name__, [why(e)]
                    step(not problems, label, problems)
    finally:
        shutil.rmtree(work, ignore_errors=True)

    outside = sorted({h for x in seen for h in x.outside})
    stopped = ", ".join(sorted({h for x in seen for h in x.stopped})) or "nothing"
    step(not outside, f"nothing went outside ({sum(x.copy for x in seen)} requests answered by the copy, {sum(x.local for x in seen)} "
                      f"from the local server, {sum(len(getattr(x, 'uploads', [])) for x in seen)} to the photo bucket answered in the browser; stopped: {stopped})",
         ["reached: " + ", ".join(outside)] if outside else [])
    print(f"\n{len(failures)} Interline, Photos and Reference side-by-side step(s) failed" if failures else "\nInterline, Photos and Reference side by side: all passed", flush=True)
    print(f"      the Interline, Photos and Reference side by side took {time.monotonic() - started:.0f} s", flush=True)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    asyncio.run(main())
