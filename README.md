# Genesis

Genesis is a private, offline-first digital legacy app backed by a FastAPI Python service.

The long-term goal is to preserve not only what a person knows, but how they think: memories, values, reasoning patterns, personality, communication style, and the context behind important life events. Future generations should be able to ask meaningful questions and receive answers grounded in intentionally saved memories.

Genesis is not designed to be a generic chatbot. The app should never invent personal memories, names, dates, or events. If a memory has not been provided by the owner, Genesis should say that it does not have a record of it.

## Current Milestone

The current milestone is a native iOS app that talks to a local Genesis backend (FastAPI + MLX), with a complete authentication and session system.

This phase focuses on:

- Native SwiftUI app structure.
- Owner, family-member, and visitor authentication modes.
- Keychain-backed session persistence.
- A chat UI grounded in backend-retrieved memories.
- Conversation history sent to backend for multi-turn context.
- Backend-side memory CRUD (create, read, delete, import).
- A local MLX model server as the inference engine.
- Guardrails that reduce hallucination by refusing to call the model when no relevant memory is found.

## Principles

- Offline first: the app is designed around local execution.
- Privacy first: the owner controls the data.
- User-owned archive: memory data should outlive any one AI model.
- No fabricated memories: answers must be grounded in saved entries.
- Small releases: each milestone should add one useful layer without overbuilding.
- Clean architecture: SwiftUI views do not own business logic or networking.

## App Overview

The app has three user-facing flows depending on who is logged in.

### Owner flow (full access)

| Tab | Purpose |
| --- | --- |
| Chat | Ask questions, receive memory-grounded answers, view source titles. |
| Archive | View, search, add, delete, and import memories to/from the backend. |
| Settings | Configure persona, backend URL, MLX server address, model, connection tests. |

### Family member flow

Family members log in with a handle + password registered by the owner on the backend. They reach the same `VisitorChatView` as guests but are authenticated with a persistent identity. Their session is stored in Keychain and restored on next launch.

### Visitor (guest) flow

Visitors enter their name and self-register. The backend issues a signed visitor token. The visitor sees `VisitorChatView` — a read-only, single-session chat interface with a "Leave" button that clears the session and returns to the entry screen.

---

## Entry Screen

`LegacyAI/Views/EntryView.swift`

The entry screen is shown whenever there is no valid session in Keychain. It presents three choices:

- **Owner Login** — enter the backend `GENESIS_AUTHOR_TOKEN` to authenticate.
- **Family Member Login** — enter a registered handle and password (`POST /v1/family/login`).
- **Visit as Guest** — enter a display name to self-register (`POST /v1/visitors/self-register`).

---

## Repository Layout

```text
Genesis
├── App
│   └── Assets.xcassets
├── LegacyAI
│   ├── Info.plist
│   ├── LegacyAIApp.swift
│   ├── Models
│   │   ├── ChatMessage.swift
│   │   └── LifeEntry.swift
│   ├── Resources
│   │   └── sample_entries.json
│   ├── Services
│   │   ├── AppSettings.swift
│   │   ├── ArchiveStore.swift
│   │   ├── BackendClient.swift
│   │   ├── ChatStore.swift
│   │   ├── MLXChatService.swift
│   │   ├── ModelSettings.swift
│   │   └── SessionManager.swift
│   └── Views
│       ├── ChatView.swift
│       ├── ContentView.swift
│       ├── EntryView.swift
│       ├── SettingsView.swift
│       └── VisitorChatView.swift
├── Genesis.xcodeproj
├── GenesisTests
├── GenesisUITests
└── README.md
```

The active iOS app code lives under `LegacyAI`.

---

## Active Code Structure

### Models

`LegacyAI/Models/LifeEntry.swift`

Defines one saved memory. Categories include childhood, family, career, values, advice, relationships, imported, and other.

`LegacyAI/Models/ChatMessage.swift`

Defines messages shown in the chat UI, including role (`user` / `assistant`) and optional source memory titles for assistant responses.

---

### Services

`LegacyAI/Services/AppSettings.swift`

Persists app settings in `UserDefaults`:

