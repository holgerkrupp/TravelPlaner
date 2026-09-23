# TravelPlaner privacy inventory

This document describes the data handled by the current first vertical slice.

## On-device data

- Trips, ordered stops, selected interests, saved Places, cached Place snapshots, cached vote aggregates, locally submitted suggestion status, and visit-eligibility evidence are stored in the app's SwiftData store.
- Visit evidence retains only the Place ID, observation time, distance, accuracy, and an expiry. It is not a movement history.
- Nearby discovery uses a one-shot When In Use location request only after the user chooses “Near me”, map-region discovery, or voting. Location is not collected continuously for basic browsing.
- Cached Place snapshots are evicted after 30 days. No analytics identifier or advertising profile is created.

## CloudKit data

- Public `Place` records contain source-backed POI data and provenance so devices can share a cooperative cache. They do not contain user movement.
- `PlaceVote` contains the Place ID, vote value, verification type, optional coarse visit month, and update time. The record name is a one-way account/place key and no public UI exposes the account identity.
- `PlaceSuggestion` contains the user-provided candidate details and moderation status as a separate, untrusted record type. It is never treated as a canonical Place without developer review.
- Publishing and voting require an authenticated iCloud account. Public Place reads and local browsing remain useful without one.

## Permissions and sharing

- The app requests When In Use location permission in context and does not request Always permission for the basic vertical slice.
- Local notifications are requested only after the user enables travel-companion hints.
- CloudKit public records are subject to the deployed container's schema and security permissions described in `CLOUDKIT.md`.
- Users can use the app without granting location permission; map/list browsing, interests, saved Places, and trip editing remain available.
