import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { describe, expect, it } from "vitest";

type TauriConfiguration = {
  app: {
    security: {
      capabilities: string[];
      csp: string;
    };
    withGlobalTauri: boolean;
  };
  plugins?: Record<string, unknown>;
};

type Capability = {
  permissions: string[];
  windows: string[];
};

function readJson<T>(relativeUrl: string): T {
  return JSON.parse(
    readFileSync(fileURLToPath(new URL(relativeUrl, import.meta.url)), "utf8"),
  ) as T;
}

describe("frontera de seguridad Tauri", () => {
  it("no expone APIs nativas durante el spike", () => {
    const configuration = readJson<TauriConfiguration>(
      "../src-tauri/tauri.conf.json",
    );
    const capability = readJson<Capability>(
      "../src-tauri/capabilities/main.json",
    );

    expect(configuration.app.withGlobalTauri).toBe(false);
    expect(configuration.app.security.capabilities).toEqual(["main"]);
    expect(configuration.app.security.csp).not.toContain("https:");
    expect(configuration.plugins).toBeUndefined();
    expect(capability.windows).toEqual(["main"]);
    expect(capability.permissions).toEqual([]);
  });
});
