# Fusing Vitrine with the Spotify++ feature set

Vitrine already *is* half of what people mean by "Spotify++": `Shared/AdBlock` ports
EeveeSpotify's Hide ads, Hide upsells and Spoof Premium (`AdBlock.h:12-14`), the request
rewriting behind them (`Premium.m`, `AdNetwork.x`, `Feeds.m`), crossfade and automix
(`Crossfade.x`) and radio shuffle/repeat (`RadioModes.x`), all under `<Shared>`, so they work
in both looks. This doc is the plan for the *rest* of the Spotify++ surface: the EeveeSpotify
Reincarnated behaviours Vitrine does not have yet.

Reference: [SideloadLabs/EeveeSpotifyReincarnated](https://github.com/SideloadLabs/EeveeSpotifyReincarnated),
`Master`, GPL-3.0 like Vitrine. Everything here is re-implemented, not copied: Eevee is
Swift + Orion, Vitrine is Objective-C + Logos, and a port follows Vitrine's layers, keys and
`Settings/SGModPage` rows, never Eevee's file shape.

## Where things stand

- `docs/parity.md` tracks parity with **spoti.pw** (Vitrine's upstream). This tracks parity
  with **EeveeSpotifyReincarnated** (Vitrine's ad/Premium source). Keep them apart.
- Vitrine is tested on iOS 27 already (`docs/parity.md`, "checked on an iPhone 15 Pro (iOS 27)").

## iOS 27: the approach

Nothing has to move for iOS 27. The redesign is Liquid Glass and needs iOS 26+;
`SGRedesignAvailable()` (`Core/SGUIMode.h`) answers YES on 27 because it is `@available(iOS 26.0, *)`
and 27 satisfies it, and `tweak/Makefile` builds `iphone:clang:latest:16.0`, i.e. the newest SDK
CI has. So the whole feature set runs on 27 today.

Deliberate choices:

1. **Keep the floors.** Native stays iOS 16.1, redesign stays iOS 26+. Do not raise either to 27
   just to say "for 27" — that drops phones for no gain.
2. **One SDK, newest.** CI's `latest-stable` Xcode (27 SDK) is the only build. Add no per-SDK pins.
3. **Gate new APIs, not new OSes.** Where a 27-only API helps, guard with `@available(iOS 27, *)`
   and keep the 26 path under it. Audit every `@available(iOS 26.0, *)` site to confirm it still
   compiles and behaves against the 27 SDK.
4. **Warn on the new OS.** The install warning (`App/Onboarding/Onboarding.h`) and About say the
   supported *Spotify* versions; make sure the text also says the redesign wants iOS 26+ so a 27
   reader is told, not surprised.

## The ports, by tier

Each is a feature directory in `Shared/` (works in both looks): `<Feature>.h` (keys + API),
`<One>.x` per mechanism with its own `%ctor`, `<Feature>Settings.m` for its rows, and a
`Model.m` if the hooks and the page share plain ObjC. `App/Pages.m` puts the page on Settings.
Verify each hook against a recorded tree (`make session`) or the binary before writing it, as
`docs/tweaks.md` requires.

### Tier 1 — Premium UI unlocks (small, high value) — **built**

Eevee's `Sources/EeveeSpotify/Premium/`. These make Spotify Free look paid. Built together as one
feature, `Shared/PremiumUI/`, since they are all "what the account state would unlock", with keys
`spotifyglass.premiumui.*` and a "Spotify++" section on the Premium page. Each hook is off until its
switch is on and guards itself on the class or selector being there, the way `AdBlock` guards its own.

| Eevee file | What was ported | Vitrine home |
|---|---|---|
| `Premium/TrackRowsEnabler.x.swift` | `trackRowsEnabled: true` on the resolver init. On 9.1.x that selector is on `UIView`, so `TrackRows.x` hooks `UIView` only after `instancesRespondToSelector:`. | `Shared/PremiumUI/TrackRows.x` |
| `Premium/LikedSongsEnabler.x.swift` | The `artist-entity-view-liked-tracks-row` into the artist hub JSON (`LikedSongs.x`; hooks the same builder method as `AdBlock/AdHubs.x`, both call through). | `Shared/PremiumUI/LikedSongs.x` |
| `Premium/TrueShuffle.x.swift` | `SmartShuffleHandlerImplementation` found by suffix, its `checkRecommendationsEnabled` and `recommendationIsBeingAddedWithTrackID:` forced NO. | `Shared/PremiumUI/TrueShuffle.x` |
| `Premium/SiriNoPlayAsRadio.x.swift` | `INMediaItem.identifier`'s play-command JSON: drop the `play-as-radio` restriction and the `:station` suffix. | `Shared/PremiumUI/SiriRadio.x` |
| `Premium/DarkPopUps.x.swift` | Make no-Premium pop-ups dark. **Not portable:** `SPTEncorePopUpContainer` is absent from the 9.1.90 binary (checked 2026-10-18), and Eevee ships this disabled on 9.1.x too. The Encore pop-ups that remain are dark already. | — |
| `Premium/DynamicPremium+PremiumPlanRow.swift` | A "Premium" row that reflects the spoofed state. **Built** in `Premium.m` (`SGPatchPlanRow`, `SGPlanBadge`, `SGPlanOverview`), routed in `AdNetwork.x`: `v1/GetPremiumPlanRow` rewritten, `GetYourPremiumBadge` and `GetPlanOverview` synthesized. Named Spotify Premium in Spotify's green, not after the mod; Eevee's payment notice left out (its strings are gone from 9.1). Field numbers from Eevee's `.pb.swift` models. | `Shared/AdBlock/Premium.m` |

`Intents` was added to `tweak/Makefile`'s frameworks for the Siri hook. `scripts/check-layers.sh`
stays green (all new code is `Shared/`).

### Tier 2 — Robustness (prevents the bugs Eevee exists to fix)

| Eevee file | What to port | Notes |
|---|---|---|
| `SessionProtection.x.swift` (repo root, not `Premium/`) | Keep the session alive while the server disagrees, so Spoof Premium does not log the user out. **Built** as `Shared/AdBlock/SessionProtect.x`: the auth session's logout/destroy, the connectivity session's automated logout, the legacy controller's credential wipe, and the OAuth token bridge's expiry are all held, with a main-thread window for a logout the user asks for. The network half (logout endpoints answered OK, DeleteToken canceled) was already `AdNetwork.x`'s. Ably hooks left out: Eevee does not turn them on for 9.1 either. | the session's ObjC layer was the gap |
| `CarPlayCrashFix.x.swift` | The CarPlay launch crash. | guard on class presence |
| `DataLoaderServiceHooks.x.swift` | The data-loader service surface Eevee hooks for Premium. | fold into `Shared/AdBlock` |

### Tier 3 — Blocker coverage (audit Vitrine's `AdBlock` against Eevee) — **done**

Audited 2026-10-18 against `Master`, every class checked against the 9.1.90 binary before porting.
Already covered: `UpsellPopupBlocker.x.swift` (`AdPopups.x`), `UpsellServiceBlocker.x.swift` (the
Upsells group in `AdServices.x`, class for class), `HubsAdBlocker.x.swift` (`AdHubs.x`, same words),
`HttpClientURLSessionHooks.x.swift` and `DataLoaderServiceHooks.x.swift` (`AdNetwork.x`; Vitrine
answers the warm-relaunch 304 differently — it strips the request's validators so the server never
answers 304 at all — and does not need Eevee's persisted customize copy). Ported, all reimplemented:

- `ClientMessagingPlatformBlocker.x.swift` → new `Shared/AdBlock/AdMessages.x` (Hide upsells): the
  fullscreen, modal and bottom-sheet CMP containers dismissed in `viewWillAppear:`, the CMP banner,
  both Premium upsell banner elements and the upsell control panel taken down on attach. CMP's
  network fetch was only blocked with Spoof Premium on; this net covers every switch combination.
- `EeveeAdBlockerExtended.x.swift` → the Ads group in `AdServices.x`: the scroll-feed and embedded
  pipelines one layer deeper (`EmbeddedCTAElementsServiceImpl`, `EmbeddedAdControllerServiceImpl`,
  `EmbeddedAdAdapterElementProvider`, both playlist ad controllers, `LeavebehindAdElementProvider`)
  and the `EmbeddedAdAdapterElementUI` / `HtmlAdElementUI` view fallbacks. Left out: `DSAMainView`
  (the legal ad-transparency notice, moot with no ad) and the passive `AdModelChangedEventSource`
  probe (log only).
- `CleanShareLinks.x.swift` → `Shared/Privacy/CleanLinks.x`: `UIApplication.openURL` deep-link
  cleaning for the share sheet's direct-destination buttons (`SGCleanDeepLinkURL`), and
  keyed-archived NSURLs on the pasteboard (`SGCleanLinkData`, secure coding only). The pasteboard
  and share-sheet coverage Vitrine already had is wider (more parameters, per-class provider
  swizzling).

Blocked CMP surfaces count under a new "Message surfaces" row on the Premium page.

### Tier 4 — New capability

- **SponsorBlock** (`Sources/EeveeSpotify/SponsorBlock/`) → `Shared/SponsorBlock/`: **done** —
  skip podcast sponsor segments using the public SponsorBlock API. The skipper
  (`SponsorBlockSkipper.m`) is a `Shared/Player` state observer and seeks with the player's own
  `seekTo:` (exposed as `SGPlayer()`), the API client (`SponsorBlockAPI.m`) and the toast are
  straight ports, the overlay (`SponsorBlockOverlay.x`) draws the ECMKit slider's bands on the
  native look only. Per-category actions live under `spotifyglass.sponsorblock.*` on the
  SponsorBlock settings page; skips count under "Segments skipped" on the Premium page. Left out:
  submitting segments (the database is read-only here) and the submission stores/UI.
- **Lyrics providers.** Vitrine's sources (`Shared/LyricsSources/`) cover BiniLyrics, Unison,
  Musixmatch, NetEase, LrcLib, SpicyLyrics, QQMusic, KuGou — but not Eevee's **Genius** (line,
  unsynced) or **PetitLyrics** (Japanese, synced). Add `Genius.m` and `PetitLyrics.m` on the
  same provider protocol, register in `LyricsSources.m`'s ordered list and `LyricsSourcesPage.m`.
  Genius is already fetched for *meanings* (`Shared/LyricsMeanings/`) — reuse that session.

## What stays impossible (server-side)

Say so in the page footers so it is not filed as a bug: Very High audio quality, native playlist
downloading, Jam hosting, AI DJ/Playlist, and Spotify Connect as a remote. Vitrine's Lossless
(`Shared/Lossless/`) already covers the quality angle for local files.

## Defaults

Spotify++ is a "turn it on and forget it" product. Ship the AdBlock set and Tier 1 on by default
(or a one-tap "Enable Spotify++" in the tour), keep anything with a trade-off (Spoof Premium's
warning, SponsorBlock categories) opt-in.

## Build and verify

No Mac needed. The repo already builds IPAs on GitHub Actions:

1. Fork to your account, enable Actions.
2. Run **Build IPA from your own Spotify IPA** with a direct link to a decrypted Spotify
   **9.1.78 / 9.1.88 / 9.1.90** IPA. The workflow builds against the newest SDK and hands back
   `vitrine.ipa`; `make release` derives the flag table from that IPA, so no secret is needed.
   It also emits that flag table as the `sg-flaglist` artifact: download it and set it once with
   `gzip -9c SGFlagList.m | base64 | gh secret set SG_FLAG_LIST`, which is what `release.yml`'s
   compile check reads. Until then that one check job is red; the IPA build is unaffected.
3. Sign with your certificate and install; test on an iOS 27 device.
4. Keep `scripts/check-layers.sh` green: all new code here is `<Shared>`, which is the bottom of
   the one-way import chain and may not import `Native/`, `Redesigned/` or `App/`.

## Licensing and credit

Both projects are GPL-3.0. Keep `LICENSE`, grow the README's Credits with the Eevee maintainers,
and note in each ported file what it came from and that it was reimplemented.

## Order of work

1. Tier 1 (unlocks) — small, testable, visible. **Done** (`Shared/PremiumUI/`; DarkPopUps is not
   portable to 9.1, the plan page is patched in `Premium.m`).
2. Tier 2 SessionProtection — stops the logout bug. **Done** (`Shared/AdBlock/SessionProtect.x`).
3. Tier 3 audit — close blocker gaps. **Done** (CMP surfaces, the scroll-feed pipeline, deep-link
   share cleaning).
4. Tier 4 SponsorBlock (**done**, `Shared/SponsorBlock/`, minus segment submission), then Genius/PetitLyrics.
5. Onboarding/defaults pass.
