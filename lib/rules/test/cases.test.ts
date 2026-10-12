/// <reference types="node" />
// Runs every hand-made case in lib/rules/cases/ (spec §4): each file holds a part's cases, each with its input (laid
// over cases/_base.json's world), a question and the answer. An answer lists only what it checks: every key it names
// must match (numbers to within 1e-9), lists must have the same length, and {"error": "..."} expects the library to
// refuse with that text in its message.
import { readFileSync, readdirSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { ask, mergeInput, type Ask } from "./ask.js";
import { mismatches } from "./match.js";
import type { RulesInput } from "../src/index.js";

interface Case {
  name: string;
  rule?: string;
  input?: Partial<RulesInput>;
  ask: Ask;
  answer: unknown;
}
interface CaseFile {
  part: string;
  note?: string;
  input?: Partial<RulesInput>;
  cases: Case[];
}

const dir = new URL("../cases/", import.meta.url);
const base = JSON.parse(readFileSync(new URL("_base.json", dir), "utf8")) as { input: RulesInput };
const files = readdirSync(dir).filter((f) => f.endsWith(".json") && !f.startsWith("_")).sort();

describe("hand-made cases (lib/rules/cases)", () => {
  it("has cases for every part", () => {
    const parts = new Set(files.map((f) => (JSON.parse(readFileSync(new URL(f, dir), "utf8")) as CaseFile).part));
    for (const p of ["time", "block", "turns", "connections", "banks", "maintenance", "aircraftWeek", "schedule", "positions", "optimiser"]) {
      expect(parts, `no case file for ${p}`).toContain(p);
    }
  });
  for (const f of files) {
    const file = JSON.parse(readFileSync(new URL(f, dir), "utf8")) as CaseFile;
    describe(`${f} (${file.part})`, () => {
      for (const c of file.cases) {
        it(c.name, () => {
          const input = mergeInput(base.input, file.input, c.input);
          const want = c.answer as { error?: string } | null;
          if (want && typeof want === "object" && "error" in want && Object.keys(want).length === 1) {
            expect(() => ask(input, c.ask)).toThrow(String(want.error));
            return;
          }
          const got = ask(input, c.ask);
          expect(mismatches(JSON.parse(JSON.stringify(got ?? null)), want)).toEqual([]);
        });
      }
    });
  }
});
