const LOCAL_API_BASE_URL = "http://127.0.0.1:8000";
const PRODUCTION_API_BASE_URL = "https://api.kontora-pos.store";

const approvedBaseUrls = new Set([LOCAL_API_BASE_URL, PRODUCTION_API_BASE_URL]);

export type ApiEnvironment = "development" | "production";

export type ApiConfiguration = Readonly<{
  environment: ApiEnvironment;
  baseUrl: string;
  healthUrl: string;
}>;

export function createApiConfiguration(baseUrl: string): ApiConfiguration {
  if (!approvedBaseUrls.has(baseUrl)) {
    throw new Error("La URL base de la API no esta aprobada.");
  }

  const environment =
    baseUrl === LOCAL_API_BASE_URL ? "development" : "production";

  return Object.freeze({
    environment,
    baseUrl,
    healthUrl: `${baseUrl}/health/live`,
  });
}

export function resolveApiConfiguration(
  isDevelopment: boolean,
): ApiConfiguration {
  return createApiConfiguration(
    isDevelopment ? LOCAL_API_BASE_URL : PRODUCTION_API_BASE_URL,
  );
}

export const apiConfiguration = resolveApiConfiguration(import.meta.env.DEV);
