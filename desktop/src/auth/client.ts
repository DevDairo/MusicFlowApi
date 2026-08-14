import { invoke } from "@tauri-apps/api/core";

import type { AuthenticatedUser } from "./contracts";

export const authClient = {
  currentUser(): Promise<AuthenticatedUser | null> {
    return invoke<AuthenticatedUser | null>("get_current_user");
  },

  login(): Promise<AuthenticatedUser> {
    return invoke<AuthenticatedUser>("login");
  },

  cancelLogin(): Promise<void> {
    return invoke<void>("cancel_login");
  },

  logout(): Promise<void> {
    return invoke<void>("logout");
  },
};
