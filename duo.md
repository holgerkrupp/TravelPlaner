# TravelPlaner on iPhone Duo

Analysis date: 2026-09-22. This is a design and implementation plan for TravelPlaner as one adaptive SwiftUI app, not a proposal to fork the app into a separate Duo-specific product mode.

## Recommendation in one sentence

Keep trip planning and nearby discovery simple and glanceable on the outer display, let the inner display expose map + list + detail simultaneously where useful, and preserve trip, route, map, selection, search, and discovery state across every open, close, rotate, resize, and partial-fold transition.

## Device and platform baseline

Treat iPhone Duo as a continuously resizing iPhone whose layout is driven by live scene geometry, safe areas, size classes, reserved regions, and system adaptive containers.

Do not encode hardware dimensions, model names, or a "Duo mode" boolean into general layout decisions.

The implementation should:
- prefer compact/regular size class behavior over device checks;
- use live safe-area and reserved-region geometry;
- availability-guard Duo-specific APIs;
- keep the chosen deployment target where possible;
- treat every intermediate window size as valid, including Split View and partially folded states.

## Apple rules that drive this plan

- Treat Duo as one continuously resizing app.
- Preserve functionality, hierarchy, selection, map state, active trip, and work in progress across displays.
- Keep interactive controls inside the safe area.
- Avoid placing indivisible controls across the active folding/division region.
- Prefer standard SwiftUI containers such as `NavigationSplitView`, `NavigationStack`, `TabView`, `List`, sheets, alerts, menus, and inspectors.
- Use adaptive two-pane arrangements only where both panes are peer content.
- Do not infer information architecture from hinge angle.
- Keep navigation outside any fold-aware content arrangement.

## TravelPlaner information architecture

Core surfaces:

1. **Discover**
   - nearby map
   - ranked discovery list
   - interest-aware recommendations
2. **Trips**
   - saved/current trips
   - route
   - route-corridor discoveries
   - detour candidates
3. **Place detail**
   - why the place is interesting
   - imagery
   - attribution/provenance
   - visit duration
   - vote signal
   - add-to-trip/navigation actions
4. **Search / add destination**
5. **Settings / interests / privacy**
6. **Optional travel companion**
   - active trip
   - upcoming high-value discoveries
   - location/notification controls

These surfaces adapt without changing their semantic identity.

## Layout by display and pose

| Configuration | Proposed TravelPlaner layout | Fold behavior |
| --- | --- | --- |
| Closed, outer display | Compact navigation. Map and list may switch or use a compact bottom sheet. Selected trip/place opens by navigation push or sheet. | Preserve active trip, selected place, map region, route, search query, filters, and list position when opening. |
| Fully open, inner landscape | Use `NavigationSplitView`. Sidebar: Discover, Trips, Saved, Settings/Interests. Content: map/list browser or trip route. Detail: selected Place where width allows. | Map and list/detail avoid the fold using standard split behavior or explicit fold-aware peer layout. |
| Fully open, inner portrait | Prefer sidebar + content or content + detail depending on actual width. Do not force three columns. | Keep semantic state identical; only presentation changes. |
| Partially folded like a book | Prefer one usable region for map and the other for list/detail when useful. | Floating controls, search, route chips, vote controls, and primary actions must not straddle the fold. |
| Tabletop/laptop pose | Upper region for route/map context; lower interactive region for lists, trip editing, place actions, and controls. | Keep primary interaction in the lower region. |
| Standing/tent/edge poses | Favor one readable region and standard system presentation. | Avoid centered custom overlays that can land on the fold. |
| Split View / narrow window | Collapse secondary detail first, then sidebar if necessary. | Treat every intermediate width as supported. |

## Layout options per surface

### Discover: map + ranked list

| Option | Container | When it is right | Cost |
| --- | --- | --- | --- |
| D1 — map with bottom sheet/list | `Map` plus compact sheet/safe-area list affordance | Default outer display | Only one dense content surface visible at a time |
| D2 — map + list split | Two adaptive panes | Best inner landscape/book layout | Requires selection continuity and fold handling |
| D3 — map + list + detail | `NavigationSplitView` with selected Place detail | Only at genuinely wide inner sizes | Three-column compression risk |

Recommended: D1 on compact width, D2 as the regular-width baseline, D3 only when measured geometry keeps every column useful.

### Trip planner

The trip planner has three peer concepts:
- route/map context;
- trip-stop/discovery list;
- selected Place or stop detail.

