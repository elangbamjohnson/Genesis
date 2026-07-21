# Genesis iOS Client — Developer Onboarding Handout

Welcome to the **Genesis** project! This document serves as your complete guide to understanding, setting up, and contributing to the Genesis iOS client and its connected ecosystem.

Whether you are new to iOS development, FastAPI backends, or local AI model integration, this handout will explain everything step-by-step in clear, novice-friendly terms.

---

## 1. What is Genesis?

**Genesis** is a private, offline-first digital legacy application. Its long-term goal is to preserve a person's life memories, core values, reasoning patterns, personality, and communication style so that future generations can ask questions and receive authentic answers grounded in saved memories.

### Core Principles & Non-Negotiables
1. **Offline & Local First**: Genesis is designed around local execution on your own devices—not reliant on external cloud AI APIs.
2. **Privacy First**: The owner owns and controls all data.
3. **Zero Hallucination Guarantee**: Genesis is **not** a generic chatbot. It must **never** invent personal memories, dates, names, or events. If no relevant memory exists in the database, Genesis politely informs the user that no record was found.
4. **Clean Decoupled Architecture**: SwiftUI views only present UI; they never contain raw networking or business logic.

---

## 2. High-Level Architecture (The 3-Tier System)

Genesis consists of **three distinct components** working together locally:

```
┌────────────────────────────────────────────────────────┐
│                      iOS App                           │
│     (Native SwiftUI Client - Swift 5 / iOS 17+)        │
└───────────┬────────────────────────────────┬───────────┘
            │                                │
            │ REST HTTP Requests             │ Direct Fallback
            │ (Port 8090)                    │ (Port 8080)
            ▼                                ▼
┌─────────────────────────┐      ┌───────────────────────┐
│     Genesis Backend     │      │   Local MLX Server    │
│  (FastAPI Python Server)│─────►│  (mlx_lm.server Engine)│
│  Intent & Memory Search │ REST │  (Qwen2.5 14B LLM)    │
└─────────────────────────┘      └───────────────────────┘
```

1. **iOS Client (`Genesis / LegacyAI`)**: The user interface built with Apple's **SwiftUI**. Handles authentication, user input, chat UI, memory listing, settings, and secure session management.
2. **Genesis Backend (`genesis-backend`)**: A **FastAPI (Python)** web service. Manages memory retrieval, visitor/family authentication, conversation history, and hallucination guardrails.
3. **MLX Model Server (`mlx_lm.server`)**: A local server powered by Apple Silicon MLX framework running LLMs (e.g. `Qwen2.5-14B-Instruct`). It receives memory-contextualized prompts from the backend and generates the natural text reply.

---

## 3. Tech Stack Breakdown

| Layer | Technologies Used | Purpose |
| :--- | :--- | :--- |
| **iOS Frontend** | Swift 5, SwiftUI, `URLSession`, `Keychain`, `UserDefaults` | Native iOS UI, networking, secure storage |
| **Backend API** | Python 3.11+, FastAPI, Uvicorn, SQLite, Pydantic | API endpoints, intent resolution, memory CRUD, auth |
| **AI / Inference** | MLX (`mlx_lm.server`), HuggingFace (`Qwen2.5-14B-Instruct`) | Local LLM inference engine optimized for Apple Silicon |
| **Security** | iOS Keychain, Bearer Tokens, HMAC Signed Visitor Tokens | Token storage & request authentication |

---

## 4. Authentication & User Roles

Genesis supports **three distinct user roles**, each with appropriate access boundaries:

```
                 ┌──────────────────────────────────────┐
                 │        App Launch (EntryView)        │
                 └──────────────────┬───────────────────┘
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        ▼                           ▼                           ▼
┌──────────────┐            ┌──────────────┐            ┌──────────────┐
│  Owner Mode  │            │ Family Mode  │            │ Visitor Mode │
└──────┬───────┘            └──────┬───────┘            └──────┬───────┘
       │                           │                           │
 Full Access                 Authenticated Guest          Single-Session Read-Only
 (Chat, Archive,             (Read-Only Chat)             (Self-Register with Name)
 Settings)                   (Handle + Password)          
```

### Role Mapping to Swift Files & Methods

| Role | Swift View File | Swift Service Class & Method | Backend Endpoint |
| :--- | :--- | :--- | :--- |
| **Owner** | `LegacyAI/Views/EntryView.swift` | `SessionManager.loginAsOwner(token:backendBaseURL:)`<br>→ calls `BackendClient.validateOwnerToken(...)` | `GET /v1/auth/check` |
| **Family Member** | `LegacyAI/Views/EntryView.swift` | `SessionManager.loginAsFamily(handle:password:backendBaseURL:)`<br>→ calls `BackendClient.loginFamilyMember(...)` | `POST /v1/family/login` |
| **Visitor / Guest** | `LegacyAI/Views/EntryView.swift` | `SessionManager.registerAsVisitor(name:backendBaseURL:)`<br>→ calls `BackendClient.selfRegisterVisitor(...)` | `POST /v1/visitors/self-register` |

