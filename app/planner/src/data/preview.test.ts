// The preview rule (decision #8): saving only at equinox-alliance.com and www.equinox-alliance.com.
import { describe, expect, it } from "vitest";
import { guardFetch, isPreview } from "./preview";

describe("isPreview", () => {
  it("saves only on the two live addresses", () => {
    expect(isPreview("equinox-alliance.com")).toBe(false);
    expect(isPreview("www.equinox-alliance.com")).toBe(false);
  });
  it("treats every other address as a look-only preview", () => {
    for (const host of ["equinox-alliance.pages.dev", "abc123.equinox-alliance.pages.dev", "planner-shell.equinox-alliance.pages.dev",
      "127.0.0.1", "localhost", "staging.equinox-alliance.com", "equinox-alliance.com.evil.example", "EQUINOX-ALLIANCE.COM.", ""]) {
      expect(isPreview(host), host).toBe(true);
    }
  });
});

describe("guardFetch", () => {
  const sent: string[] = [];
  const send: typeof fetch = async (input, init) => {
    sent.push(`${init?.method ?? "GET"} ${new URL(String(input)).pathname}`);
    return new Response("[]", { status: 200 });
  };
  const API = "https://ulecwsyedvwcxgdzmhoq.supabase.co";

  it("on a preview, stops every write to the data API and file storage, and lets reads, sign-in and the staff check through", async () => {
    sent.length = 0;
    const f = guardFetch(true, send);
    const refused = await f(`${API}/rest/v1/rpc/planner_save`, { method: "POST", body: "{}" });
    expect(refused.status).toBe(403);
    expect((await f(`${API}/rest/v1/todos?id=eq.1`, { method: "PATCH" })).status).toBe(403);
    expect((await f(`${API}/storage/v1/object/site-photos/x.jpg`, { method: "POST" })).status).toBe(403);
    expect((await f(`${API}/rest/v1/airlines?select=*`)).status).toBe(200);
    expect((await f(`${API}/rest/v1/rpc/is_planner_user`, { method: "POST" })).status).toBe(200);
    expect((await f(`${API}/auth/v1/token?grant_type=password`, { method: "POST" })).status).toBe(200);
    expect(sent).toEqual(["GET /rest/v1/airlines", "POST /rest/v1/rpc/is_planner_user", "POST /auth/v1/token"]);
  });

  it("on the live address, sends everything", async () => {
    sent.length = 0;
    const f = guardFetch(false, send);
    expect((await f(`${API}/rest/v1/rpc/planner_save`, { method: "POST" })).status).toBe(200);
    expect(sent).toEqual(["POST /rest/v1/rpc/planner_save"]);
  });
});
