# RoomGuard for iPhone

A native iOS 16+ live viewer for the RoomGuard Windows recorder. Works through an outbound HTTPS relay without Tailscale. Pair by scanning the PC's QR code or pasting pairing text. Camera frames use AES-256-GCM end-to-end encryption; the pairing key stays on the PC and in the iPhone Keychain. The relay carries encrypted frames. Authentication uses a derived HMAC token, so the relay does not receive the frame encryption key.

## Build in the cloud

The included GitHub Actions workflow runs on a macOS runner. Put this project in its own GitHub repository on `main`. The **Build iPhone app** workflow tests Python/CryptoKit compatibility, builds for a physical iPhone, and uploads **RoomGuard-iPhone**. Download that artifact and extract `RoomGuard.ipa`.

The IPA is unsigned for AltStore Classic or SideStore to sign with your Apple ID. No Apple ID, certificate, camera key, or video is needed by the cloud build. Private repositories use your GitHub Actions allowance; this project does not enable paid usage or change billing settings. The workflow is capped at 30 minutes.

## Install and pair

1. Send the built `RoomGuard.ipa` to Files on your iPhone.
2. In AltStore Classic or SideStore, open **My Apps**, tap **+**, and select the IPA. Follow that tool's signing instructions. Keep it refreshed according to your signing account's limits.
3. On your PC, reopen the updated RoomGuard, start recording, and choose **Phone viewing → Enable phone viewing**.
4. In the iPhone app choose **Pair camera → Scan PC pairing code** and scan the QR displayed on the PC. Alternatively paste its pairing text.
5. Turn off Wi-Fi on your iPhone and try **Watch live** on mobile data before relying on away-from-home access. The relay has been tested from this PC; the phone's network may differ.

## Limits

- The free quick tunnel uses a temporary hostname. After a PC/relay restart it can change. Pair again with the new QR before leaving home. This is a first version, not a permanent-address monitoring service. Quick tunnels have no uptime guarantee.
- PC must be on, connected to the Internet, and recording. Actual sleep/shutdown stops the webcam. Locking Windows or turning the screen off can keep recording.
- Live preview is 640 pixels wide, up to 30 fps; network speed can lower the delivered frame rate. The original PC recordings remain at the chosen profile, normally 1080p/30 fps.
- No audio, remote archive, deletion controls, recording controls, or background phone recording. Pausing the viewer does not stop the PC recorder. Two phone viewers can connect simultaneously.
- After five seconds without a recent frame, the phone removes the frozen image and shows a waiting/offline state. Reconnection is automatic while the app is foregrounded. Both devices' clocks should be correct.
- Keep pairing codes private. **Reset pairing** on the PC revokes old pairing keys. **Disable phone viewing** stops the relay. The camera recordings remain local and still follow 24-hour/storage retention; save important copies separately.

## Build locally on a Mac

Install Xcode and XcodeGen (`brew install xcodegen`). Run `xcodegen generate`, open `RoomGuard.xcodeproj`, and select your device/signing team if installing directly. The default configuration disables code signing for the cloud/AltStore build. See `.github/workflows/build.yml` for exact test and IPA packaging commands.

## Protocol

- Only the PC's loopback interface listens. Cloudflared creates an outbound HTTP/2 tunnel; no router port forwarding.
- `GET /health` exposes only service name/protocol. `/v1/status` and `/v1/live` require `Authorization: Bearer <hex HMAC-SHA256(key, "RoomGuard API v1")>`.
- `/v1/live?fps=30` is a WebSocket. Binary messages are `12-byte nonce || AES-GCM ciphertext || 16-byte tag`. Plaintext is `8-byte big-endian Unix milliseconds || JPEG`. Authenticated data is `RoomGuard frame v1` in UTF-8. Status messages contain no image data.
- Pairing format: JSON with `v:1`, HTTPS `url`, and a 32-byte URL-safe Base64 `key`. Never commit real pairing data.

References: [AltStore Classic](https://faq.altstore.io/altstore-classic/your-altstore), [Cloudflare quick tunnels](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/), [GitHub macOS runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).
