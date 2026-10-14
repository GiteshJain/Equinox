// Photos (decision #18, build pull request 12; spec docs/specs/2026-10-14-interline-photos-reference.md): the airline logos
// and destination photos for the public website, as the old planner's Photos (renderPhotos and its eq* helpers), with the
// same words and look:
//   - each of our airlines' logo, the in-game one or the uploaded one, with Upload logo / Replace and "Use the in-game
//     logo";
//   - every destination our flights reach, busiest first, with its photo (its own, uploaded or free-licensed, or its city's),
//     its flights a week and credit, Upload photo / Replace with an optional credit, and Remove for its own photo; "Missing a
//     photo only" (on at first) shows those without one, and a photo just uploaded stays in view.
// Uploads go live at once, as now: resized in the browser, put in the site-photos bucket and named through the website's
// functions (upload.ts). A preview address uploads nothing. The photos are read from site_public(), the destinations from
// the start's rules input (each rotation's days at both ends).
import { useEffect, useMemo, useRef, useState, type CSSProperties } from "react";
import { useQuery } from "@tanstack/react-query";
import { queryClient } from "../../data/query";
import { PREVIEW } from "../../data/preview";
import { useOurAirlines, useWorld } from "../../data/reads";
import { useRules } from "../../data/rules";
import { supabase } from "../../data/supabase";
import { Confirm } from "../../ui/Confirm";
import { ErrorBox } from "../../ui/ErrorBox";
import { showMessage } from "../../ui/messages";
import { loadLogos } from "../../ui/siteFiles";
import { PREVIEW_WORDS, destinations, logoLiveWords, photoLiveWords, photoOf, type Media } from "./model";
import { removeLogo, removePhoto, uploadLogo, uploadPhoto } from "./upload";

/** The website's photos and logos (site_public()'s content.media), read with GET so a preview reads them too. */
export function useMedia() {
  return useQuery({
    queryKey: ["site", "media"],
    queryFn: async (): Promise<Media> => {
      const { data, error } = await supabase.rpc("site_public", undefined, { get: true });
      if (error) throw new Error(`Couldn't read the website's photos: ${error.message}`);
      const m = (data as { content?: { media?: Media } } | null)?.content?.media ?? {};
      return { photos: m.photos ?? {}, airports: m.airports ?? {}, logos: m.logos ?? {} };
    },
  });
}

