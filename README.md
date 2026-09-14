# Foundry Companion — PoC

Flutter proof-of-concept for a system-agnostic FoundryVTT companion app.
Talks to a self-hosted
[`foundryvtt-rest-api-relay`](https://github.com/ThreeHats/foundryvtt-rest-api-relay)
(Go relay) over plain HTTP/SSE.

## What's implemented

- **Setup screen** (`lib/screens/config_screen.dart`) — enter relay URL + API
  key, test the connection via `GET /clients`, pick which connected Foundry
  world to use. Stored locally with `shared_preferences`.
- **Actor picker** (`lib/screens/actor_picker_screen.dart`) — lists actors via
  `GET /search?filter=documentType:Actor`.
- **Dynamic sheet renderer** (`lib/widgets/dynamic_json_view.dart`) — walks
  whatever JSON `GET /get` returns for an actor and builds a collapsible
  widget tree purely from each value's runtime type (map / list / number /
  bool / string / null). No D&D 5e (or any system) field names are
  hardcoded — this is the core risk this PoC set out to prove, and it's
  been tested against a real 5e actor payload (see below).
- **Roll trigger** — every numeric leaf in the sheet is tappable; tapping
  opens a dialog pre-filled with a formula and the JSON path as flavor text,
  then `POST /roll` with `createChatMessage: true` so the result lands in
  Foundry's own chat log.
- **Writable sheet** — long-press any numeric leaf for a +/- adjust dialog
  (`POST /increase`/`/decrease`); tap any string/bool leaf to edit it in
  place (`PUT /update`). A **Condities** row above the tree shows active
  effects and lets you add/remove them (`GET /effects`, `GET /effects/list`,
  `POST`/`DELETE /effects`). Same generic mechanism covers HP, resources,
  spell slots, and item fields — see "Why generic leaf-editing" below.
- **Live chat** (`lib/screens/chat_screen.dart`) — loads recent history via
  `GET /chat`, then streams new messages live.

## Why SSE instead of `web_socket_channel`

The obvious choice for "live chat listener" is a WebSocket package like
`web_socket_channel`. Before writing any Dart, I pulled the relay's actual
source (`go-relay/internal/handler/routes.go` and `sse.go` in
`ThreeHats/foundryvtt-rest-api-relay`) to get the real endpoint shapes first.
That turned up something not obvious from the outside: the WebSocket
connection in this system is only between the
**Foundry module and the relay** (`/relay`, `/ws/api`). The client-facing
real-time channel is **Server-Sent Events** on `GET /chat/subscribe`
(confirmed via `test-examples/sse-chat-subscribe.ts` in the relay repo, which
listens for `connected` / `chat-create` / `chat-update` / `chat-delete`
events).

So `pubspec.yaml` does not include `web_socket_channel`; `RelayClient.subscribeChat()`
in `lib/services/relay_client.dart` parses the SSE stream manually over Dio's
`ResponseType.stream` (needed because `x-api-key` has to go in a header,
which the plain browser `EventSource` API can't do — same reason the relay's
own test example uses a custom-fetch `EventSource` polyfill instead).

## Why generic leaf-editing instead of `/sheet` or `/dnd5e/*`

The natural-sounding plan for a "writable sheet" was to switch to `/sheet`
for a richer, computed data source. Verified live before writing any code:
`GET /sheet` is not JSON — it returns a PNG/JPEG **screenshot** of the
rendered Foundry sheet (`docs/md/api/sheet.md` in the relay repo). And the
raw `/get` document this app already uses has no derived values either
(confirmed live: a probe actor's `system.abilities.str` has `value`/
`proficient`/`max`/`bonuses` but no computed `mod`). There's no
system-agnostic JSON endpoint anywhere in the relay that exposes computed
stats for any game system generically.

The relay *does* have a `/dnd5e/*` router with dedicated endpoints for
things like spell slot consumption and inventory equip — using those would
have been the easy path to a "nicer" inventory/spellcasting UI, but only
for D&D 5e worlds. That's exactly the coupling this whole PoC exists to
avoid, so writes go through the generic `/update`, `/increase`, `/decrease`,
and `/effects*` routes instead — all system-agnostic, none of them assume
anything about what fields a "character" has.

