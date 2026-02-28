# StoryWorld — Hackathon Demo Script

**Track:** Multi-Modal Intelligence | **Time:** ~5 minutes

---

## OPENING (30 seconds) — The Hook

> "Hollywood spent $200 million making one battle scene in Lord of the Rings.
> A decade ago, that dropped to $50 million with better tools.
> Today — with AI — we can do it with **one iPhone**."

> "My name is [NAME]. This is **StoryWorld** — a voice-controlled AR film director.
> I'm going to describe two characters out loud, place them in this room,
> walk around them, call my shots, and in a few minutes — a cinematic clip plays.
> No crew. No studio. No typing."

---

## ACT 1 — Summon the World (45 seconds)

> "Every film starts with a world. I'll describe mine."

**[Tap mic / voice button]**

> *"Volcanic crater at dusk. Ember storm in the background. Red sky."*

> "That's my environment — it's generating a 360° skybox in the background right now.
> I don't wait. The camera stays live."

**[Tap mic / voice button]**

> *"Hero: a dark soldier in obsidian armor with glowing red runes carved into the chest."*

**[Tap mic / voice button]**

> *"Villain: a fire demon with molten skin, curved horns, and wings made of ash."*

> "Three API calls — AI is now generating a 3D environment and two 3D characters, all in parallel.
> Meanwhile — the camera is live. I'm already on set."

---

## ACT 2 — Place & Direct (90 seconds)

*(While generation is completing in background, explain the AR layer)*

> "When the assets are ready, the app tells me silently — no loading screens, no spinners.
> I tap to plant my characters in AR space. Right here on this floor."

**[Tap to place Soldier. Tap to place Demon. They anchor into the real room.]**

> "Now here's the part I love most — **I am the camera.**"

> "This isn't a timeline editor. This isn't a prompt box.
> I physically walk around my characters and frame every shot, like a cinematographer."

**[Walk to get a wide establishing shot]**

> "Wide establishing shot — I can see both characters in the scene."

**[Tap "Wide" button → shot captured. Shown in the strip at the bottom.]**

**[Walk around to get over-the-shoulder]**

> "Now an over-the-shoulder — I'm literally standing behind the soldier, looking at the demon."

**[Tap "OTS" button → shot 2 captured.]**

**[Crouch/step in close to the demon's face]**

> "Close up on the villain. The scale slider on the right lets me resize them
> so they tower over me — or shrink to fit the space."

**[Tap "Close Up" → shot 3 captured.]**

> "Three shots. That's enough to unlock the generate button.
> But let me grab a couple more — a low angle heroic shot, and a two-shot for the climax."

**[2 more shots captured. 5 shots in the strip.]**

---

## ACT 3 — Generate the Film (30 seconds)

> "Five shots. Framed by me, in this room, with this phone."

> "Now I hand it to Kling 3.0."

**[Tap "Generate Film"]**

> "That sends my shot frames and a GPT-5-expanded cinematic prompt to Kling's video model.
> It'll come back as a 15-second, 4K clip — multi-shot, continuous, with native audio.
> That render takes a few minutes, so for the demo..."

*(If using cached clip)*

> "...I've pre-rendered the clip so we can see the result right now."

---

## ACT 4 — The Reveal (30 seconds)

**[Tap Play. Full-screen cinematic clip plays.]**

*(Let it play in silence. Let the audience watch.)*

> "That was shot on an iPhone 15 Pro. No green screen. No crew.
> The characters are AI-generated 3D models placed in augmented reality.
> The camera work is mine — I walked those angles myself."

---

## CLOSE — The Vision (45 seconds)

> "Right now, the gatekeepers of visual storytelling are budgets and production pipelines.
> We believe anyone should be able to make a sci-fi epic, a fantasy battle, or an anime live-action film
> — with the phone in their pocket."

> "The modalities here are real and novel:
> **Voice** summons the world. **Your body** is the camera rig.
> **AI** renders what you envisioned."

> "This is StoryWorld. We're built on OpenAI Whisper, GPT-5 prompt expansion,
> Hyper3D Rodin for character generation, Blockade Labs for environments,
> and Kling 3.0 for the final cinematic output — all orchestrated on native iOS with ARKit and RealityKit."

> "The camera is always live. Generation is always non-blocking.
> There are no loading screens — because the director never waits."

**[Hold up the phone.]**

> "One iPhone. Full cinematic control. That's StoryWorld."

---

## ANTICIPATE Q&A

| Question | Answer |
|---|---|
| "How long does generation actually take?" | Skybox ~25s, characters ~60–90s each (parallel), final clip ~3–5 min — all non-blocking |
| "Is the camera framing actually doing anything?" | Yes — screenshot frames from ARKit are passed as multi-shot reference images to Kling |
| "Could you use real people?" | Yes — the requirements.md describes an image stylization path (photo → Pixar-style character) |
| "Why iOS only?" | ARKit + RealityKit give precise world-anchoring. WebXR is the cross-platform path post-hackathon |
| "What's the shot limit?" | 3 minimum to unlock generate, up to ~10 for hackathon; unlimited post-hackathon |

---

## DEMO SAFETY NET

- Pre-cache the `soldier.usdz` and `demon.usdz` models before going on stage — generation during live demos is risky
- Pre-render the Kling clip and have it ready in `reviewingClip` phase
- Have the skybox already loaded so placement is instant
- The live generation path is real and can be shown if time allows or internet is stable
