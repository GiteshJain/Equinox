// GET /api/game-schedule?u=<Gander enterprise link or id>
// Reads an airline's public flight schedule from the Gander game world and returns it as JSON.
// Only Gander enterprise pages are allowed, so this can't be used to fetch anything else.
// Cloudflare Pages Function (decision #7); same behaviour as the Netlify function it replaces.
export async function onRequestGet({ request }) {
  const reply = (body, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });

  const input = (new URL(request.url).searchParams.get("u") || "").trim();
  const id = /^\d+$/.test(input) ? input : (input.match(/gander\.airlinesim\.aero\/app\/info\/enterprises\/(\d+)/) || [])[1];
  if (!id) return reply({ error: "That isn't a Gander enterprise link." }, 400);

  // The game redirects once to attach a session; follow redirects by hand so the session cookie is kept.
  const jar = new Map();
  let url = `https://gander.airlinesim.aero/app/info/enterprises/${id}?tab=3`;
  let html = "";
  try {
    for (let hop = 0; hop < 8; hop++) {
      const res = await fetch(url, {
        redirect: "manual",
        headers: { "user-agent": "Mozilla/5.0 (EquinoxPlanner schedule check)", cookie: [...jar].map(([k, v]) => `${k}=${v}`).join("; ") },
      });
      const cookies = typeof res.headers.getSetCookie === "function" ? res.headers.getSetCookie() : (res.headers.get("set-cookie") || "").split(/,(?=\s*[A-Za-z0-9_\-]+=)/);
      for (const c of cookies) { const kv = c.split(";")[0]; const eq = kv.indexOf("="); if (eq > 0) jar.set(kv.slice(0, eq).trim(), kv.slice(eq + 1).trim()); }
      if (res.status >= 300 && res.status < 400) { url = new URL(res.headers.get("location") || "", url).toString(); continue; }
      if (!res.ok) return reply({ error: `The game answered ${res.status}.` }, 502);
      html = await res.text();
      break;
    }
  } catch (e) {
    return reply({ error: "Couldn't reach the game: " + (e instanceof Error ? e.message : String(e)) }, 502);
  }
  if (!html) return reply({ error: "The game kept redirecting." }, 502);

  const decode = (s) => s.replace(/&nbsp;/g, " ").replace(/&amp;/g, "&").replace(/&#39;/g, "'").replace(/&quot;/g, '"').replace(/&lt;/g, "<").replace(/&gt;/g, ">");
  const text = (s) => decode(s.replace(/<[^>]+>/g, " ")).replace(/\s+/g, " ").trim();
  const title = text((html.match(/<title>([\s\S]*?)<\/title>/) || [])[1] || "").split("|")[0].trim();
  const clean = html.replace(/<script[\s\S]*?<\/script>/g, "");
  const table = (clean.match(/<table[\s\S]*?<\/table>/) || [])[0] || "";
  const flights = [];
  let from = "", to = "";
  for (const row of table.match(/<tr[\s\S]*?<\/tr>/g) || []) {
    const cells = [...row.matchAll(/<t[hd][^>]*>([\s\S]*?)<\/t[hd]>/g)].map((m) => text(m[1]));
    const joined = cells.join(" | ");
    const mf = joined.match(/^from .*\(\s*([A-Z0-9]{3})\s*\)/);
    const mt = joined.match(/^to .*\(\s*([A-Z0-9]{3})\s*\)/);
    if (mf) { from = mf[1]; continue; }
    if (mt) { to = mt[1]; continue; }
    if (cells.length >= 4 && /^[A-Z0-9]{2} \d{1,4}$/.test(cells[0])) {
      const [code, no] = cells[0].split(" ");
      flights.push({ code, no, from, to, days: (cells[1] || "").replace(/[^1-7]/g, ""), dep: cells[2] || "", arr: cells[3] || "", type: cells[4] || "", valid: cells[7] || "" });
    }
  }
  return reply({ id, airline: title, checkedAt: new Date().toISOString(), flights });
}
