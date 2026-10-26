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