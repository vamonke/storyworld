# StoryWorld — Architecture

## User Flow

```
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────────┐    ┌──────────┐    ┌──────────┐
│ Welcome  │───▶│ Capture  │───▶│ Stylize  │───▶│ AR Director  │───▶│ Generate │───▶│ Playback │
│          │    │ (Camera) │    │ (Pixar)  │    │ (Voice+3D)   │    │ (Video)  │    │ (Player) │
└──────────┘    └──────────┘    └──────────┘    └──────────────┘    └──────────┘    └──────────┘
  API keys       1-2 photos      fal.ai FLUX     Place models       Kling video     Save/Share
  setup          of people       stylization      Frame shots        generation      Start over
                                 + 3D gen         Voice commands
```

## Layer Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         SwiftUI Views                           │
│                                                                 │
│  WelcomeView ─▶ CaptureView ─▶ StylizeView ─▶ ARDirectorView    │
│                                                 ─▶ GenerateView │
│                                                 ─▶ PlaybackView │
├─────────────────────────────────────────────────────────────────┤
│                     State Management                            │
│                                                                 │
│  ProjectState (@Observable)                                     │
│  ├── flowState: AppFlowState (welcome/capture/stylize/ar/...)   │
│  ├── project: Project                                           │
│  │   ├── characters: [Character]                                │
│  │   ├── shots: [Shot]                                          │
│  │   └── generatedVideoURL: URL?                                │
│  └── processing flags & progress                                │
├──────────┬──────────────┬──────────────┬────────────────────────┤
│ Camera   │ Voice        │ AR           │ API Clients            │
│          │              │              │                        │
│ Camera   │ VoiceService │ ARSession    │ FalClient (actor)      │
│ Service  │ (AudioEngine │ Manager      │ ├─ stylizeImage()      │
│ (AVCap-  │  + Whisper   │ (ARKit +     │ └─ generate3DModel()   │
│  ture)   │  + GPT-4o)   │  RealityKit) │                        │
│          │              │              │ OpenAIClient (actor)   │
│          │              │ Character    │ ├─ transcribe()        │
│          │              │ Entity       │ └─ parseIntent()       │
│          │              │ (3D model    │                        │
│          │              │  + texture)  │ VideoGeneration        │
│          │              │              │ Client (actor)         │
│          │              │ ModelLoader  │ └─ generateVideo()     │
├──────────┴──────────────┴──────────────┴────────────────────────┤
│                      Apple Frameworks                           │
│  AVFoundation │ AVAudioEngine │ ARKit │ RealityKit │ Photos     │
└─────────────────────────────────────────────────────────────────┘
```

## External API Integrations

```
┌──────────────┐         ┌──────────────────────────────────────┐
│              │         │              fal.ai                  │
│              │────────▶│  fal-ai/flux/dev/image-to-image      │
│              │         │  (Photo ─▶ Pixar-style image)        │
│              │         │                                      │
│  StoryWorld  │────────▶│  fal-ai/trellis                      │
│    (iOS)     │         │  (Image ─▶ 3D USDZ model)            │
│              │         │                                      │
│              │────────▶│  fal-ai/kling-video/v1.5/pro         │
│              │         │  (Image+prompt ─▶ MP4 video)         │
│              │         └──────────────────────────────────────┘
│              │
│              │         ┌──────────────────────────────────────┐
│              │         │             OpenAI                   │
│              │────────▶│  /v1/audio/transcriptions (Whisper)  │
│              │         │  (Audio ─▶ text)                     │
│              │         │                                      │
│              │────────▶│  /v1/chat/completions (GPT-4o)       │
│              │         │  (Text ─▶ DirectorAction)            │
└──────────────┘         └──────────────────────────────────────┘
```

## Voice Command Pipeline

```
User speaks
    │
    ▼
AVAudioEngine (PCM capture)
    │
    ▼
WAV encoding (16-bit, 44.1kHz)
    │
    ▼
OpenAI Whisper ──▶ "Make her smile and do a close up"
    │
    ▼
GPT-4o intent parsing ──▶ { action: "expression", value: "smiling" }
    │
    ▼
DirectorAction.changeExpression("smiling")
    │
    ▼
Update AR scene / capture shot / trigger generation
```

## File Map

```
storyworld/
├── storyworldApp.swift ·········· App entry, ProjectState environment
├── ContentView.swift ············ Flow router + WelcomeView
├── Config.swift ················· API key management
│
├── Models/
│   ├── Character.swift ·········· Photo + stylized image + 3D model ref
│   ├── Shot.swift ··············· ShotType enum + captured frame
│   ├── Project.swift ············ Container: characters, shots, video
│   ├── ProjectState.swift ······· @Observable flow state machine
│   └── DirectorAction.swift ····· Voice command intent enum
│
├── Services/
│   ├── CameraService.swift ······ AVCaptureSession + photo delegate
│   ├── FalClient.swift ·········· fal.ai queue-based API (submit + poll)
│   ├── OpenAIClient.swift ······· Whisper + GPT-4o multipart/JSON
│   ├── VoiceService.swift ······· Audio capture ─▶ transcribe ─▶ parse
│   ├── VideoGenerationClient.swift  Kling video via fal.ai
│   └── ModelLoader.swift ········ Download USDZ + load ModelEntity
│
├── Views/
│   ├── CaptureView.swift ········ Camera preview + capture + name
│   ├── StylizeView.swift ········ Original vs Pixar side-by-side
│   ├── ARDirectorView.swift ····· AR scene + voice + shot capture
│   ├── GenerateView.swift ······· Prompt editor + video generation
│   └── PlaybackView.swift ······· AVPlayer + save + share
│
└── AR/
    ├── ARSessionManager.swift ··· ARKit session + plane detection
    └── CharacterEntity.swift ···· 3D model or textured placeholder
```
