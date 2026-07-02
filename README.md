# Genesis

Genesis is a private, offline-first digital legacy app.

The long-term goal is to preserve not only what a person knows, but how they think: memories, values, reasoning patterns, personality, communication style, and the context behind important life events. Future generations should be able to ask meaningful questions and receive answers grounded in intentionally saved memories.

Genesis is not designed to be a generic chatbot. The app should never invent personal memories, names, dates, or events. If a memory has not been provided by the owner, Genesis should say that it does not have a record of it.

## Current Milestone

The current milestone is a local iOS chat application that talks to a local MLX model server.

This phase focuses on:

- Native SwiftUI app structure.
- A local memory archive.
- A chat UI grounded in saved memories.
- Local model selection for MLX.
- OpenAI-compatible `/v1/chat/completions` requests.
- Guardrails that reduce hallucination by refusing to call the model when no relevant memory is found.
- A simple path for adding, importing, and loading sample memories.

There is no RAG vector database yet, no embeddings, no cloud sync, no user account system, no voice cloning, and no image understanding. Those belong to later phases.

## Principles

- Offline first: the app is designed around local execution.
- Privacy first: the owner controls the data.
- User-owned archive: memory data should outlive any one AI model.
- No fabricated memories: answers must be grounded in saved entries.
- Small releases: each milestone should add one useful layer without overbuilding.
- Clean architecture: SwiftUI views do not own business logic or networking.

## App Overview

The app currently has three primary tabs:

| Tab | Purpose |
| --- | --- |
| Chat | Ask questions and receive first-person, memory-grounded answers. |
| Archive | View, search, add, delete, and import memories. |
| Settings | Configure persona voice, MLX server address, model selection, connection tests, and bundled sample imports. |

The app stores memories as `LifeEntry` records with:

- `id`
- `title`
- `content`
- `category`
- `tags`
- `date`

The app stores chat messages as `ChatMessage` records and can show which memory titles were used as sources for a response.

## Repository Layout

```text
Genesis
├── App
│   └── Assets.xcassets
├── Backend
├── Core
├── Docs
├── Features
├── Genesis.xcodeproj
├── GenesisTests
├── GenesisUITests
├── LegacyAI
│   ├── Models
│   ├── Resources
│   ├── Services
│   └── Views
├── Resources
├── Services
└── README.md
```

The active iOS app code currently lives under `LegacyAI`. The top-level folders exist for the broader Genesis architecture and future migration into a cleaner feature-based structure.

## Active Code Structure

### Models

`LegacyAI/Models/LifeEntry.swift`

Defines one saved memory. Categories include childhood, family, career, values, advice, relationships, imported, and other.

`LegacyAI/Models/ChatMessage.swift`

Defines messages shown in the chat UI, including optional source memory titles for assistant responses.

### Services

`LegacyAI/Services/ArchiveStore.swift`

Owns the local memory archive. It loads and saves `archive_entries.json` in the app documents directory, seeds from bundled sample entries on first launch, imports text files, deletes entries, and can import bundled sample memories later from Settings.

`LegacyAI/Services/RetrievalEngine.swift`

Performs local keyword-based retrieval over memory title, content, category, and tags. It scores direct term matches strongly, applies limited related-term expansion, and avoids using broad generic terms like "memory", "remember", and "tell" as retrieval signals.

`LegacyAI/Services/PersonaPromptBuilder.swift`

Builds the system and user prompts sent to the local model. It tells the model to speak in first person, rephrase memories naturally, answer only from retrieved memories, and explicitly say when a fact is not recorded.

`LegacyAI/Services/MLXChatService.swift`

Calls a local OpenAI-compatible MLX server. It supports:

- `GET /v1/models` connection checks.
- `POST /v1/chat/completions` chat requests.
- Model mismatch detection.
- Better messages for 404 model errors.
- Timeout handling for model loading or long generations.
- Device safety checks so `127.0.0.1` is only used in the simulator.

