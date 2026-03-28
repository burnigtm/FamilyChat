# FamilyChat

FamilyChat is a self-hosted family messenger with a React web client, a Rust backend service, a shared Rust crypto core, and Docker-based infrastructure assets. The active UI surface now lives in `client/web`; the older Flutter client remains in the repository as a prototype reference.

## Repository Structure

```text
.
|-- client/
|   |-- web/                 # React + Vite web client
|   `-- flutter/             # Legacy Flutter prototype
|-- core/crypto/             # Shared Rust crypto experiments
|-- server/                  # Axum API, websocket hub, persisted app store
|-- infra/                   # Docker Compose, Caddy, LiveKit configuration
`-- plan.md                  # Master implementation roadmap
```

## Prerequisites

- Rust 1.75+ (`rustup` recommended)
- Node.js 22+
- npm 10+
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
```

The Flutter tests under `client/flutter/test` still cover the legacy prototype, but the React web client is now the primary app surface.

## Notes

- `plan.md` still describes broader milestones such as attachments, push, and native clients.
- The active React web app now covers browser E2EE rooms, linked browser devices, encrypted message sync, and LiveKit call join flow. The legacy Flutter app remains prototype reference code.

## License

Apache 2.0 / MIT dual license (mirroring `libsignal-client`). Individual marketplace assets must respect their original licenses.
