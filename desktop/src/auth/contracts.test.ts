import { describe, expect, it } from "vitest";

import { describeAuthError } from "./contracts";

describe("describeAuthError", () => {
  it("conserva solo el mensaje seguro entregado por Rust", () => {
    expect(
      describeAuthError({
        code: "login_timeout",
        message: "El acceso expiro antes de completarse.",
        retryable: true,
        token: "never-expose-this",
      }),
    ).toEqual({
      message: "El acceso expiro antes de completarse.",
      retryable: true,
    });
  });

  it("usa un mensaje estable para errores no estructurados", () => {
    expect(describeAuthError(new Error("network internals"))).toEqual({
      message:
        "No fue posible completar el acceso. Comprueba tu conexion e intentalo de nuevo.",
      retryable: true,
    });
  });
});