Concretely: `POST /increase`/`/decrease` take an `attribute` **dot-path
string** (e.g. `system.attributes.hp.value`) — exactly the `path`
`DynamicJsonView` already computes per leaf while rendering. So the same
long-press mechanism that adjusts HP also adjusts a spell slot or an item's
quantity, with zero field-name-specific code — "inventory" and
"spellcasting tracker" fall out of "writable sheet" for free, since items
and spell slots are just more leaves in the same tree.

## Other things confirmed from source rather than assumed

- No `/api` prefix — routes are mounted at the server root
  (`{baseUrl}/get`, `{baseUrl}/roll`, `{baseUrl}/chat/subscribe`, ...).
- Response envelope for REST calls: `{ "type", "requestId", "success"?, "data": {...} }`,
  or `{ "error": "..." }` on failure.
- `clientId` is a **query parameter**, not a header — one relay can be paired
  to multiple Foundry worlds at once.
- `GET /get?uuid=Actor.xxx&actor=true` returns the raw actor document
  (`{ effects, items, name, system, ... }`) — `system` is exactly where the
  game-system-specific fields live, which is why the renderer has to be
  fully generic.

## Out of scope for this PoC

Auth/user management beyond the one API key (now in secure storage, see
below), dedicated Inventory/Spellcasting screens, GM tools, push
notifications, offline caching.

## Running it

```
flutter pub get
flutter run   # or: flutter build apk --debug
```

On first launch you'll land on the setup screen. Point it at your relay
(e.g. `http://192.168.178.19:3010`), paste the API key from the relay
dashboard, test the connection, and pick the test world.

Note: the relay is plain HTTP (no TLS), so
`android:usesCleartextTraffic="true"` is set in
`android/app/src/main/AndroidManifest.xml` — this'll need to change once the
relay sits behind the planned Cloudflare Tunnel (`wss://`/`https://`).

## Verified against the live relay

Tested directly against `192.168.178.19:3010` and the real test world
(`fvtt_39e66babbdbe2548`, world "Test", dnd5e). `GET /clients` returned
exactly the shape `RelayClient` expects. The world had no actors yet, so a
disposable one ("PoC Test Actor") was created via `POST /create` to exercise
the rest of the loop, then removed again via `DELETE /delete` once testing
was done — the test world currently has no actors, so point the app at a
real one, or create a new disposable test actor the same way if needed.

Confirmed working end-to-end, including a run of the actual Dart
`RelayClient` code (not just curl) against the live relay:
- `GET /get` on the test actor returns the envelope `getEntity()` expects.
- `POST /roll` returns `chatMessageCreated: true`, and the roll shows up in
  `GET /chat` right after — the round-trip in acceptance criterion #2 works.
- The `/chat/subscribe` SSE stream delivers the new message live.

### Bugs found and fixed by live testing

Backend calls checked out via curl immediately, but running the actual app
on a real device (installed via `adb`, driven via `uiautomator`/`input tap`,
not just curl) turned up three real bugs none of the earlier
compile/analyze/unit-test passes could have caught:

1. **SSE payload shape.** The relay's actual `/chat/subscribe` payload
   doesn't match its own repo's test fixture
   (`test-examples/sse-chat-subscribe.ts`), which the app was originally
   built against. On the wire, every event arrives as literally
   `event: chat-create` regardless of the real operation, with the payload
   nested one level deeper than expected:
   `{"data": {"data": <message>, "eventType": "create"|"update"|"delete"}, "type": "chat-event"}`.
   `ChatScreen._unwrapChatEvent()` now reads the operation from the inner
   `eventType` instead of the SSE event name. Worth flagging upstream to
   ThreeHats — their own example doesn't match their server's live behavior.
