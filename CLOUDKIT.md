# CloudKit deployment checklist

TravelPlaner uses the public database of `iCloud.de.holgerkrupp.travelplaner`.

## Record types

- `Place`: canonical source-backed discoveries. The record name is a deterministic SHA-256 digest of the first stable source key (`source:externalID`), so independent clients converge on one record without identifier-character collisions.
  Source freshness (`sourceUpdatedAt`) and the producer's `discoveryVersion` travel with each source reference for local revalidation and migration.
  The legacy single-source fields remain queryable; `sourcesJSON` preserves the complete provenance array.
- `PlaceVote`: one record per account/place. The record name is SHA-256 of the account key and Place UUID. Only coarse verification metadata is stored.
- `PlaceSuggestion`: untrusted user proposals. These are never read as canonical Places and require developer moderation.

## Development setup

1. Enable iCloud/CloudKit for the application identifier `de.holgerkrupp.travelplaner`.
2. Add the container identifier from `TravelPlaner/TravelPlaner.entitlements` to the app target and development environment.
3. Deploy the `Place`, `PlaceVote`, and `PlaceSuggestion` record types to the development schema before using live discovery.
4. Add query indexes for `Place.stableID`, `Place.latitude`, `Place.longitude`, `Place.source`, `Place.externalID`, `PlaceVote.placeID`, and `PlaceSuggestion.status`.
5. Verify public read access and authenticated create access. Do not grant ordinary clients update/delete access to records owned by other users.
6. Promote the schema only after the mapping and conflict tests pass.

## Development, seeding, and promotion

The development environment is the only environment used by local builds. Never reset
or seed production from a workstation.

1. Authenticate `cktool` with a short-lived CloudKit management token. Store it in the
   local keychain or `~/.config/cktool`; never put it in the repository or shell history.
2. Import or create the `Place`, `PlaceVote`, and `PlaceSuggestion` record types and
   their indexes in development.
3. Validate the schema and export a copy for review:

   ```sh
   xcrun cktool validate-schema --team-id <TEAM_ID> --container-id iCloud.de.holgerkrupp.travelplaner --environment development --file schema.json
   xcrun cktool export-schema --team-id <TEAM_ID> --container-id iCloud.de.holgerkrupp.travelplaner --environment development --output-file schema-export.json
   ```

4. Seed only a small representative set of source-backed Places. Use the stable
   source-derived record identity and the same fields emitted by
   `CloudKitPlaceRecordMapper`; do not seed user suggestions as canonical Places.
   `cktool create-record` accepts a JSON fields file and writes to the public
   database when `--database-type public` is selected.
5. Run the full simulator suite against development, verify CloudKit reads and
   conflict behavior, and promote the reviewed schema through CloudKit Dashboard.
   Production promotion is a one-way release operation and must be performed by an
   authorized project owner.

The repository intentionally does not contain a management token or an unreviewed
schema export. A local machine without a CloudKit management token can still build,
test all mapping behavior, and use bundled/cached discoveries, but cannot perform
the deployment or seed step.

## Source attribution checklist

Before publishing a source-backed Place:

- retain the source family and stable external ID;
- retain the source URL, source freshness, license, and creator/attribution fields;
- retain every independent source reference in `sourcesJSON`;
- retain per-image license, creator, and source URL metadata;
- verify that redistribution is permitted by the source license;
- show the applicable attribution in the Place detail UI;
- do not copy restricted commercial map/review content into the canonical record.

The app remains usable without an iCloud account: CloudKit failures leave locally discovered and cached Places visible, while publication and vote/suggestion writes are deferred or rejected without blocking browsing.

## Local cache policy

SwiftData place snapshots are retained for 30 days, refreshed when the same context is used, and evicted before reads/writes once older than that window. Cached vote aggregates are replaced by newer snapshots and remain timestamped so the UI can distinguish a locally restored value from a fresh CloudKit result. No continuous location history is cached.

The local model container is backed by `TravelPlanerSchemaV1` and `TravelPlanerMigrationPlan`; future schema changes must add a new version and explicit migration stage rather than silently changing stored fields.
