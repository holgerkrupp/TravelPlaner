# TravelPlaner

TravelPlaner is a native iOS travel-discovery app for finding places that are genuinely worth a visit or a small detour.

The app is intentionally **not** another exhaustive map of every business nearby. Its goal is to surface distinctive natural structures, parks, museums, historic sites, viewpoints, unusual engineering, restaurants with a special story, and other one-of-a-kind places. Users can browse around their current location or create a trip and discover relevant places along the route.

## Product principles

- **Interesting, not exhaustive.** Prefer a smaller set of meaningful discoveries over thousands of generic POIs.
- **Native Apple stack.** Swift, SwiftUI, MapKit, Core Location, CloudKit, UserNotifications, BackgroundTasks, and other first-party APIs where practical.
- **No application server.** The app should work without a custom backend. Shared data is stored in CloudKit's public database where appropriate.
- **Privacy first.** Location history stays on-device. CloudKit should not receive a user's continuous movement history.
- **Open-data friendly.** Canonical POIs should keep source/provenance and attribution metadata.
- **Human feedback improves ranking.** Visitors can vote whether a place was actually worth visiting.
- **Interests influence, but do not create a filter bubble.** User interests boost relevant discoveries without hiding everything else.

## Core experience

### Nearby discovery

The app shows curated discoveries around the user's current location as a map and list. Results are ranked by a discovery score rather than simple distance or review count.

Examples include:

- unusual natural formations
- national/state parks and reserves
- waterfalls, caves, glaciers and geological features
- museums with a distinctive collection or story
- historic or industrial structures
- architecture and engineering landmarks
- archaeological sites
- viewpoints and scenic locations
- culturally significant places
- unusual restaurants or cafés that are destinations in their own right
- small, easily missed places that are genuinely worth a detour

### Trip discovery

Users can create a trip with one or more destinations. MapKit provides routing. TravelPlaner then finds discoveries within a configurable route corridor and estimates their detour cost.

A result should communicate why it matters:

> **Worth a 9-minute detour**  
> Historic ship lift · Engineering · Industrial heritage

The route ranking should consider:

- uniqueness/notability
- user interest match
- community “worth visiting” votes
- detour time/distance
- likely visit duration
- accessibility/relevance to the trip
- source quality and confidence

### Interests

Users can choose interests such as:

- nature
- geology
- hiking
- architecture
- engineering
- aviation
- railways
- maritime
- history
- archaeology
- art
- science
- technology
- food
- unusual/quirky places
- family-friendly discoveries

Interests boost ranking but should never exclude all discoveries outside the selected topics.

## Architecture

### App

Target a modern iOS/iPadOS version and use Swift 6 with strict concurrency.

Suggested high-level modules:

```
TravelPlaner
├── App
├── Models
├── Persistence
├── CloudKit
├── Discovery
├── Location
├── Trips
├── Map
├── Voting
├── Interests
├── Suggestions
└── SharedUI
```

Use protocol-backed services so CloudKit, MapKit, Core Location and data-source behavior can be tested independently.

### Local persistence

Use SwiftData for user-owned/local data:

- trips
- saved discoveries
- preferences and interests
- cached POI snapshots
- locally observed visit eligibility
- dismissed/recently shown suggestions
- route/search state where useful

Location history must not be uploaded as a general-purpose log.

### CloudKit

Use the app's **CloudKit public database** for shared records. Public records are suitable for common POIs and community contributions. The app must be designed around CloudKit security rules and ownership semantics rather than assuming a trusted custom backend.

Proposed record types:

#### `Place`

Canonical curated discovery.

Fields should include:

- stable internal UUID
- name
- localized/alternate names where available
- latitude/longitude
- optional bounding region/radius for large destinations
- category and interest tags
- place kind: `detourStop`, `dayTrip`, `majorDestination`, `remoteDestination`
- short editorial reason to visit
- source/provenance records
- Wikidata Q-ID
- OpenStreetMap type/id when applicable
- Wikipedia/Wikivoyage identifiers when applicable
- Apple Place ID when legitimately obtained and useful for live lookup
- image metadata/attribution references
- estimated visit duration
- base notability/uniqueness score
- moderation/version fields
- created/updated timestamps

