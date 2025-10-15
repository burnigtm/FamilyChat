# FamilyChat — Secure, Self‑Hosted Messenger (Signal + LiveKit)

## Outcome

A private messenger for your family with end‑to‑end encrypted 1:1 and group chat, attachments, and voice/video calls. Cross‑platform clients (Android, iOS, Windows PC) using Flutter, a shared Rust crypto core (wrapping libsignal‑client), a Rust backend for relay and device registry, and a self‑hosted LiveKit SFU. Deployed with Docker (VPS or home server) behind TLS.

## Technology Choices

- Clients: Flutter 3.x (Android, iOS, Windows). State: Riverpod or Bloc; local DB: Drift (SQLite). Secure storage: Keychain/Keystore/DPAPI via `flutter_secure_storage`.
- Crypto core: Rust 1.7x crate wrapping `libsignal-client` (Signal Protocol: X3DH + Double Ratchet + Sender Keys for groups). Bridge via `flutter_rust_bridge`.
- Backend: Rust (Axum) + Postgres 16 + Redis 7. WebSocket for realtime envelopes, REST for control. Attachments on MinIO (S3‑compatible). Background jobs with Tokio + Redis streams.
- Calls: LiveKit Server (self‑host) + Flutter `livekit_client`. Enable E2EE with SFrame and external key provider derived per conversation.
- Infra: Docker Compose, Caddy (reverse proxy + Let’s Encrypt). Observability: Loki + Promtail (optional lightweight) and basic metrics.
- Push: FCM (Android) + APNs (iOS). Desktop uses in‑app WS notifications.

## High‑Level Architecture

- `client/flutter/` (UI, state, persistence, notifications)
- `core/crypto/` (Rust crate: identity, prekeys, sessions, group sender keys, attachment key wrapping)
- `server/` (Axum HTTP+WS, persistence, delivery, prekey service, device registry, push fanout)
- `infra/` (`docker-compose.yml`, Caddy, Postgres, Redis, MinIO, LiveKit)

## Data Model (essential entities)

- User(id, displayName, avatarUrl?, createdAt)
- Device(id, userId, deviceLabel, pushToken?, platform, createdAt, lastSeenAt)
- PreKey(id, deviceId, keyId, publicKey, createdAt, consumedAt?)
- SignedPreKey(deviceId, keyId, publicKey, signature, createdAt, rotatedAt?)
- Conversation(id, type: direct|group, title?, createdAt)
- ConversationMember(conversationId, userId, role)
- MessageEnvelope(id, conversationId, senderDeviceId, recipientDeviceId, ciphertext, type, createdAt, deliveredAt?, readAt?)
- Attachment(id, conversationId, objectKey, size, mediaType, encKeyCiphertext, createdAt)

## Critical Flows

1) Registration (primary device)

- Client generates identity key pair (Rust), signed prekey + prekeys; uploads to server.
- Server creates `User` + `Device` records; stores prekeys.

2) Device linking (secondary device)

- Primary shows QR with short‑lived linking token; secondary scans; server verifies via primary’s signed approval and attaches new `Device` with its prekeys.

3) 1:1 sending

- Sender fetches recipient device prekeys, establishes sessions (X3DH), encrypts per‑device; uploads envelopes. For attachments: generate random file key, encrypt file locally, upload to MinIO via presigned URL, send metadata + file key wrapped in Signal message.

4) Receiving

- Client maintains WS connection; pulls envelopes, decrypts, stores, acks; server marks delivered/read; optional expiry/retention policy.

5) Groups

- Create conversation; initialize Sender Key for the group; rotate on membership changes; messages use Sender Keys for efficiency.

6) Calls (LiveKit)

- Join LiveKit room scoped to conversation; derive E2EE room key via HKDF from a conversation secret; set key in LiveKit E2EE key provider; publish/subscribe.

## Security Properties

- End‑to‑end encryption for messages and attachments using Signal protocol primitives via `libsignal-client`.
- Calls protected with SFrame E2EE keys derived from conversation secrets (server never sees media keys).
- TLS (Caddy) for transport; strict auth via signed device tokens; minimum logging; message ciphertext only stored; optional message retention and local app lock/biometrics.

## Deployment (self‑host)

- `infra/docker-compose.yml` services: `server`, `postgres`, `redis`, `minio`, `livekit`, `caddy`.
- DNS A/AAAA to server; Caddy auto TLS; env files for secrets (DB, JWT, MinIO, APNs/FCM, LiveKit keys).
- Backup: nightly Postgres dump + MinIO lifecycle policies.

## Project Skeleton (paths)

- `/client/flutter/` → Flutter app
- `lib/` UI, screens (`chat/`, `calls/`, `settings/`), state, services
- `lib/bridge/` FFI glue to Rust crypto
- `lib/data/` Drift schema & repos; models
- `/core/crypto/` → Rust crate
- `src/lib.rs` FFI surface: `generate_identity`, `create_prekeys`, `encrypt_message`, `decrypt_message`, `group_sender_key_*`
- `/server/` → Rust Axum
- `src/main.rs`, `routes/`, `ws/`, `models/`, `db/`, `push/`, `livekit/keys.rs`
- `/infra/` → `docker-compose.yml`, `caddy/Caddyfile`, `livekit/config.yaml`

## Milestones

- M0: Infrastructure & skeleton running (no features)
- M1: E2EE 1:1 text chat (online delivery)
- M2: Offline delivery + receipts + message history
- M3: Attachments (encrypted upload/download)
- M4: 1:1 voice/video calls with E2EE (LiveKit)
- M5: Groups with Sender Keys
- M6: Multi‑device linking & initial sync
- M7: Push notifications (APNs/FCM)
- M8: Hardening (key rotation, backups, QA) & usability polish

## Notes & Risks

- Correct Signal protocol usage is critical; we rely on `libsignal-client` directly from Rust to reduce risk.
- iOS background delivery depends on APNs; design for resumable sync on app wake.
- Home server NAT may require port forwarding for LiveKit and Caddy; recommend VPS or router config.