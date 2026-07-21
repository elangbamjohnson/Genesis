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
                 ┌──────────────────────────────┐
                 │     App Launch (EntryView)   │
                 └──────────────┬───────────────┘
                                │
        ┌───────────────────────┼───────────────────────┐
        ▼                       ▼                       ▼
┌──────────────┐        ┌──────────────┐        ┌──────────────┐
│  Owner Mode  │        │ Family Mode  │        │ Visitor Mode │
└──────┬───────┘        └──────┬───────┘        └──────┬───────┘
       │                       │                       │
 Full Access             Authenticated Guest      Single-Session Read-Only
 (Chat, Archive,         (Read-Only Chat)         (Self-Register with Name)
 Settings)               (Handle + Password)      
```

1. **Owner Mode (Full Access)**:
   - Authenticated using `GENESIS_AUTHOR_TOKEN`.
   - Has access to **Chat**, **Archive** (Create/Edit/Delete/Import memories), and **Settings**.
2. **Family Member Mode**:
   - Log in with handle & password registered by the owner on the backend (`POST /v1/family/login`).
   - Authenticated guest experience with persistent identity stored in Keychain.
3. **Visitor / Guest Mode**:
   - Self-registers by entering their name (`POST /v1/visitors/self-register`).
   - Backend returns a signed visitor token.
   - Sees a read-only chat screen (`VisitorChatView`) with a "Leave" button to clear the session.

### How Sessions are Secured
- **Keychain Storage**: Authentication tokens are stored in the iOS **Keychain** via `SessionManager.swift`—never in `UserDefaults`.
- **Fail-Closed Security**: If Keychain cannot be read or if the backend returns HTTP `401 Unauthorized`, `SessionManager.handleUnauthorized()` immediately clears the session and returns the user to the login/entry screen.

---

## 5. How Communication & AI Interaction Works (Step-by-Step)

Here is the exact journey of a question when a user types a message into the chat:

```text
[User types question in SwiftUI] 
             │
             ▼
1. ChatStore fetches last 8 turns (4 back-and-forth exchanges) for context
             │
             ▼
2. BackendClient sends POST /v1/chat (Authorization: Bearer <token>) to Genesis Backend
             │
             ▼
3. Genesis Backend checks user token and performs Memory Retrieval
             │
     ┌───────┴──────────────────────────────┐
     │ Found matching memories?             │
     └───────┬──────────────────────┬───────┘
            YES                     NO
             │                      │
             ▼                      ▼
4a. Format prompt with memory   4b. Return default refusal message immediately!
    context & send to MLX           (No LLM call -> NO HALLUCINATION)
    Server (Port 8080)              │
             │                      │
             ▼                      │
5. MLX Server generates reply       │
             │                      │
             └───────────┬──────────┘
                         ▼
6. Backend returns JSON { "answer": "...", "source_titles": ["First Date"] }
                         │
                         ▼
7. iOS App receives JSON and renders response + citations in ChatView
```

### Key Takeaway for the AI Model Interaction
The iOS app **does not** send the raw user question directly to the AI model. Instead:
- The backend acts as a **smart mediator**.
- The backend searches for relevant memory entries.
- If memories are found, the backend constructs a **grounded system prompt** instructing the LLM to speak in first person using *only* those memories.
- If no memories match, the backend halts the flow immediately and returns a friendly refusal message, completely avoiding AI hallucinations!

---

## 6. iOS Codebase Structure & Key Services

All active iOS source code lives inside the `LegacyAI` directory:

```text
LegacyAI
├── Models
│   ├── LifeEntry.swift        # Memory data structure (category, content, tags)
│   └── ChatMessage.swift      # Chat message object (role, content, source_titles)
├── Services
│   ├── SessionManager.swift   # Single source of truth for Keychain auth sessions
│   ├── BackendClient.swift    # Network service for FastAPI endpoints (/v1/chat, /v1/memories)
│   ├── ChatStore.swift        # Handles chat history array & UserDefaults persistence
│   ├── ArchiveStore.swift     # Manages memory archive entries & local JSON caching
│   ├── MLXChatService.swift   # direct local MLX server connection (offline fallback)
│   ├── RetrievalEngine.swift  # Local keyword retrieval engine (offline fallback)
│   ├── PersonaPromptBuilder.swift # Builds LLM prompts (offline fallback)
│   └── AppSettings.swift      # Stores backend URL, MLX URL, model name in UserDefaults
└── Views
    ├── EntryView.swift        # Login & onboarding gateway screen
    ├── ContentView.swift      # Main router (routes between Entry, Owner Tabs, Visitor Chat)
    ├── ChatView.swift         # Owner interactive chat view
    ├── VisitorChatView.swift  # Guest/Family read-only chat view with leave action
    ├── EntryListView.swift    # Archive view for browsing saved memories
    ├── AddEntryView.swift     # Screen to create a new memory
    ├── ImportEntriesView.swift# Screen for bulk importing memory text files
    └── SettingsView.swift     # Configuration screen (URLs, connection tests, model picker)
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