| Setting | Key | Default |
| --- | --- | --- |
| MLX server URL | `serverBaseURL` | `http://192.168.x.x:8080` |
| Genesis backend URL | `backendBaseURL` | `http://192.168.x.x:8090` |
| Selected MLX model name | `modelName` | First supported model |
| Persona name | `personaName` | `Me` |
| Style notes | `styleNotes` | First-person calm voice |

`LegacyAI/Services/SessionManager.swift`

Single source of truth for authentication state. Stores `StoredSession` (role + token) in the iOS **Keychain** — never in `UserDefaults`. Survives app relaunch.

Supports three roles via `UserRole`:

- `.owner` — full access, token validated against `/v1/auth/check`.
- `.visitor(visitorId:visitorName:)` — read-only chat. Created by self-registration or family login.

Key methods:

| Method | Backend endpoint | Description |
| --- | --- | --- |
| `loginAsOwner(token:backendBaseURL:)` | `GET /v1/auth/check` | Validates owner token, stores session. |
| `loginAsFamily(handle:password:backendBaseURL:)` | `POST /v1/family/login` | Authenticates with handle + password. |
| `registerAsVisitor(name:backendBaseURL:)` | `POST /v1/visitors/self-register` | Issues a signed visitor token. |
| `logout(chatStore:)` | — | Clears Keychain + in-memory chat history. |
| `handleUnauthorized(chatStore:)` | — | Called on 401/403 — clears session, shows error. |

Fail-closed: any Keychain read failure → no session → entry screen.

`LegacyAI/Services/BackendClient.swift`

All HTTP communication with the Genesis FastAPI backend. Handles:

- `POST /v1/chat` — send a question with conversation history, receive an answer + source titles.
- `GET /v1/auth/check` — owner token validation.
- `POST /v1/visitors/self-register` — visitor self-registration.
- `POST /v1/family/login` — family member login.
- `GET /v1/memories` — fetch all memories (owner).
- `POST /v1/memories` — create a new memory (owner, authenticated).
- `DELETE /v1/memories/{id}` — delete a memory (owner, authenticated).
- `POST /v1/memories/import` — bulk import memories (owner, authenticated).
- `GET /health` — health check.

Applies `Authorization: Bearer <token>` to all authenticated requests. Translates `URLError` codes into human-readable `ClientError` cases. Blocks `127.0.0.1` / `localhost` on real devices (see Simulator vs Physical iPhone below).

Chat request payload shape:

```json
{
  "question": "Do you remember our first date?",
  "history": [
    { "role": "user", "content": "..." },
    { "role": "assistant", "content": "..." }
  ]
}
```

Chat response shape:

```json
{
  "answer": "Of course I do ...",
  "source_titles": ["First Date - Shillong"]
}
```

`LegacyAI/Services/ChatStore.swift`

Persists the on-device chat thread in `UserDefaults`. Builds the `history` array sent to `/v1/chat` — the last 8 turns (4 back-and-forth exchanges). Cleared on logout to prevent session bleed between users.

`LegacyAI/Services/ArchiveStore.swift`

Owns the local memory cache. Loads and saves `archive_entries.json` in the app documents directory, seeds from bundled sample entries on first launch, and can push the local archive cache to the backend.

`LegacyAI/Services/MLXChatService.swift`

Calls a local OpenAI-compatible MLX server. Supports connection checks, chat completions, model mismatch detection, timeout handling, and device safety checks.

`LegacyAI/Services/ModelSettings.swift`

Defines supported local MLX models and normalizes user-facing model names into the exact model id/path expected by the server.

---

### Views

`LegacyAI/Views/EntryView.swift`

Entry screen shown when no valid session exists in Keychain. Offers Owner Login, Family Member Login, and Visit as Guest flows. Animated transitions between modes. Shows auth errors inline.

`LegacyAI/Views/ContentView.swift`

Root view that routes between `EntryView` (no session) and the main tabbed interface (owner) or `VisitorChatView` (visitor/family session).

`LegacyAI/Views/ChatView.swift`

Owner chat interface. Sends questions + history to the backend, shows source memory titles on assistant replies, supports cancelling in-flight requests.

`LegacyAI/Views/VisitorChatView.swift`

