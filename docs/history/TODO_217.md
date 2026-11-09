# TODO 217 — Aerial moving map lines, new crown, fully responsive web panel

**Status:** plan only. The freeze is ON, so no code until "go ahead 217".

**Checked against code (2026-11-05):**
- App: `c8af499` + the 216 patch (`wip_216_app.patch`, 3.0.57+128).
- Backend web: the 216 zip (`internal/httpapi/adminweb/*`).
- Line numbers below are from those files.

**Mocks (the built UI must match these):**

| Mock | Screen |
|---|---|
| `mock_217_web01.png` | W-M1 Map on a phone |
| `mock_217_web02.png` | W-M2 photo menu |
| `mock_217_web03.png` | W-M3 Users as cards |
| `mock_217_web04.png` | W-M4 Manage, full screen |
| `mock_217_web05.png` | W-M5 Dashboard on a phone |
| `mock_217_web06.png` | W-M6 drawer |
| `mock_217_web07.png` | W-T1 tablet |
| `mock_217_app01.png` | A-1 Admin home (small map) |
| `mock_217_app02.png` | A-2 full map (light) |
| `mock_217_app03.png` | A-3 full map (dark mode) |
| `mock_217_app04.png` | A-4 person sheet |

- All pages: `mock_217_all.jpg`.
- Mock scripts: `mock217_src/`. Words in the mocks are the words in the code today; no text changes unless written below.

**Delivery:**
1. Backend zip first. It holds only web files + 1 Go test. There is no migration and no API change.
2. Then ONE app zip with ONE commit: `v3 3.0.58+129 bundle 217: ...`.
- Version: `pubspec.yaml` `version: 3.0.58+129`; `lib/core/config/app_build.dart` `kAppVersion = '3.0.58'`, `kAppBuild = 129`.

---

## 0. Left over from 216 (not code)

| # | Item | Who |
|---|---|---|
| 0.1 | Push the app zip `locallink_app_216_2026-11-05.zip` (GitHub is still at `c8af499`). 217 is built on top of 216. | you |
| 0.2 | Phone tests 216-1 .. 216-10 | you |
| 0.3 | `ui_check_216.jpg` lacks app pages 1, 2, 4, 6, 7, 13, 26 → added in 217g | me |
| 0.4 | Web map server icon outside its circle → 217a.1 | me |
| 0.5 | Web map shows "All 1": the link map lists only phones that are active and not removed on the server. Sumaira's ZTE is not active there. Check Devices on the web. | you |

---

## 1. Old tests that must change (please approve)

| Test | Today | After 217 | Why |
|---|---|---|---|
| `test/bundle214d_test.dart:60` | `expect(AdminCrown.sizeFor(28), 21);` | `closeTo(30.8, 0.01)` | the new crown is 1.1 × radius (mock) instead of 0.75 × radius |
| `test/bundle214d_test.dart:61` | `expect(AdminCrown.sizeFor(10), 12);` | `expect(AdminCrown.sizeFor(10), 13);` | the smallest crown is 13 instead of 12 |
| `test/bundle216a_test.dart:28` (216, never pushed; found while building) | `expect(AdminCrown.sizeFor(8), 12);` | `13` | same reason as 214d:61 |
| `test/nearby_190_test.dart:291` | `version: 3.0.57+128` | `version: 3.0.58+129` | version bump (same as every bundle) |

- **Approved 2026-11-05:** change 214d:60-61; new crown everywhere in the app; tablet row buttons on 2 lines.
- **Old literals that must stay** (other old tests read them):
  - `'_crown(canvas'` and `'old.crownKey != crownKey'` in `link_paths_map.dart`;
  - `'AdminCrown('` in `link_paths_full_screen.dart`;
  - keys `admin_crown`, `admin_crown_ring`, `admin_crown_stack`, `link_node_*`, `link_map_*`, `link_paths_expand`, `link_paths_empty`;
  - `CrownPainter216`, with `heightFor()` > 0 and `shouldRepaint` on `halo`;
  - `LinkPathsCanvas.placements(...)` (212f);
  - `kCrown*216` colours used by the web Go test: `#FFC727`, `#EFA300`, `#A87400`, `#E5484D`;
  - web texts in `admin_web_216_test.go`: "Click a person to see their phones.", "Sign out all phones", "Always on", "Always off", "Blocked \u00b7 relays only", "function crown216", "data-avatar-user", "data-admin-pick", "data-wifi-rule".

---

## 2. Shared numbers (web + app use the same)

### 2.1 Aerial line (one line between two nodes p → q)
- `len = |q − p|`, `mid = (p + q) / 2`.
- **Normal `n`:** the unit normal of p→q that points AWAY from the centre `C` of all nodes shown on the map (server and "You" included):
  - if `(mid − C) · n < 0`, flip `n`;
  - if `|mid − C| < 1 px`, use the normal with `n.y < 0` (bow upwards).
