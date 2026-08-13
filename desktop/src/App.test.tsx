import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import { App } from "./App";

describe("App", () => {
  it("explica el alcance del primer instalador", () => {
    const markup = renderToStaticMarkup(<App />);

    expect(markup).toContain("MusicFlow Desktop");
    expect(markup).toContain("Puerta A preparada");
    expect(markup).toContain("API publicada por separado");
  });
});
