# agents.md

This repository is intended to be implemented incrementally by coding agents. Read this file before making changes.

## Required reading

Before implementing any issue, read:

1. `README.md` — product definition, architecture, privacy model, CloudKit strategy, discovery model, voting, and implementation direction.
2. `duo.md` — adaptive-layout requirements for iPhone Duo, including compact/regular transitions, fold-safe map UI, and state continuity.
3. The GitHub issue you are implementing, including its dependency section.
4. Relevant existing code and tests before changing architecture.

Do not implement an issue in isolation from these documents.

## Product goal

TravelPlaner is not a generic business directory.

It should surface a deliberately limited set of places that are genuinely worth visiting or worth a small detour, including:

- unusual natural structures;
- parks and protected areas;
- distinctive museums;
- historic, industrial, and engineering sites;
- viewpoints;
- architecture;
- archaeological sites;
- culturally important places;
- unusual restaurants/cafés that are destinations in their own right;
- small local discoveries that generic map ranking often misses.

Prefer quality and uniqueness over result count.

## Native architecture

Prefer first-party Apple frameworks:

- Swift 6
- SwiftUI
- SwiftData
- MapKit
- Core Location
- CloudKit
- UserNotifications
- BackgroundTasks where justified

Do not add a custom application backend unless the repository requirements explicitly change.

Do not add third-party libraries for functionality already cleanly supported by Apple frameworks without a strong documented reason.

## No custom server

The app must work without a custom server.

Shared POI data is stored cooperatively in CloudKit Public Database.

Every installed app may participate in discovering missing POIs:

1. determine the relevant region/trip corridor;
2. query CloudKit first;
3. evaluate coverage;
4. query permitted open-data sources only when coverage is insufficient;
5. normalize, validate, and deduplicate;
6. show the result locally immediately;
7. publish redistributable source-backed POIs to CloudKit when the user can write.

Do not turn the app into a distributed crawler.

## CloudKit trust model

CloudKit Public Database is a cooperative cache, not unquestioned truth.

Every source-backed Place must retain provenance.

Clients must validate shared records locally.

Do not assume arbitrary clients can edit public records created by other users.

Do not make the architecture depend on last-writer-wins mutation of a canonical Place.

Prefer:

- deterministic source identities;
- idempotent create behavior;
- conflict resolution by fetching the existing record;
- append-only/source-specific enrichment when ownership makes mutation inappropriate.

## Stable Place identity

Never use list position, display name alone, or transient MapKit objects as canonical identity.

Prefer stable external/source keys such as:

- `wikidata:Q12345`
- `osm:node:123456`
- `osm:way:123456`
- provider-specific tourism IDs

Maintain a TravelPlaner-owned stable Place ID separately from external IDs.

## Data-source rules

Preferred source families:

- Wikidata
- OpenStreetMap, using an access method whose policy permits the actual usage pattern
- Wikimedia Commons
- Wikipedia/Wikivoyage as context/notability/attribution sources
- official tourism open data
- MapKit/Apple Maps for runtime mapping, routing, and place lookup where permitted

Do not scrape or build a persistent database from:

- Google Maps
- Yelp
- TripAdvisor
- Booking.com
- similar commercial services whose terms prohibit this use

Do not use the public Nominatim service for systematic POI enumeration.

Every source adapter should support, where applicable:

- cancellation;
- pagination;
- rate limiting/backoff;
- freshness policy;
- provenance;
- licensing/attribution;
- stable external IDs;
- normalization;
- deterministic test fixtures.

## Cooperative discovery rules

CloudKit-first is mandatory.

Before querying an external source:

- determine the requested trip corridor or visible region;
- check cached CloudKit coverage and freshness;
- use the shared `CoverageEvaluator`;
- avoid duplicate/overlapping queries;
- respect recent successful coverage checks.

External discovery must be demand-driven.

Opening the map, rotating the device, changing to regular width, or revealing more UI is not by itself permission to query more aggressively.