Chat interface for visitors and family members. Same chat UX as the owner view but:

- Header banner shows "Visiting as [Name]".
- "Leave" button in the navigation bar clears session and returns to `EntryView`.
- No access to Archive or Settings tabs.
- Typewriter animation on assistant responses.
- Handles `401` from backend by calling `SessionManager.handleUnauthorized`.

`LegacyAI/Views/SettingsView.swift`

Configures persona and server settings. Includes both MLX server URL and Genesis backend URL fields, connection tests, model selection, and bundled sample memory import.

---

### Resources

`LegacyAI/Resources/sample_entries.json`

Bundled seed memories. Must stay valid JSON. Copied into the app's local archive on first launch if no archive exists. Use Settings → Archive → Load bundled sample memories if the simulator already has an archive.

---

## Authentication Flow

```text
App launch
    → Load StoredSession from Keychain
    → No session?  → EntryView (choose role)
    → Has session? → ContentView (owner tabs or VisitorChatView)

Owner login:
    EntryView → enter GENESIS_AUTHOR_TOKEN
    → BackendClient.validateOwnerToken → GET /v1/auth/check
    → 200 → SessionManager stores .owner session in Keychain
    → 401 → show error

Family login:
    EntryView → enter handle + password
    → BackendClient.loginFamilyMember → POST /v1/family/login
    → 200 → SessionManager stores .visitor session in Keychain
    → 401 → show "Invalid handle or password"

Visitor self-register:
    EntryView → enter name
    → BackendClient.selfRegisterVisitor → POST /v1/visitors/self-register
    → 200 → SessionManager stores .visitor session in Keychain

Any request → 401:
    → SessionManager.handleUnauthorized
    → Clears Keychain + chat history → EntryView
```

---

## Chat Flow (Backend path)

```text
User sends question
    → ChatStore.historyForAPI() (last 8 turns)
    → BackendClient.sendChat(question, history, baseURL, authToken)
    → POST /v1/chat with Bearer token
    → Backend: intent resolution → retrieval → MLX inference
    → { answer, source_titles }
    → ChatStore.appendAssistantMessage
    → ChatView / VisitorChatView renders reply with source titles
```

The backend handles intent resolution, retrieval, tone-tier selection (owner vs. visitor vs. wife persona), and MLX generation. The iOS app passes conversation `history` so the backend can resolve follow-up questions in context.

---

## Hallucination Guardrails

Genesis reduces hallucination in several ways:

- **Backend side**: retrieval must find at least one matching memory before the model is called; intent is resolved before retrieval; empty-state responses are humane rather than fabricated.
- **Local side** (MLX-only fallback): retrieval must find at least one matching memory; generic query words are treated as stopwords; the model prompt forbids inventing personal facts.
- The UI shows source memory titles for every generated answer.

---

## Local MLX Model Server

Genesis expects a local OpenAI-compatible MLX server (port 8080 by default).

| Model | Best for | App model value |
| --- | --- | --- |
| Qwen2.5 14B Instruct | Default conversational legacy answers | `~/.cache/huggingface/mlx-qwen25-14b-instruct` |
| Qwen2.5 Coder 14B Instruct | Programming and technical explanations | `mlx-community/Qwen2.5-Coder-14B-Instruct-4bit` |

Start the default model:

```bash
mlx_lm.server --host 0.0.0.0 --port 8080 --model ~/.cache/huggingface/mlx-qwen25-14b-instruct
```

---

## Genesis Backend

The iOS app communicates with the `genesis-backend` FastAPI service (port 8090 by default).

Start the backend:

```bash
cd genesis-backend
uvicorn app.main:app --host 0.0.0.0 --port 8090 --reload
```

Backend API surface:

| Method | Path | Auth | Description |
| --- | --- | --- | --- |
| `GET` | `/health` | None | Health check |
| `GET` | `/v1/auth/check` | Owner | Validate owner token |
| `POST` | `/v1/visitors/self-register` | None | Guest self-registration |
| `POST` | `/v1/family/login` | None | Family member login |
| `POST` | `/v1/chat` | Owner or Visitor | Memory-grounded chat |
| `GET` | `/v1/memories` | Owner | List all memories |
| `POST` | `/v1/memories` | Owner | Create a memory |
| `DELETE` | `/v1/memories/{id}` | Owner | Delete a memory |
| `POST` | `/v1/memories/import` | Owner | Bulk import memories |