#### `PlaceVote`

One user's assessment of one place.

Fields:

- place reference
- voter pseudonymous CloudKit identity key
- vote: worth visiting / not worth visiting
- verification type
- coarse verification confidence
- creation date
- optional visit month/year, not precise location history

Use a deterministic record identity where feasible so one account has at most one current vote per place.

#### `PlaceSuggestion`

A user-submitted candidate place.

Fields:

- proposed name
- coordinate
- category/tags
- reason it is special
- optional public source URLs/IDs
- creator
- status metadata suitable for moderation workflow

User suggestions must never automatically become trusted canonical places solely because they were submitted.

### CloudKit limitation: no trusted server

Without a server, the client cannot make “was physically there” impossible to fake. The app should therefore use **best-effort visit verification**, be transparent about that limitation, and avoid collecting invasive location history.

The app should also avoid any CloudKit permission design where ordinary users can edit canonical POIs created by other users.

## POI data strategy

TravelPlaner should not build its database by scraping commercial map/review services.

Preferred source layers:

1. **Wikidata** — identity, classifications, notability, relationships and external IDs.
2. **OpenStreetMap** — coordinates, geometry, physical/natural features and detailed tags.
3. **Wikimedia Commons** — appropriately licensed images and attribution metadata.
4. **Wikipedia/Wikivoyage** — contextual/notability signals and links; preserve applicable license obligations.
5. **Official open tourism datasets** — when licensing permits commercial redistribution.
6. **MapKit / Apple Maps** — runtime map, route, ETA and live place lookup where permitted; do not use it as the source for an independently stored bulk POI database.

### No server ingestion

Initial POIs should be produced by a **developer-side import tool** run locally during development/release preparation:

```
Open data dumps/APIs
        ↓
Local importer / normalizer
        ↓
Validation + deduplication
        ↓
Versioned seed dataset
        ↓
Developer-only CloudKit seeder
        ↓
CloudKit Public Database
        ↓
iOS app
```

The production iOS app should not crawl Wikidata or OpenStreetMap globally.

The importer must retain per-field/source provenance and licenses so attribution and future updates remain possible.

### Place scoring

Keep the score explainable. A starting model:

```
discoveryScore =
    baseNotability
  + uniqueness
  + sourceConfidence
  + interestBoost
  + communityVoteSignal
  + routeRelevance
  - detourPenalty
  - fatigue/repetitionPenalty
```

Do not optimize for raw popularity. The app should be able to prefer a unique small museum or geological feature over a more-reviewed generic attraction.

## Location and visit verification

Use Core Location conservatively.

### Browsing

- Request When-In-Use authorization first.
- Use one-shot/current location when the user explicitly asks for nearby discoveries.
- Do not require Always authorization for basic app functionality.

### Optional travel companion mode

Users may explicitly enable a location-aware travel mode.

Use power-efficient APIs and only escalate accuracy when necessary. Potential tools include:

- `CLLocationUpdate`
- significant-location-change monitoring
- visit monitoring
- `CLMonitor`/geographic conditions for a limited set of high-value nearby places
- `CLBackgroundActivitySession` only when a user-facing feature genuinely requires live background updates

Respect the system limit on monitored geographic conditions and dynamically monitor only the most relevant nearby places.

### Eligibility to vote

A vote becomes eligible when at least one local verification path succeeds, for example:

1. **Currently there:** the user is within an appropriate radius and location accuracy is sufficient.
2. **Observed visit:** the app previously recorded a local visit/proximity event near the place.
3. **Trip evidence:** while an explicitly active trip was running, trusted Core Location samples showed presence near the discovery.