`LegacyAI/Services/ModelSettings.swift`

Defines supported local models and normalizes user-facing model names into the exact model id/path expected by the server.

`LegacyAI/Services/AppSettings.swift`

Persists app settings in `UserDefaults`, including server URL, selected model, persona name, and style notes.

### Views

`LegacyAI/Views/ContentView.swift`

Creates the main tab layout.

`LegacyAI/Views/ChatView.swift`

Displays the chat interface, retrieves relevant memories before each model call, refuses ungrounded questions when no memory matches, and supports cancelling in-flight requests.

`LegacyAI/Views/EntryListView.swift`

Displays saved memories, search, detail navigation, delete support, and entry import/add actions.

`LegacyAI/Views/AddEntryView.swift`

Creates a new memory manually.

`LegacyAI/Views/ImportEntriesView.swift`

Imports `.txt` or `.md` files as memory entries.

`LegacyAI/Views/SettingsView.swift`

Configures persona and local model server settings. It also includes connection tests, chat endpoint testing, model selection, memory count, load-error display, and a button to load bundled sample memories.

### Resources

`LegacyAI/Resources/sample_entries.json`

Bundled seed memories. This file must stay valid JSON. JSON comments are not allowed. On first app launch, this file is copied into the app's local archive if no archive exists yet. If the simulator already has an empty archive, use Settings -> Archive -> Load bundled sample memories.

## Memory Flow

The current flow is deliberately simple:

```text
Saved memories
    -> ArchiveStore
    -> RetrievalEngine
    -> PersonaPromptBuilder
    -> MLXChatService
    -> Local MLX model
    -> ChatView
```

When the user sends a question:

1. `ChatView` trims the question.
2. `RetrievalEngine` searches saved memories.
3. If no relevant memory is found, the app returns a deterministic no-record response without calling the model.
4. If relevant memories are found, `PersonaPromptBuilder` creates a grounded prompt.
5. `MLXChatService` sends the request to the local MLX server.
6. The response is shown with source memory titles.

This is the first hallucination guardrail: no retrieved memory means no model generation.

## Hallucination Guardrails

Genesis currently reduces hallucination in several ways:

- Retrieval must find at least one matching memory before the model is called.
- Generic query words are treated as stopwords.
- Related-term matching is limited and cannot freely pull unrelated memories.
- The model prompt explicitly forbids inventing personal facts.
- The prompt tells the model to say when a record is missing.
- The UI shows source memory titles for generated answers.

These guardrails are not a replacement for full RAG, citations, or evaluation tests, but they are enough for the current local prototype.

## Local Model Server

Genesis expects a local OpenAI-compatible MLX server.

The app currently supports these models:

| Model | Best for | App model value |
| --- | --- | --- |
| Qwen2.5 14B Instruct (Local) | Default conversational legacy answers | `/Users/johnsonelangbam/.cache/huggingface/mlx-qwen25-14b-instruct` |
| Qwen2.5 Coder 14B Instruct | Programming and technical explanations | `mlx-community/Qwen2.5-Coder-14B-Instruct-4bit` |

Start the default local Instruct model:

```bash
mlx_lm.server --host 0.0.0.0 --port 8080 --model ~/.cache/huggingface/mlx-qwen25-14b-instruct
```

Start the Coder model:

```bash
mlx_lm.server --host 0.0.0.0 --port 8080 --model mlx-community/Qwen2.5-Coder-14B-Instruct-4bit
```

The selected model in Genesis must match the model currently served by MLX.

## Simulator vs Physical iPhone

For the iOS Simulator, this can work:

```text
http://127.0.0.1:8080
```

For a physical iPhone, do not use `127.0.0.1` or `localhost`; those point to the phone itself. Use the Mac's LAN IP.

Find the Mac LAN IP:

```bash
ipconfig getifaddr en0
```

Then use:

```text
http://<mac-lan-ip>:8080
```

