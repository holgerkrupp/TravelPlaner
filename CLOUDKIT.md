# CloudKit deployment checklist

TravelPlaner uses the public database of `iCloud.de.holgerkrupp.travelplaner`.

## Record types

- `Place`: canonical source-backed discoveries. The record name is derived from the first stable source key (`source:externalID`), so independent clients converge on one record.
  Source freshness (`sourceUpdatedAt`) and the producer's `discoveryVersion` travel with each source reference for local revalidation and migration.
- `PlaceVote`: one record per account/place. The record name is SHA-256 of the account key and Place UUID. Only coarse verification metadata is stored.
- `PlaceSuggestion`: untrusted user proposals. These are never read as canonical Places and require developer moderation.

## Development setup

1. Enable iCloud/CloudKit for the application identifier `de.holgerkrupp.travelplaner`.
2. Add the container identifier from `TravelPlaner/TravelPlaner.entitlements` to the app target and development environment.
3. Deploy the `Place`, `PlaceVote`, and `PlaceSuggestion` record types to the development schema before using live discovery.
4. Add query indexes for `Place.latitude`, `Place.longitude`, `Place.source`, `Place.externalID`, `PlaceVote.placeID`, and `PlaceSuggestion.status`.
5. Verify public read access and authenticated create access. Do not grant ordinary clients update/delete access to records owned by other users.
6. Promote the schema only after the mapping and conflict tests pass.

The app remains usable without an iCloud account: CloudKit failures leave locally discovered and cached Places visible, while publication and vote/suggestion writes are deferred or rejected without blocking browsing.

## Local cache policy

SwiftData place snapshots are retained for 30 days, refreshed when the same context is used, and evicted before reads/writes once older than that window. Cached vote aggregates are replaced by newer snapshots and remain timestamped so the UI can distinguish a locally restored value from a fresh CloudKit result. No continuous location history is cached.
