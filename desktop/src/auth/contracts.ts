export type AuthenticatedUser = Readonly<{
  subject: string;
  username: string;
  displayName: string;
  email: string | null;
  emailVerified: boolean;
}>;

export type AuthUiState =
  | Readonly<{ kind: "restoring" }>
  | Readonly<{ kind: "signedOut" }>
  | Readonly<{ kind: "signingIn" }>
  | Readonly<{ kind: "signedIn"; user: AuthenticatedUser }>
  | Readonly<{ kind: "error"; message: string; retryable: boolean }>;

export type AuthCommandError = Readonly<{
  code?: string;
  message?: string;
  retryable?: boolean;
}>;

export function authErrorCode(error: unknown): string | null {
  if (typeof error !== "object" || error === null) {
    return null;
  }

  const code = (error as AuthCommandError).code;
  return typeof code === "string" ? code : null;
}

export function describeAuthError(error: unknown): {
  message: string;
  retryable: boolean;
} {
  if (typeof error === "object" && error !== null) {
    const commandError = error as AuthCommandError;
    if (
      typeof commandError.code === "string" &&
      typeof commandError.message === "string"
    ) {
      return {
        message: commandError.message,
        retryable: commandError.retryable !== false,
      };
    }
  }

  return {
    message:
      "No fue posible completar el acceso. Comprueba tu conexion e intentalo de nuevo.",
    retryable: true,
  };
}
