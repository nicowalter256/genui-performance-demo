# GenUI Performance Demo

The demo app for **"When the AI Builds the Widget Tree"** (FlutterBytes 2026).

It's one screen, a weekend trip planner built with the GenUI SDK, that can run in two modes:

| | Naive | Optimised | Slide |
| --- | --- | --- | --- |
| Catalog | Every basic widget + 7 unused shop widgets, long descriptions | Only what the trip screen needs, short descriptions | Fix 2 |
| Streaming | Waits for the whole model response | Hands each chunk to GenUI as it arrives, shows a skeleton, asks the model to send the UI in small steps | Fix 1 |
| Rebuilds | `UniqueKey` around every component, so it's thrown away on every update | `ValueKey(component id)` + `DataMemo` (rebuild only when that component's data changes) | Fix 3 |
| Layout | Eager `Row` of every place, 2400×1600 photos decoded into 180×110 tiles | Capped at 12, lazy `ListView.builder`, fixed height, `cacheWidth` | Fix 4 |

A built-in metrics panel records the numbers for the "Before → after" slide.

## 1. Set up (once)

You need Flutter **3.35.7 or newer** (3.38+ recommended) and a Gemini API key from [Google AI Studio](https://aistudio.google.com/app/apikey).

```bash
cd genui_perf_demo
flutter create --platforms=android,ios --project-name genui_perf_demo .
rm test/widget_test.dart        # the generated test refers to a counter app that doesn't exist
flutter pub get
```

`flutter create .` only adds the missing platform folders. It doesn't touch the files in `lib/`.

**Android: allow internet in profile/release builds.** Open `android/app/src/main/AndroidManifest.xml` and add this line above `<application`:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

Without it, the app works in debug mode but every request fails in profile mode.

## 2. Run it

Always measure in **profile mode on a real phone**, with the performance overlay **off** (the overlay itself costs raster time) (debug-mode numbers are meaningless):

```bash
flutter run --profile --dart-define=GEMINI_API_KEY=YOUR_KEY
```

Optional `--dart-define`s:

- `GEMINI_MODEL=...`: the Gemini model (default `gemini-3-flash-preview`)
- `DEMO_PROMPT=...`: the prompt pre-filled in the text box (default: a 2-day weekend in Kampala)

## 3. Use it on stage

The app bar has:

- **Naive / Optimised** switch: starts a fresh conversation in that mode.
- **Speedometer**: Flutter's performance overlay (the red/green frame bars).
- **Chart icon**: the metrics panel.
- **Refresh**: a fresh conversation in the same mode.

Suggested flow:

1. Opening demo (slide 3): **Naive**, overlay on, metrics panel hidden. Tap send and let the audience watch the blank wait and the jank.
2. After Fix 1 (slide 10): switch to **Optimised**, send the same prompt. The header appears first, then the days fill in, and the overlay stays calmer.

Record a screen capture of both before the talk, in case the Wi-Fi or the API lets you down.

## 4. Collect the numbers for slide 17

1. Open the metrics panel and tap **Reset**.
2. In **Naive**: tap Refresh, send, then wait until the panel title goes back from "Recording…" to "Averages" (about 1.5 seconds after the response finishes). Repeat 5 times.
3. Do the same in **Optimised**. For fairer numbers, alternate modes (naive, optimised, naive, …), because network and model latency vary from minute to minute.
4. Tap the **copy** icon: a Markdown table of the averages goes to the clipboard.

What each number means:

| Metric | Measured from → to | Slide tile |
| --- | --- | --- |
| Prompt tokens (est.) | System prompt characters ÷ 4 (an estimate; check your provider's usage dashboard for exact numbers) | Prompt tokens |
| First token | Send → first chunk from the model | (mostly network + model) |
| Prompt → first frame | Send → first frame showing a real trip component | Prompt → first frame |
| Stream done | Send → last chunk | (about the same in both modes) |
| Widget builds | `build()` calls of the trip widgets during the run | Rebuilds per update |
| Widget remounts | Trip widgets thrown away and created again | Rebuilds per update |
| Janky frames | Frames whose build or raster phase went over 16.7 ms, from the first trip component until 1.5 s after the stream ends (the waiting spinner isn't counted) | Janky frames |
| Worst frame | The slowest single frame in that same window | (good for the Fix 4 story) |

Use only the numbers you actually measure. Stream-done time is usually about the same in both modes, and that's the point of Fix 1: the total wait doesn't change, but the user sees something much sooner.

## 5. DevTools

The app adds Timeline events you can find in the DevTools Performance view:

- `genui.send`, `genui.firstToken`, `genui.firstFrame`, `genui.streamDone`: instant markers for each stage
- `genui.applyMessage`: the time spent applying each A2UI message to the surface

## Code map

```
lib/
  main.dart                  screen, mode switch, overlay, skeleton
  planner_session.dart       model ↔ GenUI wiring; streaming vs buffering (Fix 1)
  ai_client.dart             Gemini through dartantic_ai
  metrics.dart               timings, build/mount counters, frame timings
  metrics_panel.dart         the on-screen table + copy to Markdown
  catalog/trip_catalog.dart  naive vs optimised catalog items (Fixes 2–4), DataMemo
  catalog/trip_widgets.dart  shared leaf widgets that count their builds/mounts
  catalog/shop_catalog.dart  unused widgets that bloat the naive prompt
  config.dart                API key, model, demo prompt
```

## Notes and caveats

- **I couldn't compile this.** It was written against the `genui` 0.10.6 source on GitHub (October 2026). If something doesn't compile, the likely cause is an API difference in whichever 0.10.x version pub resolves. Pinning `genui: 0.10.6` in `pubspec.yaml` usually fixes that. The places that touch the GenUI API are `planner_session.dart`, `main.dart` (the `Surface` widget) and `catalog/trip_catalog.dart`.
- `genui` is alpha. Its README says it's being redesigned into new packages (`a2ui_core`, `a2ui_agent`, `a2ui_flutter`) with a different API. Say which version you used on a slide.
- Photos come from picsum.photos, seeded by a word the model chooses, so the model never makes up image URLs.
- Not built into the app: parsing on a background isolate (the GenUI adapter parses internally) and event debouncing. Both are in the talk as patterns only.