If publication back to CloudKit fails, keep the POI locally and continue the user experience.

## Privacy requirements

Location privacy is a hard requirement.

Do not upload continuous user movement/location history to CloudKit.

Visit verification should retain only the minimum local evidence needed to determine voting eligibility.

Basic discovery must work without Always location authorization.

Request When-In-Use first and only in context.

Background/Always behavior must be opt-in and tied to a clear user-facing travel-companion feature.

Do not introduce analytics or tracking that conflicts with the README privacy principles.

## Voting requirements

A user may vote whether a Place was worth visiting only when local visit eligibility exists.

The model is best-effort, not fraud-proof. Do not claim otherwise.

Rules:

- one active vote per user/place as strongly as CloudKit/client architecture permits;
- votes can be changed;
- no-vote is neutral;
- small sample sizes must not be presented as strong consensus;
- ranking should use a confidence-aware signal, not raw percentage alone;
- precise visit history must not be uploaded with a vote.

## User suggestions

User suggestions are not canonical source-backed Places.

Keep them in a separate record type/workflow.

A user suggestion must not silently become a trusted POI simply because it exists in CloudKit.

## Discovery and ranking

Ranking must remain explainable.

Inputs may include:

- base notability;
- uniqueness;
- source confidence;
- user-interest match;
- community vote signal;
- route relevance;
- detour cost;
- repetition/fatigue penalties.

User interests are a boost, not a hard filter.

Do not turn TravelPlaner into a popularity/review-count ranking engine.

A small unique place should be able to outrank a generic highly reviewed place.

## Map and routing requirements

Use MapKit for map display and route/detour work.

Avoid full route calculation for every candidate.

Use staged filtering:

1. geographic/corridor filter;
2. approximate distance-to-route;
3. discovery ranking;
4. full MapKit detour calculation for top candidates only.

Map/list selection must use the same stable Place identity.

Do not execute separate equivalent discovery requests just because map and list are rendered independently.

## Swift concurrency

Use Swift 6 concurrency correctly.

Requirements:

- avoid shared mutable global state;
- use actors for mutable shared service state where appropriate;
- isolate UI-facing observable state correctly;
- make domain values `Sendable` where reasonable;
- do not silence concurrency warnings with unsafe annotations unless fully justified;
- support task cancellation for stale map/search/source queries.

Do not keep long-running network or CloudKit operations on the main actor.

## SwiftData

Use SwiftData for user-owned/local state and caches.

Support in-memory stores for tests and previews.

Plan schema versioning from the first production schema.

Do not store a continuous movement history.

Avoid unnecessarily coupling pure domain types to persistence implementation details.

## Adaptive layout and iPhone Duo

`duo.md` is required reading for UI work.

Core rules:

- no separate Duo app mode;
- no device-name checks for layout;
- use live geometry and size classes;
- preserve semantic state across compact/regular/fold changes;
- map, route, Trip, selected Place, search, filters, and edits must survive resizing;
- custom map controls must respect asymmetric safe areas;
- no interactive control may straddle the active fold;
- network/discovery behavior must not become more aggressive merely because more UI is visible.

If a UI issue changes navigation, map structure, sheets, toolbars, floating controls, detail presentation, or split behavior, verify it against `duo.md`.

## Accessibility

All user-facing work must consider:

- VoiceOver;
- Dynamic Type, including accessibility sizes;
- sufficient target sizes;
- Reduce Motion;
- non-color-only communication;
- meaningful control labels;
- right-to-left layout;
- keyboard support where relevant.

Map annotations must have useful accessible labels and must not rely solely on visual icons.

## Offline and unreliable network behavior

Road trips frequently have poor connectivity.

New features should degrade gracefully when:

- CloudKit is unavailable;
- an open-data source times out;
- MapKit routing is unavailable;
- the user has no iCloud account;
- external-source rate limits are reached.

