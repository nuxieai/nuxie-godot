# Version Matrix

| Nuxie Godot | Godot | Android SDK | iOS SDK |
| --- | --- | --- | --- |
| `0.3.0` | `4.5.1` | `ai.nuxie:nuxie-android:0.1.0` | `nuxie-ios` revision `19e9e56c572c96977af978f87de91828f74ea86d` |

The wrapper uses exact native dependency versions. Android local validation may supply the same coordinate through `NUXIE_ANDROID_MAVEN_REPO` or substitute an exact source checkout through `NUXIE_ANDROID_SOURCE_DIR`. iOS remains pinned to an immutable revision until the hard-cut native SDK is tagged; release metadata must retain the canonical `https://github.com/nuxieai/nuxie-ios.git` location and `nuxie-ios` identity.
