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
  then `POST /roll` with `createChatMessage: true` and `speaker: <actor
  UUID>` so the result lands in Foundry's own chat log attributed to the
  character (name + portrait), not a generic API user.
- **Writable sheet** — long-press any numeric leaf for a +/- adjust dialog
  (`POST /increase`/`/decrease`); tap any string/bool leaf to edit it in
  place (`PUT /update`). A **Conditions** row above the tree shows active
  effects and lets you add/remove them (`GET /effects`, `GET /effects/list`,
  `POST`/`DELETE /effects`). Same generic mechanism covers HP, resources,
  spell slots, and item fields (including fields on embedded Items, via
  their own UUID — see "Why an optional sheet template" below) — see "Why
  generic leaf-editing" below.
- **Live chat** (`lib/screens/chat_screen.dart`) — loads recent history via
  `GET /chat`, then streams new messages live.
- **Optional per-system sheet template** (`lib/sheet_templates/`) — when the
  connected world's system is recognized, the actor screen renders a
  purpose-built, traditional-looking sheet instead of the generic tree: a
  header, ordered name → HP/AC/Prof → ability scores: scrolling a tab's
  content clips the name and ability grid away to nothing while the
  HP/AC/Prof boxes shrink continuously to about half height (more room for
  what you're actually looking at, HP/AC/Prof always in reach), then
  expand back to full size on scroll-up, then a tab bar (Skills & Saves,
  Inventory, Spells, Features, Raw Data). The generic tree is still
  there underneath, unfiltered, as the "Raw Data" tab — the fallback for
  any system without a template, and the guarantee that a template never
  hides data it doesn't specifically surface. `Dnd5eSheetTemplate` is the
  reference implementation — see "Why an optional sheet template" below.

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

## Why an optional per-system sheet template

The generic tree is honest and universal, but doesn't look or feel like a
character sheet — a real sheet layout (ability score blocks, a skill list,
an HP bar) unavoidably encodes assumptions about what fields exist, which
is exactly what the generic renderer avoids. Rather than compromise that
for every system, `lib/sheet_templates/sheet_template.dart` defines a small
`SheetTemplate` interface: `ActorSheetScreen` looks one up by the connected
world's `systemId` and renders it if found, falling back to the generic
tree otherwise (also true per-actor: `Dnd5eSheetTemplate` itself falls back
for any `type` other than `"character"`, so an NPC in a dnd5e world doesn't
get a bogus half-populated character sheet). Every template embeds the full
generic tree too, collapsed, so nothing a template doesn't specifically
surface is ever inaccessible.

`Dnd5eSheetTemplate` is the reference implementation, and reuses the Phase 1
write mechanism directly rather than inventing new ones — its ability score
cards long-press into the same `/increase`/`/decrease` adjust dialog, keyed
off the same dot-path (`system.abilities.str.value`) the generic tree
already computes. Since the raw document has no derived values (see above),
`lib/sheet_templates/dnd5e_formulas.dart` computes standard 5e tabletop math
itself — ability modifier, proficiency bonus, skill/save bonus — and is
deliberately conservative: it ignores arbitrary `bonuses.check`/`.save`
formula strings rather than evaluate untrusted formulas, and only computes
AC for the common `calc: "default"` case, showing the raw value or "—"
otherwise instead of a guessed-wrong number.

### Inventory/Spells/Features, Tidy 5e Sheets-inspired

Foundry stores gear, spells, and class/race/background features all as the
same `Item` document type, distinguished only by `item.type` — so an
early version of this template that just listed `items[]` lumped a sword,
a spell, and a racial trait together under one generic "Items" heading.
Viewing a real, 28-item D&D Beyond-imported character made that obviously
wrong. Fixed by researching
[`kgar/foundry-vtt-tidy-5e-sheets`](https://github.com/kgar/foundry-vtt-tidy-5e-sheets)
(the actively maintained Tidy 5e Sheets fork) as a layout reference and
borrowing its *organizational structure* — not a pixel clone, and not its
desktop-only features (grid view, drag-drop, search): a persistent
header/summary, then tabs for Skills & Saves, Inventory (grouped by item
type: Weapons/Equipment/Consumables/Tools/Containers/Loot), Spells (grouped
by level, cantrips first), and Features (grouped by
race/background/class/feat). `lib/sheet_templates/dnd5e_item_categories.dart`
does the bucketing as a pure, unit-tested function, with an explicit
"other" fallback per category so an unrecognized `item.type` is never
silently dropped — the same "always show everything" guarantee "Raw Data"
already makes.

Making the new Inventory/Spells tabs interactive (quantity, equipped,
prepared) surfaced a real relay quirk: an actor's own `/update` with a
dot-path like `items.<id>.system.quantity` silently no-ops, because `items`
is an embedded collection needing `updateEmbeddedDocuments`, not a flat
actor property — confirmed live via curl. But the same generic
`/update`/`/increase`/`/decrease` `uuid` parameter also accepts an **item's
own UUID** (`Actor.<actorId>.Item.<itemId>`) and edits it directly —
confirmed live (`quantity` 1→7). `ActorSheetScreen` and
`SheetTemplateContext`'s adjust/edit-leaf methods gained an optional
`targetUuid` (defaulting to the actor) so item-scoped edits reuse the exact
same generic mechanism as everything else, no new relay-client methods
needed.

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

## Phase 1.5 (dnd5e sheet template) — also verified live

Same pattern again: a disposable "Sheet Template Test" actor (STR 16, DEX
14, an embedded `Fighter` class item at level 5, Athletics proficiency) was
created via `POST /create` so every computed number had a hand-checkable
answer, driven through the rebuilt app via `adb`/`uiautomator`, and deleted
afterward.

**A real bug turned up immediately**: the template rendered a completely
blank screen — no error, no red screen, nothing in logcat. Root cause: a
`Row(crossAxisAlignment: CrossAxisAlignment.stretch)` as a direct `ListView`
child. `stretch` needs a bounded height to stretch into; a `ListView` gives
unbounded height to its children (normal for scrolling), so this throws a
`RenderFlex` layout exception — but *layout*-phase exceptions (unlike
*build*-phase ones) don't get Flutter's usual red-screen substitution, and
none of the usual tools helped: `flutter analyze`/`flutter test` were clean
(runtime issue, not static), a `try/catch` around the template's `build()`
caught nothing (the throw happens later, during layout), logcat showed
nothing under any tag on this device. Root-caused by bisection — swap the
real body for a trivial `Center(Text(...))` to confirm the wiring was fine,
then add pieces of the real content back one at a time. Fixed by wrapping
that `Row` in `IntrinsicHeight`. Full writeup in `TODO.md`.

With that fixed, verified live end-to-end:
- Every computed number checked out by hand: STR/DEX modifiers **+3**/**+2**,
  proficiency bonus **+3** (level 5 → `2 + floor((5-1)/4)`), Athletics
  **+5** (DEX mod + proficiency, since this skill's stored `ability` was
  `dex`, not the "expected" `str` — read from the data as stored, not
  assumed), AC **12** (`10 + dex mod`, `calc: "default"`).
- Tapped the STR ability card → roll dialog pre-filled `1d20 + 3` → rolled
  → confirmed in Foundry's chat log (`1d20 + 3 = 12`).
- Tapped HP's `-` button (the dedicated quick-adjust, not the dialog) →
  `GET /get` confirmed `hp.value` went `30` → `29`.
- Expanded "Ruwe data" at the bottom — the full generic tree, same as
  Phase 1, still there and interactive underneath the template.

One thing that looked like a template bug wasn't: the probe actor only
showed STR/DEX and one skill at first. Root-caused to the probe itself — it
was created with a *partial* `system.abilities`/`system.skills` payload,
which the relay appears to replace wholesale rather than merge into the
schema defaults, so the other fields were genuinely missing from the
document. A second, completely bare actor (`{name, type: "character"}`, no
`system` data) came back from `GET /get` with all 6 abilities and all 18
skills, which the template rendered correctly. Real actors — created
normally in Foundry, or via the relay with no/full `system` data — always
have the full set; this was purely an artifact of how the test data was built.

**Also fixed while testing this**: rolls weren't attributed to the
character in Foundry's chat log — they showed up as the generic API/GM
user. `RelayClient.postRoll()` wasn't sending the `speaker` param `POST
/roll` accepts. Confirmed live: passing `speaker: "<actor UUID>"` makes the
relay resolve it into a proper `{actor, alias}` on the resulting chat
message. Fixed at the single dialog call site (`ActorSheetScreen`), so it
covers every roll path — generic-tree numeric leaves and the dnd5e
template's ability/save/skill rolls alike. Re-verified from the actual UI:
tapping an ability card now produces a chat message headed with the
character's name, both on the relay (`speaker.alias`) and in the app's own
chat screen.

## Phase 1.5b (tabbed Inventory/Spells/Features) — also verified live

Same disposable-actor pattern: a "Tab Layout Probe" actor (one weapon, one
consumable, one cantrip, one 3rd-level spell, and a race/class/feat feature
each) was created via `POST /create`, driven through the rebuilt app via
`adb`/`uiautomator`, and left for cleanup (see `TODO.md`).

**A real UX bug turned up mid-verification**: right after confirming an
item-scoped edit worked (toggling "equipped" on a weapon via its own item
UUID — see "Inventory/Spells/Features" above), a follow-up screenshot
showed the tab bar had silently reset from "Inventory" back to "Skills &
Saves". Root cause: `ActorSheetScreen` refetched through a
`FutureBuilder<_SheetData>` with a fresh `Future` on every reload — which
every successful edit triggers — so `FutureBuilder` briefly hit
`ConnectionState.waiting` and rendered a full-screen spinner in place of
the whole body, tearing down and rebuilding the `DefaultTabController`
(and losing the selected tab) on every single edit. Fixed by replacing the
`Future`/`FutureBuilder` pair with plain `_data`/`_loadError`/`_initialLoad`
state: the full-screen spinner now only appears on the very first load,
and every later reload keeps rendering the previous data (same widget
subtree, same `TabController`) until the refetch resolves.

With that fixed, verified live via `uiautomator` (dumping the UI tree
immediately after each edit and checking the tab element's `selected`
attribute, not just eyeballing a screenshot):
- **Inventory tab**: toggled the equipped icon on a weapon — tab stayed on
  "Inventory" afterward, and the icon visually flipped from filled to
  outlined, matching the toggle.
- **Spells tab**: grouped correctly into "Cantrips" and "3rd Level (0
  slots)" (slot count read from `system.spells.spell3.value`); toggled the
  prepared indicator on the cantrip — tab stayed on "Spells" afterward.
- **Features tab**: grouped correctly into Race/Class Features/Feats.
- **Read-only pass against William's real, 28-item sheet**: Inventory
  correctly grouped his actual gear into Weapons/Tools/Containers; Spells
  correctly showed only Cantrips (accurate for a level-1 Artificer with no
  leveled spells yet); Features correctly grouped Race (Tiefling), one
  Background, and several Class Features/Feats. No edits made to his actor.

## Phase 1.5c (even ability grid, collapsing header) — also verified live

Two follow-up requests once the tabbed layout above was in place: the
ability score grid split 6 cards into an uneven 4-then-2 layout (a plain
`Wrap` at a fixed card width, so it just wrapped whenever it ran out of
room), and the header/HP/AC/ability summary should shrink out of the way
while scrolling a tab's content, restoring on scroll-up.

The grid fix was straightforward: `_AbilitiesGrid` now builds two even
`Row`s of up to three `Expanded` cards each, rather than letting a `Wrap`
decide the split.

The collapsing header took two attempts. `Dnd5eSheetTemplate` wraps the tab
bar in a `NestedScrollView` with a `SliverAppBar` (`pinned: true, floating:
true`) holding the full header as `flexibleSpace.background`; each tab is
its own `CustomScrollView` with a `SliverOverlapInjector` matching the
header's `SliverOverlapAbsorber` (the standard Flutter pattern for a
`SliverAppBar` + `TabBar` combo — needed so the five tabs don't fight over
one shared scroll controller). The first attempt tried to show a compact
"HP/AC/Prof" summary via `FlexibleSpaceBar.title`, which is *supposed* to
crossfade in as the header collapses — verified live that it didn't: once
fully collapsed, no such text appeared anywhere, and `uiautomator`
confirmed the toolbar band reserved for it measured close to zero height
rather than the expected `toolbarHeight`. Rather than keep fighting
`SliverAppBar` internals under `NestedScrollView`, the compact summary
became a plain, always-visible row inside the app bar's `bottom` (next to
the `TabBar`, which *is* reliably pinned) — a small trade-off (the compact
stats show even while the big header is also expanded) for behavior that
actually works instead of a reservation that silently failed to render
anything.

The other correction was `_headerExpandedHeight` itself: an initial guess
based on estimated font/padding metrics (320) turned out far too small —
verified live that the second row of the ability grid was being clipped
off entirely. Fixed by measuring real on-device bounds via `uiautomator
dump` (cross-checked against this device's actual `devicePixelRatio`, 4.0,
from `wm density`/`wm size`) instead of guessing again.

Verified live end-to-end on William's real sheet: the 2×3 ability grid
renders correctly; scrolling down in Skills & Saves collapses the header to
a compact "HP 9/9 · AC 13 · Prof +2" line while the tab content gets the
freed-up space; a *small* scroll-up from deep in a long list (not just
from the very top) immediately starts re-revealing the header, thanks to
`floating: true`; scrolling back to the top restores it in full. Also
re-confirmed the earlier tab-selection-survives-an-edit fix still holds
under this restructuring — toggled "equipped" on William's real "Hammer",
confirmed via `uiautomator` that the Inventory tab stayed selected, then
toggled it back to leave his actor as found.

## Phase 1.5d (keep HP/AC/Prof full size, only hide name + ability grid) — also verified live

First attempt at this follow-up shrank the HP/AC/Prof boxes down into a
persistent compact row while scrolled (a `compact` flag on
`_HpCard`/`_AcCard`/`_StatCard`, sharing a `_StatRow` widget between the
two sizes) — that surfaced a real bug (the shrunk HP card's -/+ buttons
overflowed their row, since Flutter's `IconButton` enforces a Material
minimum 48dp tap target regardless of `constraints`/`padding`, fixed by
swapping to a plain `InkWell`+`Icon` for the compact variant), but turned
out to be a misread of the actual request: the boxes should stay exactly
as big as they always were, always pinned at the top — only the name/class
line and ability score grid should hide on scroll.

Corrected by removing the `compact` flag entirely (dead code once nothing
needed a second size) and moving the unmodified, full-size `_StatRow` into
the `SliverAppBar`'s always-visible `bottom`, next to the `TabBar` — so
HP/AC/Prof render exactly as they did before any of this collapsing-header
work started, just permanently pinned instead of scrolling away with the
name and ability grid. `_statRowHeight` (how much room the `bottom` needs
to reserve for the full-size row) was measured live the same way as the
rest of these constants — an initial guess of 98 overflowed by 5px
on-device, corrected to 104.

Verified live on William's real sheet: scrolling down hides the name and
ability grid while HP/AC/Prof stay pinned at their original full size,
unchanged, above the tab bar; scrolling up restores the full header
exactly as before, with no overflow anywhere.

## Phase 1.5e (HP/AC/Prof above the ability grid, and actually shrinking) — also verified live

A third round on this same header, and the most specific correction yet:
HP/AC/Prof needed to sit *above* the ability grid (name → HP/AC/Prof →
abilities, not the other way around), stay full size only when fully
scrolled to the top, and *continuously shrink to about half height* while
scrolling down — the previous fix made them static, which (again) wasn't
the ask. There was also a real, separate bug in the same area: with
HP/AC/Prof below the ability grid, INT/WIS/CHA were getting visually cut
off. Root cause: `SliverAppBar.flexibleSpace.background` renders behind
the app bar's pinned parts (toolbar + `bottom`), and the height budgeted
for name + ability grid was a bit too small — the overflow was rendering
*behind* the always-on-top HP/AC/Prof + `TabBar` strip, hiding it, the
same "guessed a height, it was too small" mistake as every previous round
on this header, just manifesting as an overlap instead of a clip.

`SliverAppBar`/`FlexibleSpaceBar` can't do a *continuously* shrinking
persistent element at all — `flexibleSpace.title` only supports a
fixed-size crossfade (and didn't reserve space correctly even for that,
per the first attempt at this header), and `bottom` is a fixed
`PreferredSize`, not scroll-aware. Replaced both with a hand-written
`SliverPersistentHeaderDelegate` (`_CollapsingHeaderDelegate`), which gets
`shrinkOffset` directly: computes a collapse fraction `t` from it, then a
small `_ClipToHeight` helper (`SizedBox` + `ClipRect` + `OverflowBox`)
clips the name row and ability grid away to nothing as `t → 1`, while
`_StatRow` gained a continuous `scale` parameter
(`lerpDouble(1.0, 0.5, t)`) driving its font sizes/padding/icon sizes
directly, replacing the discrete `compact` bool from the earlier (wrong)
attempt. `maxExtent`/`minExtent` are built algebraically from the same
per-piece height constants so the built content's height exactly equals
the sliver's current extent at every scroll position, with no slack to
overflow.

Verified live on William's real sheet: HP/AC/Prof now render above the
ability grid; at rest, all 6 ability cards are fully visible (the
INT/WIS/CHA clipping is gone); scrolling down hides the name and ability
grid completely while HP/AC/Prof visibly shrink to about half height,
staying fully interactive — round-tripped HP `9/9` → `8/9` → `9/9` using
the shrunk -/+ buttons, located precisely via a cropped and upscaled
screenshot rather than a guessed tap coordinate, since the shrunk targets
are small; scrolling back up restores everything to full size exactly as
before.

## Remaining before this is more than a PoC

Nothing acceptance-critical is outstanding. The "Tab Layout Probe" test
actor has since been removed (deleted directly in Foundry, since a
curl-based delete would have needed reading the live API key out of the
phone's encrypted storage, which was correctly refused as credential
materialization) — future live sheet-template testing uses William's real
character instead of fresh disposable probes where practical. Worth doing
next: live-test item/spell-slot editing and the sheet template against a
newly-populated actor, implement a `SheetTemplate` for a second system whenever there's a live
world to test one against, decide whether to report the SSE fixture
mismatch upstream to ThreeHats, and the out-of-scope items above (dedicated
GM tools, push notifications, offline caching, real multi-user auth) once
this grows past PoC scope. See `TODO.md` for the fuller roadmap.
