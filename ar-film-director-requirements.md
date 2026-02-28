# AR Film Director — Product Requirements

**Project:** OpenAI Hackathon — Multi-Modal Intelligence Track  
**Target:** iOS mobile demo, live on-stage presentation  
**Date:** February 2026

---

## 1. Vision

A voice-controlled AR film production tool. One person, one phone, can generate a cinematic fantasy battle from nothing — characters summoned by voice, placed in AR space, manually framed into shots, then rendered into a 4K film with orchestral audio.

**The demo sentence:** *"I described two characters out loud, walked around them in AR, framed 6 shots like a cinematographer, and a 15-second film appeared."*

---

## 2. Core User Flow

```
1. Speak a character description → 3D model generates in background
2. Speak an environment description → 360° skybox generates in background
3. Assets arrive silently → tap to place in AR space
4. Walk around physically, tap shot type buttons to capture frames
5. Tap "Generate Film" → Kling 3.0 renders multi-shot clip in background
6. Film plays — 15 seconds, 4K, with orchestral audio
```

All generation happens **non-blocking**. The camera stays live at all times. The user is never waiting at a loading screen.

---

## 3. ProductionPhase State Machine

The app is always in exactly one `ProductionPhase`. Transitions are **automatic** — triggered by background job completions, not manual taps.

| Phase | Description | Triggers next phase when... |
|---|---|---|
| `idle` | Home screen, nothing active | User submits prompts |
| `generatingWorld` | Skybox API call in flight | Panorama URL returned |
| `placingWorld` | Env ready, awaiting characters | A character becomes ready |
| `generatingCharacter` | ≥1 Rodin job in flight | Either character USDZ ready |
| `placingCharacters` | Models ready, user placing in AR | ≥1 character placed + env ready |
| `takingShots` | Characters in AR space, camera active | User triggers clip generation |
| `generatingClip` | Kling 3.0 job in flight | Video URL returned |
| `reviewingClip` | Clip ready for playback | User resets or goes back to shots |

### Phase rules
- **Mood never blocks generation.** `ProductionPhase` is a UI concern only. Background jobs (`GenerationStatus`) run regardless of current phase.
- **Both characters generate in parallel.** Villain generation does not wait for hero to complete.
- **Clip generation is non-blocking.** User can continue capturing shots while clip renders. Additional shots captured during render can be used for a second clip.
- **Auto-advance only.** There are no manual "next phase" buttons. The app advances when assets are ready.

---

## 4. Session State

```
FilmSession
├── phase: ProductionPhase
├── hero: ARCharacter?          (slot: .hero)
├── villain: ARCharacter?       (slot: .villain)
├── environment: AREnvironment?
├── shots: [ARShot]             (ordered, max ~10 for hackathon)
└── clips: [ARClip]             (can accumulate multiple)
```

### Character
```
ARCharacter
├── id, slot (.hero | .villain)
├── name, voicePrompt, generationPrompt
├── status: idle → queued → generating → ready → placed
├── modelURL: URL?          (local USDZ path)
├── anchorIdentifier: UUID? (AR world anchor)
└── rodinJobId: String?     (for polling)
```

### Environment
```
AREnvironment
├── voicePrompt, generationPrompt
├── status: GenerationStatus
├── panoramaURL: URL?       (8K equirectangular from Blockade Labs)
└── skyboxJobId: String?
```

### Shot
```
ARShot
├── id, index
├── frameImageData: Data    (PNG of AR screenshot)
├── cameraAngle: CameraAngle
├── klingPrompt: String     (GPT-5 expanded per-shot prompt)
├── duration: Double        (seconds for this shot in final clip)
└── characterSlots: [CharacterSlot]
```

### Clip
```
ARClip
├── id, shotIds: [UUID]
├── status: GenerationStatus
├── videoURL: URL?
├── cinematicStyle: CinematicStyle
├── audioPrompt: String
└── generatedAt: Date?
```

---

## 5. Characters

**Hard limit: 2 characters for hackathon demo.**

| Slot | Role | Example prompt |
|---|---|---|
| `.hero` | Warrior, protagonist | "dark soldier in obsidian armor, glowing red runes" |
| `.villain` | Monster, antagonist | "fire demon with molten skin and curved horns" |

Characters are referred to by slot internally. Names are extracted from voice prompts by GPT-5.

---

## 6. Camera Angles / Shot Types

7 predefined shot types, each maps to a button in `takingShots` phase:

| Shot Type | Button Label | Default Duration |
|---|---|---|
| `wideEstablishing` | Wide | 3.0s |
| `mediumTwoShot` | Two Shot | 2.5s |
| `mediumSingle` | Medium | 2.5s |
| `closeUpFace` | Close Up | 2.0s |
| `overTheShoulder` | OTS | 2.5s |
| `lowAngleHeroic` | Low Angle | 2.5s |
| `insertDetail` | Insert | 1.5s |

Minimum 3 shots required to unlock "Generate Film". Recommended 6 shots for a full 15-second clip.

---

## 7. API Stack