Recommended:
- compact: route/map as main content, list/detail through sheet or push;
- regular: route/map + list side by side;
- very wide: route/list/detail only when each remains readable.

Do not create separate trip models or navigation stacks for compact and regular layouts.

### Place detail

Compact:
- push or sheet;
- scrollable content;
- primary actions in toolbar or reachable action area.

Regular:
- detail column or inspector-like pane where appropriate.

Folded:
- never split one small detail card across the fold;
- a full detail may occupy one usable region while map/list remains in the other;
- route, save, and vote controls stay with the Place detail they affect.

### Search and destination picking

Attach search to the content it filters.

- Discover search belongs to Discover.
- Trip destination search belongs to the trip editor.
- Search must not migrate to unrelated detail chrome just because the display expands.

Preserve query text, focus, selected completion, and results during resize where platform behavior allows.

## Concrete implementation requirements

### 1. Make navigation width-driven, not device-driven

Choose compact vs split navigation from live horizontal size class and usable width.

Do not use phone-vs-tablet checks as a reason to force compact layout.

Use one navigation/state model for both presentations.

Suggested stable scene state:
- selected root section;
- selected Trip;
- selected Place;
- navigation path;
- active detail/sheet;
- map camera/region;
- route;
- search query;
- discovery filters;
- list scroll anchor.

### 2. Preserve map continuity

The map must not reset because a fold changes layout.

Preserve:
- map camera/region;
- selected annotation;
- route overlay;
- visible trip stops;
- user-follow state;
- route-corridor overlay;
- discovery filtering.

Do not recreate the map state object when switching layout branches.

### 3. Keep map and list selection bidirectional

Selecting a Place in the list selects/highlights the same Place on the map.

Selecting a map annotation selects/scrolls to the same list item.

This must remain true before, during, and after a fold transition.

Use stable `Place.ID` values, never array indexes.

### 4. Keep route/discovery work independent from view lifetime

Route calculation, corridor discovery, CloudKit checks, and POI enrichment belong in long-lived services/models.

Opening/closing Duo must never:
- cancel a valid route just because a view disappears;
- restart external discovery unnecessarily;
- duplicate CloudKit/open-data requests;
- lose detour calculations;
- publish duplicate POIs.

Cancel only genuinely stale UI-scoped work.

### 5. Make discovery cards width-independent

Discovery cards must support:
- compact one-column list;
- wider split/grid where useful;
- Dynamic Type;
- long localized names;
- missing images;
- multiple provenance labels.

Never hard-code card widths from assumed Duo dimensions.

### 6. Keep controls with the content they affect

Map-owned:
- recenter;
- map style if exposed;
- visible-region refresh/deeper search;
- route overview.

List-owned:
- interests/categories;
- ranking/sort;
- search.

Trip-owned:
- edit/reorder stops;
- route options;
- start companion mode;
- add/remove Place.

Place-owned:
- save;
- add to trip;
- navigate;
- vote;
- share;
- attribution/source actions.

Do not move these into generic root chrome just because a vertical bar is available.

### 7. Treat the fold as a reserved region

Use system layouts first.

Query the active division/folding region only for custom overlays, map controls, cards, or other indivisible content that could land on it.

Conceptual availability-guarded hook:

```swift
GeometryReader { proxy in
    let fold = proxy.reservedRegions(kind: .division).first?.frame
    DiscoveryMapOverlay(foldingRegion: fold)
}
```

Verify the exact API against the targeted SDK.

### 8. Design floating map controls for asymmetric safe areas

Every floating control uses live safe-area information.

Never assume:
- leading/trailing insets are equal;
- the right side is always safe;
- top-right is clear of cameras/system UI;
- an inner fold is zero-width.

### 9. Preserve in-flight editing

Opening, closing, or folding must not discard:
- trip-name edits;
- destination search;
- stop reordering;
- trip notes;
- interest selection;
- place suggestions.

Use stable view identity and scene/model state.

### 10. Preserve scroll by identity

Width/fold changes alter row/card heights.

Prefer stable Place/Trip anchors over raw pixel offsets.

## Open/close transition contract

| Outer display state | Inner display state | Rule |
| --- | --- | --- |
| Discover map, no selection | Discover split map/list | Same camera and filters |
| Discover map, Place selected | Map/list with Place selected, optional detail | Exact selection preserved |
| Trip route visible | Trip map + stop/discovery list | Same route and selected stop/Place |
| Place detail pushed | Selected Place in detail column | Closing restores meaningful compact navigation |
| Search active | Search remains attached to corresponding content | Query/results/focus survive where possible |
| Trip edit active | Wider editor/split layout | Draft and reorder state survive |
| Companion mode active | Same active trip/monitoring | Location behavior does not change just because device opens |

