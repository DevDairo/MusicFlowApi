# syntax=docker/dockerfile:1.7

ARG KEYCLOAK_IMAGE=quay.io/keycloak/keycloak:26.7.0@sha256:0f198be292568439d700cdbfb893e69a6009bb43a94a06a945b1d3d506c76b13

FROM ${KEYCLOAK_IMAGE} AS builder

ENV KC_DB=postgres \
    KC_HEALTH_ENABLED=true \
    KC_METRICS_ENABLED=true

RUN /opt/keycloak/bin/kc.sh build

FROM ${KEYCLOAK_IMAGE}

ENV KC_DB=postgres \
    KC_HEALTH_ENABLED=true \
    KC_METRICS_ENABLED=true

COPY --from=builder /opt/keycloak/ /opt/keycloak/
COPY --chown=1000:0 realm-musicflow.json /opt/keycloak/data/import/realm-musicflow.json
COPY --chown=1000:0 --chmod=0555 start-musicflow-keycloak.sh /opt/keycloak/bin/start-musicflow-keycloak.sh

ENTRYPOINT ["/opt/keycloak/bin/start-musicflow-keycloak.sh"]
