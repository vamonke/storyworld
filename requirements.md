# OpenAI Hackathon — AI Film Director
**Track:** Multi-Modal Intelligence  
**Concept:** Voice-controlled AR film director that places AI characters in physical space, calls shots, and generates a cinematic clip in real-time on stage.

---

## Core Demo Flow

1. **Capture** — Take photos of 2 real people (judges, teammates, audience)
2. **Stylize** — Convert photos into 3D characters
3. **Place** — Anchor characters in AR on stage using mobile camera
4. **Edit** — Use voice to adjust the 3D character in real-time (change pose, facial expression, outfit, mood) before shooting begins
5. **Direct** — Walk around characters, take different shots (over-the-shoulder, wide, close-up)
6. **Generate** — Pass 3 reference frames + scene prompt → single continuous video clip
7. **Reveal** — Play the clip. Audience sees themselves in a film.

---

## Modalities Used

| Modality | Role |
|---|---|
| **Voice** | Primary input — all direction, scene prompts, character changes |
| **Camera** | AR anchor, spatial navigation, shot framing |
| **Image** | Character reference capture → stylization → frame extraction |
| **Video** | Final output — multi-frame scene generation |
| **Text** | Scene prompt passed to video model (e.g. "Marriage Story, kitchen argument, she's leaving") |

---

## Technical Requirements

### Voice → Text
- Low latency STT (target < 1s)
- Options: OpenAI Whisper, Whisper live streaming

### Image Stylization
- Input: real photo of person
- Output: Pixar/animated style character reference
- Options: FLUX with style LoRA, fal.ai image-to-image

### AR Placement
- Anchor 3D character to physical location in space
- User can walk around it (front, back, left, right)
- Options: ARKit (iOS), WebXR
- Characters can be pre-cached 3D models or stylized image planes

### Shot Direction
- Human-directed — user physically walks around the AR character to frame shots
- Over-the-shoulder, wide shot, close-up, combined shot
- Tap an on-screen button to capture each frame/shot

### Video Generation
- Input: 3 reference frames (shot 1, shot 2, shot 3) + dramatic scene prompt
- Output: single continuous video clip (no stitching)
- Target duration: 4 seconds per shot or ~12s combined
- Options: Kling multi-shot, multi-frame reference models (research latest)

### Caching Strategy
- Pre-generate 3D character assets during hackathon for demo reliability
- Pre-stylize reference images of judges/organizers before presentation
- Live generation available but cached path is primary demo path

---

## Stack (Proposed)

| Layer | Tool |
|---|---|
| Mobile app | Swift / React Native / Expo |
| AR | ARKit or WebXR |
| STT | OpenAI Whisper |
| Image stylization | fal.ai (FLUX / img2img) |
| 3D generation | TRELLIS 2 / Meshy-6 via fal.ai |
| Video generation | Kling multi-shot or equivalent multi-frame model |
| Orchestration | Mastra or simple API chaining |
| LLM (intent parsing) | GPT-4o (voice command → structured action) |

---

## Anchor Demo Moment

> You take a photo of a hackathon judge. Their Pixar-style character appears in AR on stage. You walk around them, call out three shots with your voice. You say *"generate — Marriage Story, kitchen argument, she just found out."* 30 seconds later, a cinematic clip plays. The judge sees themselves in a film.

---

## Scope Constraints

- **Must work on mobile** (iOS preferred)
- **Voice-only input** — no typing during demo
- **2 characters max** for demo reliability
- **3 scenes / shots** — enough for narrative, not too many to generate
- **Pixar/stylized** — avoids uncanny valley with real faces, artifacts are charming not creepy
- **Caching is fair game** — pre-load characters and stylized references before presenting

---

## Nice to Have (Post-Hackathon)

- Live 3D generation from voice prompt (no cache)
- Character lip-sync + voice response
- Audience member can submit their own photo live
- Export final clip directly to phone