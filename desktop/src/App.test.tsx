import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import { App, HealthStatusCard, type HealthUiState } from "./App";

describe("App", () => {
  it("explica el alcance limitado de la puerta B", () => {
    const markup = renderToStaticMarkup(<App />);

    expect(markup).toContain("MusicFlow Desktop");
    expect(markup).toContain("API pendiente de comprobacion");
    expect(markup).toContain("Comprobar conexion");
    expect(markup).toContain("API por HTTPS y Cloudflare Tunnel");
    expect(markup).not.toContain("procesar URL");
  });

  it.each<[HealthUiState, string]>([
    [{ kind: "loading" }, "Comprobando la API"],
    [{ kind: "online" }, "API disponible"],
    [
      { kind: "error", message: "No se pudo conectar con la API." },
      "No se pudo conectar con la API.",
    ],
  ])("presenta el estado %s", (state, expectedText) => {
    const markup = renderToStaticMarkup(<HealthStatusCard state={state} />);

    expect(markup).toContain(expectedText);
  });
});