### How Sessions are Secured & Handled in Code
- **Keychain Storage**: Sessions are represented by `StoredSession` structs (`LegacyAI/Services/SessionManager.swift`) stored securely in iOS **Keychain** using `saveToKeychain(_:)`—never in `UserDefaults`.
- **Fail-Closed Logout & Expired Sessions**: If Keychain read fails or if any network call returns HTTP `401 Unauthorized`, `SessionManager.handleUnauthorized(chatStore:)` is triggered:
  1. Calls `deleteFromKeychain()` to drop the token.
  2. Calls `chatStore.clear()` (`LegacyAI/Services/ChatStore.swift`) to erase in-memory thread history so no messages leak between sessions.
  3. Resets `currentSession = nil`, which forces `ContentView.swift` to route back to `EntryView.swift`.

---

## 5. How Communication & AI Interaction Works (Step-by-Step)

Here is the exact journey of a question, detailing the responsible Swift file, class/struct, and method name at every stage:

```text
[User types question in SwiftUI] 
             │
             ▼
1. ChatView.swift (or VisitorChatView.swift) triggers send() async method
             │
             ▼
2. ChatStore.swift -> ChatStore.historyForAPI() fetches last 8 turns (4 back-and-forth exchanges)
             │
             ▼
3. ChatStore.swift -> ChatStore.appendUserMessage(question) saves user question to history
             │
             ▼
4. BackendClient.swift -> BackendClient.sendChat(question:history:baseURL:authToken:) sends POST /v1/chat
             │
             ▼
5. Genesis FastAPI Backend validates Bearer token & performs Memory Search
             │
     ┌───────┴──────────────────────────────┐
     │ Found matching memories?             │
     └───────┬──────────────────────┬───────┘
            YES                     NO
             │                      │
             ▼                      ▼
6a. Backend formats system prompt    6b. Backend returns default refusal message immediately
    & sends request to MLX Server        (No LLM call -> NO HALLUCINATION GUARANTEE)
    (http://127.0.0.1:8080)              │
             │                      │
             ▼                      │
7. MLX Server generates LLM reply        │
             │                      │
             └───────────┬──────────┘
                         ▼
8. Backend returns ChatReply JSON: { "answer": "...", "source_titles": ["First Date"] }
                         │
                         ▼
9. ChatStore.swift -> ChatStore.appendAssistantMessage(reply.answer, sourceTitles: reply.sourceTitles)
   saves reply and updates SwiftUI view with typewriter animation
```

### Detailed Step-by-Step Method Breakdown

1. **User Action & Input Handling**:
   - **File**: `LegacyAI/Views/ChatView.swift` (Owner) or `LegacyAI/Views/VisitorChatView.swift` (Visitor/Family)
   - **Method**: `triggerSend()` → `send() async`
   - **Description**: Captures user input string from `@State private var draft`.

2. **Fetching Conversation History for Context**:
   - **File**: `LegacyAI/Services/ChatStore.swift`
   - **Class**: `@MainActor final class ChatStore: ObservableObject`
   - **Method**: `func historyForAPI() -> [BackendClient.ChatTurn]`
   - **Description**: Filters prior user/assistant messages and extracts up to `maxHistoryTurns = 8` turns formatted as `[BackendClient.ChatTurn]` to send as context.

3. **Appending User Message**:
   - **File**: `LegacyAI/Services/ChatStore.swift`
   - **Method**: `func appendUserMessage(_ content: String)`
   - **Description**: Creates `ChatMessage(role: .user, content: content)` and saves to `UserDefaults`.

4. **Executing Network HTTP Request**:
   - **File**: `LegacyAI/Services/BackendClient.swift`
   - **Struct**: `struct BackendClient`
   - **Method**: `func sendChat(question: String, history: [ChatTurn], baseURL: String, authToken: String) async throws -> ChatReply`
   - **Description**: Constructs `URLRequest` for `POST /v1/chat`, adds `Authorization: Bearer <authToken>`, encodes JSON payload, and calls `URLSession.shared.data(for:)`.

5. **Receiving & Appending Assistant Response**:
   - **File**: `LegacyAI/Services/ChatStore.swift`
   - **Method**: `func appendAssistantMessage(_ content: String, sourceTitles: [String])`
   - **Description**: Decodes `BackendClient.ChatReply`, appends assistant message with `sourceEntryTitles`, and publishes changes to trigger SwiftUI UI update.

6. **Error Handling & Unauthorized Session Reset**:
   - **File**: `LegacyAI/Services/SessionManager.swift`
   - **Method**: `func handleUnauthorized(chatStore: ChatStore)`
   - **Description**: Catches `BackendClient.ClientError.unauthorized` (HTTP 401/403), deletes Keychain session, calls `chatStore.clear()`, and returns user to `EntryView`.

