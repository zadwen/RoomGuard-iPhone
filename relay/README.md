# RoomGuard permanent relay

This Worker gives the Windows recorder and iPhone a permanent `workers.dev` address. PC restarts reconnect with the existing key. No VPN or inbound PC network port is required.

`src/index.js` forwards end-to-end encrypted JPEG frames through one SQLite-backed Durable Object, using its WebSocket hibernation API. It stores only authentication hashes and the current pairing generation. It does not store footage or possess the encryption key. A four-frame acknowledgement window bounds each viewer's outgoing buffer. Two viewers are allowed, and the PC sends frames only when someone is viewing.

## Deploy

1. Use an existing Cloudflare account on the free Workers plan. Install Node.js and run `npm ci` here.
2. `npx wrangler login --scopes account:read user:read workers_scripts:write` authorizes deployment. The original setup used encrypted OS credential storage via Wrangler's `--use-keyring` option.
3. Run `npx wrangler deploy`. A `workers.dev` account subdomain must be registered. Keep the same Worker name and account subdomain to preserve the address.
4. Generate a random 32-byte pairing key **on the recording PC**, preserving any existing key. The Windows source's `phone_server.relay_hashes(key)` calculates the publisher and viewer authentication hashes.
5. Set `PUBLISHER_HASH` and `VIEWER_HASH` using `wrangler secret bulk` from a private local JSON file containing those hashes. Never upload the actual key. New deployments fail closed until these values exist. Updates preserve the stored pairing generation; do not delete the Durable Object or replace its authentication state during routine updates.
6. Save `{"url":"https://your-worker.your-subdomain.workers.dev"}` to `%LOCALAPPDATA%\RoomGuard\phone-relay.json` and the Base64 key in `phone-pairing.key`. Enable phone viewing in RoomGuard and scan once with the iPhone.

## Validation

`npm run dev` runs a disposable local relay at `http://127.0.0.1:18766`. Supply `.dev.vars` with the hashes derived from `bytes(range(32))` for the public test vector. From the Windows project, set `ROOMGUARD_TEST_RELAY` to that loopback address and run `test_relay.py`. It covers authentication, publisher-role separation, encrypted delivery, PC reconnect with unchanged pairing, bounded buffering, and key rotation. It refuses to run against a public endpoint.

The production smoke test used generated test images, verified encrypted decoding, and restarted the publisher while retaining the viewer and pairing. An iPhone/mobile-network end-to-end test still requires the user's phone.

Cloudflare's free plan has daily usage limits: <https://developers.cloudflare.com/durable-objects/platform/pricing/>. No paid plan is enabled by this project. Do not treat this relay as unlimited cloud recording; the 24-hour archive stays on the PC.