- **Curve:** quadratic, control point `ctrl = mid + n × k × len`. The peak height is half of that offset.
  - Full map (app and web): `k = 0.60` → peak = 0.30 × len.
  - Small map (app Admin home card): `k = 0.36` → peak = 0.18 × len (it must stay inside 104 dp).
- **Colours by link:**

| Link | Web | App |
|---|---|---|
| server | `#3FB26F` | `#12A150` |
| Wi-Fi Direct | `#F5A524` | `#E8A317` |
| mesh | `#8B5CF6` | `#7C5CDB` |
| local Wi-Fi | `#2DD4BF` | `#14A3A0` |

- **Layers, bottom to top** (lw = line width: web 2.2; app 2.2 small / 2.4 full):

| # | Layer | Width | Colour | Opacity | Notes |
|---|---|---|---|---|---|
| 1 | Glow | lw + 6 | link colour | dark 0.45 / light 0.18 | blur 3 |
| 2 | Base | lw | link colour | 0.55 | |
| 3 | Dashes | lw | dark: link colour mixed 50 % with white; light: link colour mixed 12 % with black | 1.0 | dash 6, gap 14; offset moves 20 px every 2 s (one loop / 2 s), direction p → q |
| 4 | Glow dot | — | white core r 2.6 + halo r 5.5 (link colour, opacity 0.35) | — | tail = last 14 % of the path behind the dot, fading 0.9 → 0; light theme adds a 1.4 px ring in the link colour round the core |

- **Glow dot timing:** one trip every 3 s, start offset `index × 0.23` of a trip, so the dots are not in step.
- **Blocked link:** grey dashed (web `#8b949e`, app `kLinkBlockedGrey`), dash 5 / gap 6 (web) and 7 / 5 (app, as today), width 1.8. No glow, no motion, no dot.
- **App offline server link** (`_dashedServerLink`): stays red/grey alternating on the aerial path. No motion.

### 2.2 When motion is off
Lines stay drawn (layers 1–3 at offset 0, no dot). Motion is off when:
- **web:** `prefers-reduced-motion: reduce`, OR the tab is hidden (`document.hidden`);
- **app:**
  - `MediaQuery.disableAnimations == true` (Android "Remove animations");
  - OR battery saver is on;
  - OR the map is not on screen (TickerMode off / another page on top);
  - OR the app is paused.

### 2.3 New crown (mock look, one drawing for web + app)
- **Box:** width `w`, height `0.88 w`. Numbers are fractions of `w` from the top-left of the box. No clip: pearls may stick out by 0.05 w.
- **Shadow:** body + band, moved (+0.03 w, +0.05 w), black 43 %, blur sigma 0.04 w.
- **Body polygon:** (0.10, 0.715) (0.03, 0.235) (0.30, 0.475) (0.50, 0.095) (0.70, 0.475) (0.97, 0.235) (0.90, 0.715).
  - Fill: vertical gradient `#FFE985` (0) → `#FFC727` (0.5) → `#E09A12` (1).
- **Band:** rounded rect x 0.08 … 0.92, y 0.675 … 0.875, radius 0.05 w, fill `#EFA300`.
- **Pearls:** circles r 0.075 w at (0.03, 0.215), (0.50, 0.075), (0.97, 0.215), fill `#FFF1B0`.
- **Outline:** `#A87400`, width max(0.8, 0.035 w), round joins, on body, band and pearls.
- **Jewels on the band** (centre y 0.775):
  - red `#E5484D` ellipse at x 0.50 (rx 0.065 w, ry 0.055 w);
  - blue `#3B82F6` ellipses at x 0.27 and 0.73 (rx 0.045 w, ry 0.038 w);
  - each has a white 65 % highlight dot at the top-left (r 0.2 × rx);
  - outline half width.
- **Shine:** a line from (0.20, 0.635) to (0.14, 0.355), white 47 %, width 0.03 w.
- **Size on a photo of radius R:** `w = max(13, 1.1 R)`.
- **Position:** centred over the photo. The band covers the gold ring (outer edge R + 2.6) and its bottom touches the photo edge (0.4 px in, so old test 214d "touches the photo" stays green): crown top = photo top + 0.4 − 0.88 w.

---

## 217a — Web: fixes + responsive frame

Files: `adminweb/styles.css`, `index.html`, `app.js`, `components.js`, `views.js`.

1. **Server icon bug (W-M1).**
   - Cause: `styles.css:1136` `.map216-world svg { position:absolute; left:0; top:0; overflow:visible }` also hits the `i-server` icon inside `.map216-server`.
   - Fix: change the selector to `.map216-world > svg`. The icon is centred again in its 52 px circle.