The Mac and iPhone must be on the same Wi-Fi network, and the MLX server should be started with `--host 0.0.0.0`.

## Xcode And Permissions

The project is wired into `Genesis.xcodeproj`.

The app uses `LegacyAI/Info.plist` for local networking:

- `NSLocalNetworkUsageDescription`
- `NSAppTransportSecurity`
- `NSAllowsLocalNetworking = YES`

The app should avoid blanket arbitrary networking because the product goal is private local execution.

## Running The App

Build from Xcode by opening:

```text
Genesis.xcodeproj
```

Or build from the command line:

```bash
xcodebuild build -project Genesis.xcodeproj -scheme Genesis -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/GenesisDerivedData
```

Before chatting:

1. Start the MLX server.
2. Open Genesis.
3. Go to Settings.
4. Select the matching model.
5. Confirm the server address.
6. Run Test connection.
7. Run Test chat response.
8. Add or import memories in Archive.

## Adding Memories

Current options:

- Add a memory manually in Archive.
- Import `.txt` or `.md` files.
- Load bundled sample memories from Settings.

Each memory should be specific. Short, concrete entries work better than broad life summaries because retrieval is currently keyword-based.

Recommended memory shape:

- One event, belief, lesson, or relationship per entry.
- Clear title.
- Natural first-person content.
- Useful tags such as `childhood`, `school`, `family`, `career`, or a person's name.
- Date if known; approximate dates are acceptable if the entry says they are approximate.

## Current Limitations

- Retrieval is keyword-based, not semantic.
- There is no vector database yet.
- There is no backend integration yet in the active app path.
- There is no authentication or account system.
- There is no encryption layer implemented yet.
- Imported files become simple memory entries without chunking.
- The model can still phrase things poorly if the retrieved memory is too broad or ambiguous.
- The app is not ready for sensitive production use until encryption, export, backup, deletion, and audit behavior are designed.

## Future Pipeline

The intended evolution is incremental:

1. Improve archive data quality with better fields, tags, dates, and relationship metadata.
2. Add local embeddings and sqlite-vec for semantic retrieval.
3. Add chunking and citation-like source tracking.
4. Add a FastAPI backend for local services that should not live in the iOS app.
5. Add a memory ingestion pipeline for journals, markdown files, GitHub content, and structured notes.
6. Add evaluation tests for hallucination, grounding, and refusal behavior.
7. Add local encryption, backup, export, and deletion guarantees.
8. Add timeline views for life events.
9. Add relationship graph support.
10. Add personality and decision-modeling layers.
11. Add voice support only after the memory and privacy architecture is stable.
12. Add image understanding only when local models and explicit consent flows are ready.

## Backend Direction

The repository includes a `Backend` folder, but the active milestone is still iOS plus a local MLX server.

The planned backend stack is:

- Python
- FastAPI
- Local-only execution
- sqlite-vec initially
- PostgreSQL only if the data model outgrows SQLite
- Neo4j only in later graph-focused phases

The backend should eventually own heavier ingestion, embedding, retrieval, and indexing work while the iOS app remains the user-facing interface.

## Design Rules For Future Work

- SwiftUI views should talk to view models or services, not directly to networking.
- Business logic should stay out of views.
- Services should be protocol-oriented where substitution matters.
- The archive format should remain model-independent.
- Never add a feature that requires cloud access for core operation.
- Prefer local, inspectable data formats until there is a strong reason not to.
- Do not commit private memory data unless that is an explicit choice.

## Project Status

Genesis currently has a working local prototype:

- Native SwiftUI app.
- Local archive storage.
- Manual memory entry.
- Text/Markdown import.
- Bundled sample memory import.
- Local MLX connection tests.
- Model picker for supported Qwen models.
- Grounded prompt generation.
- Deterministic no-memory response.
- Source memory titles in chat responses.

The next good step is to improve memory ingestion from trusted sources, then replace keyword retrieval with local semantic retrieval.