2. **`setState` crash.** `ActorPickerScreen._load()` and
   `ActorSheetScreen._load()` did `setState(() => _future = _client.foo())`
   — an arrow callback, so it evaluates to the assignment's value, which is
   the `Future` `_client.foo()` returns. Flutter's `setState` asserts its
   callback returns `void` and throws
   ("setState() callback argument returned a Future") the instant you open
   the actor list. Only showed up on-device, mid-tap, in red. Fixed by
   using a block body (`{ _future = ...; }`) in both places.
3. **SSE connection silently dying after ~15s.** `RelayClient`'s shared
   `Dio` sets `receiveTimeout: Duration(seconds: 15)` for ordinary REST
   calls. The relay's own SSE keepalive ticker
   (`go-relay/internal/handler/sse.go`) *also* fires every 15 seconds. Same
   period on both sides means an inevitable race: confirmed live, the chat
   screen showed "live", then flipped to "offline" a few keepalive cycles
   in, and a message posted externally during that window never appeared —
   it was in Foundry's chat log fine, just not delivered to the app. Fixed
   by setting `receiveTimeout: Duration.zero` (no timeout) specifically on
   the `/chat/subscribe` request. Re-verified live: connection held past 40s
   (two-plus keepalive cycles), and an externally-posted message appeared
   in the app with no manual refresh.

## Verified end-to-end, on-device, against the live relay

All three PoC acceptance criteria confirmed on the actual compiled app
(debug APK, installed via `adb install`, driven via `uiautomator`), not just
curl:

1. ✅ **Actor loads, fully dynamic.** Opened "PoC Test Actor" — a disposable
   test actor created via `POST /create` for this pass and deleted again
   afterward (see above). The whole nested
   `system.abilities.str.{value,proficient,max,...}` tree rendered correctly
   with no 5e-specific code.
2. ✅ **Roll round-trip.** Tapped `system.abilities.str.value` (10) →
   roll dialog pre-filled `1d20 + 10` → tapped Roll → SnackBar showed
   `1d20 + 10 = 30 CRIT!` → confirmed in the app's own chat screen moments
   later, and independently via `GET /chat` on the relay.
3. ✅ **Live chat, no refresh.** With the chat screen open, posted a message
   directly through the relay (equivalent to typing in Foundry) — it
   appeared in the app automatically, connection status staying "live"
   throughout.

## Phase 1 (writable sheet) — also verified live

Same pattern as above: a disposable "Phase1 Test Actor" was created via
`POST /create`, driven through the rebuilt app via `adb`/`uiautomator`, and
deleted again afterward. Each UI action was independently confirmed on the
relay side too, not just trusted from the app's own screen:

- **+/- adjust**: long-pressed `system.attributes.hp.value` (10), applied
  -1 → app showed 9 → `GET /get` on the relay confirmed `hp.value: 9`.
- **String edit**: edited `name` via the dialog → saved → `GET /get`
  confirmed the new value.
- **Bool toggle**: tapped `system.attributes.inspiration` (`false`) → `GET
  /get` confirmed `true`.
- **Conditions**: added "Half Cover" from the `/effects/list`-driven picker
  → `GET /effects` showed it (`statuses: ["coverHalf"]`) → removed it via
  the chip's ✕ → `GET /effects` confirmed the list was empty again.
- **Secure storage migration**: the already-configured test phone (from
  the earlier PoC session, API key in plain `shared_preferences`) opened
  straight to the actor list after installing the rebuilt app — no
  re-entering the key — confirming `RelayConfig`'s migration to
  `flutter_secure_storage` ran correctly against a real pre-existing install.

Not yet live-tested: item fields (`items[i].system.quantity`/`equipped`)
and prepared-spell slots, since the probe actor had neither — see
`TODO.md`.

## Remaining before this is more than a PoC

Nothing acceptance-critical is outstanding. Worth doing next: live-test
item/spell-slot editing against a populated actor, decide whether to
report the SSE fixture mismatch upstream to ThreeHats, and the out-of-scope
items above (dedicated GM tools, push notifications, offline caching, real
multi-user auth) once this grows past PoC scope. See `TODO.md` for the
fuller roadmap.