2. **Sizes.**
   - Phone: up to 640 px.
   - Tablet: 641–1000 px.
   - PC: over 1000 px.
   - Old rules (1240 / 1000 / 720 / 1100) stay.
   - New blocks go at the END of `styles.css` under the comment `/* Bundle 217: responsive */`:
     - `@media (max-width: 640px)`;
     - `@media (min-width: 641px) and (max-width: 1000px)`.
   - The page never scrolls sideways (only the chips bars and the map stage move inside themselves).

3. **Top bar ≤ 640 (W-M1, W-M2, W-M3 …).** `index.html:136–170`.
   - **Shown:** `#menu-toggle`, `.crumbs strong#crumb-view` (18 px / 600, one line, ellipsis), `#refresh-button`, `#notifications-button`, `#identity-button` (photo only, 30 px).
   - **Hidden:** `#crumb-sub`, `#search-wrap`, `#theme-button`, `.identity-button .who`, the chevron in `#identity-button`, `#signout-button`.
   - **Order:** `#refresh-button` moves right after the title. With CSS `order` (no HTML move): `.topbar { display:flex }`, `#refresh-button { order: -1 }` inside `.topbar-actions`, and `.topbar-actions { margin-left: 0; flex: 1; justify-content: flex-end }` with the refresh button `margin-right: auto`.
   - `.topbar` height 56 px (`--topbar-height: 56px` in the 640 block); gap 4 px; buttons 40 × 40.
   - **All widths:**
     - `.signout216 { white-space: nowrap; flex-shrink: 0 }` (fixes "Sign out" on 2 lines);
     - `.crumbs strong { white-space: nowrap; overflow: hidden; text-overflow: ellipsis }`;
     - `.topbar-actions > * { flex-shrink: 0 }`.
   - **Tablet:** `#search-wrap` and `#theme-button` hidden (theme is in the photo menu); name + level + Sign out stay (W-T1).

4. **Photo menu (W-M2).**
   - `app.js:262 openIdentityMenu()` keeps the same items, words and `data-menu` values: Refresh data / Toggle light / dark / Privacy & access / Sign out.
   - **New head:** `ui.avatar216({ userId: session.user_id, name: session.username, hasAvatar: !!session.has_avatar, admin: true, size: 40 })`, then the username (15 / 600) and `{Role} · signed in until you sign out` (11 px, grey) — the same text as today.
   - **CSS:**
     - `.menu` width 256, radius 14, background `var(--surface-raised)`, border `var(--border-strong)`, 8 px under the photo, right edge = the photo's right edge;
     - `.menu-item` height 44, icon 18, gap 12;
     - dividers under the head and above Sign out;
     - Sign out keeps `.danger` (`#ff7a6e` in dark).
   - **Phone:** `.menu { right: 12px; max-width: calc(100vw - 24px) }`.
   - **Close:** tap outside (already in `app.js:747`) and Esc (already in `app.js:1125`).

5. **Drawer (W-M6), up to 1000 px.**
   - `.sidebar` width 280 px (`max-width: 86vw`); nav rows 40 px; group titles 10.5 px uppercase.
   - Add a close X button in `.sidebar-head`, shown only below 1000 px. It calls the same code as the `#drawer-scrim` click (`app.js:1143`).
   - **Swipe left closes:** pointerdown on `.sidebar` → if `dx < −60` on pointerup → close.
   - Picking a nav item closes it (already in `app.js:213`).
   - Groups and pages stay the same as the PC sidebar.

6. **Tables → cards ≤ 640 (W-M3).** One change in `components.js:211 table()` (used by all 10 `ui.table(` calls):
   - **Every `<td>`:**
     - add `data-label="${esc(c.label)}"`;
     - add class `col-first` on column 0;
     - add `col-act` when the column label is `''`;
     - add `col-status` on the first pill cell (see below);
     - add `hide-tab` when `columns[i].hideTablet`.
   - **CSS ≤ 640:**
     - `.table-wrap table, .table-wrap thead, .table-wrap tbody, .table-wrap tr, .table-wrap td { display:block }`;
     - `.table-wrap thead { display:none }`;
     - `.table-wrap tr { position:relative; background:var(--surface); border:1px solid var(--border); border-radius:12px; padding:14px; margin:0 0 10px; display:grid; grid-template-columns:repeat(3,minmax(0,1fr)); gap:10px 8px }`;
     - `td.col-first { grid-column:1 / -1; padding-right:96px; border-bottom:1px solid var(--border); padding-bottom:12px }`;
     - in JS, the FIRST cell after column 0 that holds `class="pill216` also gets `col-status` (Users: Status; Devices: Link now) → `td.col-status { position:absolute; top:14px; right:14px }`. Other pill cells (Admin level) stay in the grid;
     - `td::before { content: attr(data-label); display:block; font-size:10.5px; color:var(--text-tertiary); margin-bottom:4px }`;
     - no label on `.col-first`, `.col-act` or the absolute pill;
     - `td.col-act { grid-column:1 / -1; display:flex; justify-content:flex-end }`;
     - `.cell-actions { flex-wrap:wrap }`;
     - `td { border:0; padding:0; text-align:left }` (also `.num`).
   - **Users (W-M3):** today's columns map exactly to the card: Person head, Status pill top-right, Admin level / Phones / Last seen, Manage bottom-right.
   - **Phones by build** (`views.js:1825`, a raw `<table class="table">`): build it with `ui.table({ columns: [{label:'Build'},{label:'Phones'},{label:'Last seen'}], rows, emptyMessage: 'No phone has sent its build yet (apps from 3.0.54 do).' })`. `rows` = arrays instead of `<tr>` strings (`views.js:1798`).
   - `.table-wrap { overflow-x:auto }` stays for 641 px and up.

