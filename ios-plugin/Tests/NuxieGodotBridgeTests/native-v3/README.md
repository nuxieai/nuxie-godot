# Native v3 adapter fixtures

These four exact profiles derive from the pinned iOS SDK's
`fixtures/journeys/planes/release.json` at
`28587b9b8e0c1fbcb012ebdff9645626706adcb8`. They use the public development
Ed25519 test key derived from the explicit `[0x42; 32]` seed. No production key
or verification bypass participates.

The signed screenless Journey receives `wrapper_v3_probe` through the shipped
adapter and projects typed number, string and Boolean event values into its
completion report. The independent expected output is
`{"event":{"probeNumber":42,"probeText":"native-v3-wrapper","probeBoolean":true},"responses":{}}`.
The adapter must forward `journey_started` then `journey_completed`, with one
matching generated Journey UUID, generation 0, and outcome `continue`.

`retired-v1.json` and `retired-v2.json` have valid signatures under the current
v3 domain, isolating schema rejection from signature rejection.
`wrong-domain.json` carries the same valid v3 descriptor as `accepted.json`,
but its genuine signature uses the retired v2 domain. Native authentication must
fail before any authoritative feature publication or Journey activity. Tests
require the native `JourneyReleaseAuthenticationError` unified log, successful
profile transport and working ordinary event ingest, alongside absence of
Journey events.

These exercise actual native admission, Journey and bridge activity/event
behavior. The public adapter does not expose form editing or live run values;
these cases do not qualify rendered text input, devices or licensed editors.

| Profile | SHA-256 |
| --- | --- |
| accepted.json | `52fc6361719faa0d004726d2a274493950d00a03113ce53406ce4142414213d2` |
| retired-v1.json | `a84d369e85e6cc43519d9ee309c9071a0dd6eeb910f611031aaa227af5753630` |
| retired-v2.json | `2d16f8481b5fcbb8bbcc7a9acd326dda847aa079ccb6716b407d074fd29ee743` |
| wrong-domain.json | `45cd397c331299c9f15be40f6921f53b974c9844be8296c8d25274129b662b68` |
