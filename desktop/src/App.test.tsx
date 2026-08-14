import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";

import { AuthPanel } from "./App";
import type { AuthUiState } from "./auth/contracts";

const actions = {
  onLogin: vi.fn(),
  onCancel: vi.fn(),
  onLogout: vi.fn(),
  onToggleRegistration: vi.fn(),
};

function renderState(state: AuthUiState, registrationExpanded = false) {
  return renderToStaticMarkup(
    <AuthPanel
      state={state}
      registrationExpanded={registrationExpanded}
      {...actions}
    />,
  );
}

describe("interfaz de acceso", () => {
  it("explica el login externo sin solicitar credenciales en React", () => {
    const markup = renderState({ kind: "signedOut" });

    expect(markup).toContain("Continuar con MusicFlow");
    expect(markup).toContain("MusicFlow nunca ve tu contraseña");
    expect(markup).toContain("Crear cuenta");
    expect(markup).not.toContain('type="password"');
    expect(markup).not.toContain("access_token");
    expect(markup).not.toContain("refresh_token");
  });

  it("comunica honestamente que el registro beta esta restringido", () => {
    const markup = renderState({ kind: "signedOut" }, true);

    expect(markup).toContain("Registro por invitacion durante la beta");
    expect(markup).toContain("verificacion de correo");
  });

  it.each<[AuthUiState, string]>([
    [{ kind: "restoring" }, "Preparando MusicFlow"],
    [{ kind: "signingIn" }, "Continua en tu navegador"],
    [
      {
        kind: "error",
        message: "El acceso expiro antes de completarse.",
        retryable: true,
      },
      "Intentar nuevamente",
    ],
    [
      {
        kind: "signedIn",
        user: {
          subject: "user-1",
          username: "demo",
          displayName: "Dairo Demo",
          email: "demo@example.test",
          emailVerified: true,
        },
      },
      "Hola, Dairo Demo",
    ],
  ])("presenta el estado esperado", (state, expectedText) => {
    expect(renderState(state)).toContain(expectedText);
  });
});