7. **Tablet table (W-T1), 641–1000.**
   - Devices (`views.js:662`) column `Build` gets `hideTablet: true`.
   - `.hide-tab { display:none }` inside the tablet block.
   - `.cell-actions { flex-wrap:wrap; justify-content:flex-start; max-width:190px }` → the row buttons wrap to 2 lines (Rename + Wi-Fi rule, then Remove phone).
   - Other tables stay as they are.

8. **Side panel full screen ≤ 640 (W-M4).** `views.js:556 manage216()`.
   - The head row becomes a sticky head: back arrow (`data-side216-close`, aria-label "Back") + `Manage {name}` (16 / 600) + the existing X.
   - Under it: the person row (photo 48 + name + @user), then today's sections and words: Status / Admin level / Wi-Fi rule / Phones.
   - **CSS ≤ 640:**
     - `.side216 { width:100%; border-left:0; padding:0 16px 24px }`;
     - `.side216-head { position:sticky; top:0; height:56px; background:var(--surface); z-index:1; display:flex; align-items:center; gap:12px; margin:0 -16px; padding:0 16px; border-bottom:1px solid var(--border) }`;
     - the back arrow is hidden over 640 px;
     - `.opt216` min-height 48;
     - `.side216 .chips216 { flex-wrap:wrap }`;
     - `.side216 .btn` → `display:block; width:100%; height:44px; margin:8px 0 0` (the inline `style="margin-left:8px"` on "Sign out all phones", `views.js:598`, moves into a class `side216-danger`).
   - Same full-screen rule for `.modal` (confirm, rename, reject box): `.modal { width:100%; max-width:none; position:fixed; left:0; right:0; bottom:0; border-radius:16px 16px 0 0 }`; `.modal-actions .btn { flex:1; height:44px }`.

9. **Chips bars ≤ 640.**
   - `.bar216 > .chips216, .bar216 .chips216 { flex-wrap:nowrap; overflow-x:auto; scrollbar-width:none; -webkit-mask-image:linear-gradient(90deg,#000 85%,transparent) }`.
   - The search input above them is full width (`.search216 { width:100% }`).
   - Pills like "2 admins · 5 people" go on their own line under the chips.

10. **Dashboard ≤ 640 (W-M5).** Today's content, no new data.
    - `.tiles216` stays at 2 columns (rule at 1100), `.tile216` height 82, value 22 px.
    - The `split-1-1` already becomes 1 column.
    - Chart: `xLabelCount` = 6 → 4 when `window.innerWidth <= 640` (labels never overlap).
    - "Needs a look" rows min-height 50.

11. **General ≤ 640.**
    - `--space-page: 14px`; panel padding 14.
    - `overflow-wrap:anywhere` on `.person216 .sub`, `td`, `.tag`.
    - Inputs 40 px tall.
    - Every button at least 40 px tall.

---

## 217b — Web: Map page (W-M1)

Files: `views.js` (map, lines 1064–1212), `styles.css` (map216 part), `components.js` (`crown216`, `avatar216`), `index.html` (sprite).

