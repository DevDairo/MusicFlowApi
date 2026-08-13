# syntax=docker/dockerfile:1.7

ARG NODE_IMAGE=node:24.17.0-bookworm-slim
ARG RUST_IMAGE=rust:1.96.1-bookworm
ARG PNPM_VERSION=11.15.1

FROM ${NODE_IMAGE} AS javascript-lock
ARG PNPM_VERSION
RUN npm install --global "pnpm@${PNPM_VERSION}"
WORKDIR /workspace
COPY package.json ./
RUN pnpm install --lockfile-only --ignore-scripts

FROM ${RUST_IMAGE} AS rust-lock
WORKDIR /workspace/src-tauri
COPY src-tauri/Cargo.toml ./
COPY src-tauri/build.rs ./
COPY src-tauri/src ./src
RUN cargo generate-lockfile

FROM scratch AS lockfiles
COPY --from=javascript-lock /workspace/pnpm-lock.yaml /pnpm-lock.yaml
COPY --from=rust-lock /workspace/src-tauri/Cargo.lock /src-tauri/Cargo.lock

FROM ${NODE_IMAGE} AS javascript-dependencies
ARG PNPM_VERSION
RUN npm install --global "pnpm@${PNPM_VERSION}"
WORKDIR /workspace
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile --ignore-scripts

FROM javascript-dependencies AS quality
COPY . .
RUN pnpm format:check
RUN pnpm lint
RUN pnpm test
RUN pnpm build

FROM ${NODE_IMAGE} AS node-runtime

FROM ${RUST_IMAGE} AS windows-toolchain
ARG PNPM_VERSION
COPY --from=node-runtime /usr/local/ /usr/local/
RUN apt-get update \
    && apt-get install --yes --no-install-recommends clang lld llvm nsis \
    && rm -rf /var/lib/apt/lists/*
RUN npm install --global "pnpm@${PNPM_VERSION}"
RUN rustup target add x86_64-pc-windows-msvc
RUN cargo install --locked --version 0.22.0 cargo-xwin
RUN rustup component add rustfmt

FROM windows-toolchain AS windows-builder
ARG ACCEPT_MICROSOFT_SDK_LICENSE=no
RUN test "${ACCEPT_MICROSOFT_SDK_LICENSE}" = "yes"
ENV XWIN_ACCEPT_LICENSE=1
WORKDIR /workspace
COPY package.json pnpm-lock.yaml ./
COPY --from=javascript-dependencies /workspace/node_modules ./node_modules
COPY . .
RUN pnpm tauri icon src-tauri/app-icon.svg --output src-tauri/icons
RUN cargo fmt --manifest-path src-tauri/Cargo.toml -- --check
RUN pnpm tauri build \
    --runner cargo-xwin \
    --target x86_64-pc-windows-msvc \
    --bundles nsis \
    -- --locked

FROM scratch AS artifact
COPY --from=windows-builder /workspace/src-tauri/target/x86_64-pc-windows-msvc/release/bundle/nsis/ /
