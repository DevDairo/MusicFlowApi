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

FROM ${RUST_IMAGE} AS rust-lock-check
WORKDIR /workspace/src-tauri
COPY src-tauri/Cargo.toml src-tauri/Cargo.lock ./
COPY src-tauri/build.rs ./
COPY src-tauri/src ./src
RUN --mount=type=cache,target=/usr/local/cargo/registry,sharing=locked \
    cargo metadata --locked --no-deps --format-version 1 > /dev/null

FROM ${NODE_IMAGE} AS javascript-dependencies
ARG PNPM_VERSION
RUN npm install --global "pnpm@${PNPM_VERSION}"
WORKDIR /workspace
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile --ignore-scripts

FROM javascript-dependencies AS icon-builder
COPY src-tauri/app-icon.svg ./src-tauri/app-icon.svg
RUN pnpm tauri icon src-tauri/app-icon.svg --output src-tauri/icons

FROM ${RUST_IMAGE} AS rust-quality
RUN rustup component add rustfmt
RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        build-essential \
        libayatana-appindicator3-dev \
        librsvg2-dev \
        libssl-dev \
        libwebkit2gtk-4.1-dev \
        libxdo-dev \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /workspace/src-tauri
COPY src-tauri/Cargo.toml src-tauri/Cargo.lock ./
COPY src-tauri/build.rs ./
COPY src-tauri/tauri.conf.json ./
COPY src-tauri/capabilities ./capabilities
COPY --from=icon-builder /workspace/src-tauri/icons ./icons
COPY src-tauri/src ./src
RUN cargo fmt -- --check
RUN --mount=type=cache,target=/usr/local/cargo/registry,sharing=locked \
    --mount=type=cache,target=/workspace/src-tauri/target,sharing=locked \
    cargo test --locked

FROM scratch AS lockfiles
COPY --from=javascript-lock /workspace/pnpm-lock.yaml /pnpm-lock.yaml
COPY --from=rust-lock /workspace/src-tauri/Cargo.lock /src-tauri/Cargo.lock

FROM javascript-dependencies AS quality
COPY . .
RUN pnpm format:check
RUN pnpm lint
RUN pnpm test
RUN pnpm build

FROM rust-quality AS quality-rust

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
COPY --from=icon-builder /workspace/src-tauri/icons ./src-tauri/icons
RUN cargo fmt --manifest-path src-tauri/Cargo.toml -- --check
RUN --mount=type=cache,target=/usr/local/cargo/registry,sharing=locked \
    --mount=type=cache,id=musicflow-windows-x86_64-target,target=/workspace/src-tauri/target/x86_64-pc-windows-msvc,sharing=locked \
    pnpm tauri build \
    --runner cargo-xwin \
    --target x86_64-pc-windows-msvc \
    --bundles nsis \
    -- --locked \
    && mkdir -p /workspace/artifact \
    && cp /workspace/src-tauri/target/x86_64-pc-windows-msvc/release/bundle/nsis/*-setup.exe /workspace/artifact/

FROM scratch AS artifact
COPY --from=windows-builder /workspace/artifact/ /
