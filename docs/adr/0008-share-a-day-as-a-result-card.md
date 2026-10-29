# Share a day as a Result Card through the iPhone share sheet

People want to post or send a day's reading the way they share a workout: a picture, through
whatever app they already use. A day with a real Daily Sleep Prediction now has a Share button.
It opens a preview of the Result Card, a 1080 × 1350 picture of the number, its band, the
comparison with the average night and the three Contributions that moved it most. The system share
sheet then offers Messages, Mail, WhatsApp, Instagram, Save Image and the rest. A short line of
text goes with it for apps that take text.

We considered sharing plain text only, like a Family Update. It works everywhere, but it is not
what people mean by sharing a post, and a picture carries the ring and the reasons at a glance. We
also considered `UIActivityViewController` with a temporary file, as Export does (ADR 0007). The
card is rendered in memory and handed over as an image, so there is no file of ours to delete, and
`ShareLink` is enough.

## Consequences

The photo is off the card by default and is included only when the user switches it on. That
choice is remembered. Journal answers, medicines and notes are never on the card, whatever the
settings: a post can travel much further than a message to family.

While Baseline Forming there is no Share button, for the same reason no number goes out in a Family
Update (ADR 0006): the value is the average night, not a reading, and someone seeing it cold would
take it as one. Unusable and unread days cannot be shared either.

The card is always drawn in light mode, at one text size, so it looks the same to whoever receives
it. Once shared, the picture is outside the app's control. The preview shows exactly what will be
sent before anything leaves the phone.
