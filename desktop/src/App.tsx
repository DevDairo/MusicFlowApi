import { useState } from "react";

import { apiConfiguration } from "./api/config";
import { checkApiHealth, describeHealthError } from "./api/health";

const boundaries = [
  "Cliente instalado en Windows",
  "API por HTTPS y Cloudflare Tunnel",
  "Worker y PostgreSQL privados",
] as const;

export type HealthUiState =
  | Readonly<{ kind: "idle" }>
  | Readonly<{ kind: "loading" }>
  | Readonly<{ kind: "online" }>
  | Readonly<{ kind: "error"; message: string }>;

const healthCopy = {
  idle: {
    title: "API pendiente de comprobacion",
    message: "Consulta manual, sin polling ni reintentos automaticos.",
  },
  loading: {
    title: "Comprobando la API",
    message: "Esperando una respuesta valida del endpoint de salud.",
  },
  online: {
    title: "API disponible",
    message: "El servicio publico respondio con el contrato esperado.",
  },
} as const;

export function HealthStatusCard({ state }: { state: HealthUiState }) {
  const copy = state.kind === "error" ? null : healthCopy[state.kind];

  return (
    <div
      className={`status-card status-card--${state.kind}`}
      role="status"
      aria-live="polite"
    >
      <span className="status-dot" aria-hidden="true" />
      <div>
        <strong>{copy?.title ?? "No se pudo comprobar la API"}</strong>
        <p>{copy?.message ?? (state.kind === "error" ? state.message : "")}</p>
      </div>
    </div>
  );
}

export function App() {
  const [healthState, setHealthState] = useState<HealthUiState>({
    kind: "idle",
  });

  async function handleHealthCheck() {
    setHealthState({ kind: "loading" });
    try {
      await checkApiHealth(apiConfiguration);
      setHealthState({ kind: "online" });
    } catch (error) {
      setHealthState({ kind: "error", message: describeHealthError(error) });
    }
  }

  return (
    <main className="app-shell">
      <section className="hero" aria-labelledby="app-title">
        <div className="brand-mark" aria-hidden="true">
          <span />
          <span />
          <span />
        </div>
        <p className="eyebrow">MusicFlow Desktop</p>
        <h1 id="app-title">Tu audio, procesado con una arquitectura clara.</h1>
        <p className="summary">
          Esta puerta valida una conexion limitada con la API. No habilita
          trabajos, autenticacion, biblioteca ni procesamiento multimedia.
        </p>

        <HealthStatusCard state={healthState} />

        <div className="health-actions">
          <button
            type="button"
            onClick={handleHealthCheck}
            disabled={healthState.kind === "loading"}
          >
            {healthState.kind === "loading"
              ? "Comprobando..."
              : "Comprobar conexion"}
          </button>
          <span>
            {apiConfiguration.environment === "production"
              ? "API remota"
              : "API local de desarrollo"}
          </span>
        </div>

        <ul className="boundaries" aria-label="Limites de despliegue">
          {boundaries.map((boundary) => (
            <li key={boundary}>{boundary}</li>
          ))}
        </ul>
      </section>

      <footer>
        <span>Incremento tecnico 3</span>
        <span>Tauri + React + TypeScript</span>
      </footer>
    </main>
  );
}