1. **Aerial lines.** Replace the `<line>` (`views.js:1128`) with a group per edge.
   - **Group:** `<g class="link217 l-${link}${blocked?' blocked':''}${dim?' dim':''}">`.
   - **Inside it:**
     - `<path class="glow" d="M p Q ctrl q"/>`, `<path class="base" …/>`, `<path class="flow" id="lk${i}" …/>`;
     - plus the dot: `<g class="dot"><circle r="5.5" class="halo"/><circle r="2.6" fill="#fff"/><animateMotion dur="3s" begin="-${(i*0.69)%3}s" repeatCount="indefinite"><mpath href="#lk${i}"/></animateMotion></g>`.
   - Centre `C` = the average of `pos` over all nodes + the server (§2.1), `k = 0.60`.
   - **CSS:**
     - `.link217 path { fill:none; stroke:var(--lc); stroke-linecap:round }`;
     - `.link217 .glow { stroke-width:8.2; opacity:.45; filter:blur(3px) }`;
     - `.link217 .base { stroke-width:2.2; opacity:.55 }`;
     - `.link217 .flow { stroke:var(--lc2); stroke-width:2.2; stroke-dasharray:6 14; animation:flow217 2s linear infinite }`;
     - `@keyframes flow217 { to { stroke-dashoffset:-20 } }`;
     - `.link217 .halo { fill:var(--lc); opacity:.35 }`.
   - `--lc` = the link colour (`ui.LINKS_216[link].color`); `--lc2` = the colour mixed 50 % with white. `--lc2` is computed in JS with a new `ui.mix217(hex, '#ffffff', .5)` helper in `components.js`.
   - **Blocked:** only `<path class="base">` with `stroke:#8b949e; stroke-dasharray:5 6; opacity:1; stroke-width:1.8`. No glow, flow or dot.
   - **Dim** (filter chip): `.link217.dim { opacity:.2 } .link217.dim .flow { animation:none } .link217.dim .dot { display:none }`.
   - **Motion off:**
     - `@media (prefers-reduced-motion: reduce) { .link217 .flow { animation:none } .link217 .dot { display:none } }`;
     - `document.addEventListener('visibilitychange', …)` sets `.paused` on `[data-map-stage]` → `.paused .flow { animation-play-state:paused }` and `svg.pauseAnimations()` / `unpauseAnimations()` for the dots.

2. **Fit on open (W-M1 note "Opens fitted").** Add a function `fit217()`:
   - **Box:** the min/max of `pos` for all shown nodes + the server.
   - **Margins:** 60 px on the sides and top, 80 px at the bottom (name tags).
   - `k = clamp(min(stageW / boxW, stageH / boxH), 0.4, 1.6)`.
   - `x = (stageW − boxW·k) / 2 − boxMinX·k`; `y = (stageH − boxH·k) / 2 − boxMinY·k`.
   - **Called:** on the first mount, on a filter change, on window resize (debounced 150 ms), and by the fit button.
   - Replaces the old block at `views.js:1209–1211`.
   - `mapView.fitted` remembers that the user moved or zoomed. While true, a quiet refresh does not re-fit.

3. **Fit button.**
   - The 3rd zoom button `data-map-zoom="centre"` (text `◎`) becomes `data-map-zoom="fit"` with a new `i-fit` sprite icon (4 corners) and `aria-label="Fit everyone"`.
   - It calls `fit217()` and clears `mapView.fitted`.

4. **Pinch zoom.** Pointer events on `[data-map-stage]` (`touch-action:none` is already set).
   - Keep `const pts = new Map()` of `pointerId → {x,y}`.
   - **1 pointer:** drag as today.
   - **2 pointers:**
     - on start, save `d0` = distance, `m0` = midpoint (stage coords), `k0, x0, y0`;
     - on move: `k = clamp(k0 · d/d0, 0.4, 3)`; `x = m.x − (m0.x − x0) · k/k0`; `y = m.y − (m0.y − y0) · k/k0`.
   - **pointerup / pointercancel:** remove that pointer. Back to 1 pointer → restart the drag from it.
   - Any drag or pinch sets `mapView.fitted = true`.

5. **Stage + legend (W-M1).**
   - `.map216-stage { height: clamp(320px, 52vh, 620px) }`.
   - ≤ 640: `.map216-legend` moves under the stage (`position:static; display:flex; flex-wrap:wrap; gap:6px 16px; margin:12px 2px 0`).
   - Legend items keep today's words. The blocked item shows 3 short dashes instead of a dot.
   - The "Phones (N)" panel is under the map (already 1 column under 1100).

6. **Crown (web).** `components.js:382 crown216(width)` draws the §2.3 crown in SVG.
   - `viewBox="-6 -6 112 94"` (room for the pearls), svg `width = w × 1.12`, `height = w × 0.94`.
   - **Gradient** `<linearGradient id="cr217" x1="0" y1="0" x2="0" y2="1">`, stops `#FFE985` 0, `#FFC727` .5, `#E09A12` 1. The same id in every crown is fine: identical defs.
   - Polygon, rounded band rect `#EFA300`, 3 pearls `#FFF1B0`, outline `#A87400`, jewels `#E5484D` / `#3B82F6`, shine line.
   - `.crown216 { filter: drop-shadow(0 1px 1px rgba(0,0,0,.35)) }`.
   - Size limits stay 10–28 → 10–32.
   - **`avatar216`** (`components.js:410`): `crown216(size * 0.55)` (= 1.1 R); `.av216-crown { top:0; transform: translate(-50%, calc(-100% + .4px)) }` (the ring is a box-shadow 2.6 px outside the photo; the band covers the ring and touches the photo edge, same as the app).
   - **Top-bar photo** (`app.js:679`): `crown216(15)`; `#identity-initial.has-crown .av216-crown` uses the same transform.
   - Level cards in Manage (`views.js:578`): `crown216(12)` stays (smaller, same drawing).

7. **Server node.** `.map216-server` stays 52 px. The icon size is 22 px (`.map216-server .icon { width:22px; height:22px }`).