| Layer | Service | Endpoint | Notes |
|---|---|---|---|
| Voice → Text | OpenAI Whisper | `/v1/audio/transcriptions` | <1s latency |
| Prompt expansion | GPT-5 | `/v1/chat/completions` | Expands raw voice into structured 3D/video prompts |
| 3D generation | Hyper3D Rodin v2 | `fal-ai/hyper3d/rodin/v2` via fal.ai | USDZ native output, multi-image, PBR |
| 360° environment | Blockade Labs Skybox AI | `POST /api/v1/skybox` | Model 3, Fantasy Landscape style, 8K |
| AR rendering | ARKit + RealityKit | iOS native | USDZ → `ModelEntity`, equirectangular → `SKySphere` |
| Video generation | Kling 3.0 Omni | `fal-ai/kling-video/v3` | Multi-shot storyboard, 15s, 4K, native audio |

### Generation timing (approximate)
- Skybox: ~20–30 seconds
- 3D character (Rodin v2): ~60–90 seconds per model, both run in parallel
- Kling 3.0 clip (15s, 4K): ~3–5 minutes
- Total blocking time for user: **zero** (all async)

---

## 8. Background Generation Architecture

All API calls fire non-blocking via Swift `async/await` tasks. Polling is every 5 seconds.

```
User taps button
  → dispatch(action) called immediately
  → Task { await api.call() } fires in background
  → UI returns to AR camera immediately
  → On completion: dispatch(completionAction) on MainActor
  → autoAdvancePhase() runs
  → Notification toast appears ("⚔️ Soldier ready — tap to place")
```

Asset status lifecycle: `idle → queued → generating → ready → placed`

Phase and asset status are independent. A clip can be `generating` while phase is `takingShots`.

---

## 9. UI / HUD Requirements

### Always visible
- Phase badge (top center) — current `ProductionPhase` with breathing dot when generating
- Asset status row — `World`, `Soldier`, `Monster` badges showing `GenerationStatus` color

### Phase-specific panels (bottom sheet)
- **idle** — text fields for env/hero/villain prompts + "SUMMON ALL" button
- **generatingWorld / generatingCharacter** — progress indicator, subtext "keep exploring"
- **placingCharacters** — "PLACE SOLDIER" / "PLACE MONSTER" buttons, "START SHOOTING" CTA
- **takingShots** — 6 shot type buttons in 2×3 grid, "GENERATE FILM" appears after shot 3
- **generatingClip** — minimal indicator, user stays in AR
- **reviewingClip** — PLAY / MORE SHOTS / RESET

### Shot strip
- Horizontal scrollable thumbnail row visible during `takingShots`, `generatingClip`, `reviewingClip`
- Shows shot index + camera angle icon
- Tap × to delete a shot

### Notifications
- Toast-style, slide in from top, auto-dismiss after 4 seconds
- Key moments: env ready, each character ready, clip ready

### Design constraints
- **Camera always fills full screen** — no UI element obscures the AR view except translucent overlays
- All panels: dark glass (`black 65% opacity`), monospaced typography, minimal chrome
- No loading screens — the camera is always the primary content

---

## 10. The Demo Clip

**Scene:** Fantasy warrior vs monster — "The Confrontation"

**6-shot sequence:**
1. Wide establishing — both characters, environment visible, slow push in
2. Medium two-shot — standoff tension, between the characters
3. Low angle on hero — soldier looming, heroic
4. Monster close-up — face/horns, menacing
5. Over-the-shoulder — from soldier's back, monster facing camera
6. Wide pull — both in frame, environment, the moment before battle

**Kling 3.0 prompt structure:**
```
Shot 1 (0-3s): Wide establishing, [soldier] and [monster] face off in [env], slow push in
Shot 2 (3-5.5s): Medium two-shot, tension, [env] background
Shot 3 (5.5-8s): Low angle heroic on [soldier], looming, powerful
Shot 4 (8-10s): Close-up [monster] face, embers floating, intense
Shot 5 (10-12.5s): Over-shoulder from [soldier] toward [monster]
Shot 6 (12.5-15s): Wide pull-back, lightning, epic scale

Audio: [cinematicStyle.audioPrompt]
Resolution: 4K, 60fps
```

---

## 11. Agent-Ready Architecture

All user actions are dispatched through a single `dispatch(_ action: DirectorAction)` function. **Buttons currently call this function. An AI agent will call the same function via tool calls — zero refactoring required.**

### Agent tool definitions (future)

```json
[
  {
    "name": "set_environment",
    "parameters": { "prompt": "string" }
  },
  {
    "name": "generate_hero",
    "parameters": { "prompt": "string" }
  },
  {
    "name": "generate_villain",
    "parameters": { "prompt": "string" }
  },
  {
    "name": "capture_shot",
    "parameters": { "angle": "CameraAngle", "description": "string" }
  },
  {
    "name": "generate_clip",
    "parameters": { "shot_ids": ["uuid"], "style": "CinematicStyle" }
  },
  {
    "name": "get_session_state",
    "parameters": {}
  }
]
```

`get_session_state` returns the full `FilmSession` as JSON — the agent reads current phase, character statuses, shot count, and decides what to do next.

---

## 12. Out of Scope (Hackathon)

- Voice input (buttons only for hackathon — voice layer added post-demo)
- More than 2 characters
- Manual phase transitions (auto-advance only)
- Clip editing / timeline scrubbing
- Social sharing / export
- Android / web support
- Saving/restoring sessions

---

## 13. Files

| File | Description |
|---|---|
| `FilmDirectorState.swift` | Full state machine — models, actions, store, services |
| `DirectorView.swift` | SwiftUI HUD — all phase panels, shot strip, notifications |
| `ar-film-director-requirements.md` | This document |
| `ar-film-director-state-machine.md` | Original state machine design spec |