Owner authentication uses a static `GENESIS_AUTHOR_TOKEN` set in the backend `.env` file. Visitor tokens are HMAC-signed and validated against the database on every request — stale tokens are rejected with `401`.

---

## Simulator vs Physical iPhone

For the iOS Simulator:

```text
http://127.0.0.1:8080    (MLX server)
http://127.0.0.1:8090    (Genesis backend)
```

For a physical iPhone, do not use `127.0.0.1` or `localhost`. Use the Mac's LAN IP:

```bash
ipconfig getifaddr en0
```

Then use:

```text
http://<mac-lan-ip>:8080    (MLX server)
http://<mac-lan-ip>:8090    (Genesis backend)
```

The Mac and iPhone must be on the same Wi-Fi network. Both servers must be started with `--host 0.0.0.0`.

---

## Xcode And Permissions

The project is wired into `Genesis.xcodeproj`.

The app uses `LegacyAI/Info.plist` for local networking:

- `NSLocalNetworkUsageDescription`
- `NSAppTransportSecurity`
- `NSAllowsLocalNetworking = YES`

---

## Running The App

1. Start the MLX server (`--host 0.0.0.0 --port 8080`).
2. Start the Genesis backend (`--host 0.0.0.0 --port 8090`).
3. Open `Genesis.xcodeproj` in Xcode.
4. Build and run on device or simulator.
5. Set the backend URL and MLX URL in Settings.
6. Run Test connection for both.
7. Log in (owner token, family handle/password, or guest name).

---

## Adding Memories (Owner)

- Add a memory manually in Archive → syncs to backend.
- Import `.txt` or `.md` files → bulk-sent to backend.
- Load bundled sample memories from Settings.

Each memory should be specific. One event, belief, lesson, or relationship per entry. Clear title, natural first-person content, useful tags, and a date if known.

---

## Current Limitations

- Retrieval is keyword-based on the local fallback path; the backend uses intent + attribute matching.
- No vector database or local embeddings yet.
- The model can still phrase things poorly if the retrieved memory is too broad or ambiguous.
- The app is not ready for sensitive production use until encryption, export, backup, deletion, and audit behavior are designed.

---

## Future Pipeline

1. Replace keyword retrieval with local semantic retrieval (sqlite-vec + embeddings).
2. Add chunking and citation-like source tracking.
3. Add evaluation tests for hallucination, grounding, and refusal behavior.
4. Add local encryption, backup, export, and deletion guarantees.
5. Add timeline views for life events.
6. Add relationship graph support.
7. Add personality and decision-modeling layers.
8. Add voice support only after the memory and privacy architecture is stable.
9. Add image understanding only when local models and explicit consent flows are ready.

---

## Design Rules For Future Work

- SwiftUI views should talk to `SessionManager`, `ChatStore`, or `BackendClient` — not raw networking.
- Business logic should stay out of views.
- Services should be protocol-oriented where substitution matters.
- The archive format should remain model-independent.
- Never add a feature that requires cloud access for core operation.
- Prefer local, inspectable data formats until there is a strong reason not to.
- Do not commit private memory data unless that is an explicit choice.
- The backend is the source of truth for memories; the local `ArchiveStore` is a cache and offline fallback.

---

## Project Status

Genesis currently has a working backend-connected prototype:

- Native SwiftUI app.
- Owner / family / visitor authentication with Keychain session persistence.
- Backend-connected memory CRUD (create, read, delete, import).
- Conversation history sent to backend for multi-turn context.
- Memory-grounded chat via Genesis backend + MLX.
- Deterministic no-memory response on backend and local fallback.
- Source memory titles shown in chat responses.
- Visitor session DB validation — stale tokens rejected with `401`.
- Typewriter animation on assistant responses (visitor view).
- Local MLX connection tests and model picker in Settings.

The next good step is to replace keyword retrieval with semantic retrieval using embeddings, then expand the backend's intent resolution for more question phrasings.
