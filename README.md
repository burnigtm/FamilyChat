# FamilyChat

FamilyChat is a secure, self-hosted messenger for families that combines end-to-end encrypted messaging, attachments, and LiveKit-powered calls. The project mirrors the milestones defined in [`plan.md`](plan.md) and is split across Flutter clients, a shared Rust crypto core, a Rust backend service, and Docker-based infrastructure assets.

## Repository Structure

```
.
├── client/flutter            # Flutter app for Android, iOS, Windows
│   ├── lib/
│   │   ├── bridge/           # FFI glue (stubbed) for the Rust crypto core
│   │   ├── chat/             # Conversation UI + controllers
│   │   ├── calls/            # LiveKit call lobby placeholder
│   │   ├── data/             # Drift database bootstrap
│   │   └── services/         # HTTP + WebSocket clients
├── core/crypto               # Rust crate exposing FFI-compatible E2EE helpers
├── server                    # Axum backend for device registry and messaging
├── infra                     # Docker Compose, Caddy, LiveKit configuration
└── plan.md                   # Master implementation roadmap
```

## Prerequisites

- **Rust** 1.75+ (`rustup` recommended). Ensure `%USERPROFILE%\.cargo\bin` is on your `PATH`.
- **Flutter** 3.24 (stable channel). Add `C:\src\flutter\bin` (or your install path) to the `PATH`.
- **Docker & Docker Compose** for running the infrastructure bundle.

After installing the toolchains, open a new shell so the updated `PATH` values are picked up.

## Development Workflow

### Rust workspace

```powershell
# From repo root
cargo check
cargo test
```

The workspace currently includes:
- `core/crypto`: FFI-friendly stubs for Signal-style identity/prekey generation, message encryption placeholders, and group sender key rotation.
- `server`: Axum service exposing REST + WebSocket endpoints, Redis fan-out, and LiveKit key derivation helpers.

### Flutter client

```powershell
cd client/flutter
flutter pub get
flutter analyze
flutter test
```

The Flutter application is scaffolded with Riverpod state management and GoRouter navigation. It currently mocks crypto operations via `lib/bridge/crypto_stub.dart`, paving the way for `flutter_rust_bridge` integration once the Rust FFI is stable.

### Infrastructure

Bootstrap a local stack with Docker Compose:

```powershell
cd infra
copy .env.example .env   # update secrets & domain
docker compose up --build
```

Services:
- `server`: Axum binary from this workspace
- `postgres`: chat metadata
- `redis`: push fan-out + background jobs
- `minio`: attachment storage
- `livekit`: WebRTC SFU
- `caddy`: TLS termination and routing

### Testing Strategy

The repository includes unit tests that exercise:
- Crypto crate FFI contracts and data structures (`core/crypto/src/lib.rs`, `core/crypto/tests`).
- Server-side key derivation, models, and placeholder routes (`server/src/**`, `server/tests`).
- Flutter widget and provider logic (under `client/flutter/test/`).

Run either workspace tests or individual package suites when contributing new features.

```powershell
cargo test                    # Rust tests
flutter test                  # Flutter unit/widget tests
```

## Documentation & Roadmap

- `plan.md` captures the full milestone roadmap (M0 infrastructure through M8 hardening).
- Inline Rust doc comments provide contextual details for core modules and FFI surfaces.
- The Flutter codebase includes TODO markers where LiveKit integration and real data synchronization will land.

Contributions should update milestone progress in `plan.md` as features graduate through the roadmap.

## License

Apache 2.0 / MIT dual license (mirroring `libsignal-client`). Individual marketplace assets (e.g., Flutter icons) must respect their original licenses.
