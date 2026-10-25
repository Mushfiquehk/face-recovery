# Lock photos with the phone, keep the store readable, delete exports after sharing

Face Scan photos are written with `NSFileProtectionComplete`, so they cannot be read whenever the
phone is locked. Photos saved before this are raised to the same class at launch. Photos are only
ever read on screen or by Export, both of which need the phone unlocked, so this costs nothing.

The SwiftData store, which holds Journal Entries with medicines and notes, keeps the system default
(`completeUntilFirstUserAuthentication`). We considered locking it the same way, but the Family
Update intent (ADR 0006) reads it from a Time of Day automation that usually runs on a locked phone,
and under complete protection that automation would fail. Until the first unlock after a restart the
store is still unreadable.

Both stay in the phone's iCloud or Finder backups. A Personal Team has no CloudKit, so a backup is
the only copy besides Export, and excluding them would make a lost phone a lost dataset. Users should
keep Finder backups encrypted, and Advanced Data Protection on if they want iCloud backups
end-to-end encrypted.

An export is every photo and Journal Entry as plain files. It is now built only when the user taps
Share and deleted as soon as the share sheet closes, whether or not anything was shared. Any export
folder left in the temporary directory by a crash is removed at the next launch.

## Consequences

`ShareLink` gives no signal when its sheet closes, so Export presents `UIActivityViewController`
itself. A cancelled share means rebuilding the export next time, which is a few seconds of copying.
Anything that later needs photos while the phone is locked, such as a background re-measure, must
revisit this decision rather than lower the class quietly.