Store eligibility locally in SwiftData. Do not upload a user's movement trace.

For very large destinations (for example national parks or islands), use a destination-specific polygon/region or larger verification radius. For small POIs, use a tighter radius.

The CloudKit vote can include only coarse metadata such as `verificationType` and `confidence`.

## Voting

The app should ask a simple question:

> Was this place worth visiting?

Possible initial choices:

- 👍 Worth visiting
- 👎 Not worth it

Requirements:

- only verified visitors can vote
- one active vote per iCloud account/place
- users can change their vote
- aggregate results are shown only after a minimum vote threshold to reduce misleading tiny samples
- ranking should use a Bayesian/confidence-aware signal rather than raw percentage
- a place with no votes must not be treated as poor quality

## Suggestions and moderation

Users should be able to suggest a missing discovery, particularly small local places that open datasets miss.

Because there is no trusted application server:

- suggestions are separate from canonical `Place` records
- submitting a suggestion does not publish it as trusted POI content
- the developer/editor workflow promotes approved suggestions into canonical POIs
- canonical records remain protected from arbitrary client edits

A developer utility may inspect pending suggestions and create/update approved canonical records using the developer's authenticated CloudKit environment.

## Map and trip model

Use MapKit for:

- map rendering
- search for user-entered trip destinations
- routes and alternate routes
- travel time
- detour calculations
- opening destinations/routes in Apple Maps where appropriate

The discovery engine should query POIs around:

- current visible map region
- current location
- trip destinations
- a route corridor

For route discovery, avoid calculating a full alternate route for every POI immediately. Use staged filtering:

1. bounding/corridor geographic filter
2. approximate distance-to-route
3. discovery score
4. calculate real MapKit detour ETA only for top candidates

This keeps the UI responsive and reduces MapKit work.

## Background behavior

TravelPlaner should remain useful without continuous GPS.

When travel companion mode is enabled:

- fetch candidates ahead of movement
- monitor only a small rotating set of high-ranked discoveries
- use local notifications to surface exceptional nearby places
- throttle repeated hints
- never notify for every POI
- respect Focus, notification permission and the user's quiet preferences

A typical hint:

> **Something unusual is 8 minutes away**  
> Historic observatory — one of only three surviving examples of its type.

## Offline behavior

Trips often have poor connectivity.

Cache:

- currently relevant POIs
- saved trip POIs
- lightweight images where licensing/storage permits
- route discovery metadata
- vote aggregate snapshots

Do not promise full offline MapKit routing unless the platform API supports the required experience.

## Privacy

Principles:

- no custom analytics backend required for core operation
- no sale of location data
- no continuous location history in CloudKit
- local visit proof remains local
- upload only the minimum data required for shared votes/suggestions
- explain why Always/background location permission is useful before requesting it
- core map/trip browsing works with When-In-Use authorization

## Initial milestone

The first usable milestone should demonstrate the entire vertical slice:

1. launch native SwiftUI app
2. load curated POIs from CloudKit public DB
3. show them on a MapKit map and in a list
4. support interests
5. create a trip and route
6. rank POIs around the route
7. calculate detour time for top candidates
8. locally verify that a user visited a POI
9. allow an eligible visitor to vote
10. sync/show aggregate vote information

Only after that vertical slice should the project broaden data ingestion and background discovery.

## Development order

Implementation is tracked in GitHub Issues. Issues explicitly state dependencies so multiple coding agents can work without stepping on unfinished foundations.

## Example target places

The data model should comfortably represent:

- Lençóis Maranhenses National Park
- Antelope Canyon
- Sequoia National Park
- Socotra
- Marble Caves
- Taylor Glacier
- Vinicunca / Rainbow Mountain

These examples intentionally cover single POIs, large protected areas, remote destinations and alias-heavy places.

## License

Add the application license before public release. Third-party/open-data attribution requirements are separate from the source-code license and must be preserved in the app and data pipeline.
