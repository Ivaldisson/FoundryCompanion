# TODO — Foundry Companion PoC

## Roadmap: PoC → usable D&D Beyond replacement

The PoC proves the core loop (view actor, roll, live chat). To become something
actually usable day-to-day at the table, roughly in this order:

### Phase 1 — Solidify the single-player core
- [ ] Switch from the raw `/get` document to the `/sheet` endpoint (Foundry's own
      computed values) as the primary data source — the raw document is fine for
      proving the round-trip, but doesn't reflect derived stats (modifiers, active
      effects) the way a real sheet needs to.
- [ ] Make the sheet **writable**, not just viewable — at minimum: HP, resource/slot
      counters, and toggling conditions. This is the single biggest gap between "PoC"
      and "usable at the table."
- [ ] Inventory: list items, equip/unequip, use/consume — reuses the same dynamic
      rendering approach as the sheet.
- [ ] Spellcasting/resource tracker: slots and charges, decrement on cast/use.
- [ ] Secure the API key in `flutter_secure_storage` instead of a plain config file
      (relevant now that this becomes a real app people install, not just a dev PoC).

### Phase 2 — Player-facing parity with D&D Beyond
- [ ] Rest handling: short/long rest actions that trigger the right resource resets.
- [ ] Compendium browser: search spells/items/features read-only, for prep outside
      a session — check what the relay's `/structure` + compendium endpoints expose.
- [ ] Push notifications: "your turn", "you took damage" — the current SSE chat
      stream only works while the app is foregrounded; this needs either a foreground
      service or a proper push backend (FCM) fed by relay events.
- [ ] Multi-character support (a player with more than one PC, or a GM with several
      NPCs open at once) — ties into the `/structure` + folders exploration already
      on the list below.

### Phase 3 — GM tooling
- [ ] Initiative tracker: combat order, HP/condition edits on NPCs/monsters.
- [ ] NPC/monster quick lookup, with local caching for when wifi at the table drops.
- [ ] Player status dashboard: HP/resources for the whole party at a glance.

### Phase 4 — Robustness
- [ ] Offline-first caching (Hive/Isar) for sheets and compendium data, syncing once
      the relay connection returns — right now the app is unusable the moment the
      relay drops, which is the opposite of what you want at a physical table.
- [ ] Retry/backoff for a genuinely dead relay (noted below too) — the manual
      reconnect button is fine for a PoC, not for something you hand to other players.
- [ ] Auth layer once more than one person uses this against the same relay —
      right now it's a single shared API key with no per-user identity or permissions.

### Phase 5 — Ship it
- [ ] Cloudflare Tunnel for the relay (`wss://foundry-relay.shakycomma.org`) so the
      app works off the home network — and flip `usesCleartextTraffic` back to false
      once that's TLS end-to-end.
- [ ] README with setup instructions, screenshots, and a clear "unofficial fan
      project, not affiliated with Foundry Gaming LLC" disclaimer.
- [ ] Pick a license consistent with the Foundry module ecosystem (most
      community modules/relays use MIT or GPL-3.0 — worth matching whichever the
      `foundryvtt-rest-api-relay` itself uses, for compatibility).
- [ ] GitHub Actions to build a release APK on tag, so players don't need to build
      from source themselves.

## Next Steps

- [x] ~~Decide what to do with the "PoC Test Actor" left in the test world (created via `POST /create` to have something to point the app at) — keep it for further manual testing, or have it deleted.~~ — deleted.
  - Removed via `DELETE /delete?uuid=Actor.29yqdOgjmpHlksRA` on the relay; confirmed gone via `GET /search?filter=documentType:Actor` (no `WorldEntity` results left, only compendium entries). The test world now has no actors — point the app at a real one, or create a new disposable test actor the same way if needed again.
- [ ] Consider reporting the SSE fixture mismatch upstream to ThreeHats (`foundryvtt-rest-api-relay`) — see Bugs below.
- [ ] Explore the relay endpoints not yet touched by the app: `GET /rolls`/`GET /lastroll` (roll history), `GET /sheet` (Foundry's own computed sheet, vs. the raw `/get` document this PoC uses — could be a nicer source for a future non-raw sheet view), `/structure` + folders (for actor organization once there's more than one).
- [ ] From the brief's own "onthouden voor later" list, once this grows past PoC scope: auth layer for multiple players, offline-first caching, GM dashboard (initiative tracker, NPC lookup, player status).
- [ ] Get the relay reachable externally via the planned Cloudflare Tunnel (`wss://foundry-relay.shakycomma.org`) — needed before testing the app off the home network. When that happens, revisit `android:usesCleartextTraffic="true"` in `android/app/src/main/AndroidManifest.xml`, since the tunnel would be TLS.

