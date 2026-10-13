# LocalLink Backend API Contract

Extracted 2026-10-14 from the Flutter client source of truth
(`lib/core/services/locallink_api.dart`, `lib/core/services/websocket_service.dart`,
`lib/features/*/data`). Use this to align `localLinkBackend` with the app.

## Transport

- **REST:** `{baseUrl}/api/v1/...` — JSON bodies, `Authorization: Bearer <device token>`.
- **WebSocket:** `{wsUrl}/ws` (scheme derived from REST base; authenticated with the
  device token). Client sends and receives JSON text frames.
- **Discovery probe:** `GET {baseUrl}/api/v1/pairing/info` **without** auth — the app
  uses it to validate a server address before pairing (6s timeout).
- Selected mutating calls include an **`Idempotency-Key` header** — the backend must
  deduplicate retries by that key (recovery-code rotate, etc.).
- Success is HTTP **200** (or 201 on POST-create); any other status raises with the
  server-provided error body surfaced to the user.

## REST endpoints the app calls

### Auth & account
| Method & path | Purpose |
|---|---|
| `POST /api/v1/auth/register` | Create account (username/password; first-run setup) |
| `POST /api/v1/auth/login` | Log in, returns device token + account |
| `GET  /api/v1/auth/me` | Validate current token, fetch account |
| `POST /api/v1/auth/logout` | Revoke token |
| `GET  /api/v1/status` | Server status (paired-user overview) |

### Profile & directory
| Method & path | Purpose |
|---|---|
| `GET  /api/v1/profile` | Own profile |
| `PUT  /api/v1/profile` | Update profile (display name, phone visibility…) |
| `POST /api/v1/profile/avatar` | Upload avatar (multipart) |
| `GET  /api/v1/profile/avatar` | Download avatar |
| `GET  /api/v1/directory/name?q=` | Search users by name |
| `GET  /api/v1/directory/phone?phone=` | Exact phone lookup |
| `GET  /api/v1/directory/user/{userId}` | Profile by user id |

### Devices & identity keys
| Method & path | Purpose |
|---|---|
| `POST /api/v1/devices` | Register current device |
| `GET  /api/v1/account/devices` | List account devices |
| `POST /api/v1/account/devices/revoke` | Revoke a device |
| `POST /api/v1/device-key` | Publish device signing/identity public key |
| `GET  /api/v1/device-keys` (+`/history`) | Peer public keys (+ versions) |
| `GET  /api/v1/device-key/history` | Own key history |
| `GET  /api/v1/device-keys/history` | All devices' key history |
| `POST /api/v1/device-key/rotate` | Rotate identity key |

### Messaging & sync
| Method & path | Purpose |
|---|---|
| `POST /api/v1/messages/ack` | Acknowledge receipt (REST fallback) |
| `GET  /api/v1/sync?cursor=` | Incremental catch-up (messages, statuses) |
| `POST /api/v1/groups` | Create group |
| `GET/POST /api/v1/groups/members` | Group membership |
| `POST /api/v1/group-messages` | Group message REST path |
| `GET/POST /api/v1/calls`, `POST /api/v1/calls/reconcile` | Call history + reconciliation |

### Account transfer, recovery, restore
| Method & path | Purpose |
|---|---|
| `POST /api/v1/account/transfer/start` · `/cancel` · `/complete` | Move account between devices (QR) |
| `POST /api/v1/account/recovery/request` · `/status` · `/complete` | Recovery flow |
| `GET  /api/v1/account/recovery-code/status`, `POST .../rotate`, `POST .../disable` | Recovery codes (idempotent rotate) |
| `GET  /api/v1/account/restore/manifest`, `GET /api/v1/account/restore/data` | Backup restore |
| `GET  /api/v1/account/crypto-backup` | Encrypted crypto material backup |

### Admin (`/api/v1/admin/*`)
`login`, `logout`, `summary`, `users`, `user/status`, `user/network`, `devices`,
`device/rename`, `device/revoke`, `device/network`, `groups`, `calls`, `transfers`,
`recovery`, `network`, `privacy`, `security` (GET/PUT), `settings` (GET/PUT),
`sessions`, `session/revoke`, `logs`, `backup`, `runtime`, `admin` (create admin).

## WebSocket protocol (`/ws`)

### App → server
| `type` | Fields | Notes |
|---|---|---|
| `send_message` | `id`, `recipient_id`, `body`, `created_at`, `attachment_ids[]?` | Sent with `durable: true` (client queues while offline) |
| `send_group_message` | `id`, `group_id`, `body`, `created_at`, `attachment_ids[]?` | Durable |
| `ack_delivery` | `id` | Receiver → sender delivery acknowledgement |
| `presence_update` | `server_connected`, `wifi_direct_connected`, `lan_available`, `mesh_available`, `wifi_enabled`, `managed_device`, `signing_public_key`, `status_updated_at`… | Fan out to interested devices |

### Server → app
| `type` | Meaning / required behavior |
|---|---|
| `message` | New incoming direct message `{id, sender_id, recipient_id, body, created_at, attachments?, server_seq}`. **Client replies `ack_delivery`** |
| `message_ack` | Server accepted an outbound message → client marks `server_accepted` and removes it from the outbox |
| `delivery_ack` | Some recipient device acked `{id, status, created_at?}` → delivered |
| `presence` / presence events | `{device_id, name?, network_status, server_connected, wifi_direct_connected, last_seen_at, status_updated_at}` |
| `error` | `{message/code}` — surfaced via diagnostics |

## Backend behaviors the app depends on (alignment checklist)

1. **`pairing/info` is public** and stays fast — every LAN discovery check hits it.
2. **Token per device**; `auth/me` must validate it; revoked devices' tokens die.
3. **Outbox semantics:** for each `send_message`, emit `message_ack` to the sender
   promptly, then `message` to *every online device of the recipient user*, and relay
   the recipient's `ack_delivery` back to the sender as `delivery_ack`.
4. **Offline catch-up:** messages sent while a device is offline are delivered through
   `/api/v1/sync` (cursor-based) when it reconnects; keep `server_seq` monotonic.
5. **Presence fanout:** forward `presence_update` to devices that share any
   conversation/group, include `last_seen_at`.
6. **Idempotency:** retried mutating calls with the same `Idempotency-Key` return the
   original result, never a duplicate effect.
7. **Attachments:** `attachment_ids` in frames reference files already uploaded via the
   files API; the WS layer never carries binary.
8. **Group fanout** mirrors direct fanout (ack → member devices → delivery acks).
