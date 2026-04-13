# React Native + Expo Research Notes (SDK 55)

## Ground truth (confirmed)
- Expo SDK 55 released Feb 2026. React Native 0.83. React 19.2. Node 20.19+.
- New Architecture is DEFAULT; Legacy Architecture DROPPED.
- Expo Router v7 ships with SDK 55.
- 75% smaller OTA updates via Hermes bytecode diffing.
- Min OS: Android 7+, iOS 15.1+.

## Topic 1: Project structure & config

### app.json vs app.config.ts
- Static (app.json): CLI tools can auto-update it.
- Dynamic (app.config.ts): env-based switching, imports, autocomplete via types.
- Rule: use app.config.ts when you need per-env values (dev/staging/prod bundle IDs, icons, API URLs).

### Env vars
- `EXPO_PUBLIC_*` prefix: statically inlined at build via `process.env.EXPO_PUBLIC_FOO` dot notation.
- Bracket notation (`process.env['EXPO_PUBLIC_FOO']`) does NOT inline. Gotcha.
- EXPO_PUBLIC_ is visible in compiled bundle — NEVER secrets.
- Secrets: EAS Secrets, referenced in eas.json build profiles, never shipped to client.

### Config plugins
- Extend native config without ejecting. Required for libraries that need native changes in managed workflow.
- Runs during `expo prebuild` (which EAS Build runs server-side). User never touches ios/android dirs.

### Managed workflow constraint
- Never check in `ios/` or `android/` directories. If a library docs say "edit Info.plist", look for a config plugin or find a replacement.

### Pending / TODO for this topic
- [ ] package manager: pnpm vs bun vs npm — what does EAS support best?

## Topic 2: expo-router v7 navigation

### File-based routing basics
- `app/` dir = routes. Files auto-become screens. Auto deep-linking.
- `_layout.tsx` = layout for a segment (wraps children).
- `(group)` = logical grouping, doesn't affect URL. Useful for `(auth)` vs `(app)` splits.
- `[id].tsx` = dynamic segment. `[...slug].tsx` = catch-all.
- `index.tsx` = default route for a segment.

### Stack (default)
- Default `<Stack />` wraps React Navigation Native Stack → uses native UINavigationController (iOS) and Fragment-based nav (Android).
- Native stack = platform-correct push animations automatically (slide-right iOS, slide-up Android).
- Fall back to JS stack only if you need custom transitions the native stack can't do.

### Screen options
- Configure via `<Stack.Screen name="x" options={{...}} />` (parent) or `<Stack.Screen options={{...}} />` inside the child (dynamic, per-render).
- iOS-specific: `headerLargeTitle`, `headerBlurEffect`, `headerSearchBarOptions`, `fullScreenGestureEnabled`.
- Presentation modes: `modal`, `formSheet` (iOS sheet), `transparentModal`, `fullScreenModal`.

### Typed routes
- Enable: `experiments.typedRoutes: true` in app.json (still gated behind experiments as of SDK 55).
- Auto-generates `.expo/types/router.d.ts` on `expo start`.
- `<Link href="/posts/123" />` is statically typed — invalid routes fail type check.
- Query params: manual — pass generic to `useLocalSearchParams<{ q: string }>()`.
- Gotcha: typed routes gen has had flakiness historically; commit the generated types or regen in CI.

### Hooks
- `useRouter()` — imperative `router.push()`, `router.replace()`, `router.back()`.
- `useLocalSearchParams()` — params for this route only.
- `useGlobalSearchParams()` — params from any route; re-renders on any change (perf trap).
- `useSegments()` — current URL segments as array; use for auth redirects in root layout.
- `useFocusEffect` from expo-router — run effect when screen focused (not just mounted).

### Auth pattern
- Put auth check in root `_layout.tsx`.
- Use `useSegments()` to know if user is in `(auth)` or `(app)` group.
- Use `<Redirect href="..." />` component for declarative redirects during render.

## Topic 3: Animations & gestures

### Reanimated 4 (SDK 55 default)
- Ships with SDK 55. Requires New Architecture (which is now default).
- `react-native-worklets` is a separate dep; `babel-preset-expo` auto-configures the plugin. DON'T manually add `react-native-worklets/plugin` to babel.config.js — duplicate plugins break things.
- Core APIs:
  - `useSharedValue(initial)` — mutable value on UI thread, `.value` read/write, no re-render.
  - `useAnimatedStyle(() => ({ transform: [{ translateX: sv.value }] }))` — worklet that returns style, runs on UI thread.
  - `withTiming(to, { duration })`, `withSpring(to, { damping, stiffness })`, `withSequence(...)`, `withRepeat(...)`, `withDelay(...)`.
  - `interpolate(value, [inputs], [outputs], Extrapolation.CLAMP)`.
  - `useDerivedValue(() => ...)` — computed shared value.
  - `runOnJS(fn)(args)` — call JS from worklet (e.g., navigate, setState). Required when crossing thread boundary.
  - `runOnUI(fn)()` — call worklet from JS imperatively.

### Reanimated 4 CSS-style animations (new)
- `transitionProperty: 'opacity'`, `transitionDuration: '300ms'` directly on style.
- Use CSS transitions for the 80% state-driven case. Use worklets (useSharedValue + withTiming) for the 20% needing frame-level control.

### Layout animations
- Entering: `<Animated.View entering={FadeIn.duration(300)} />` — runs when mounted.
- Exiting: `exiting={FadeOut.duration(200)}` — runs before unmount.
- Layout: `layout={LinearTransition.springify()}` — animates between layouts.
- Presets: `FadeIn`, `SlideInRight`, `ZoomIn`, `BounceIn`, etc.