export function Photos() {
  const world = useWorld();
  const airlinesQ = useOurAirlines(world.data?.id);
  const rulesQ = useRules(world.data?.id);
  const mediaQ = useMedia();
  const [logos, setLogos] = useState<Record<string, string> | null>(null);
  const [missingOnly, setMissingOnly] = useState(true);
  const [recent, setRecent] = useState<ReadonlySet<string>>(new Set());
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const [asking, setAsking] = useState<{ what: "photo" | "logo"; key: string } | null>(null);
  const credits = useRef(new Map<string, string>());
  useEffect(() => {
    let alive = true;
    loadLogos().then((l) => { if (alive) setLogos(l); }).catch(() => { if (alive) setLogos({}); });
    return () => { alive = false; };
  }, []);

  const rules = rulesQ.data?.rules;
  const dests = useMemo(() => {
    if (!rules) return null;
    const days = new Map<number, { l1?: number; l2?: number }>();
    for (const l of rules.legs) {
      if (l.rotation_id == null) continue;
      const d = days.get(l.rotation_id) ?? {};
      if ((l.leg_no ?? 1) === 1) d.l1 ??= l.days_utc.length;
      else d.l2 ??= l.days_utc.length;
      days.set(l.rotation_id, d);
    }
    const rots = [...rules.rotations.values()].sort((a, b) => a.id - b.id).flatMap((r) => {
      const route = rules.routes.get(r.route_id);
      const d = days.get(r.id) ?? {};
      return route ? [{ hub: route.hub_code, dest: route.dest_code, days: d.l1 ?? d.l2 ?? 0 }] : [];
    });
    return destinations(rots, new Map([...rules.airports.values()].map((a) => [a.code, a.city ?? null])));
  }, [rules]);
  const media = mediaQ.data;
  const airlines = (airlinesQ.data ?? []).map((a) => a.planner_name ?? a.public_name ?? a.game_name ?? "").filter(Boolean);

  async function act(key: string, run: () => Promise<string | void>) {
    if (PREVIEW) {
      showMessage(PREVIEW_WORDS);
      return;
    }
    setBusy(key);
    try {
      const words = await run();
      if (words) setNote(words);
      await queryClient.invalidateQueries({ queryKey: ["site"] });
    } catch (e) {
      showMessage(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(null);
    }
  }
  const upPhoto = (code: string, city: string, file: File) => act("ph:" + code, async () => {
    await uploadPhoto(code, file, credits.current.get(code) ?? "", media?.airports?.[code]);
    setRecent((s) => new Set([...s, code]));
    return photoLiveWords(city);
  }).catch(() => undefined);
  const upLogo = (al: string, file: File) => act("lg:" + al, async () => {
    await uploadLogo(al, file, media?.logos?.[al]);
    return logoLiveWords(al);
  });

  const loadError = world.error ?? airlinesQ.error ?? rulesQ.error ?? mediaQ.error;
  const ready = !!(media && dests && logos && airlinesQ.data);
  const all = dests ?? [];
  const missing = media ? all.filter((d) => !photoOf(media, d.code)) : [];
  const list = media ? (missingOnly ? all.filter((d) => !photoOf(media, d.code) || recent.has(d.code)) : all) : [];
  return (
    <main className="view photos" data-screen="photos" data-photos-ready={ready ? "yes" : "no"} data-photos-busy={busy ?? ""}>
      <div className="vh"><h1>Website photos</h1><p>Airline logos and destination photos for the public website. Uploads go live straight away; the planner resizes them for the web first.</p></div>
      {loadError ? <ErrorBox error={loadError} /> : null}
      <div className="board">
        <div id="ph-root">
          {!ready || !media ? <div className="empty">Loading the website's photos…</div> : (
            <>
              {note ? <div className="ph-note" data-ph-note>{note}</div> : null}
              <h3 className="rh" style={{ margin: "0 0 6px" }}>Airline logos</h3>
              <p className="note" style={{ margin: "0 0 14px" }}>The in-game logos are only 120 × 23 pixels, so they look soft when the website shows them large. Upload a sharper version (a PNG with a transparent background, at least 600 pixels wide) and the website uses it everywhere.</p>
              <div className="ph-grid" style={{ marginBottom: 30 }}>
                {airlines.map((a) => {
                  const up = media.logos?.[a];
                  const src = up ? up.url : logos?.[a] ?? "";
                  return (
                    <div className={"ph-card" + (busy === "lg:" + a ? " ph-busy" : "")} data-lg={a} key={a}>
                      <div className="ph-img" style={{ background: "#fff", aspectRatio: "3/1" } as CSSProperties}>
                        {src ? <img src={src} alt="" style={{ objectFit: "contain", padding: "18px 26px" }} /> : null}
                        <span className={"tag" + (up ? " live" : "")}>{up ? "Uploaded" : "In-game, 120 × 23"}</span>
                      </div>
                      <div className="ph-body">
                        <b>{a}</b>
                        <div className="ph-acts">
                          <label className="primary">{up ? "Replace" : "Upload logo"}<input type="file" accept="image/png,image/webp" data-lg-up={a} hidden
                            onChange={(e) => { const f = e.currentTarget.files?.[0]; e.currentTarget.value = ""; if (f) void upLogo(a, f); }} /></label>
                          {up ? (asking?.what === "logo" && asking.key === a
                            ? <Confirm question={`Go back to the in-game logo for ${a}?`} yes="Use the in-game logo" onNo={() => setAsking(null)}
                              onYes={() => { setAsking(null); void act("lg:" + a, () => removeLogo(a, up)); }} />
                            : <button type="button" className="link" data-lg-rm={a} onClick={() => setAsking({ what: "logo", key: a })}>Use the in-game logo</button>) : null}
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>
              <h3 className="rh" style={{ margin: "0 0 12px" }}>Destination photos</h3>
              <div className="ph-tools">
                <label className="toggle" style={{ display: "inline-flex", gap: 8, alignItems: "center" }}>
                  <input type="checkbox" id="ph-missing" checked={missingOnly} onChange={(e) => setMissingOnly(e.currentTarget.checked)} /> Missing a photo only
                </label>
                <span className="note">{missing.length} of {all.length} destinations have no photo. Landscape photos at least 1,200 px wide work best.</span>
              </div>
              <div className="ph-grid">
                {list.length ? list.map((d) => {
                  const p = photoOf(media, d.code);
                  return (
                    <div className={"ph-card" + (busy === "ph:" + d.code ? " ph-busy" : "")} data-ph={d.code} key={d.code}>
                      <div className="ph-img">
                        {p ? <><img src={p.url} alt="" loading="lazy" /><span className={"tag" + (recent.has(d.code) ? " live" : "")}>{recent.has(d.code) ? "Live on the website" : p.kind}</span></> : d.code}
                      </div>
                      <div className="ph-body">
                        <b>{d.city} <span className="note">{d.code}</span></b>
                        <span className="small">{d.n} flights a week{p && p.credit ? ` · ${p.credit}` : ""}</span>
                        <input type="text" placeholder="Credit (optional): photographer, licence" data-ph-credit={d.code}
                          onChange={(e) => credits.current.set(d.code, e.currentTarget.value)} />
                        <div className="ph-acts">
                          <label className="primary">{p ? "Replace" : "Upload photo"}<input type="file" accept="image/*" data-ph-up={d.code} hidden
                            onChange={(e) => { const f = e.currentTarget.files?.[0]; e.currentTarget.value = ""; if (f) void upPhoto(d.code, d.city, f); }} /></label>
                          {p && p.removable ? (asking?.what === "photo" && asking.key === d.code
                            ? <Confirm question={`Remove the photo for ${d.city}? The website goes back to the city photo or the plain card.`} yes="Remove" onNo={() => setAsking(null)}
                              onYes={() => { setAsking(null); void act("ph:" + d.code, () => removePhoto(d.code, media.airports?.[d.code])); }} />
                            : <button type="button" className="link" data-ph-rm={d.code} onClick={() => setAsking({ what: "photo", key: d.code })}>Remove</button>) : null}
                        </div>
                      </div>
                    </div>
                  );
                }) : <div className="empty">Every destination has a photo.</div>}
              </div>
            </>
          )}
        </div>
      </div>
    </main>
  );
}
