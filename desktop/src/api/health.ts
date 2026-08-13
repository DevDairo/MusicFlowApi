import { fetch as tauriFetch } from "@tauri-apps/plugin-http";

import type { ApiConfiguration } from "./config";

const HEALTH_TIMEOUT_MILLISECONDS = 5_000;
const HEALTH_CONNECT_TIMEOUT_MILLISECONDS = 5_000;

export type ApiHealth = Readonly<{
  status: "alive";
}>;

export type ApiHealthErrorCode =
  "http" | "invalid-response" | "network" | "timeout";

export class ApiHealthError extends Error {
  constructor(
    readonly code: ApiHealthErrorCode,
    message: string,
  ) {
    super(message);
    this.name = "ApiHealthError";
  }
}

export type HealthFetch = (
  input: string | URL | Request,
  init?: Parameters<typeof tauriFetch>[1],
) => Promise<Response>;

function isHealthResponse(value: unknown): value is ApiHealth {
  return (
    typeof value === "object" &&
    value !== null &&
    "status" in value &&
    value.status === "alive"
  );
}

function isTimeout(error: unknown): boolean {
  return (
    error instanceof DOMException &&
    (error.name === "AbortError" || error.name === "TimeoutError")
  );
}

export async function checkApiHealth(
  configuration: ApiConfiguration,
  request: HealthFetch = tauriFetch,
): Promise<ApiHealth> {
  try {
    const response = await request(configuration.healthUrl, {
      method: "GET",
      headers: { Accept: "application/json" },
      connectTimeout: HEALTH_CONNECT_TIMEOUT_MILLISECONDS,
      signal: AbortSignal.timeout(HEALTH_TIMEOUT_MILLISECONDS),
    });

    if (!response.ok) {
      throw new ApiHealthError(
        "http",
        `La API respondio con HTTP ${response.status}.`,
      );
    }

    let body: unknown;
    try {
      body = await response.json();
    } catch {
      throw new ApiHealthError(
        "invalid-response",
        "La API devolvio una respuesta que no es JSON.",
      );
    }

    if (!isHealthResponse(body)) {
      throw new ApiHealthError(
        "invalid-response",
        "La respuesta de salud no cumple el contrato esperado.",
      );
    }

    return body;
  } catch (error) {
    if (error instanceof ApiHealthError) {
      throw error;
    }
    if (isTimeout(error)) {
      throw new ApiHealthError(
        "timeout",
        "La API no respondio dentro del tiempo permitido.",
      );
    }
    throw new ApiHealthError(
      "network",
      "No fue posible establecer conexion con la API.",
    );
  }
}

export function describeHealthError(error: unknown): string {
  if (!(error instanceof ApiHealthError)) {
    return "No fue posible comprobar la API. Intenta nuevamente.";
  }

  switch (error.code) {
    case "timeout":
      return "La API tardo demasiado en responder. Intenta nuevamente.";
    case "http":
    case "invalid-response":
      return "La API respondio de forma inesperada. Intenta mas tarde.";
    case "network":
      return "No se pudo conectar con la API. Comprueba tu conexion.";
  }
}
