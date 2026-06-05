# donna-app

React Native iOS app for Donna — tap the mic to talk with the voice backend.

## Setup

```bash
npm install
cd ios && pod install && cd ..
```

From the repo root, start the voice server (see [../README.md](../README.md)):

```bash
npm run dev:server
```

## Run (iOS)

```bash
npm start
# separate terminal:
npm run ios
```

Requires Xcode and the [React Native environment](https://reactnative.dev/docs/set-up-your-environment) for iOS.

Bundle ID: `com.donna.app`

## Voice backend URL

Configured in [`src/config.ts`](src/config.ts):

| Where you run the app | Host used |
|-----------------------|-----------|
| iOS Simulator | `127.0.0.1` (default) |
| Android Emulator | `10.0.2.2` (default) |
| Physical iPhone | Set `VOICE_SERVER_HOST_OVERRIDE` to your Mac's LAN IP |

Find your Mac's IP: `ipconfig getifaddr en0`

When you start the server, it prints the exact `ws://` URLs to use. Restart the iOS app after changing `config.ts`.

## How it works

1. Tap mic → WebSocket session + 16 kHz PCM streaming
2. Client VAD (~500 ms silence) → `turn.end`
3. Server STT → LLM → TTS → `audio.out` chunks
4. App plays reply; mic stays on for the next utterance
5. Tap again to end the session
