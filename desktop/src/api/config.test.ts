import { describe, expect, it } from "vitest";

import { createApiConfiguration, resolveApiConfiguration } from "./config";

describe("configuracion de la API", () => {
  it("selecciona el origen local solo para desarrollo", () => {
    expect(resolveApiConfiguration(true)).toEqual({
      environment: "development",
      baseUrl: "http://127.0.0.1:8000",
      healthUrl: "http://127.0.0.1:8000/health/live",
    });
  });

  it("selecciona el dominio HTTPS para produccion", () => {
    expect(resolveApiConfiguration(false)).toEqual({
      environment: "production",
      baseUrl: "https://api.kontora-pos.store",
      healthUrl: "https://api.kontora-pos.store/health/live",
    });
  });

  it.each([
    "https://kontora-pos.store",
    "https://api.kontora-pos.store/health/ready",
    "https://other.kontora-pos.store",
    "http://api.kontora-pos.store",
    "https://user:password@api.kontora-pos.store",
  ])("rechaza el origen no aprobado %s", (baseUrl) => {
    expect(() => createApiConfiguration(baseUrl)).toThrow(
      "La URL base de la API no esta aprobada.",
    );
  });
});