---

## 217c — App: aerial moving lines (A-1, A-2, A-3)

File: `lib/features/admin/presentation/widgets/link_paths_map.dart` (812 lines).

1. **`LinkPathsCanvas` (line 283) becomes a `StatefulWidget`.**
   - Same constructor and parameters; `static placements()` stays.
   - The State has `SingleTickerProviderStateMixin, WidgetsBindingObserver` and `late final AnimationController _flow = AnimationController(vsync: this, duration: const Duration(seconds: 6))`.
   - One 6 s cycle = 3 dash loops (2 s each) and 2 dot trips (3 s each).
   - **`_syncMotion()`:**
     - `on = LinkMotion217.allowed(context)`, where `allowed` = `!MediaQuery.disableAnimations && !LinkMotion217.powerSave.value && LinkMotion217.debugForce != false`;
     - `on && !_flow.isAnimating` → `_flow.repeat()`;
     - `!on` → `_flow.stop(); _flow.value = 0`.
   - **Called:** in `didChangeDependencies`, on `LinkMotion217.powerSave` changes (listener), and on `didChangeAppLifecycleState` (paused → stop; resumed → `LinkMotion217.refresh()` then sync).
   - TickerMode already mutes the ticker when another route covers the map.
   - `dispose()`: remove the observer and listener; `_flow.dispose()`.

2. **`_LinkPathsPainter` (line 429).**
   - **New fields:** `final Animation<double>? flow; final bool motion; final bool dark; final bool small;`. Pass `super(repaint: flow)` so only the canvas repaints, never the widget tree.
   - **New `Path _aerial(Offset p, Offset q, Offset centre)`:** per §2.1, `k = small ? 0.36 : 0.60`. It replaces every `_arc(...)` call in `paint()` (lines 603, 614, 629, 633, 642, 646). The `bend:` values go away; the `_arc` method stays for `_dashedServerLink` (now built on `_aerial`).
   - `centre` = the average of `s`, `sv` and all values of `place`.
   - **`_flowLine(canvas, path, color, index)`** draws §2.1 layers 1–4:
     - glow: `Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)`;
     - dashes: `PathMetric.extractPath` from `offset = ((v * 3) % 1) * 20` (v = `flow?.value ?? 0`);
     - dot: `t = ((v * 2) + index * 0.23) % 1` via `metric.getTangentForOffset(t * len)`; the tail is 6 short segments fading back over 14 % of the length;
     - when `!motion`: no dot, dash offset 0.
   - **Colours:**
     - dashes: dark → `Color.lerp(color, Colors.white, .5)`; light → `Color.lerp(color, Colors.black, .12)`;
     - glow alpha: dark .45 / light .18.
   - `index` = the edge order: server link 0, server arcs, mesh chain, then the self → device lines.
   - **Blocked:** `_dashed(canvas, _aerial(...), kLinkBlockedGrey)` (no motion).
   - **Server circle** (lines 657–667):
     - fill `dark ? const Color(0xFF161B22) : Colors.white`;
     - border `dark ? const Color(0xFF2F6BFF) : const Color(0xFFB2CCFF)`;
     - the cloud icon stays (`_text(... Icons.cloud_outlined ...)`).
   - **`shouldRepaint`:** keep every existing line (incl. `old.crownKey != crownKey`) and add `old.motion != motion || old.dark != dark || old.small != small`.
   - **Legacy crown** (lines 703 / 716): `_crown(canvas, …)` keeps its name, but its body (721–729) calls `paintCrown217(canvas, topCentre, width)` from `admin_crown.dart` instead of the 👑 emoji.

3. **`LinkPathsCanvas.build`** creates the painter with `flow: _flow, motion: _flow.isAnimating, dark: c.dark, small: widget.small`.

4. **New small class in the same file:**
   ```dart
   class LinkMotion217 {
     static final ValueNotifier<bool> powerSave = ValueNotifier(false);
     static bool? debugForce;             // tests: true / false / null
     static const _ch = MethodChannel('locallink/device');
     static Future<void> refresh() async { try { powerSave.value = (await _ch.invokeMethod<bool>('powerSave').timeout(const Duration(milliseconds: 300))) ?? false; } catch (_) { powerSave.value = false; } }
     static bool allowed(BuildContext c) => debugForce ?? (!(MediaQuery.maybeOf(c)?.disableAnimations ?? false) && !powerSave.value);
     @visibleForTesting static void resetForTest() { debugForce = null; powerSave.value = false; }
   }
   ```
   - `refresh()` runs once in the first `initState` of a `LinkPathsCanvas`, and on every resume.
   - Log: `LINK_MOTION on|off why=<anim|saver|paused>` (only when the state changes).

5. **Admin home card** (`admin_panel_screen.dart:793 _mapCard`): no change in this file. The height stays 104.
   - In `LinkPathsMap.build` (line 223, `SizedBox(height: 12)`) the gap under the subtitle goes 12 → 16, so the bigger crowns on top-row nodes stay under the subtitle.