---

## 6. iOS Codebase Structure & Key Services

All active iOS source code lives inside the `LegacyAI` directory:

```text
LegacyAI
├── Models
│   ├── LifeEntry.swift        # Struct: Memory entry (id, category, title, content, date, tags)
│   └── ChatMessage.swift      # Struct: Chat message (id, role, content, sourceEntryTitles)
├── Services
│   ├── SessionManager.swift   # Class: SessionManager (Keychain auth & role management)
│   ├── BackendClient.swift    # Struct: BackendClient (HTTP REST calls to FastAPI /v1 endpoints)
│   ├── ChatStore.swift        # Class: ChatStore (Manages conversation thread history & max 8 turns)
│   ├── ArchiveStore.swift     # Class: ArchiveStore (Manages memory archive entries & local JSON caching)
│   ├── MLXChatService.swift   # Class: MLXChatService (Direct local MLX server fallback connection)
│   ├── RetrievalEngine.swift  # Struct: RetrievalEngine (Local keyword retrieval fallback engine)
│   ├── PersonaPromptBuilder.swift # Struct: PersonaPromptBuilder (Local LLM prompt builder)
│   └── AppSettings.swift      # Class: AppSettings (UserDefaults manager for URLs & active model)
└── Views
    ├── EntryView.swift        # View: Entry screen gateway (Owner Token, Family Login, Guest Register)
    ├── ContentView.swift      # View: Root router (Routes between EntryView, Owner Tabs, VisitorChatView)
    ├── ChatView.swift         # View: Owner chat view with backend connection & source citations
    ├── VisitorChatView.swift  # View: Guest/Family read-only chat view with typewriter animation
    ├── EntryListView.swift    # View: Archive view for searching and browsing saved memories
    ├── AddEntryView.swift     # View: Form view to add a new memory manually
    ├── ImportEntriesView.swift# View: File importer view to bulk-upload .txt/.md memories
    └── SettingsView.swift     # View: Settings tab (Server URLs, connection test, local model picker)
```

---

## 7. How to Setup and Run Locally

To run and test the complete Genesis experience on your development machine:

### Step 1: Start the Local MLX AI Model Server
Open a terminal and launch the MLX model server (requires Apple Silicon Mac):
```bash
mlx_lm.server --host 0.0.0.0 --port 8080 --model ~/.cache/huggingface/mlx-qwen25-14b-instruct
```

### Step 2: Start the Genesis FastAPI Backend
Open a second terminal, navigate to the backend repo, and start Uvicorn:
```bash
cd genesis-backend
uvicorn app.main:app --host 0.0.0.0 --port 8090 --reload
```

### Step 3: Configure and Launch the iOS App in Xcode
1. Open `Genesis.xcodeproj` in Xcode.
2. Select your target (iOS Simulator or Physical iPhone) and press **Cmd + R** to run.

> [!IMPORTANT]
> **Networking Tip (Simulator vs Physical iPhone)**
> - **iOS Simulator**: Use `http://127.0.0.1:8090` for backend and `http://127.0.0.1:8080` for MLX server.
> - **Physical iPhone**: You **cannot** use `127.0.0.1` or `localhost`. Run `ipconfig getifaddr en0` in your Mac terminal to get your LAN IP (e.g., `http://192.168.1.50:8090`). Both your Mac and iPhone must be on the same Wi-Fi network.

### Step 4: Verify Connection in App Settings
1. Go to the **Settings** tab in the app.
2. Enter your Backend URL (`http://127.0.0.1:8090`) and MLX Server URL (`http://127.0.0.1:8080`).
3. Tap **Test Connection** for both to ensure green status indicators.

---

## 8. Coding Guidelines for New Contributors

As you start contributing code to Genesis, please follow these principles:

1. **Separation of Concerns**: Keep SwiftUI views clean! Views should only render UI and call functions on `SessionManager`, `BackendClient`, or `ChatStore`. Do not write raw `URLSession` calls or data manipulation inside SwiftUI view files.
2. **Never Bypass Guardrails**: Grounding is Genesis's defining feature. Never write code that allows the LLM to generate unstructured responses without memory grounding.
3. **Handle Errors Gracefully**: Always handle network failures or auth errors (`401`) cleanly using `ClientError` and `SessionManager.handleUnauthorized()`.
4. **Offline First Mindset**: The backend is the source of truth, but the iOS app maintains local fallback capabilities (`ArchiveStore` / `RetrievalEngine`) so basic functionality works offline.

---

## Next Steps & Future Roadmap
- **Semantic Vector Search**: Transitioning from keyword search to local embedding vector search (`sqlite-vec`).
- **Enhanced Citations**: Showing inline memory snippets alongside source titles.
- **Timeline & Relationship Graph**: Visualizing life events chronologically.

Welcome aboard, and happy coding! 🚀
