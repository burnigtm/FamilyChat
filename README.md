# FamilyChat

FamilyChat is a self-hosted family messenger with a React web client, an Android-focused Flutter client, a Rust backend service, a shared Rust crypto core, and Docker-based infrastructure assets.

## Repository Structure

```text
.
|-- client/
|   |-- web/                 # React + Vite web client
|   `-- flutter/             # Flutter Android client
|-- core/crypto/             # Shared Rust crypto experiments
|-- server/                  # Axum API, websocket hub, persisted app store
|-- infra/                   # Docker Compose, Caddy, LiveKit configuration
`-- plan.md                  # Master implementation roadmap
```

## Prerequisites

- Rust 1.75+ (`rustup` recommended)
- Node.js 22+
- npm 10+
- Flutter SDK
- Docker & Docker Compose

## Development Workflow

### Rust server

```powershell
# From repo root
cargo check -p familychat-server
cargo test -p familychat-server
```

The server now provides:

- device registration and session bootstrap
- short-lived browser linking tokens
- room creation and membership management
- per-device wrapped room keys and encrypted message envelopes backed by a JSON state file
- device-scoped websocket delivery for live updates
- LiveKit access token issuance for encrypted calls
- static serving for the built React bundle

### React web client

```powershell
cd client/web
npm install
npm run dev
```

The web client includes:

- browser device registration and token-based linking
- local persistence for session, device keys, room keys, room list, and cached timelines
- browser-side room-key wrapping and message encryption with Web Crypto
- split-pane room and thread layout
- group membership changes with room-key rotation
- LiveKit voice/video calls with client-side E2EE key derivation
- websocket-driven live updates
- env-based API and websocket endpoints via `VITE_API_BASE_URL` and `VITE_WS_BASE_URL`

Create a production build with:

```powershell
cd client/web
npm run build
```

### Flutter Android client

```powershell
cd client/flutter
flutter pub get

# If this checkout does not yet contain generated Android files:
flutter create . --platforms=android

flutter test
flutter test integration_test -d emulator-5554
flutter run -d android
```

The Flutter client now includes:

- Android device registration and token-based linking
- persisted session, device keys, room keys, room list, and cached timelines
- Android-side room-key wrapping and message encryption with `package:cryptography`
- mobile room list, thread view, member rotation flow, and composer UI
- LiveKit voice/video calls with client-side E2EE key derivation
- websocket-driven live updates
- env-based API and websocket endpoints via `FAMILYCHAT_API_BASE_URL` and `FAMILYCHAT_WS_BASE_URL`

The generated Android platform scaffold is not committed in this branch because the Flutter SDK was not available in the current environment. Run `flutter create . --platforms=android` inside `client/flutter` before building on a workstation with Flutter installed.

### Infrastructure

Bootstrap the full stack with Docker Compose:

```powershell
cd infra
copy .env.example .env
docker compose up --build
```

Services:

- `server`: Axum server plus the built React bundle
- `postgres`: reserved for later structured persistence work
- `redis`: reserved for later fan-out/background work
- `minio`: attachment storage
- `livekit`: WebRTC SFU
- `caddy`: TLS termination and edge routing

The server persists its current room/message state at `/var/lib/familychat/state.json` inside the container, backed by the `server_data` Docker volume.
Set `LIVEKIT_URL` to the public websocket endpoint that browsers should connect to. The default compose setup expects `wss://familychat.localhost/livekit`, which Caddy proxies to the LiveKit container.

## Testing

```powershell
cargo test -p familychat-server
cd client/web; npm run build
cd client/flutter; flutter test
cd client/flutter; flutter test integration_test -d emulator-5554
```

The web client and Flutter Android client now both cover encrypted rooms, linked devices, encrypted message sync, and LiveKit call join flows. The Android client also includes `integration_test/` coverage for device or emulator runs. Rust tests remain the source of truth for the backend behavior.

## Notes

- `plan.md` still describes broader milestones such as attachments and push.
- The active React web app and Flutter Android client both cover local E2EE room keys, linked devices, encrypted message sync, membership rotation, and LiveKit call join flow.

## License

Apache 2.0 / MIT dual license (mirroring `libsignal-client`). Individual marketplace assets must respect their original licenses.