6. **Full map** (`link_paths_full_screen.dart:405`): no change needed. The canvas animates by itself. The sheet (line 200) is unchanged (A-4); only the crown look changes, through 217d.

7. **Native** (`android/.../MainActivity.kt:245`, channel `locallink/device`): add a branch
   ```kotlin
   } else if (call.method == "powerSave") {
       result.success(try { (getSystemService(Context.POWER_SERVICE) as android.os.PowerManager).isPowerSaveMode } catch (e: Exception) { false })
   ```
   - It goes before the final `else`.
   - No other native file changes. `BackgroundChannels.kt` (its own `locallink/device` handler) is NOT touched; the map only runs in the UI engine.

---

## 217d — App: new crown everywhere (A-1 … A-4)

File: `lib/core/widgets/admin_crown.dart` (266 lines).

1. **`CrownPainter216.paint`** (lines 25–86) draws the §2.3 crown.
   - Add 3 colours: `kCrownTop217 = Color(0xFFFFE985)`, `kCrownLow217 = Color(0xFFE09A12)`, `kCrownPearl217 = Color(0xFFFFF1B0)`, plus `kCrownBlue217 = Color(0xFF3B82F6)`.
   - Keep `kCrownFill216` (middle stop), `kCrownBand216` (band), `kCrownLine216` (outline) and `kCrownGem216` (red jewel).
   - The body fill is `Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [kCrownTop217, kCrownFill216, kCrownLow217], stops: [0, .5, 1]).createShader(rect)`.
   - Shadow: `canvas.drawPath(shadowPath.shift(Offset(.03*w, .05*w)), Paint()..color = Colors.black.withValues(alpha: .43)..maskFilter = MaskFilter.blur(BlurStyle.normal, .04*w))`.
   - The `halo` option stays: same idea, drawn round the new body / band / pearls when `halo != null`.
   - The drawing lives in a top-level `void paintCrown217(Canvas canvas, Offset topCentre, double w, {Color? halo})`; `CrownPainter216.paint` calls it with `topCentre = Offset(size.width / 2, (size.height - .88 * w) / 2)`.
2. `CrownPainter216.heightFor(w)` → `w * 0.88`.
3. `AdminCrown.sizeFor(r)` → `math.max(13.0, r * 1.1)` (old tests 214d:60–61, see §1).
4. **`AdminCrown.decorate`** (line 157), `Positioned(top: …)` → `top: 0.4 - h` (h = `heightFor(w)`), so the base sits 2 px into the ring (the ring outer edge is R + 2.6).
5. **Everything that shows a crown gets the new look by itself:**
   - `AdminCrown.mark` (tags, the top crown button in Admin home, titles);
   - `AdminPersonAvatar216` (it uses `AdminCrown.decorate`, `admin_kit216.dart:1629`);
   - the map nodes, the hero card, the sheet;
   - the "Admin · Owner" tag (`AdminRoleTag216`).
6. **No change** in `admin_kit216.dart`, `admin_ui216.dart`, `admin_panel_screen.dart`, or the Settings card files.

---

## 217e — Backend Go test (new) — `internal/httpapi/admin_web_217_test.go`

Read the files through `adminWebFS` (like the 216 test) and check:
- **`styles.css`:**
  - contains `.map216-world > svg`, `@media (max-width: 640px)`, `@media (min-width: 641px) and (max-width: 1000px)`, `td::before`, `@keyframes flow217`;
  - contains `prefers-reduced-motion` followed by `.link217 .flow`;
  - `.signout216` contains `white-space: nowrap`;
  - `.side216-head` contains `position: sticky`;
  - does NOT contain `.map216-world svg {`.
- **`components.js`:** `data-label=`, `col-first`, `col-act`, `hide-tab`, `mix217`, `cr217`, `#FFE985`, `#3B82F6`. The old `#FFC727` / `#EFA300` / `#A87400` / `#E5484D` stay (216 test).
- **`views.js`:**
  - contains `animateMotion`, `class="link217`, `fit217(`, `data-map-zoom="fit"`, `Fit everyone`, `hideTablet: true`;
  - does NOT contain `<line x1=` or `<table class="table">`;
  - still contains "Click a person to see their phones." (216 test).
- **`index.html`:** `id="i-fit"`.
- **`app.js`:** `openIdentityMenu` contains `avatar216(` and the 4 menu words.

---

## 217f — App tests (new; old tests unchanged except §1)

`test/bundle217c_test.dart`:
1. **Painter geometry:** `_aerial` exposed via `@visibleForTesting static Offset aerialControl(Offset p, Offset q, Offset centre, {bool small})`.
   - For p(0,0), q(100,0), centre(50,50) the control is (50, −60) (bows up, away from the centre).
   - With `small` it is (50, −36).
