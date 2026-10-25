# Send Family Updates through the user's own Shortcuts automation

Family and friends of the person scanning want to know how they are each day without asking. The
app exposes a single App Intent, Get Today's Family Update, that returns the day's Family Update as
plain text. The user, or someone helping them, builds a daily Time of Day automation in Shortcuts
that passes it to Send Message. The app itself never sends anything.

We considered writing Perceived Recovery to Apple Health as State of Mind and relying on Health
Sharing. It is the more integrated route, but HealthKit is not available to a Personal Team, the
Sleep Prediction has no Health type, invented sleep times would pollute Health's sleep record, and
Health Sharing hides State of Mind notes and has nowhere for Journal factors or medicines. A
backend that texts or emails family was rejected because it would move Journal Entries off the
phone to a server we run, against ADR 0003's no-backend stance.

## Consequences

Family Updates are off until the user turns them on, and the switch is checked every time the
intent runs, so turning it off in Settings stops every automation at once. The intent runs without
opening the app, so the PIN lock does not apply to it; the switch is the control instead.

A Family Update includes the Daily Sleep Prediction, Perceived Recovery and sleep by default;
Journal factors and medicines only when chosen. Photos and notes are never included, whatever the
settings. While Baseline Forming, no number is sent, because a provisional value read cold by a
relative is more likely to alarm than inform.

Only today is ever described, since that is the only day an automation asks for. A missing photo
is reported rather than skipped: for someone checking on an older relative, no photo by mid-morning
is itself worth knowing.