## Bugs

- [x] ~~`setState()` callback argument returned a Future — crashed the app the instant the actor list opened~~ — fixed.
  - `lib/screens/actor_picker_screen.dart` and `lib/screens/actor_sheet_screen.dart` both had `setState(() => _future = _client.foo())`. That's an arrow callback, so it evaluates to the assignment's value — the `Future` `_client.foo()` returns. Flutter's `setState` asserts its callback returns `void` and throws.
  - Fix: block body (`setState(() { _future = ...; })`) in both places instead of the arrow form.
  - Found live, on-device, via `uiautomator`-driven testing — not caught by `flutter analyze`/`flutter test`.
- [x] ~~`/chat/subscribe` SSE connection silently died ~15–20s after connecting, even though the "live" indicator never changed to reflect it until the next keepalive miss~~ — fixed.
  - `RelayClient`'s shared `Dio` instance sets `receiveTimeout: Duration(seconds: 15)` for ordinary REST calls. The relay's own SSE keepalive ticker (`go-relay/internal/handler/sse.go`) also fires every 15 seconds. Identical period on both sides — the client's timeout would eventually race the server's next keepalive and fire first, silently ending the stream. Confirmed live: an externally-posted chat message never reached the app because the stream had already died by then, even though the UI still said "live" one screen ago.
  - Fix: `receiveTimeout: Duration.zero` (no timeout) specifically on the `/chat/subscribe` request in `lib/services/relay_client.dart`, leaving the 15s timeout in place for regular REST calls. Re-verified live: connection held past 40s (two-plus keepalive cycles), and a message posted externally during that window appeared in the app automatically.
- [x] ~~`/chat/subscribe` payload shape didn't match the relay repo's own test fixture~~ — fixed.
  - The app was originally built against `test-examples/sse-chat-subscribe.ts` from `ThreeHats/foundryvtt-rest-api-relay`, which listens for distinct SSE event names (`chat-create`/`chat-update`/`chat-delete`) each carrying a flat `ChatMessage` object.
  - Live testing showed the real relay sends **every** event as literally `event: chat-create` regardless of the actual operation, with the payload nested one level deeper: `{"data": {"data": <message or {"id":...}>, "eventType": "create"|"update"|"delete"}, "type": "chat-event"}`. Confirmed for both `create` and `delete` against the live relay.
  - Fix: `ChatScreen._unwrapChatEvent()` now reads the operation from the inner `eventType` field instead of the SSE event name, with a flat-shape fallback in case the relay is fixed upstream later.
  - Not independently verified: the `update` case — there's no REST endpoint to trigger a chat message edit, so this is coded by inference from the same nesting pattern as `create`/`delete`, not confirmed live.
- [ ] Whisper/private messages, and non-`base` chat message types (emote, OOC, in-character) haven't been exercised — `ChatMessage.fromJson` should handle them (same shape, different `type`/`whisper` fields) but this is untested against a real whisper.
- [ ] No retry/backoff on a genuinely dead relay (e.g. relay container restarts) beyond the manual "Opnieuw verbinden" button on the chat screen — worth revisiting if this becomes more than a PoC.

## Install/Deploy Gotchas

- [x] ~~`flutter install -d <device>` failed with `"build/app/outputs/flutter-apk/app-release.apk" does not exist"`~~ — worked around.
  - It defaults to a release build even when only a debug APK had been built. Installed directly instead: `adb install -r build/app/outputs/flutter-apk/app-debug.apk`.
- [x] ~~`adb shell input tap` sequences kept hitting the wrong element~~ — root-caused and worked around.
  - Screenshots read back through the image tool are downscaled (this device: 1440×3168 real, shown as 909×2000), and several taps were computed straight off the *displayed* image without multiplying by the ~1.58 scale factor back to real device pixels — landing taps ~230px too high/left each time.
  - Also lost time to swipe-momentum: a screenshot taken right after a fling-scroll can still be mid-animation, so coordinates read off it are already stale by the time the next tap lands.
  - Reliable fix used from then on: `adb shell uiautomator dump` + parse `bounds="[x1,y1][x2,y2]"` for the exact real-pixel tap target (Flutter's semantics tree gives every `ExpansionTile`/leaf a `content-desc` too, e.g. `"str\n6 velden, Collapsed"`, which made finding the right node trivial) instead of estimating from a screenshot.
- [x] ~~Screen showed solid black on first `adb exec-out screencap`~~ — not a bug, device was asleep/locked.
  - `adb shell input keyevent KEYCODE_WAKEUP` woke the display, but a secured (PIN/biometric) lock screen still blocked the UI — didn't attempt to bypass it, asked the user to unlock instead.