### Shared value gotchas
- NEVER read `.value` during render — violates Rules of React. Use `useAnimatedStyle` / `useDerivedValue`.
- NEVER destructure: `let { value } = sv` breaks reactivity.
- NEVER mutate nested: `sv.value.x = 50` — reassign the whole object.
- Large arrays: use `sv.modify(arr => { arr.push(x); return arr })`, not direct push.
- Async on JS thread: `sv.value = 5; console.log(sv.value)` may show old value.
- React Compiler compat: use `sv.get()` / `sv.set()` instead of `.value`.

### Gesture Handler v2 (declarative API)
- `GestureDetector` wraps views. Gestures are plain JS objects from `Gesture.Pan()`, `Gesture.Tap()`, `Gesture.LongPress()`, `Gesture.Pinch()`, etc.
- Wrap app root in `<GestureHandlerRootView style={{ flex: 1 }}>` (expo-router template does this by default — verify).
- Callbacks: `onBegin`, `onUpdate`, `onEnd`, `onFinalize`. These run as worklets when paired with Reanimated — UI thread, 60fps+.
- Composition:
  - `Gesture.Race(a, b)` — first to activate wins.
  - `Gesture.Simultaneous(a, b)` — both active together (pan + pinch).
  - `Gesture.Exclusive(a, b)` — only one, priority = declaration order. Use for tap-vs-swipe disambiguation.

### Native Stack (react-native-screens)
- `createNativeStackNavigator` (and expo-router's default `<Stack />`) uses `UINavigationController` on iOS and Fragment on Android.
- Platform-correct default transitions automatically: slide-from-right (iOS), vary by Android theme/version.
- Prefer native stack over JS stack unless you need a transition the native stack can't do. Native is faster, uses less JS bridge traffic, and feels right on each platform.
- Caveat: native stack transitions can't be fully customized on Android — if you need a specific non-standard transition everywhere, you lose platform correctness.

### Native-feel checklist
- Use native stack for screen transitions (platform-correct push/pop).
- Use `presentation: 'modal'` or `'formSheet'` (iOS) for modals — don't reinvent with a JS overlay.
- Swipe-back gesture: `fullScreenGestureEnabled: true` on iOS for edge-swipe from anywhere.
- Haptics on interactions: `expo-haptics` `Haptics.impactAsync(ImpactFeedbackStyle.Light)` on taps, `.selectionAsync()` on picker changes.
- Respect reduced motion: `AccessibilityInfo.isReduceMotionEnabled()` → skip Reanimated entrance/exit.

## Topic 4: Data fetching & state (TanStack Query on RN)

### Why TanStack Query on RN
- Same story as web: server state ≠ client state. Don't put server data in useState/Context/Redux.
- Handles caching, background refetch, stale-while-revalidate, retries, optimistic updates.
- Same query key factory pattern as web skill.

### Required RN-specific wiring
RN has no `window`, no `focus`/`blur`/`online` events. You MUST manually wire these or refetch-on-focus and refetch-on-reconnect silently do nothing.

```tsx
// App.tsx (or root _layout.tsx)
import * as Network from 'expo-network'
import { AppState, Platform } from 'react-native'
import { focusManager, onlineManager } from '@tanstack/react-query'

// Online detection (Expo Network API)
onlineManager.setEventListener(setOnline => {
  const sub = Network.addNetworkStateListener(state => setOnline(!!state.isConnected))
  Network.getNetworkStateAsync().then(s => setOnline(!!s.isConnected))
  return sub.remove
})

// Focus detection (AppState instead of window.focus)
AppState.addEventListener('change', status => {
  if (Platform.OS !== 'web') focusManager.setFocused(status === 'active')
})
```

### Screen focus refetch
- expo-router / React Navigation provide `useFocusEffect` — fires when a screen becomes focused (not just mount).
- Pattern: call `query.refetch()` inside `useFocusEffect`; guard first-mount with a ref to avoid double fetch.
- Alternative: `useQuery({ ..., subscribed: isFocused })` using `useIsFocused()` — unsubscribes off-screen to save work.

### Recommended QueryClient defaults for RN
```tsx
new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 60_000,           // 1 min default — mobile users switch apps often
      gcTime: 5 * 60_000,
      retry: 2,                     // mobile flakiness → retry a bit
      refetchOnReconnect: true,    // needs onlineManager wired
      refetchOnWindowFocus: true,  // needs focusManager wired
    },
    mutations: { retry: 0 },
  },
})
```

### Offline-first persistence
- `@tanstack/query-async-storage-persister` + `PersistQueryClientProvider`.
- Storage: `@react-native-async-storage/async-storage` for normal cached data (unencrypted).
- NEVER persist tokens via AsyncStorage — use `expo-secure-store` (Keychain/Keystore).
- Mutation persistence can queue offline mutations and replay on reconnect; call out as advanced.

### Query key factory (same as web skill)
```tsx
export const queryKeys = {
  me: ['me'] as const,
  posts: {
    all: ['posts'] as const,
    list: (filter?: string) => ['posts', { filter }] as const,
    detail: (id: string) => ['post', id] as const,
  },
} as const
```

### Devtools
- `tanstack-query-dev-tools-expo-plugin` — devtools overlay on device. Worth mentioning.

### Gotchas
- Module-scope `new QueryClient()` works fine on RN (no SSR). Still prefer `useState(() => new QueryClient())` for hot-reload safety.
- `refetchOnWindowFocus` does nothing without AppState wiring — easy to miss.
- `refetchOnReconnect` does nothing without onlineManager wiring.
- `window.location` / `navigator.onLine` don't exist on native.
- Don't put server data in Zustand/Redux/Context — let React Query own it.

