import { describe, expect, it, vi } from "vitest";

import { resolveApiConfiguration } from "./config";
import {
  ApiHealthError,
  checkApiHealth,
  describeHealthError,
  type HealthFetch,
} from "./health";

const productionConfiguration = resolveApiConfiguration(false);

function createFetch(response: Response): HealthFetch {
  return vi.fn<HealthFetch>().mockResolvedValue(response);
}

describe("cliente de salud", () => {
  it("realiza un GET al endpoint aprobado y valida el contrato", async () => {
    const request = createFetch(
      new Response(JSON.stringify({ status: "alive", checks: null }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }),
    );

    await expect(
      checkApiHealth(productionConfiguration, request),
    ).resolves.toEqual({ status: "alive", checks: null });
    expect(request).toHaveBeenCalledTimes(1);
    expect(request).toHaveBeenCalledWith(
      "https://api.kontora-pos.store/health/live",
      expect.objectContaining({
        method: "GET",
        connectTimeout: 5_000,
      }),
    );
  });

  it("clasifica un codigo HTTP no exitoso", async () => {
    const request = createFetch(new Response("Unavailable", { status: 503 }));

    await expect(
      checkApiHealth(productionConfiguration, request),
    ).rejects.toMatchObject({ code: "http" });
  });

  it.each([
    new Response("not-json", { status: 200 }),
    new Response(JSON.stringify({ status: "ready" }), { status: 200 }),
  ])("rechaza respuestas incompatibles", async (response) => {
    await expect(
      checkApiHealth(productionConfiguration, createFetch(response)),
    ).rejects.toMatchObject({ code: "invalid-response" });
  });

  it("clasifica timeout y fallo de transporte sin filtrar detalles", async () => {
    const timeoutRequest = vi
      .fn<HealthFetch>()
      .mockRejectedValue(new DOMException("internal detail", "TimeoutError"));
    const networkRequest = vi
      .fn<HealthFetch>()
      .mockRejectedValue(new Error("private network detail"));

    await expect(
      checkApiHealth(productionConfiguration, timeoutRequest),
    ).rejects.toMatchObject({ code: "timeout" });
    await expect(
      checkApiHealth(productionConfiguration, networkRequest),
    ).rejects.toMatchObject({ code: "network" });
  });

  it("convierte errores internos en mensajes accionables", () => {
    expect(describeHealthError(new ApiHealthError("network", "secret"))).toBe(
      "No se pudo conectar con la API. Comprueba tu conexion.",
    );
    expect(describeHealthError(new Error("secret"))).not.toContain("secret");
  });
});