2. **Motion on:** pump `LinkPathsCanvas` with 3 nodes → `_flow.isAnimating` is true (via a debug getter `LinkPathsCanvasState.debugAnimating`) → pump 1 s → no exception.
3. **Motion off by "Remove animations":** wrap in `MediaQuery(data: MediaQueryData(disableAnimations: true))` → not animating.
4. **Motion off by battery saver:** `LinkMotion217.powerSave.value = true` → not animating. Back to false → animating.
5. **Paused:** `tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused)` → not animating.
6. **Blocked node:** a recording canvas (`PictureRecorder` → count paths) shows no dot circle for a blocked-only map.
7. **`shouldRepaint`:** true when `dark` or `motion` changes; source still contains `'old.crownKey != crownKey'` and `'_crown(canvas'`.
8. **Dark server fill:** the painter with `dark: true` draws the server circle in `0xFF161B22` (via the recording canvas colour list).
- `tearDown`: `LinkMotion217.resetForTest()`.

`test/bundle217d_test.dart`:
1. `AdminCrown.sizeFor(40)` = 44; `sizeFor(5)` = 13; `CrownPainter216.heightFor(50)` = 44.
2. `AdminCrown.decorate(radius: 24, …)`: the crown's bottom is 3 ± 0.5 px below the ring top, i.e. 0.4 px inside the photo (`getRect(find.byKey('admin_crown'))`).
3. `paintCrown217` draws without error at w = 13, 26 and 40 (golden-free: `toImage`, no exception).
4. The `mark()` key `admin_crown` is still found.

Every test file that pumps a map uses `pump()`, never `pumpAndSettle()` (the line animation repeats). I checked: none of the old tests that pump the map use `pumpAndSettle` on a map screen. Their `pumpAndSettle` calls (213f, 197b) are on other screens.

---

## 217g — UI check (mock vs built)

- **`ui_check_217.jpg`:**
  - A-1, A-2, A-3, A-4 built vs mock (`test/bundle216ui_pages_test.dart` style: `RepaintBoundary` + `toImage`, motion frozen with `LinkMotion217.debugForce = false` and a fixed dot phase via `debugPhase`);
  - the 7 app pages missing from 216 (1, 2, 4, 6, 7, 13, 26).
- The web cannot be rendered here (no browser). The web is checked by 217e plus your phone / PC tests below.

---

## Phone / PC tests for you (after the deploy + APK)

| # | Where | Do | Expected |
|---|---|---|---|
| 217-1 | Web Map on the phone | open Map | fits everyone, curved lines with moving dashes + dot, server icon inside its circle |
| 217-2 | same | pinch, drag, press the fit button | smooth zoom / move; fit brings everyone back |
| 217-3 | phone Settings → Remove animations ON | open the web Map | lines stay, nothing moves |
| 217-4 | web on the phone | top bar on every page | one line; Sign out only in the photo menu |
| 217-5 | web on the phone | Users, Devices, Sessions, Calls, App version | cards; no sideways scroll anywhere |
| 217-6 | web on the phone | Users → Manage | full screen, back arrow closes, buttons full width |
| 217-7 | PC window ~800 px | Devices | table without Build; buttons on 2 lines; drawer menu; Sign out on one line |
| 217-8 | app Admin home + full map | look | aerial lines move; new crown on photos, sheet, tag, top button |
| 217-9 | app with battery saver ON | open the full map | lines stay, no motion; turn the saver OFF + come back → moves again |
| 217-10 | app in dark mode | open the full map | dark map like A-3 |

---

## Files touched (nothing else)

**Backend (zip 1):**
- `internal/httpapi/adminweb/styles.css`, `index.html`, `app.js`, `components.js`, `views.js`;
- new `internal/httpapi/admin_web_217_test.go`.

**App (zip 2):**
- `lib/features/admin/presentation/widgets/link_paths_map.dart`;
- `lib/core/widgets/admin_crown.dart`;
- `android/app/src/main/kotlin/com/sajjad/locallink/MainActivity.kt` (1 branch);
- `pubspec.yaml`, `lib/core/config/app_build.dart` (version);
- new `test/bundle217c_test.dart`, `test/bundle217d_test.dart`;
- old tests per §1: `test/bundle214d_test.dart` lines 60–61, `test/nearby_190_test.dart:291`;
- `TODO_217.md`, `APPLY_217.md`.

`link_paths_full_screen.dart` and `admin_panel_screen.dart` are NOT changed.

## Build order
1. 217a + 217b + 217e (backend zip; `go test ./...` must be green).
2. 217d (crown) → its tests + 216a / 214d / 214e.
3. 217c (lines) → its tests + 212f / 212g / 214d / 216c / 216d / 216ui_pages.
4. Version, full test run in chunks (never in parallel), analyze ≤ 159.
5. 217g UI check, zip, `APPLY_217.md` with PowerShell steps.