## What may change and what may not

May change:
- column count;
- pane ratio;
- toolbar axis;
- card/grid count;
- pushed vs sheet vs detail-column presentation;
- list bottom-sheet vs peer pane.

May not change:
- active Trip;
- route;
- selected Place;
- map camera unexpectedly;
- search query;
- interests/filters;
- valid POI discovery task just because layout changed;
- visit eligibility;
- saved/vote state;
- companion-mode activation.

## In-flight interactions to test

- Pan map while opening/folding.
- Pinch/zoom map during resize.
- Reorder trip stops during resize.
- Type in destination search during resize.
- Fold while Place detail is open.
- Receive CloudKit/open-data results while layout changes.
- Start/stop companion mode during geometry change.
- Cast a vote while detail presentation migrates.

Map gestures must not jump because the underlying state object was replaced.

## POI discovery considerations on Duo

Duo adaptation must not multiply network work.

Keep these invariants:
- CloudKit-first coverage check remains mandatory;
- open-data fallback stays demand-driven;
- visible-region queries are debounced/coalesced;
- opening Duo does not trigger a deep scan;
- the same trip corridor uses the same coverage cache regardless of layout;
- one logical query feeds map and list.

## Tabletop-specific opportunity

Upper/view-at-a-distance region:
- route/map;
- current trip context;
- upcoming notable detour preview.

Lower/interactive region:
- ranked discoveries;
- stop editing;
- trip controls;
- place actions.

Implement through adaptive region-aware layout, not a `tabletop == true` product branch.

## Verification matrix

### Outer display
- Discover controls remain reachable.
- Place details fit at largest Dynamic Type.
- Trip editing keeps primary actions visible.
- Search/filters remain usable.
- No custom map control collides with system regions.

### Fully open inner landscape
- Sidebar/split layout appears where intended.
- Map/list selection stays synchronized.
- Detail only appears when widths remain useful.
- Route remains identical to compact state.

### Fully open inner portrait
- Bars/layout adapt without resetting state.
- Map/list proportions remain useful.
- Detail does not become excessively wide.

### Partial fold / book
- No map button, search field, route chip, vote control, or primary action crosses the fold.
- Map and list can occupy separate usable regions.
- Sheets/popovers/menus remain usable.

### Tabletop
- Map/route remains legible above.
- Interactive controls remain below.
- No essential action requires touching the upper region.

### Split View / narrow widths
- Secondary detail collapses first.
- Trip/map state persists.
- No clipped toolbar blocks navigation.

### Accessibility
Test:
- VoiceOver;
- Reduce Motion;
- Bold Text;
- largest accessibility text sizes;
- right-to-left layout;
- keyboard navigation where supported.

## Implementation order

1. Build normal TravelPlaner state/navigation without Duo-specific branches.
2. Drive compact vs regular presentation from size class/live width.
3. Give map camera, Place selection, Trip, route, search, and filters stable shared state.
4. Implement adaptive map/list layouts.
5. Add detail-column behavior for wide layouts.
6. Audit floating map controls against safe areas.
7. Add fold avoidance only where custom overlays need it.
8. Add resize/state-continuity tests.
9. Validate book/tabletop layouts in Device Hub.
10. Tune visual density only after behavior is correct.

## Agent implementation rules

When implementing Duo-related work:
- do not create a separate target or Duo mode;
- do not duplicate domain state between compact and regular layouts;
- do not make service/network behavior depend on fold pose;
- prefer system adaptive containers;
- availability-guard new SDK APIs;
- preserve semantics over exact visual position;
- add compact ↔ regular continuity tests;
- validate map controls against asymmetric safe areas and fold regions.

## Relationship to the main architecture

This document supplements `README.md`.

The README remains authoritative for:
- CloudKit cooperative POI caching;
- client-side open-data discovery;
- provenance/licensing;
- privacy;
- visit verification;
- voting;
- trips;
- ranking.

This document is authoritative for Duo/adaptive presentation of those features.

## Sources

Use the current Apple documentation available with the targeted SDK when implementing Duo-specific APIs:

- Preparing your app for iPhone Duo — Technology Overview
- Designing for iPhone Duo — Human Interface Guidelines
- iPhone Duo technical specifications
- Apple Duo design/implementation Tech Talks

Do not use numeric planning dimensions as runtime device detection.
