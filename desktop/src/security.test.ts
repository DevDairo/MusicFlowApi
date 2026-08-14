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
  permissions: Array<
    | string
    | {
        identifier: string;
        allow: Array<{ url: string }>;
      }
  >;
  windows: string[];
};

function readJson<T>(relativeUrl: string): T {
  return JSON.parse(
    readFileSync(fileURLToPath(new URL(relativeUrl, import.meta.url)), "utf8"),
  ) as T;
}

describe("frontera de seguridad Tauri", () => {
  it("expone solo el health aprobado mediante el cliente nativo", () => {
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
    expect(capability.permissions).toEqual([
      {
        identifier: "http:default",
        allow: [
          { url: "http://127.0.0.1:8000/health/live" },
          { url: "https://api.kontora-pos.store/health/live" },
        ],
      },
    ]);

    const serializedPermissions = JSON.stringify(capability.permissions);
    expect(serializedPermissions).not.toContain("*");
    expect(serializedPermissions).not.toContain("/health/ready");
    expect(serializedPermissions).not.toContain("https://kontora-pos.store");
    expect(serializedPermissions).not.toContain("auth.kontora-pos.store");
    expect(serializedPermissions).not.toContain("opener");
  });
});
