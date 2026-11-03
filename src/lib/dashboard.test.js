import { describe, expect, mock, test } from "bun:test";

mock.module("@/integrations/supabase/client", () => ({ supabase: {} }));
const { deltaText, formatMetricValue } = await import("./dashboard");

describe("metric numeric formatting", () => {
  test("numeric text percentage delta is expressed in points", () => {
    expect(deltaText({ delta: "2.0", unit: "%" })).toBe("+2 pts");
  });
  test("negative numeric text uses a true minus and French decimal", () => {
    expect(deltaText({ delta: "-10.8", unit: null })).toBe("−10,8");
  });
  test("other delta units have a separating space", () => {
    expect(deltaText({ delta: "3", unit: "j" })).toBe("+3 j");
  });
  test("null, NaN and zero have no delta", () => {
    for (const delta of [null, NaN, "NaN", 0, "0.0"]) {
      expect(deltaText({ delta, unit: "%" })).toBe("");
    }
  });
  test("metric percentages use exactly one decimal with attached unit", () => {
    expect(formatMetricValue(38.6, "%")).toBe("38,6%");
    expect(formatMetricValue(40, "%")).toBe("40,0%");
  });
  test("metric values use at most one decimal with attached units", () => {
    expect(formatMetricValue(3, "j")).toBe("3j");
    expect(formatMetricValue("10.86", null)).toBe("10,9");
  });
});
const { ecartText, ecartFleche, moisText, moisTitre, dernierMoisTermine } = await import("./dashboard");

describe("F4 révisée : évolution par rapport au mois précédent", () => {
  test("écart d'un taux en points, avec une décimale", () => {
    expect(ecartText("2.0", "%")).toBe("+2,0 pts");
    expect(ecartText(0.5, "%")).toBe("+0,5 pt");
  });
  test("écart d'un comptage, entier avec un vrai signe moins", () => {
    expect(ecartText(-11, null, true)).toBe("−11");
  });
  test("écart nul affiché 0, sans signe", () => {
    expect(ecartText("0.0", "%")).toBe("0 pt");
    expect(ecartFleche(0)).toBe("■");
  });
  test("sans mois précédent : N.C.", () => {
    expect(ecartText(null, "%")).toBe("N.C.");
  });
  test("mois en toutes lettres", () => {
    expect(moisText("2026-10-01")).toBe("octobre 2026");
    expect(moisTitre("2026-10-01")).toBe("Octobre 2026");
  });
  test("dernier mois terminé, à Paris", () => {
    expect(dernierMoisTermine(new Date("2026-11-03T09:00:00Z"))).toBe("2026-10-01");
    expect(dernierMoisTermine(new Date("2026-10-31T23:30:00Z"))).toBe("2026-10-01");
    expect(dernierMoisTermine(new Date("2026-01-15T12:00:00Z"))).toBe("2025-12-01");
  });
});
