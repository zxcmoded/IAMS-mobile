---
name: android-agp9-builtin-kotlin-blocker
description: Why share_plus/file_picker can't be bumped past the versions that still self-apply KGP, and what would need to change to lift the block
metadata:
  type: project
---

The Android build is pinned to AGP 9.0.1 (`android/settings.gradle.kts`) with the Flutter
template's interim flags in `android/gradle.properties`: `android.newDsl=false`,
`android.builtInKotlin=false`. This combination only works as long as *every* plugin with Kotlin
sources still unconditionally applies `org.jetbrains.kotlin.android` itself (the old pre-AGP9
pattern) — this repo is NOT on AGP 9's built-in-Kotlin compilation path.

**Why:** newer plugin releases increasingly gate their own KGP self-application on
`ANDROID_GRADLE_PLUGIN_VERSION >= 9` (assuming the *host* project has migrated to built-in
Kotlin). Once a plugin does that gate check and skips applying KGP, and our `builtInKotlin=false`
means AGP itself also doesn't compile Kotlin for that module, the module's Kotlin sources
silently fail to compile (manifests as "Unresolved reference" inside the plugin's own sibling
files, or as `GeneratedPluginRegistrant.java: cannot find symbol <PluginClass>` — the class never
got built at all). Confirmed this exact failure with `share_plus` >=13.2.0 (needs the AGP9 gate
to drop its own KGP — this is also the fix for the "plugins that apply KGP" warning) and with
`file_picker` >=11.0.0 (same gate introduced there too).

Flipping `android.builtInKotlin=true` to give AGP9 built-in Kotlin compilation to those
gated plugins in turn breaks `connectivity_plus` (pinned `^7.3.1`, **already latest** — no newer
version exists to fix this): Flutter's own Gradle tooling fails to evaluate `:connectivity_plus`
under `builtInKotlin=true` with "the 'org.jetbrains.kotlin.android' plugin is no longer required
... since AGP 9.0" even though `connectivity_plus`'s own `build.gradle` never applies that plugin
itself — this looks like a Flutter-injected compatibility shim for old-style plugins, not
something fixable by touching `connectivity_plus`'s pubspec constraint.

**How to apply:** don't attempt to silence the "plugins that apply Kotlin Gradle Plugin (KGP)"
warning by bumping `share_plus`/`file_picker` alone — anything >= the version that drops KGP
self-application requires `android.builtInKotlin=true`, which is currently blocked by
`connectivity_plus`. Revisit when either (a) `connectivity_plus` ships a built-in-Kotlin-safe
release, or (b) someone deliberately works out a per-subproject KGP-application workaround in
`android/app/build.gradle.kts` (e.g. an `allprojects`/`subprojects` block that explicitly applies
`org.jetbrains.kotlin.android` only to modules that still need it) and accepts the added
complexity. Until then, the ceiling versions that still build clean are `file_picker: ^10.3.10`
(NOT 10.3.11 — that specific patch is retracted on pub.dev) and `share_plus: ^10.1.4`; both still
trigger the KGP warning but the build succeeds. See [[toolchain-broken-xcode]] for the unrelated
broken-Xcode workaround needed to run any of this tooling on this dev machine.
