# LegacyAI Phase 1

LegacyAI is a private, offline-first digital legacy app. Phase 1 proves the simplest loop: real memories in, honestly grounded first-person answers out.

## Create The Xcode Project

1. Create a new iOS App project in Xcode.
2. Use SwiftUI for the interface.
3. Use Swift for the language.
4. Set the deployment target to iOS 16 or later.
5. Add the `LegacyAI` folder to the app target.

This repository already wires the generated files into the existing `Genesis.xcodeproj`.

## Files

- `LegacyAI/Models`: Codable memory and chat message models.
- `LegacyAI/Services`: JSON archive storage, keyword retrieval, prompt building, local MLX chat client, and settings.
- `LegacyAI/Views`: Chat, archive, import, add-memory, and settings screens.
- `LegacyAI/Resources/sample_entries.json`: Seed memories copied into the archive on first launch.
- `LegacyAI/Info.plist`: Local-network and local-HTTP permissions.

## Info.plist

The app needs local networking for a local MLX server. Use:

- `NSLocalNetworkUsageDescription`
- `NSAppTransportSecurity` with `NSAllowsLocalNetworking = YES`

Do not enable blanket arbitrary loads.

## Local Model Server

Run your OpenAI-compatible MLX server on the Mac. Genesis currently supports these chat models:

| Model | Use case | App model value |
| --- | --- | --- |
| Qwen2.5 14B Instruct | Default conversational legacy answers | `/Users/johnsonelangbam/.cache/huggingface/mlx-qwen25-14b-instruct` |
| Qwen2.5 Coder 14B Instruct | Programming and technical explanations | `mlx-community/Qwen2.5-Coder-14B-Instruct-4bit` |

For the default local Instruct model:

```bash
mlx_lm.server --host 0.0.0.0 --port 8080 --model ~/.cache/huggingface/mlx-qwen25-14b-instruct
```

For the Coder model:

```bash
mlx_lm.server --host 0.0.0.0 --port 8080 --model mlx-community/Qwen2.5-Coder-14B-Instruct-4bit
```

Select the same model in the app Settings screen. The app can only talk to the model currently loaded by the MLX server. The app stores the expanded absolute path for local folders because `~` is only expanded by your shell.

The iPhone and Mac must be on the same Wi-Fi network.

Find the Mac LAN IP:

```bash
ipconfig getifaddr en0
```

Then set the app server address to:

```text
http://<mac-lan-ip>:8080
```

Do not use `127.0.0.1` or `localhost` on a physical iPhone. Those addresses point to the phone itself. They only work from the iOS Simulator.

## Deferred

Phase 1 intentionally does not include semantic embeddings, access control, fine-tuning, voice cloning, cloud sync, authentication, or image understanding.
