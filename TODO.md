# TODO — Foundry Companion PoC

## Roadmap: PoC → usable D&D Beyond replacement

The PoC proves the core loop (view actor, roll, live chat). To become something
actually usable day-to-day at the table, roughly in this order:

### Phase 1 — Solidify the single-player core
- [x] ~~Switch from the raw `/get` document to the `/sheet` endpoint (Foundry's own
      computed values) as the primary data source — the raw document is fine for
      proving the round-trip, but doesn't reflect derived stats (modifiers, active
      effects) the way a real sheet needs to.~~ — dropped, premise was wrong.
  - Verified live: `GET /sheet` is not a JSON endpoint — it returns a PNG/JPEG
    screenshot of the rendered sheet (`docs/md/api/sheet.md` in the relay repo).
    And the raw `/get` document has no derived/computed values at all (confirmed
    live: a probe actor's `abilities.str` has no `mod`). There is no
    system-agnostic JSON endpoint anywhere in the relay's route surface that
    exposes computed stats. See the next item for what actually covers this gap.
- [x] ~~Make the sheet **writable**, not just viewable — at minimum: HP, resource/slot
      counters, and toggling conditions. This is the single biggest gap between "PoC"
      and "usable at the table."~~ — done, generically.
  - Extended `DynamicJsonView`/`ActorSheetScreen` instead of building a
    dedicated editor: long-press any numeric leaf → +/- dialog → `POST
    /increase`/`/decrease` (same JSON path the roll dialog already uses); tap
    any string/bool leaf → edit dialog / instant toggle → `PUT /update`
    (Foundry's native flattened dot-key update, confirmed live). New
    "Condities" row above the tree: chips from `GET /effects`, add via a
    picker over `GET /effects/list`, remove via `DELETE /effects`. All fully
    system-agnostic — none of the relay's dnd5e-specific `/dnd5e/*` routes are
    used. Verified live end-to-end (HP 10→9, a string field edit, a bool
    toggle, and add/remove of a "Half Cover" condition), each confirmed
    independently via `GET /get`/`GET /effects` on the relay, not just the app UI.
- [x] ~~Inventory: list items, equip/unequip, use/consume — reuses the same dynamic
      rendering approach as the sheet.~~ — covered for free by the item above.
  - `items[]` was already rendered generically by `DynamicJsonView`; the new
    leaf-editing mechanism makes `items[i].system.quantity`/`equipped`/etc.
    editable the same way as any other field, with no inventory-specific code.
    A class item (`Fighter`) was live-tested for display in the Phase 1.5
    pass below, but `quantity`/`equipped` editing on an actual equipment
    item is still untested — worth a quick pass next time there's a
    populated actor to test.
- [x] ~~Spellcasting/resource tracker: slots and charges, decrement on cast/use.~~ —
      covered for free by the same mechanism.
  - `system.spells.spell1-9/pact` and `system.resources.*` are just more
    numeric leaves — the same long-press +/- adjust covers them. Not
    separately live-tested (the probe actor was a fresh level-1 character
    with no spells prepared); worth a quick pass against a caster.
- [x] ~~Secure the API key in `flutter_secure_storage` instead of a plain config file
      (relevant now that this becomes a real app people install, not just a dev PoC).~~ — done.
  - `RelayConfig` now stores/reads `apiKey` via `flutter_secure_storage`
    (Android Keystore-backed); `baseUrl`/`clientId`/`clientLabel` stay in
    `shared_preferences` since they aren't secrets. One-time migration on
    `load()` moves any pre-existing plaintext key over and scrubs it from
    prefs — verified live: the already-configured test phone opened straight
    to the actor list on the rebuilt app with no re-entry of the key needed.

### Phase 1.5 — Traditional character sheet look
- [x] ~~Give the app a traditional character-sheet look instead of the generic
      JSON tree.~~ — done, as an optional per-system template layer.
  - Discussed the tradeoff first: a real "traditional sheet" layout (ability
    score blocks, skill list, HP bar) unavoidably encodes assumptions about
    what fields exist, which is what the generic renderer exists to avoid.
    Landed on a `SheetTemplate` abstraction (`lib/sheet_templates/`) —
    `ActorSheetScreen` picks a template by the connected world's `systemId`
    (now persisted in `RelayConfig`, previously only `clientId`/`clientLabel`
    were); if none matches, or the actor's `type` doesn't fit (e.g. an NPC
    in a dnd5e world), it falls back to the generic tree, embedded as a
    collapsed "Ruwe data" section inside the template too so nothing is
    ever hidden.
  - Shipped `Dnd5eSheetTemplate` as the reference implementation:
    header (name/class/level), HP block with dedicated -/+ (not tap-to-roll —
    HP isn't something you roll), AC, ability score cards, saving throws,
    skills, currency, and a simple items list. All writes still go through
    the same generic `/increase`/`/decrease`/`/update` mechanism from Phase 1
    — `POST /increase` already takes a dot-path `attribute` string, which is
    exactly what `DynamicJsonView` computes per leaf, so the template reuses
    it directly instead of introducing new write paths.
  - Deliberately does **not** use the relay's dnd5e-specific `/dnd5e/*`
    routes (spell slot consumption, inventory equip endpoints) — would work
    for this one system but reintroduces exactly the coupling the PoC exists
    to avoid.
  - The raw `/get` document has no derived values (see Phase 1 above), so
    the template computes standard 5e tabletop math itself
    (`lib/sheet_templates/dnd5e_formulas.dart`, unit tested): ability
    modifier, proficiency bonus, skill/save bonus. Deliberately conservative
    — ignores `bonuses.check`/`.save` formula strings (arbitrary Foundry
    roll formulas, unsafe to evaluate client-side) and only computes AC for
    the common `calc: "default"` case, showing the raw `flat` value or "—"
    otherwise rather than a guessed-wrong number.
  - Verified live end-to-end against a probe actor (STR 16, DEX 14, Fighter
    level 5): every computed number checked out by hand
    (mod +3/+2, proficiency +3, Athletics +5, AC 12); tapped an ability card
    → rolled `1d20 + 3`, confirmed in Foundry's chat; tapped HP -1 →
    confirmed `29` via `GET /get`. Deleted the probe actor afterward.
  - **Not a bug, but worth recording**: that first probe actor only showed
    STR/DEX (abilities) and Athletics (skills) — looked like the template
    was dropping fields. Root-caused: the probe was created via `POST
    /create` with a *partial* `system.abilities`/`system.skills` payload
    (only the fields I bothered to set), and the relay appears to replace
    those nested objects wholesale rather than deep-merging into the
    system's schema defaults — so con/int/wis/cha and the other 17 skills
    were genuinely absent from the stored document, not just hidden by the
    template. Confirmed by creating a second, completely bare actor
    (`{name, type: "character"}`, no `system` data at all) — that one came
    back from `GET /get` with all 6 abilities and all 18 skills present,
    which the template then rendered correctly. So: real actors (created
    normally in Foundry, or via `/create` with no/full `system` data) will
    always show everything; only a deliberately-partial API-created probe
    won't. No template fix needed.
  - **Next system**: implement `SheetTemplate` for another system (Pathfinder
    2e is the next most-likely candidate given Foundry's ecosystem) and
    register it in `SheetTemplateRegistry` — the mechanism is generic, only
    the per-system widget/formula file needs writing. No live system to test
    against yet, so left for whenever there's a second world to point this at.
- [x] ~~Redesign the dnd5e template into a tabbed, Tidy 5e Sheets-inspired
      layout, with real gear separated from spells and class/race/background
      features~~ — done.
  - Prompted by viewing William's real, 28-item D&D Beyond-imported
    character: gear, spells, and features are all just Foundry `Item`
    documents distinguished only by `item.type`, and the old single "Items"
    list lumped all of it together. Researched `kgar/foundry-vtt-tidy-5e-sheets`
    (the maintained Tidy 5e Sheets fork) as a layout reference — borrowed its
    *organizational structure* (a persistent header, then tabs for
    skills/saves, Inventory grouped by item type, Spells grouped by level,
    Features grouped by race/background/class/feat), not its desktop-only
    features (grid view, drag-drop, search), which are out of scope.
  - New pure categorization function, `categorizeItems()` in
    `lib/sheet_templates/dnd5e_item_categories.dart` (unit tested,
    `test/dnd5e_item_categories_test.dart`): buckets an actor's `items[]`
    into inventory-by-type / spells-by-level / features-by-type, with an
    explicit "other" fallback bucket per category so an unrecognized
    `item.type` is never silently dropped — same "always show everything"
    guarantee the generic tree/"Raw Data" fallback already makes.
  - `lib/sheet_templates/dnd5e_sheet_template.dart` rewritten around a
    `DefaultTabController`: the header/HP/AC/ability-score summary stays
    fixed above the tabs; the rest became 5 tabs (Skills & Saves, Inventory,
    Spells, Features, Raw Data — the last one still the full, unfiltered
    `DynamicJsonView`, unchanged as the ultimate fallback).
  - **New capability, discovered while scoping this**: an actor's own
    `/update` with a dot-path like `items.<id>.system.quantity` silently
    no-ops — confirmed live via curl — because `items` is an embedded
    collection needing `updateEmbeddedDocuments`, not a flat actor property.
    But targeting the *item's own UUID* directly (`Actor.<actorId>.Item.<itemId>`)
    through the exact same generic `/update`/`/increase`/`/decrease` `uuid`
    parameter works correctly (confirmed live: `quantity` 1→7 via curl).
    Generalized `ActorSheetScreen`'s adjust/edit-leaf methods and
    `SheetTemplateContext`'s callback types to take an optional
    `targetUuid` (defaulting to the actor), so the new Inventory tab's
    quantity/equipped edits and the Spells tab's prepared toggle are fully
    interactive using this — no new relay-client methods needed, since
    `adjustAttribute`/`updateField` already take a bare UUID string.
  - Verified live end-to-end on a disposable "Tab Layout Probe" actor (one
    weapon, one consumable, one cantrip, one 3rd-level spell, a race/class/feat
    feature each): tab bucketing correct, quantity/equipped/prepared edits
    all confirmed via `GET /get` and via the actual app UI (not just curl).
    Also did a read-only pass against William's real sheet — Inventory
    (Weapons/Tools/Containers), Spells (Cantrips, correctly empty of leveled
    spells for an Artificer 1), and Features (Race/Background/Class
    Features/Feats) all categorized correctly on real, messy imported data.

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
- [x] ~~Clean up the "Phase1 Test Actor" created to live-verify the writable-sheet work~~ — deleted.
  - Same pattern as above: created via `POST /create`, used to verify the long-press adjust/edit-leaf/conditions mechanism end-to-end on-device, removed via `DELETE /delete?uuid=Actor.skQGXYD99SldXJtF` once done. Test world has no actors again.
- [x] ~~Clean up the "Sheet Template Test" probe actor created to live-verify the dnd5e sheet template~~ — deleted.
  - Same pattern as the previous two: created via `POST /create` (with a `str`/`dex`/embedded `Fighter` class item for checkable math), used to verify the template end-to-end on-device, removed via `DELETE /delete?uuid=Actor.chITmcD0lxtKXirM`. Test world has no actors again.
- [x] ~~Translate the remaining Dutch UI strings (dialog labels, error
      messages, tooltips) to English~~ — done.
  - Audited the whole `lib/` tree, not just widget `Text()` — included
    `RelayException` messages in `relay_client.dart`, which surface
    directly as SnackBar text and are just as user-facing. Covered
    `config_screen.dart`, `actor_picker_screen.dart`, `chat_screen.dart`,
    `actor_sheet_screen.dart` (every dialog), `relay_models.dart`'s
    "Unknown world" fallback, and the dnd5e template's "Raw Data"/"AC (see
    raw data)" strings. `test/widget_test.dart` updated to match the
    renamed "Relay URL" field label.
- [ ] Delete the "Tab Layout Probe" test actor (`Actor.PkanG6DRZOSDeUQk`)
      from the test world now that the tabbed-layout work above is verified
      — same pattern as the other probe actors above (`DELETE /delete`), but
      not done yet: doing it via curl needs the live API key, which lives
      only in the phone's encrypted `flutter_secure_storage` and was
      correctly refused when reading it directly off the device was
      attempted (credential materialization). Delete it the same way as
      before (ask for the key, or delete via Foundry's own UI) next time
      there's a live pass against the relay.
- [ ] Consider reporting the SSE fixture mismatch upstream to ThreeHats (`foundryvtt-rest-api-relay`) — see Bugs below.
- [ ] Explore the relay endpoints not yet touched by the app: `GET /rolls`/`GET /lastroll` (roll history), `/structure` + folders (for actor organization once there's more than one). (`GET /sheet` was explored — it's a PNG/JPEG screenshot, not JSON; see Phase 1 above. Could still be worth showing as a supplementary visual, but it's not a data source.)
- [ ] Live-test the generic leaf-editing mechanism (Phase 1) against an actor that actually has items and prepared spells — the probe actor used to verify it was a fresh level-1 character with neither, so `items[i].system.quantity/equipped` and `system.spells.spell1-9` edits are implemented but not independently confirmed live yet.
- [ ] From the brief's own "onthouden voor later" list, once this grows past PoC scope: auth layer for multiple players, offline-first caching, GM dashboard (initiative tracker, NPC lookup, player status).
- [ ] Get the relay reachable externally via the planned Cloudflare Tunnel (`wss://foundry-relay.shakycomma.org`) — needed before testing the app off the home network. When that happens, revisit `android:usesCleartextTraffic="true"` in `android/app/src/main/AndroidManifest.xml`, since the tunnel would be TLS.

## Bugs

- [x] ~~Rolls posted from the app weren't attributed to the character in
      Foundry's chat log — showed up as the generic API/GM user instead of
      the actor's name~~ — fixed. Flagged by the user as important, and
      rightly so: for a companion app this is core, not cosmetic.
  - `RelayClient.postRoll()` never sent the optional `speaker` param `POST
    /roll` accepts, so the relay/Foundry had no actor to attribute the roll
    to. Confirmed live: without `speaker`, the resulting chat message had
    `speaker: {actor: null, alias: undefined}`; with `speaker: "<actor
    UUID>"`, the relay resolves it into a proper `{actor: "<id>", alias:
    "<actor name>"}` on the chat message — exactly what makes Foundry's own
    chat log show the character's name instead of "Gamemaster".
  - Fix: `postRoll()` gained an optional `speaker` param; `ActorSheetScreen`
    passes `widget.uuid` on every call. Since both the generic tree's
    numeric-leaf rolls and the dnd5e template's ability/save/skill rolls go
    through the same `_openRollDialogFor()`, one fix point covers all roll
    paths. Verified live from the actual UI (not just curl): tapped an
    ability card → rolled → chat message showed `speaker.alias: "Bare Actor
    Probe"`, and the app's own chat screen displayed the actor's name as
    the message header instead of the GM.
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
- [x] ~~New dnd5e sheet template rendered a completely blank screen (below the Condities row) — no error, no red screen, no crash, nothing in logcat~~ — fixed.
  - Root cause: `Row(crossAxisAlignment: CrossAxisAlignment.stretch, ...)` (the HP/AC/Proficiency row) as a direct child of a `ListView`. `CrossAxisAlignment.stretch` needs the `Row` to know its own bounded height to stretch children into; a `ListView` gives its children *unbounded* height (normal for a vertically-scrolling list). That combination throws a `RenderFlex` layout exception — but layout-phase exceptions (unlike build-phase ones) don't get Flutter's usual red-screen `ErrorWidget` substitution, and on this device/renderer (Impeller/Vulkan) nothing reached logcat either — the whole list's paint just silently aborted, with the exception fully invisible.
  - Diagnosis took real bisection since normal tools didn't help: `flutter analyze`/`flutter test` were clean (this is a *runtime layout* issue, not a static/build one); a `try/catch` wrapped around the template's `build()` caught nothing (the throw happens during the later *layout* pass, not while the widget tree is being constructed); logcat showed nothing under any tag. What worked: replacing the real body with a trivial `Center(Text(...))` to confirm the wiring (`Expanded`/`Column` in `ActorSheetScreen`) was fine, then adding pieces of the real content back one at a time until the exact widget that reintroduced the blank screen was found.
  - Fix: wrap that `Row` in `IntrinsicHeight`, which gives it a bounded height computed from its children's intrinsic height, letting `stretch` work safely — `lib/sheet_templates/dnd5e_sheet_template.dart`.
  - Also kept a `try/catch` around `Dnd5eSheetTemplate.build()` regardless (falls back to the generic tree on any exception) — doesn't catch layout-phase issues like this one, but is still worth having for genuine data-shape/build-time surprises on unusual actors.
- [x] ~~Tab selection reset to the first tab ("Skills & Saves") after every
      single edit on the new dnd5e tabbed sheet~~ — fixed.
  - Found live, immediately after verifying the new item-scoped equipped
    toggle worked: a follow-up screenshot showed the tab bar back on
    "Skills & Saves" even though the edit had been made from "Inventory".
  - Root cause: `ActorSheetScreen` refetched via `FutureBuilder<_SheetData>`
    with a fresh `Future` assigned on every `_load()` call (which every
    successful edit/roll triggers, alongside pull-to-refresh) — a fresh
    `Future` means `FutureBuilder` briefly returns to
    `ConnectionState.waiting`, which was rendered as a full-screen spinner
    replacing the whole body. That tore down and rebuilt the entire widget
    subtree including `DefaultTabController`, resetting to tab index 0
    every time — invisible until the sheet actually had tabs to lose.
  - Fix: replaced the `Future<_SheetData>?`/`FutureBuilder` pattern with
    plain `_data`/`_loadError`/`_initialLoad` state fields. `build()` now
    only shows the full-screen spinner on the very first load
    (`_data == null && _initialLoad`); every subsequent `_load()` keeps
    rendering the previous `_data` (same widget subtree, same
    `TabController`) until the refetch resolves, with a non-blocking
    orange banner if a background refresh fails instead of blanking the
    screen. Verified live via `uiautomator`: tapped Inventory → edited the
    equipped toggle on "Test Sword" → dumped the UI tree immediately after
    → the Inventory tab was still `selected="true"`. Also confirmed on the
    Spells tab's prepared-toggle edit.
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
