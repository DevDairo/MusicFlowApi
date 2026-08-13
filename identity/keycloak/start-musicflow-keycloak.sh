#!/usr/bin/env bash

set -Eeuo pipefail

read_secret() {
    local secret_path="$1"
    local secret_name="$2"

    if [[ ! -r "${secret_path}" ]]; then
        printf 'Required secret is not readable: %s\n' "${secret_name}" >&2
        exit 1
    fi

    local secret_value
    secret_value="$(<"${secret_path}")"

    if [[ -z "${secret_value}" ]]; then
        printf 'Required secret is empty: %s\n' "${secret_name}" >&2
        exit 1
    fi

    printf '%s' "${secret_value}"
}

export KCRAW_DB_PASSWORD
KCRAW_DB_PASSWORD="$(read_secret /run/secrets/keycloak_db_password keycloak_db_password)"

export KCRAW_BOOTSTRAP_ADMIN_PASSWORD
KCRAW_BOOTSTRAP_ADMIN_PASSWORD="$(
    read_secret \
        /run/secrets/keycloak_bootstrap_admin_password \
        keycloak_bootstrap_admin_password
)"

exec /opt/keycloak/bin/kc.sh start --optimized --import-realm
