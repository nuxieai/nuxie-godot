# Version Matrix

## Current mapping

| nuxie-godot | Android native SDK | iOS native SDK |
| --- | --- | --- |
| `0.1.0` | `io.nuxie:nuxie-android:0.0.1` (or local `:nuxie-android-sdk` when linked) | `nuxie-ios` `main@7b75d5042353786b597f199590ae8f6516228226` |

## Notes

- Android build will use local checkout modules when `../nuxie-android` exists:
- `:nuxie-core`
- `:nuxie-android-sdk`
- iOS dependency pin is tracked in `ios-plugin/Package.resolved`.
- Update this file whenever wrapper behavior changes or native SDK refs move.
