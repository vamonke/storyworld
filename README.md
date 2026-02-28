# StoryWorld

Voice-controlled AR film director for iOS. Speak characters into existence, place them in augmented reality, walk around them as a cinematographer, capture shots, and generate a cinematic clip — all without typing.

Built for the OpenAI Hackathon, Multi-Modal Intelligence track.

---

## Demo Flow

1. **Describe** — Speak a hero and villain into existence (e.g. *"dark soldier in obsidian armor"*, *"fire demon with molten skin"*)
2. **Describe the world** — Speak an environment (e.g. *"volcanic crater at dusk, ember storm"*)
3. **Wait (background)** — 3D models and 360° skybox generate in parallel while the camera stays live
4. **Place** — Tap to anchor characters in AR space
5. **Frame shots** — Walk around physically, tap shot type buttons (Wide, Close Up, OTS, etc.)
6. **Generate** — Tap "Generate Film" → Kling 3.0 renders a 15-second 4K clip
7. **Watch** — The film plays. The audience sees themselves in a scene.

---

## Architecture

All generation is non-blocking. The camera is always live. No loading screens.

```
Voice → Whisper STT → GPT-5 intent parsing → fal.ai APIs
                                                ├── Hyper3D Rodin v2 → USDZ character
                                                ├── Blockade Labs Skybox AI → 360° environment
                                                └── Kling 3.0 Omni → 4K video clip

AR rendering: ARKit + RealityKit (USDZ ModelEntity + equirectangular sky sphere)
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full layer diagram and file map.

---

## State Machine

The app advances through `ProductionPhase` automatically as background jobs complete:

```
idle → generatingWorld → placingWorld → generatingCharacter
     → placingCharacters → takingShots → generatingClip → reviewingClip
```

Phase transitions are triggered by asset readiness, not user taps.

---

## API Stack

| Layer | Service |
|---|---|
| Speech-to-text | OpenAI Whisper |
| Prompt expansion | GPT-5 |
| 3D character generation | Hyper3D Rodin v2 via fal.ai |
| 360° environment | Blockade Labs Skybox AI |
| Video generation | Kling 3.0 Omni via fal.ai |
| AR rendering | ARKit + RealityKit (iOS native) |

---

## Setup

1. Clone the repo and open `storyworld.xcodeproj` in Xcode
2. Set your API keys in `Config.swift`:
   - `FAL_API_KEY` — [fal.ai](https://fal.ai)
   - `OPENAI_API_KEY` — [platform.openai.com](https://platform.openai.com)
   - `BLOCKADE_LABS_API_KEY` — [skybox.blockadelabs.com](https://skybox.blockadelabs.com)
3. Build and run on a physical iOS device (ARKit requires hardware)

---

## Requirements

- iOS 17+
- Physical iPhone or iPad with LiDAR recommended
- Xcode 15+

---

## Hackathon Scope

- 2 characters max (hero + villain slots)
- 3–6 shots for a 15-second clip
- Buttons only — voice layer is post-hackathon
- Pre-caching characters before demo is encouraged for reliability

See [requirements.md](requirements.md) for full product requirements and [ar-film-director-requirements.md](ar-film-director-requirements.md) for the detailed spec.