Previously cached relevant POIs should remain usable.

A publication failure must not hide a POI already discovered locally.

## Licensing and attribution

Provenance is part of the data model, not an afterthought.

Do not discard:

- source IDs;
- source URLs where needed;
- license;
- author/creator attribution;
- image attribution;
- source timestamps.

Do not assume all Wikimedia Commons images use the same license.

Do not copy source text unless the license and attribution model are explicitly handled.

## Issue implementation workflow

Before coding:

1. read this file;
2. read `README.md`;
3. read `duo.md` for UI work;
4. read the issue and its dependencies;
5. inspect current code and tests;
6. verify dependencies are implemented or build only the truly independent portion.

During implementation:

- keep changes focused on the issue;
- reuse existing models/services instead of creating parallel architectures;
- add tests with the feature;
- document necessary architectural deviations;
- do not silently broaden scope.

After implementation:

- run tests;
- build affected targets;
- check Swift concurrency warnings;
- test empty/error/offline states;
- test no-iCloud behavior for CloudKit writes;
- verify attribution when surfacing data/media;
- for UI changes, test compact and regular width;
- for map/location changes, check permission and privacy behavior.

## Dependency discipline

GitHub issues explicitly list dependencies.

Do not work around an unfinished dependency by creating a second competing abstraction.

If an issue needs an interface belonging to a dependency, either:

- use/wait for the dependency;
- or introduce only the smallest compatible protocol/fixture needed.

## Testing expectations

Prefer deterministic unit tests for:

- Place identity and deduplication;
- source normalization;
- coverage evaluation;
- ranking;
- route candidate filtering;
- visit eligibility;
- vote aggregation;
- persistence mapping;
- CloudKit mapping/conflict behavior.

Use protocol-backed mocks instead of requiring live CloudKit or public APIs in unit tests.

Representative fixtures should include:

- Lençóis Maranhenses National Park
- Antelope Canyon
- Sequoia National Park
- Socotra
- Marble Caves
- Taylor Glacier
- Vinicunca / Rainbow Mountain

These cover point-like attractions, large areas, remote destinations, natural features, and aliases.

## Performance expectations

Be especially careful with:

- map-region query churn;
- duplicate CloudKit queries;
- repeated open-data source queries;
- image loading;
- route calculations;
- annotation rendering;
- large SwiftData fetches;
- background location use.

Debounce and cancel stale map-region work.

Coalesce overlapping discovery requests.

Do not calculate full detour routes for every candidate.

## Security and validation

Because there is no trusted application server:

- validate CloudKit records;
- validate source identifiers;
- validate coordinates and enum/category values;
- require provenance for source-backed Places;
- keep free-form user content separate from source-derived data;
- do not expose privileged CloudKit credentials or developer-only mutation paths in the consumer app.

## Design direction

TravelPlaner should feel calm and selective.

Do not flood the UI with:

- every nearby restaurant;
- raw OSM density;
- hundreds of map pins;
- unexplained scores/badges;
- excessive notifications.

Prefer:

- a limited ranked set;
- clear "why this is interesting" copy;
- detour time;
- expected visit duration;
- meaningful categories/interests;
- progressive disclosure;
- strong map/list synchronization.

The product question is:

> Would the user regret driving past this?

Features should reinforce that question.

## Naming

The repository is currently named `TravelPlaner`.

Do not rename targets, bundle identifiers, CloudKit containers, or the product opportunistically inside unrelated issues.

Handle any rename in a dedicated issue.

## Documentation authority

If documents conflict:

1. explicit current GitHub issue requirements win for that scoped implementation;
2. `README.md` is authoritative for product architecture;
3. `duo.md` is authoritative for Duo/adaptive-layout behavior;
4. `agents.md` is authoritative for implementation discipline and cross-cutting engineering constraints.

If an implementation would contradict a higher-level product constraint, document the conflict rather than silently changing the architecture.
