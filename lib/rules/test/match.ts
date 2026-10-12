// How a case's answer is compared with what the library gives: every key the answer names must match (numbers to
// within 1e-9), lists must have the same length, and anything the answer leaves out isn't checked.

/** Where the answer and what the library gave differ, as paths; empty when they match. */
export function mismatches(got: unknown, want: unknown, path = "answer"): string[] {
  if (typeof want === "number" && typeof got === "number") return Math.abs(got - want) <= 1e-9 ? [] : [`${path}: ${got}, expected ${want}`];
  if (Array.isArray(want)) {
    if (!Array.isArray(got)) return [`${path}: not a list (${JSON.stringify(got)?.slice(0, 120)})`];
    if (got.length !== want.length) return [`${path}: ${got.length} item(s), expected ${want.length} (${JSON.stringify(got).slice(0, 300)})`];
    return want.flatMap((w, i) => mismatches(got[i], w, `${path}[${i}]`));
  }
  if (want !== null && typeof want === "object") {
    if (got === null || typeof got !== "object") return [`${path}: ${JSON.stringify(got)}, expected an object`];
    return Object.entries(want).flatMap(([k, w]) => mismatches((got as Record<string, unknown>)[k], w, `${path}.${k}`));
  }
  return got === want ? [] : [`${path}: ${JSON.stringify(got)}, expected ${JSON.stringify(want)}`];
}
