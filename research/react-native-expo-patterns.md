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

## Topic 5: Native capabilities via Expo modules

### General permissions pattern
- Permissions are TWO layers: (1) declare in app.config.ts, (2) request at runtime.
- **iOS:** must add usage strings to `ios.infoPlist` (e.g., `NSCameraUsageDescription`). Missing = app store rejection + crash.
- **Android:** declare in `android.permissions` array. Block unwanted with `android.blockedPermissions`.
- Changes to native permissions require a new build — OTA updates cannot change them.
- Prefer library-specific config plugin props (e.g., `expo-camera` plugin's `cameraPermission`) over hand-editing infoPlist — clearer intent, less duplication.

### Runtime request pattern: `usePermissions` hook
Every Expo module with permissions exposes a `usePermissions()` hook:
```tsx
import { useCameraPermissions } from 'expo-camera'

function Screen() {
  const [permission, requestPermission] = useCameraPermissions()

  if (!permission) return <LoadingState />          // still loading
  if (!permission.granted) {
    return (
      <View>
        <Text>Camera access needed</Text>
        <Button onPress={requestPermission} title="Grant" />
      </View>
    )
  }
  return <Camera />
}
```

### Testing rejection scenarios
- Once a user denies, the OS blocks further prompts. You must uninstall/reinstall to test the "first time" flow again.
- For persistent denial, detect `permission.canAskAgain === false` and deep-link to settings with `Linking.openSettings()`.

### expo-secure-store (for tokens/secrets)
```tsx
import * as SecureStore from 'expo-secure-store'

await SecureStore.setItemAsync('access_token', token)
const token = await SecureStore.getItemAsync('access_token')
await SecureStore.deleteItemAsync('access_token')
```
- Backing: iOS Keychain, Android Keystore-encrypted SharedPreferences.
- Size limit: ~2KB (iOS Keychain historically rejects >2048 bytes). DON'T store JWTs with massive claims or encoded images.
- Always use async API. Sync blocks the JS thread.
- `keychainAccessible` option controls when value is readable (e.g., `WHEN_UNLOCKED`, `AFTER_FIRST_UNLOCK`).
- `requireAuthentication: true` → biometric gate on read. Warning: key becomes inaccessible if user changes biometric enrollment.
- Don't assume iOS persistence across uninstall — not guaranteed even though Keychain technically can.

### AsyncStorage vs SecureStore decision
| Use case | Storage |
|----------|---------|
| Auth tokens, API keys, user PII | `expo-secure-store` |
| User preferences, cached server data, theme choice | `@react-native-async-storage/async-storage` |
| Large files, downloaded media | `expo-file-system` |

### expo-notifications
```tsx
// Set handler EARLY (root _layout.tsx module scope)
Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowBanner: true, shouldShowList: true,
    shouldPlaySound: true, shouldSetBadge: true,
  }),
})
```
- Get push token: `Notifications.getExpoPushTokenAsync({ projectId })` — requires EAS project ID.
- Android 13+: explicit POST_NOTIFICATIONS permission prompt required (handled by `requestPermissionsAsync()`).
- Android: MUST call `setNotificationChannelAsync()` before requesting token. Channel-less notifications silently fail on API 26+.
- iOS: use `response.ios.status` field, not root `status`, for nuanced permission states (PROVISIONAL, EPHEMERAL).
- iOS: repeating time-interval triggers must be ≥60s or they don't fire.
- **Push notifications unavailable in Expo Go on Android from SDK 53+.** MUST use a dev build. Local notifications still work in Expo Go.
- Two listeners: `addNotificationReceivedListener` (fired while foregrounded) and `addNotificationResponseReceivedListener` (fired on tap, including from killed state).

### expo-camera
- Use `<CameraView />` (the modern API; deprecated `<Camera />` is gone).
- Permissions via `useCameraPermissions` hook.
- Don't mount multiple `<CameraView />` at once — Android has a single-session constraint.

### expo-image-picker
- Call `requestMediaLibraryPermissionsAsync()` BEFORE `launchImageLibraryAsync()`, otherwise the OS prompt appears mid-interaction and feels janky.
- `allowsEditing: true` gives users in-flow crop on both platforms.
- Android: if activity is killed while picker is open, use `getPendingResultAsync()` on resume to recover the selection. Test with "Don't keep activities" enabled.
- iOS HEIC: pickers return HEIC by default; set `mediaTypes` and handle conversion if uploading to a backend that expects JPEG.

### expo-file-system
- Modern SDK 55 API is object-based: `new File(uri)`, `new Directory(uri)` — replaces the old function-based API.
- `copyToCacheDirectory: true` on document picker is required for safe access — the source URI may be ephemeral.
- Use `Paths.cache` for temporary files (can be purged by OS), `Paths.document` for persistent user data.

### expo-location
- Permissions split: `foreground` and `background` are separate. Requesting background requires foreground first.
- Background location on iOS requires `UIBackgroundModes: ['location']` in infoPlist AND a justification for app store review.
- Managed workflow supports background location, but understand the review implications before committing.

### Managed-workflow friendly checklist
- [ ] Config plugins used (not manual ios/android dir edits)
- [ ] Permission usage strings set in app.config.ts
- [ ] `usePermissions()` hooks used for runtime checks
- [ ] SecureStore for tokens, AsyncStorage for preferences, FileSystem for blobs
- [ ] Notification channel set on Android before token fetch
- [ ] Dev build used for notifications (not Expo Go)

## Topic 6: Styling (NativeWind) + safe areas + keyboard

### NativeWind v4/v5 setup with Expo SDK 55
Files touched:
1. `metro.config.js` — wrap config with `withNativewind`
2. `babel.config.js` — preset already handles NativeWind in expo template
3. `tailwind.config.js` — standard Tailwind config with `content: ['./app/**/*.{ts,tsx}']`
4. `global.css` — imports Tailwind layers + nativewind theme
5. `nativewind-env.d.ts` — types
6. Import `global.css` at top-level component (root `_layout.tsx`), NOT at the `AppRegistry.registerComponent` entry
7. Pin `lightningcss@1.30.1` in package.json `overrides` — newer versions cause deserialization errors

```js
// metro.config.js
const { getDefaultConfig } = require('expo/metro-config')
const { withNativewind } = require('nativewind/metro')

const config = getDefaultConfig(__dirname)
module.exports = withNativewind(config, { input: './global.css' })
```

### Using classes
```tsx
<View className="flex-1 bg-white dark:bg-neutral-900">
  <Text className="text-lg font-semibold text-neutral-900 dark:text-white">Hello</Text>
</View>
```
- Use `className` on any RN primitive.
- `dark:` prefix works out of the box.
- No native platform variants (`ios:`/`android:`) — use `Platform.select()` or conditional classes.

### Dark mode
- Set `userInterfaceStyle: 'automatic'` in app.config.ts — enables Expo to follow system appearance.
- Read: `const { colorScheme } = useColorScheme()` from `nativewind`.
- Set manually: `colorScheme.set('dark' | 'light' | 'system')`.
- Persist user choice with AsyncStorage, hydrate on launch.
- Always offer a "System" option if showing a manual toggle.

### Safe areas
Don't trust `vh`/`100%` — iPhone notches, dynamic islands, Android navigation bars all eat into the viewport.

```tsx
// Root _layout.tsx — wrap ONCE at the root
import { SafeAreaProvider, initialWindowMetrics } from 'react-native-safe-area-context'
<SafeAreaProvider initialMetrics={initialWindowMetrics}>{children}</SafeAreaProvider>
```
`initialMetrics` avoids a 1-frame layout jump on first render.

### Hook vs component
- **Prefer `useSafeAreaInsets()`** over `<SafeAreaView>`. Mixing the two causes flickering because they update on different timing.
- Apply insets selectively — usually only `top` (for screens without a header) and `bottom` (for screens with fixed CTAs).
- Don't wrap the whole app in a single SafeAreaView. Apply per-screen.

```tsx
function Screen() {
  const insets = useSafeAreaInsets()
  return (
    <View style={{ paddingTop: insets.top, paddingBottom: insets.bottom }} className="flex-1">
      {content}
    </View>
  )
}
```

### When NOT to apply insets
- Screens inside expo-router's native `<Stack>` with a visible header → the header already handles the top inset.
- Screens inside `<Tabs>` → the tab bar handles the bottom inset.
- Rule: apply insets at the OUTERMOST container, and only for edges not already handled by a navigator.

### Keyboard handling
**Use `react-native-keyboard-controller`, not RN's built-in `KeyboardAvoidingView`.**
- Built-in KAV: platform-specific behavior, janky animations, poor on Android, hard to customize.
- keyboard-controller: identical behavior on iOS and Android, animated in sync with native keyboard, better API, better perf.
- Available in Expo Go since SDK 54 (Nov 2024).

```tsx
// root _layout.tsx
import { KeyboardProvider } from 'react-native-keyboard-controller'
<KeyboardProvider>{children}</KeyboardProvider>
```

Components:
- `<KeyboardAvoidingView>` from keyboard-controller (not RN).
- `<KeyboardAwareScrollView>` — scroll form into view when input focused.
- `<KeyboardToolbar>` — iOS-style Next/Previous/Done bar above the keyboard for field traversal.
- `useReanimatedKeyboardAnimation()` → returns shared values for height/progress; drive your own Reanimated styles in sync with native keyboard timing.

### Status bar
- Use `<StatusBar style="auto" />` from `expo-status-bar` (auto adapts to color scheme).
- For per-screen style: set inside each screen component so it updates on navigation.
- On Android, `translucent` (default on expo-router) lets content render behind the status bar — plan your safe-area insets accordingly.

### dvh / vh equivalents
- RN doesn't have `vh`/`dvh` — use `Dimensions.get('window')` or `useWindowDimensions()`.
- `useWindowDimensions()` auto-updates on rotation / fold / split-screen; prefer it over `Dimensions.get()`.

## Topic 7: Performance

### New Architecture (SDK 55)
- Legacy Architecture is DROPPED. Everything runs on New Arch (Fabric + TurboModules).
- Synchronous layout measurements replace async bridge — enables FlashList v2 to render without size estimates.
- Hermes is the default JS engine. Hermes V1 is experimental in SDK 55 (via `useHermesV1` in expo-build-properties) but requires building RN from source — wait for stable release.

### Lists: ALWAYS use FlashList (v2) over FlatList
FlashList v2 is a ground-up rewrite for New Architecture:
- **No more `estimatedItemSize`** — synchronous layout measurement handles it.
- **No more `overrideItemLayout`** — gone in v2.
- Drop-in replacement for FlatList API in most cases.

```tsx
import { FlashList } from '@shopify/flash-list'

<FlashList
  data={items}
  renderItem={({ item }) => <PostCard post={item} />}
  keyExtractor={item => item.id}  // still required and important
/>
```

### FlashList best practices
- **`keyExtractor` is required.** Prevents glitches when items re-layout while scrolling upward.
- **Memoize `renderItem`** with `useCallback`, or extract to a stable reference. Inline closures cause re-renders of every row on state change.
- **Memoize row components** with `React.memo`. FlashList recycles rows aggressively — unmemoized rows re-render every recycle.
- **Remove explicit `key` props** from children inside `renderItem` — can conflict with FlashList's recycling.
- **Nested lists:** horizontal-in-vertical requires BOTH to be FlashList for optimal layout timing.
- **New Architecture only** — v2 will not run on legacy arch. Fine for SDK 55.

### FlashList item patterns
```tsx
// BAD: inline closure, new function every render
<FlashList renderItem={({ item }) => <Row item={item} onPress={() => handle(item.id)} />} />

// GOOD: stable reference, memoized row
const Row = React.memo(function Row({ item, onPress }: Props) { ... })
const renderItem = useCallback(
  ({ item }: { item: Post }) => <Row item={item} onPress={handlePress} />,
  [handlePress],
)
```

### Images: always use `expo-image`, never RN's `<Image>`
Why:
- Native backing: SDWebImage (iOS), Glide (Android) — battle-tested, fast, memory-efficient.
- Disk + memory caching with configurable policies.
- Blurhash/thumbhash placeholders (compact base64-ish representations).
- Smooth transitions on source change (no flicker).
- WebP/AVIF/SVG/HEIC support.
- Prefetching: `Image.prefetch(url)`.

```tsx
import { Image } from 'expo-image'

<Image
  source={{ uri: post.image_url }}
  placeholder={{ blurhash: post.image_blurhash }}
  contentFit="cover"
  transition={200}
  cachePolicy="memory-disk"
  recyclingKey={post.id}  // CRITICAL in FlashList — resets content before new image loads
/>
```

### Image gotchas
- `useImage` hook without `maxWidth`/`maxHeight` can crash from OOM on large images.
- `placeholderContentFit` should match `contentFit` to avoid scale jump between placeholder and final image.
- In FlashList rows, ALWAYS set `recyclingKey` — otherwise recycled rows briefly show the previous item's image.

### Re-render hygiene
- **React Compiler** is not yet default in SDK 55; manual memoization still matters.
- Use `React.memo` on list row components.
- Use `useCallback`/`useMemo` for props passed to memoized children and for FlashList `renderItem`.
- **Context re-render trap:** any consumer of a context re-renders when ANY field in the context value changes. Split contexts by update frequency (e.g., theme context vs. auth context vs. user-settings context) instead of one giant AppContext.
- For Reanimated animations, DON'T put animation values in React state — use `useSharedValue` so updates bypass React reconciliation entirely.

### Bundle size & startup
- Hermes bytecode is precompiled — faster startup than V8.
- SDK 55 adds 75% smaller OTA updates via Hermes bytecode diffing. No code change required, just use EAS Update.
- Code splitting: expo-router handles route-based lazy loading automatically.
- Import specific functions: `import debounce from 'lodash/debounce'` not `import _ from 'lodash'`.
- Inspect bundle with `npx expo export --dump-sourcemap` + `source-map-explorer`.

### Profile on real devices
- iOS Simulator and Android Emulator are NOT representative of perf on low-end devices.
- Test on: older iPhone SE / low-tier Android (Moto G, Samsung A-series).
- Use React DevTools Profiler to find slow renders.
- Use Flipper or React Native Performance Monitor (`Cmd+M` / shake → "Show Perf Monitor") for FPS and RAM.

## Topic 8: Testing (unit + integration)

### Stack
- **jest-expo** — preset, installs Jest + all needed transforms.
- **@testing-library/react-native (RNTL)** — component queries and events.
- **expo-router/testing-library** — renderRouter, route assertions.
- **@testing-library/jest-native** — extra matchers (deprecated in RNTL v12+; RNTL has built-ins now).

NO `react-test-renderer` — deprecated, doesn't support React 19. Always use RNTL.

### Setup
```bash
npx expo install jest jest-expo @testing-library/react-native @types/jest --dev
```

`package.json`:
```json
{
  "scripts": { "test": "jest", "test:watch": "jest --watchAll" },
  "jest": {
    "preset": "jest-expo",
    "transformIgnorePatterns": [
      "node_modules/(?!((jest-)?react-native|@react-native(-community)?|expo(nent)?|@expo(nent)?/.*|@expo-google-fonts/.*|react-navigation|@react-navigation/.*|@unimodules/.*|unimodules|sentry-expo|native-base|react-native-svg|@shopify/flash-list|nativewind|react-native-css-interop))"
    ]
  }
}
```
The `transformIgnorePatterns` list is the #1 source of "SyntaxError: Unexpected token export" errors. Add new libs here when you see them.

### jest-expo auto-mocks
- The preset auto-mocks the "native part" of Expo SDK modules — SecureStore, Notifications, Camera, etc. all return stubs by default.
- You don't need to mock `expo-*` modules manually unless you need specific return values.
- Override behavior per-test: `(SecureStore.getItemAsync as jest.Mock).mockResolvedValue('token')`.

### React Native Testing Library basics
```tsx
import { render, screen, userEvent } from '@testing-library/react-native'

test('submits form', async () => {
  const user = userEvent.setup()
  render(<LoginScreen />)

  await user.type(screen.getByPlaceholderText('Email'), 'jp@test.com')
  await user.type(screen.getByPlaceholderText('Password'), 'secret')
  await user.press(screen.getByRole('button', { name: /sign in/i }))

  expect(await screen.findByText('Welcome')).toBeOnTheScreen()
})
```

### `userEvent` vs `fireEvent` — prefer userEvent
- `fireEvent.press()` only calls the `onPress` prop — no press-in/press-out, no state transitions.
- `userEvent.press()` simulates the full native press sequence (begin → end → onPress) — catches more bugs.
- `userEvent.type()` simulates real keystrokes, triggers `onChangeText` per character.
- Always `await` userEvent calls — they're async.
- Always call `userEvent.setup()` at the start of each test.

### Queries: priority order
1. `getByRole('button', { name: /save/i })` — accessibility-first
2. `getByLabelText('Email')` — form inputs
3. `getByPlaceholderText(...)` — fallback for inputs without labels
4. `getByText(...)` — for visible text
5. `getByDisplayValue(...)` — for inputs with existing values
6. `getByTestId(...)` — LAST resort, only when nothing else works

### Testing expo-router navigation
```tsx
import { renderRouter, screen } from 'expo-router/testing-library'

test('navigates to detail on tap', async () => {
  const user = userEvent.setup()
  renderRouter(
    { index: HomeScreen, 'posts/[id]': PostScreen },
    { initialUrl: '/' },
  )

  await user.press(screen.getByText('Post 1'))
  expect(screen).toHavePathname('/posts/1')
})
```

Matchers on `expect(screen)`:
- `toHavePathname('/posts/1')`
- `toHavePathnameWithParams('/posts/1?ref=home')`
- `toHaveSegments(['posts', '[id]'])`
- `toHaveRouterState({...})`

### Mocking router hooks (when NOT using renderRouter)
```tsx
const mockPush = jest.fn()
jest.mock('expo-router', () => ({
  ...jest.requireActual('expo-router'),
  useRouter: () => ({ push: mockPush, back: jest.fn(), replace: jest.fn() }),
  useLocalSearchParams: () => ({ id: 'post-123' }),
}))
```

### TanStack Query in tests
```tsx
function renderWithQuery(ui: React.ReactElement) {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  })
  return render(<QueryClientProvider client={client}>{ui}</QueryClientProvider>)
}
```
- `retry: false` — otherwise a failing test waits for 3 retries before finishing.
- Mock service functions with `jest.fn()` wrappers (same pattern as web skill).

### Mocking native modules in test setup
`jest-setup.ts`:
```ts
// Silence known noisy warnings from Reanimated in tests
require('react-native-reanimated').setUpTests()

// Mock expo-haptics (no-op is fine)
jest.mock('expo-haptics', () => ({
  impactAsync: jest.fn(),
  notificationAsync: jest.fn(),
  selectionAsync: jest.fn(),
}))
```
Reference from `jest.setup` in package.json: `"setupFilesAfterEach": ["<rootDir>/jest-setup.ts"]`.

### Common test gotchas
- **Reanimated components:** must import `react-native-reanimated/mock` OR call `require('react-native-reanimated').setUpTests()` in setup, otherwise tests crash.
- **Gesture handler:** similar — import `'react-native-gesture-handler/jestSetup'` in setup file.
- **FlashList** renders items async. Use `findBy*` queries, not `getBy*`, for items.
- **Haptics, notifications, secure-store:** auto-mocked by jest-expo, return undefined. Fine for most tests.
- **Async waits:** use `findBy*` or `waitFor(() => expect(...).toPass())`, not arbitrary timers.
- **`act()` warnings:** usually mean you forgot `await` on a state-updating call. Add the await.
- **`tsc --noEmit` on tests:** Jest doesn't type-check. Run tsc separately in CI to catch test type errors.
- **Module scope mocks:** `jest.mock` is hoisted, but the factory still runs at import. If the factory references uninitialized vars, use `jest.doMock` with explicit `require()`.

### What to test
- **Unit:** pure utilities, hooks (via `renderHook`), reducers, Zod schemas.
- **Integration:** full screen renders with mocked API — the layer we get most value from.
- **Skip:** snapshot tests (brittle, high-maintenance), exact style matchers, implementation details.
- **Don't bother E2E** in v1 (per user decision).

### Coverage targets
- Aim for high coverage on services and screen integration tests, not line coverage for its own sake.
- Every screen should have at least: happy path, loading state, error state, one key interaction.

## Topic 9: Release pipeline (EAS Build, Submit, Update)

### The three services
- **EAS Build** — cloud-hosted builder. Takes your JS/config, produces .ipa (iOS) / .apk or .aab (Android).
- **EAS Submit** — uploads built binaries to App Store Connect (iOS) and Google Play Console (Android).
- **EAS Update** — serves JS/asset OTA updates to shipped apps. Bypasses store review for non-native changes.

All three configured via `eas.json` at repo root.

### Mental model: two layers
Every binary has two layers:
1. **Native layer** — compiled code, permissions, native modules. Baked into the .ipa/.aab. Only changeable by shipping a new binary.
2. **JS/asset layer** — your React code, images, translations. Swappable via EAS Update.

The **runtime version** is the contract between them. An update can only run on a build with a matching runtime version.

### Build profiles (eas.json)
Three standard profiles:

```json
{
  "cli": { "version": ">= 15.0.0" },
  "build": {
    "development": {
      "developmentClient": true,
      "distribution": "internal",
      "ios": { "simulator": true }
    },
    "preview": {
      "distribution": "internal",
      "channel": "preview",
      "env": { "EXPO_PUBLIC_API_URL": "https://staging.api.com" }
    },
    "production": {
      "channel": "production",
      "autoIncrement": true,
      "env": { "EXPO_PUBLIC_API_URL": "https://api.com" }
    }
  },
  "submit": {
    "production": {
      "ios": { "appleId": "...", "ascAppId": "..." },
      "android": { "serviceAccountKeyPath": "./google-service-account.json", "track": "internal" }
    }
  }
}
```

Profile purposes:
- **development** — installs expo-dev-client (dev menu, Metro connection, debugging). Internal distribution. `ios.simulator: true` lets you run on the sim.
- **preview** — production-like build without dev tools. Internal distribution (TestFlight internal / Play internal track). Use for team QA.
- **staging** (optional) — extends `preview`, points at staging API.
- **production** — store-bound build. `autoIncrement: true` bumps buildNumber (iOS) / versionCode (Android) automatically.

Extend profiles with `"extends": "production"` to avoid duplication.

### Env vars in EAS
- `env` field in profile — sets `EXPO_PUBLIC_*` at build time for that profile.
- Secrets (never exposed to JS bundle): `eas secret:create` stores on EAS servers, referenced by name in eas.json or read at build time.
- NEVER put API secrets in `EXPO_PUBLIC_*` — they end up in the bundle and are trivially extractable.

### Runtime version policy (critical decision)
Set in app.config.ts:
```ts
export default {
  runtimeVersion: { policy: 'fingerprint' },  // RECOMMENDED for prod
  updates: { url: 'https://u.expo.dev/your-project-id' },
}
```

Policies:
- **`fingerprint`** (RECOMMENDED) — `@expo/fingerprint` hashes every file that could affect native (package.json, plugins, app.config.ts, native folders). Changes → new runtime version → new build required. Deterministic. Safest.
- **`appVersion`** — bumps on app.config.ts `version` change. Simple but error-prone: you can change a native dep without bumping version → OTA ships broken update to old binary.
- **`sdkVersion`** — only bumps on SDK upgrade. Too loose for most apps.
- **Explicit string** (`"1.0.0"`) — full manual control. Only if you have a strong reason.

**Use fingerprint. Everything else leaks bugs to production.**

### What CAN ship via OTA (EAS Update)
- JS code changes (components, hooks, logic)
- Copy, translations, styling tweaks
- Image assets (bundled)
- Bug fixes in non-native code
- Feature flags toggling JS paths

### What CANNOT ship via OTA (requires new build)
- Any new native dependency (new `expo-*` module, react-native-* with native code)
- Permission changes (adding camera, location)
- App icon / splash screen
- Bundle identifier / app name
- Expo SDK upgrade
- Config plugin additions
- `app.config.ts` native fields

**Rule of thumb: if fingerprint changes, it's not OTA-able.** That's why fingerprint policy is the right choice — it's self-enforcing.

### Channels and branches
- **Branch** = a linear history of updates (like a git branch).
- **Channel** = a pointer from a build to a branch. Builds subscribe to a channel; you publish updates to a branch; a channel decides which branch a build listens to.
- Standard: one channel per environment (`production`, `preview`, `staging`).
- `eas update --branch production --message "fix login crash"` — publishes.
- Advanced: rollouts — `eas channel:edit production --branch rollout-v1.2.3` with percentage gating.

### Versioning strategy (app store compliance)
App stores care about two fields:
- **iOS:** `CFBundleShortVersionString` (marketing version, e.g., `1.2.3`) + `CFBundleVersion` (build number, monotonic integer).
- **Android:** `versionName` (marketing) + `versionCode` (monotonic integer).

In app.config.ts:
```ts
export default {
  version: '1.2.3',                        // marketing version (both stores)
  ios: { buildNumber: '1' },                // auto-incremented by EAS
  android: { versionCode: 1 },              // auto-incremented by EAS
}
```

With `autoIncrement: true` in the production profile, EAS bumps the build number server-side on each build. Commit it back to eas.json via `eas build:version:set` if you want it tracked in git, or let EAS own it (simpler).

### Credentials
- **iOS:** Apple Developer account required. EAS can generate distribution certs + provisioning profiles automatically — the default and recommended path. You provide Apple ID + app-specific password, EAS handles the rest.
- **Android:** EAS generates a keystore on first build. **Back up the keystore** (`eas credentials` → download) — losing it means you can never update your app on Play Store, even after losing publishing rights.
- **Play Store service account:** create a service account in Google Cloud Console, grant it "Release Manager" role in Play Console, download the JSON key, reference in eas.json `submit.production.android.serviceAccountKeyPath`.

### Typical release flow
```
1. Feature PR merges to main
2. Dev builds locally, tests in dev client
3. Cut a preview build: `eas build --profile preview --platform all`
4. Install via internal distribution link → team QA
5. If clean: `eas build --profile production --platform all --auto-submit`
6. EAS Submit pushes to TestFlight (iOS) and Play Internal track (Android)
7. Promote through test tracks → production in App Store Connect / Play Console
8. Hotfixes: `eas update --branch production --message "fix X"` (if JS-only)
9. Real native fix: new production build cycle
```

### Automation (EAS Workflows)
- `.eas/workflows/*.yml` — GitHub Actions-like syntax, runs on EAS servers.
- Example jobs: build-on-tag, submit-after-build, update-on-main-push.
- Cheaper alternative: use GitHub Actions with the `expo/expo-github-action` to trigger `eas build`.

### Rollback strategy
- OTA rollback: `eas update --branch production --republish --group <old-group-id>` — re-publishes a previous update group, pushing it to all clients.
- Binary rollback: cannot truly roll back a store release. Must push a new build with the old code (version bumped). Use staged rollouts (Play Console) to catch issues before 100% distribution.

### Store review gotchas
- **iOS:** App Store Review Guideline 4.3 — don't ship "spam" duplicate apps. 2.5.2 — no downloading executable code post-approval (EAS Update JS is explicitly allowed; WebViews loading remote HTML are borderline).
- **iOS:** must have real functionality at review time. No "coming soon" screens.
- **Android:** Data Safety form (Play Console) — must declare all data collected. False declarations = removal.
- **Both:** privacy policy URL required. Set in app.config.ts and store listing.
- **iOS:** expect 24–48 hour review on first submission, faster on updates. Use TestFlight for internal testing to avoid review cycles.

### Observability post-release
- **expo-application + expo-updates** to read current `updateId` and `runtimeVersion` — log with every error.
- **Sentry (sentry-expo)** — source-mapped crash reporting. Uploads maps per build via EAS Build hook.
- **Critical:** tag errors with `updateId` so you know exactly which OTA caused a spike.

## Topic 10: iOS vs Android gotchas

The #1 source of bugs in RN apps: assuming something works the same on both platforms because it worked in one. Always test on both simulators, and ideally real devices for each.

### Platform detection
```tsx
import { Platform } from 'react-native'

Platform.OS              // 'ios' | 'android' | 'web'
Platform.Version         // iOS: string '16.0' | Android: number 33
Platform.select({ ios: 'a', android: 'b', default: 'c' })
```
- Prefer `Platform.select` in style/prop values; cleaner than `Platform.OS === 'ios' ? a : b`.
- Never key features off `Platform.Version` for iOS without parsing — it's a string.

### Shadows
- **iOS:** use `shadowColor`, `shadowOffset`, `shadowOpacity`, `shadowRadius`. No effect on Android.
- **Android:** use `elevation` (a number). No fine control — just depth. No effect on iOS.
- Must set BOTH if you want a shadow on both platforms.
- With NativeWind: `shadow-md` works on iOS; Android needs explicit `elevation-*` via style or a platform-specific class.

```tsx
// Shadow that works on both
<View
  style={{
    shadowColor: '#000', shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1, shadowRadius: 4,  // iOS
    elevation: 3,                          // Android
  }}
/>
```

### Text rendering
- **Android font weights:** only `'normal'` and `'bold'` are reliably understood. Numeric weights (`'600'`, `'700'`) often collapse to `'normal'` unless you've loaded a custom font with that exact weight.
- **iOS font weights:** the full range (`'100'` through `'900'` plus named weights) works natively with the system font.
- Solution: load custom fonts with specific weights via `expo-font`, name each weight explicitly (`Inter-Regular`, `Inter-SemiBold`, `Inter-Bold`), and use `fontFamily` rather than `fontWeight`.
- **Line height:** Android adds extra padding above/below text glyphs by default; iOS doesn't. Set `includeFontPadding: false` on Android text for pixel-perfect layout.
- **Text truncation:** `numberOfLines={1}` + `ellipsizeMode="tail"` — works on both, but Android truncates earlier with multibyte chars.

### Keyboard behavior
- Built-in `KeyboardAvoidingView` `behavior` prop: iOS wants `'padding'`, Android wants `'height'` — or just use `react-native-keyboard-controller` (recommended, see topic 6) to get identical behavior.
- **iOS:** keyboard animates in with native timing (usually 250ms ease-out). Hook via keyboard-controller to match.
- **Android:** keyboard can resize the window OR pan it (app-level `windowSoftInputMode`). Expo managed defaults to `adjustResize`.
- **Android:** hardware back button closes keyboard first before navigating. iOS has no back button; users dismiss with a tap outside or scroll.

### Back button (Android only)
- iOS has no hardware/system back button — all back navigation is via swipe-from-edge or header back button.
- Android back button needs explicit handling for modals, custom navigators, and confirm-before-leave:
```tsx
import { BackHandler } from 'react-native'
useEffect(() => {
  const sub = BackHandler.addEventListener('hardwareBackPress', () => {
    if (hasUnsavedChanges) { showConfirmDialog(); return true }  // true = consumed
    return false  // false = default back behavior
  })
  return () => sub.remove()
}, [hasUnsavedChanges])
```
- expo-router handles the common case automatically — only intercept for app-level needs.

### Edge-to-edge (Android 15+, SDK 55)
**Major change in SDK 55:** Google now enforces edge-to-edge display when targeting Android SDK 35+. The app draws behind the status bar and nav bar by default. No opt-out.

Consequences:
- `statusBarTranslucent` prop is deprecated and is now a no-op.
- `backgroundColor` on `<StatusBar>` is deprecated — the status bar is always transparent.
- `expo-navigation-bar` — most methods are no-ops under edge-to-edge.
- Your content WILL render behind the system bars unless you use safe areas (see topic 6).
- **Use `useSafeAreaInsets()` to pad all screens.** If you don't, text and buttons will sit under the status bar on Android.
- Test with gesture navigation AND 3-button navigation enabled (Settings → System → Gestures). The nav bar is transparent in gesture mode, translucent in 3-button mode.

### Status bar
- Use `<StatusBar style="auto" />` from `expo-status-bar`. `auto` adapts to the underlying theme.
- Per-screen: set inside each screen component so it updates on navigation.
- On Android with edge-to-edge, the status bar is transparent; only the text color (`light`/`dark`) matters now.
- On iOS, content renders under the status bar; your top padding / nav header handles this.

### Switch / native controls
- `<Switch>` looks dramatically different per platform (iOS rounded pill; Android Material thumb+track). Intentional.
- Don't try to match them — use platform-native look. If you need a unified look, build a custom component from scratch.
- `<Picker>` — same story. Prefer `@react-native-picker/picker` or build a bottom-sheet selector.

### Haptics (expo-haptics)
- Both platforms support impact (light/medium/heavy), notification (success/warning/error), and selection feedback.
- iOS: uses Taptic Engine — very crisp. Lean on haptics liberally on iOS.
- Android: uses vibration motor — less precise. Some devices disable all haptic feedback in battery-saver mode or by user setting. Don't rely on haptics as the only feedback for an action.

### Permissions UX
- **iOS:** permission prompt is a one-shot modal. If the user denies, the app cannot re-prompt programmatically — must deep-link to Settings.
- **Android:** can re-prompt up to 2 times (on modern versions). After that, denial becomes permanent until app reinstall.
- Pattern: show a custom rationale screen BEFORE calling `requestPermission()` so users understand the value ask.
- On denial, detect `canAskAgain === false` and `Linking.openSettings()`.
- **iOS:** permission descriptions in `NSCameraUsageDescription` etc. must clearly explain WHY or Apple rejects at review.

### App icons & splash screens (native-only, must be in new build)
- Configure via `expo-splash-screen` + `ios.icon` / `android.adaptiveIcon` in app.config.ts.
- Android adaptive icons are required for modern Android: foreground (transparent PNG) + background (solid color or image). Icons without adaptive treatment look broken on Android 8+.
- iOS: single icon image, multiple sizes auto-generated. Transparent backgrounds are rejected — use solid.
- Splash screen: `expo-splash-screen` config plugin handles both. Don't hand-craft — use the plugin.

### Fonts
- Load once at root: `useFonts` hook from `expo-font`.
- Keep splash visible until fonts load: `await SplashScreen.preventAutoHideAsync()` at module scope, `await SplashScreen.hideAsync()` after fonts ready.
- **Android:** custom fonts must have their weight baked into the filename/family name. Can't trust `fontWeight: '600'` — use `fontFamily: 'Inter-SemiBold'`.

### Gestures and swipe-back (iOS)
- iOS: swipe-from-left-edge to pop a screen is the native behavior. Enabled by default in native stack.
- `fullScreenGestureEnabled: true` on native stack lets users swipe from anywhere, not just the edge.
- Android has no equivalent — back gesture comes from the system nav, not your stack.
- Test: if a user can't swipe back on iOS for a routine screen, you're fighting the platform.

### Debugging tools
- **iOS Simulator:** `I` to hard-reload, shake gesture = `Cmd+Ctrl+Z`, perf monitor via dev menu.
- **Android Emulator:** `R R` to reload, `Cmd+M` for dev menu.
- **Real devices:** shake physical device → dev menu.
- **Flipper** is dead (deprecated); use React Native DevTools (built in) + Chrome DevTools for network.

### Checklist: test on both before merging
- [ ] Shadows visible on both
- [ ] Text weights look right on both (Android fonts loaded?)
- [ ] Keyboard doesn't cover focused input on either
- [ ] Android back button does the right thing at every screen
- [ ] Safe-area insets applied (Android edge-to-edge)
- [ ] App icon looks right (iOS full-bleed, Android adaptive)
- [ ] Permissions prompt shows the right explanation string (iOS)
- [ ] Works in gesture nav AND 3-button nav (Android)
- [ ] Works on oldest supported OS (iOS 15.1, Android 7)

## Topic 11: Anti-patterns synthesis

Distilled from topics 1-10 plus common production mistakes. These are the things that silently cost hours or ship bugs.

### Treating RN like the web
**The mistake:** Using web patterns in RN — `map()` for long lists, CSS `vh` units, `window.location`, `localStorage` for auth, `<div onClick>`, assuming DOM exists.

**Cost:** Broken behavior at runtime, performance cliffs on long lists, lost auth state on app restart.

**Fix:** RN is not the DOM.
- Long lists → FlashList, never `.map()`.
- No `vh`/`dvh` → `useWindowDimensions()`.
- No `window.location` → `Linking.openURL()`, `router.push()`.
- Auth tokens → `expo-secure-store`, never `AsyncStorage`.
- No click events — `Pressable`, `TouchableOpacity`, or `<Button>` (though the built-in Button is basically unusable, write your own).

### Pretending iOS and Android behave the same
**The mistake:** Building for one platform, assuming the other "just works." Not testing on both until right before release.

**Cost:** Shadow missing on Android (no `elevation`), fonts rendering wrong weight on Android, content sitting under the status bar on Android edge-to-edge, hardware back button doing the wrong thing.

**Fix:** Test on both simulators during active development, not at the end. Build a per-PR smoke test: render the changed screen on both iOS and Android before merging.

### Skipping the RN-specific wiring for TanStack Query
**The mistake:** Using the defaults from web docs — `refetchOnWindowFocus: true`, `refetchOnReconnect: true` — without wiring `focusManager` to AppState and `onlineManager` to Network.

**Cost:** Options silently no-op. Stale data shown when user returns to app from background. No refetch after reconnect.

**Fix:** Wire focusManager + onlineManager in the root layout. It's 15 lines. Do it once.

### Keyboard handling via built-in KeyboardAvoidingView
**The mistake:** Using RN's `KeyboardAvoidingView` with `behavior="padding"` on iOS / `"height"` on Android, hoping for the best.

**Cost:** Different behavior per platform, janky animation, form inputs still covered on edge cases, hours spent tweaking offsets.

**Fix:** Use `react-native-keyboard-controller` for identical behavior on both platforms. Since Expo SDK 54 it's included in Expo Go.

### Wrapping the whole app in SafeAreaView
**The mistake:** One `<SafeAreaView style={{flex:1}}>` at the root, assuming it handles all safe areas forever.

**Cost:** Safe areas applied where headers/tabbars already handle them → double padding. Flickering from mixing SafeAreaView with `useSafeAreaInsets` downstream.

**Fix:** `SafeAreaProvider` at the root (one time), then `useSafeAreaInsets()` per-screen, applying only the edges the screen actually needs.

### Module-scope state in Reanimated worklets
**The mistake:** Reading `sv.value` during render, destructuring shared values, mutating nested object fields.

**Cost:** Silent reactivity loss, stale UI, "why isn't my animation running" debugging sessions.

**Fix:** Shared values are ONLY accessed from worklets (`useAnimatedStyle`, `useDerivedValue`). Reassign the whole object, never mutate in place. For large arrays use `sv.modify()`.

### Inline closures in FlashList `renderItem`
**The mistake:** `renderItem={({item}) => <Row item={item} onPress={() => handle(item.id)} />}`

**Cost:** New function every render → every row re-renders → dropped frames on scroll, stuttering on low-end devices.

**Fix:** Memoize `renderItem` with `useCallback`, memoize row components with `React.memo`, stable `keyExtractor`.

### Not setting `recyclingKey` on images in lists
**The mistake:** `<Image source={{uri: item.url}} />` inside a FlashList row without `recyclingKey`.

**Cost:** Recycled rows briefly show the previous item's image as the new one loads. Looks broken.

**Fix:** `<Image recyclingKey={item.id} ... />` on any image in a recycled list row.

### RN's built-in `<Image>` over expo-image
**The mistake:** Shipping with `Image` from `react-native` because "it works."

**Cost:** No disk cache, no blurhash placeholder, flicker on source change, higher memory use, no WebP/AVIF support.

**Fix:** Always use `expo-image`. Zero reasons not to.

### `AsyncStorage` for auth tokens
**The mistake:** Storing JWTs / refresh tokens in `@react-native-async-storage/async-storage`.

**Cost:** Tokens are readable by any app with filesystem access on rooted/jailbroken devices. Trivial to exfiltrate with a malicious config plugin.

**Fix:** `expo-secure-store` for tokens. iOS Keychain / Android Keystore. Respect the 2KB size limit.

### EXPO_PUBLIC_ for secrets
**The mistake:** `EXPO_PUBLIC_API_KEY=sk_live_xxx` in `.env`.

**Cost:** Statically inlined into the JS bundle. Trivially extractable with `apktool` or by reading the .ipa. Effectively public.

**Fix:** Never put secrets in `EXPO_PUBLIC_*`. Call your backend which holds the secret. If you MUST ship a key (e.g. third-party public keys), at least understand it's world-readable.

### `appVersion` runtime version policy
**The mistake:** Using `runtimeVersion: { policy: 'appVersion' }` in app.config.ts.

**Cost:** You can add a native dependency without bumping the app version, then ship an OTA update. The update reaches old binaries that don't have the native code → crash loop on launch.

**Fix:** Use `fingerprint` policy. Deterministic, self-enforcing, prevents this entire class of bug.

### Losing the Android keystore
**The mistake:** Letting EAS generate an Android keystore, never downloading a backup.

**Cost:** Lose access to your EAS account or the keystore gets corrupted → permanently cannot update your app on Play Store. Ever. Even with Apple-style recovery, Google Play's signing requires the same key forever (unless you enrolled in Play App Signing).

**Fix:** `eas credentials` → download and back up the keystore to 1Password / secure storage immediately after first production build. Alternatively, enable Play App Signing so Google owns the upload key recovery.

### Not testing on real devices
**The mistake:** Shipping after testing only on iOS Simulator and Android Emulator.

**Cost:** Simulators don't hit the same perf cliffs as real low-end devices. Memory constraints, CPU throttling, real haptics, real camera, real notifications — none work the same on sim.

**Fix:** At minimum: one cheap Android (Moto G / Samsung A-series) and one older iPhone (SE / iPhone 11). Test every release candidate on both.

### Screen component doing everything
**The mistake:** One 800-line screen file with JSX + state + API calls + validation + navigation logic + side effects.

**Cost:** Unmaintainable. Impossible to unit test. Every change risks breaking everything.

**Fix:** Screens are orchestration only. Business logic in hooks (`useCreatePost`, `useAuth`). Pure functions for validation/transforms. Service functions for API calls.

### Missing permissions descriptions in app.config.ts
**The mistake:** Adding a config plugin that requires a permission (e.g., camera) but not setting the usage description.

**Cost:** iOS build succeeds, app crashes on first permission request. Or: app store rejection at review.

**Fix:** Every iOS permission needs an `ios.infoPlist.NS*UsageDescription`. Better: use the library's config plugin props (e.g., `expo-camera` plugin's `cameraPermission`) which set the string for you.

### Not wiring `onlineManager` and shipping "offline support"
**The mistake:** Adding `@tanstack/query-async-storage-persister` and calling it offline-first.

**Cost:** Queries show stale data but all mutations still silently fail when offline. User thinks the app works, their changes never sync.

**Fix:** Offline support is a design choice, not a library. Either (a) properly use mutation queueing with replay, test offline → online transitions, and handle conflicts, or (b) detect offline state and block writes with a clear UI.

### Not handling Android 13+ notification permission
**The mistake:** Calling `getExpoPushTokenAsync()` without first requesting `POST_NOTIFICATIONS` permission on Android 13+.

**Cost:** Token fetch succeeds but notifications never appear. User never sees a prompt. Silent failure.

**Fix:** Always call `requestPermissionsAsync()` before `getExpoPushTokenAsync()`. Always call `setNotificationChannelAsync()` on Android before either.

### Debugging in Expo Go and shipping a dev build
**The mistake:** Developing entirely in Expo Go, then discovering on first dev build that a library isn't bundled or behaves differently.

**Cost:** Half the native modules you need aren't in Expo Go (push notifications on Android from SDK 53, custom native modules, any library not in the Expo Go bundle).

**Fix:** Move to a dev build early. `eas build --profile development --platform ios` once at the start of the project, then run `expo start --dev-client`. Your dev loop is the same as Expo Go but with the full native module set.

### Snapshot tests as the primary test suite
**The mistake:** Autogenerating `toMatchSnapshot()` tests for every component.

**Cost:** Tests break on every style change without catching real bugs. Devs stop reading diffs and blind-update snapshots. Coverage number looks great, signal is zero.

**Fix:** Integration tests with `renderRouter` from `expo-router/testing-library`, asserting real user flows (render → interact → verify navigation/state). No snapshots.

### Hand-writing navigation instead of using native stack
**The mistake:** Building a custom JS-based stack for "more control," skipping `react-native-screens` native stack.

**Cost:** Non-native transitions, worse performance, more JS work, platform-incorrect swipe-back, hacky iOS modal presentation.

**Fix:** expo-router's default Stack is already native stack. Don't disable it. Use `presentation: 'modal' | 'formSheet'` for modals. Let the platform do the work.

## Topic 12: Offline usage

Offline support is a design choice, not a library install. The minute you ship "offline" you own queue replay, conflict resolution, and the UX of stale data. Pick a level of offline ambition before writing code.

Three tiers, in order of difficulty:
1. **Read-only cache** — show last-known data when offline. TanStack Query persistence covers this.
2. **Queued writes** — accept mutations offline, replay on reconnect. Needs idempotency keys + a retry plan.
3. **Offline-first** — local DB is source of truth, server is sync target. Use WatermelonDB / op-sqlite, not React Query.

### Persistence layer decision matrix

| Need | Use | Why |
|------|-----|-----|
| User prefs, theme, small JSON | `@react-native-async-storage/async-storage` | Async, simple, ubiquitous, ~6MB Android limit |
| Hot-path reads (every render), feature flags, MMKV-style sync access | `react-native-mmkv` | Synchronous, ~30x faster than AsyncStorage, optional AES encryption, JSI |
| Structured/relational data, queries, joins | `expo-sqlite` | SQL, JSI in SDK 55 (sync API available), backed by SQLite 3.44+ |
| Heavy offline-first with reactive observers | `WatermelonDB` (over SQLite) or `@op-engineering/op-sqlite` | Lazy loading, observable queries, sync protocol, scales to 10k+ rows |
| Auth tokens, secrets | `expo-secure-store` (covered topic 5) | Keychain/Keystore — never AsyncStorage |
| Large blobs, downloaded media | `expo-file-system` | Filesystem, not key-value store |

- **AsyncStorage gotchas:** unencrypted (plain text on disk), single-threaded native queue (writes serialize), Android has a default ~6MB limit (raise via `android:largeHeap` but don't), no querying. Storing >100KB per key is a smell.
- **MMKV gotchas:** requires a dev build (no Expo Go), needs config plugin `react-native-mmkv` in app.config.ts, sync API blocks JS thread on huge values, encryption key itself must live in SecureStore.
- **expo-sqlite gotchas:** in SDK 55 the JSI sync API (`openDatabaseSync`) is the default — old async API still works but new code should use sync. Migrations are manual; write a `version` PRAGMA and migrate forward in a single transaction at boot.
- **Decision rule:** prefs → AsyncStorage. Hot-path / very-frequent reads → MMKV. Structured queries → SQLite. True offline-first → WatermelonDB. Don't reach for SQLite "just in case" — it's overhead you'll regret.

### TanStack Query offline persistence

```tsx
// src/lib/queryClient.tsx
import AsyncStorage from '@react-native-async-storage/async-storage'
import { QueryClient } from '@tanstack/react-query'
import { PersistQueryClientProvider } from '@tanstack/react-query-persist-client'
import { createAsyncStoragePersister } from '@tanstack/query-async-storage-persister'

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      gcTime: 1000 * 60 * 60 * 24,    // 24h — must be >= maxAge or entries get GC'd before persist
      staleTime: 1000 * 60,
      networkMode: 'offlineFirst',     // serve cache while offline; refetch when online
    },
    mutations: { networkMode: 'offlineFirst', retry: 0 },
  },
})

const persister = createAsyncStoragePersister({
  storage: AsyncStorage,
  throttleTime: 1000,                  // batch writes; AsyncStorage is slow
  key: 'rq-cache-v1',
})

export function QueryProvider({ children }: { children: React.ReactNode }) {
  return (
    <PersistQueryClientProvider
      client={queryClient}
      persistOptions={{
        persister,
        maxAge: 1000 * 60 * 60 * 24,   // discard cached snapshots older than 24h
        buster: `${Constants.expoConfig?.version}-${Updates.updateId ?? 'dev'}`,
      }}
    >
      {children}
    </PersistQueryClientProvider>
  )
}
```

- **`gcTime` MUST be >= `maxAge`.** Otherwise queries get garbage-collected from memory before the persister can save them, and you persist nothing.
- **`buster` invalidates the entire cache** when its value changes. Bind it to app version + updateId so a release with a new schema wipes incompatible caches automatically.
- **Throttle writes.** AsyncStorage is slow — `throttleTime: 1000` keeps the persister from blocking on every state change.
- **Serialization gotchas:** Dates become strings on rehydrate, `Map`/`Set`/`undefined` are dropped, class instances lose their prototype. Keep query data as plain JSON. If you need richer types, write `serialize`/`deserialize` overrides.
- **`networkMode: 'offlineFirst'`** is the magic flag — without it, queries refuse to run when offline and you see an infinite spinner.
- **Consider MMKV persister** (`@tanstack/query-sync-storage-persister` + a thin MMKV adapter) for noticeably faster hydrate on cold start.

### Mutation queuing & replay

TanStack Query v5 supports mutation persistence via the same persister. Pair with `dehydrate`/`hydrate` to serialize the mutation cache:

```tsx
import { onlineManager } from '@tanstack/react-query'

// 1. Default a mutation that survives reload
queryClient.setMutationDefaults(['createPost'], {
  mutationFn: (input: PostInput) => api.createPost(input),
  retry: 3,
  // CRITICAL: replay handler used by the persister on resume
})

// 2. On boot, after hydrate, kick off any paused mutations
queryClient.resumePausedMutations().then(() => queryClient.invalidateQueries())
```

- **Pause-on-offline:** when `onlineManager` reports offline, mutations enter a `paused` state instead of running. They sit in memory + persisted cache.
- **FIFO replay on reconnect:** `resumePausedMutations()` runs them in submission order. **Order is preserved per mutation key, not globally** — if you need strict global order, use a single mutation key and a queue.
- **Idempotency keys are non-negotiable.** Generate a UUID client-side per mutation, send as `Idempotency-Key` header, server dedupes. Without this, a network blip mid-replay creates duplicates.
- **What breaks:** mutations that depend on previous mutations' server-assigned IDs (e.g., "create parent → create child with parentId"). Either resolve client-side first (UUIDs everywhere) or chain via local IDs that the server maps.
- **Mutation functions must be defined before hydrate.** If you `setMutationDefaults` after hydrate, paused mutations have no `mutationFn` and silently drop on `resumePausedMutations()`. Set defaults at module scope, not inside a component.
- **Don't `retry` infinitely.** A bad mutation locks the queue forever. Cap at 3 with exponential backoff, then surface a "tap to retry" or "discard" UI.

### Network detection beyond `isConnected`

```tsx
import * as Network from 'expo-network'
import { onlineManager } from '@tanstack/react-query'

onlineManager.setEventListener(setOnline => {
  const sub = Network.addNetworkStateListener(state => {
    // Use isInternetReachable, NOT isConnected
    setOnline(state.isInternetReachable ?? state.isConnected ?? false)
  })
  return sub.remove
})
```

- **`isConnected`** = device is associated with a WiFi/cellular interface. **TRUE in airplane-mode WiFi-on, captive portals, hotel splash pages, and any network with no actual internet.**
- **`isInternetReachable`** = a real ping/probe succeeded. The only signal worth gating writes on.
- **Captive portals** (hotel WiFi, airport, conference networks): `isConnected: true`, `isInternetReachable: false`. If you trust `isConnected`, every request hangs until timeout.
- **Caveat:** `isInternetReachable` can be `null` initially (probe in progress). Treat null as "unknown" — show the existing online state until you get a definitive answer.
- **Don't poll `getNetworkStateAsync()` in a loop.** Use the listener; it's event-driven and free.

### Offline UX patterns

- **Persistent offline banner** at the top of the app shell when `!onlineManager.isOnline()`. Don't surprise users. Animate in/out with Reanimated layout.
- **Disable write buttons when offline AND the action isn't queueable.** Greyed-out + tooltip "You're offline" is clearer than a failed toast.
- **Pending sync indicator:** count of `useIsMutating()` paused mutations rendered as a small badge (e.g., "3 pending"). Tap → list of queued items + retry/discard.
- **Show stale data with a visual cue.** A subtle "Last updated 2h ago" caption on cached screens. Don't pretend cached data is live.
- **Optimistic updates while queued:** apply the change to the cache immediately via `onMutate`, even if the mutation is paused. The user sees their action take effect; the queue handles the eventual sync.
- **On reconnect, don't auto-refetch everything.** Refetch the visible screen via `useFocusEffect`, let other queries refetch on next focus. Mass refetch on reconnect = janky resync UI.

### Conflict resolution

- **Last-write-wins (LWW):** simplest. Server takes whatever arrives last. Fine for "draft notes," "user prefs," anything where users own their own data and won't co-edit.
- **Server-authoritative refetch:** on mutation success, invalidate the related query and refetch. Server's response wins; client's optimistic update gets reconciled. Default for most CRUD apps.
- **ETags / version numbers:** client sends `If-Match: <version>`; server returns 412 Precondition Failed on conflict. Client surfaces a "this changed elsewhere — reload?" prompt. Use for shared/collaborative resources.
- **Tombstones for deletes:** if you delete a record offline, store a tombstone (`{id, deletedAt}`) so a concurrent server-side update doesn't resurrect it on next sync. WatermelonDB does this for you; hand-rolled needs care.
- **Ask the user only for genuine semantic conflicts** (their offline edit vs. someone else's online edit on the same field). Don't ask for trivial diffs — auto-merge whitespace, ordering, etc.

### Common mistakes

1. **Claiming "offline support" without testing mutation replay.** Cost: queries cache, writes silently drop, user changes never sync. Fix: airplane-mode the device, perform writes, toggle airplane off, verify the writes actually hit the server.
2. **Assuming AsyncStorage is encrypted.** Cost: PII / partial tokens sit in plain text on disk. Fix: tokens → SecureStore; sensitive prefs → MMKV with encryption key from SecureStore.
3. **Storing large blobs in AsyncStorage.** Cost: writes block JS thread for hundreds of ms, Android hits the 6MB ceiling, hot-path reads stutter. Fix: blobs → `expo-file-system`, structured data → SQLite, key-value → MMKV.
4. **Trusting `isConnected` instead of `isInternetReachable`.** Cost: hotel WiFi / captive portal screens look online but every fetch hangs until timeout. Fix: gate `onlineManager` on `isInternetReachable`.
5. **Not testing offline → online transitions.** Cost: replay order bugs, duplicate inserts, missing `mutationFn`, ghost queries. Fix: add an integration test that toggles `onlineManager` mid-flight; manually test airplane → on at least once per release.
6. **Missing `buster` on schema change.** Cost: you ship a release that renames a field, persisted cache hydrates with the old shape, screens crash on load. Fix: bind `buster` to `appVersion + updateId` so every release auto-invalidates.
7. **`gcTime < maxAge` in PersistQueryClientProvider.** Cost: cache GC'd from memory before persist — you persist nothing, "offline support" doesn't actually work. Fix: `gcTime >= maxAge`, both 24h+ for offline use cases.
8. **No idempotency keys on replayable mutations.** Cost: a single network retry creates duplicate records. Fix: client-generated UUID per mutation, sent as `Idempotency-Key` header, server dedupes.

### Testing offline flows

```tsx
// Unit: mock network state and onlineManager
import { onlineManager } from '@tanstack/react-query'

beforeEach(() => onlineManager.setOnline(true))

test('queues mutation when offline and replays on reconnect', async () => {
  onlineManager.setOnline(false)
  const { result } = renderHook(() => useCreatePost(), { wrapper })
  await act(() => result.current.mutate({ title: 'draft' }))
  expect(api.createPost).not.toHaveBeenCalled()

  onlineManager.setOnline(true)
  await waitFor(() => expect(api.createPost).toHaveBeenCalledWith({ title: 'draft' }))
})
```

- **Unit:** mock `expo-network` (`addNetworkStateListener`), drive `onlineManager.setOnline(true|false)` directly. jest-expo auto-mocks the native module.
- **Manual iOS:** macOS has Network Link Conditioner (Additional Tools for Xcode) — install on the simulator, simulate "100% Loss" / "Edge" / "3G". Closer to real behavior than airplane mode.
- **Manual Android:** Emulator → Extended Controls (`...` button) → Cellular tab → set "Data status: Denied" or use airplane mode toggle.
- **Real device airplane mode** is the gold standard and the only way to catch captive-portal / weak-signal edge cases. Test before every release.
- **Test the boring transitions:** mid-mutation airplane on, mid-fetch airplane off, foreground from background while offline, kill app while mutations queued and reopen (verify `resumePausedMutations` still fires).

## Topic 13: Accessibility

React Native a11y is less discoverable than web a11y. There's no DOM inspector for VoiceOver/TalkBack, and it's easy to ship a screen that's unusable to screen reader users without noticing. The fix is to treat a11y as a first-class API surface — and to actually test with the screen reader on.

### Core props every touchable needs

```tsx
<Pressable
  accessible
  accessibilityRole="button"
  accessibilityLabel="Save draft"
  accessibilityHint="Saves the current post without publishing"
  accessibilityState={{ disabled: isSaving, busy: isSaving }}
  onPress={save}
>
  <Text>Save</Text>
</Pressable>
```

- **`accessible`** groups child elements under one a11y node. Without it, a Pressable containing an icon + text becomes two separate reader stops.
- **`accessibilityRole`** tells the reader what this is. Common roles: `button`, `link`, `header`, `image`, `imagebutton`, `text`, `search`, `switch`, `tab`, `tablist`, `adjustable`.
- **`accessibilityLabel`** is what the reader reads. Defaults to visible text, but override when the visible text is ambiguous ("+" → "Add post").
- **`accessibilityHint`** is a secondary description for non-obvious actions. Don't duplicate the label. Users can turn it off, so don't put critical info here.
- **`accessibilityState`** describes current state: `{ disabled, selected, checked, busy, expanded }`. Without this, a disabled button still reads as tappable.
- **`accessibilityValue`** for adjustable things: `{ min, max, now, text }`. Slider, progress bar, stepper.

### Dynamic announcements

```tsx
import { AccessibilityInfo } from 'react-native'

await savePost()
AccessibilityInfo.announceForAccessibility('Post saved')

// iOS-only: queue after current speech finishes
AccessibilityInfo.announceForAccessibilityWithOptions('Post saved', { queue: true })
```

- Use for toasts, form errors, route changes, async success/failure — anywhere a sighted user sees a visual change that a reader would miss.
- **Don't announce on every keystroke.** Throttle to ~500ms or announce only on blur.
- Route changes are auto-announced by expo-router if you set `accessibilityRole="header"` on the screen title.

### Focus management

```tsx
import { AccessibilityInfo, findNodeHandle } from 'react-native'

const errorRef = useRef<View>(null)

useEffect(() => {
  if (error && errorRef.current) {
    const node = findNodeHandle(errorRef.current)
    if (node) AccessibilityInfo.setAccessibilityFocus(node)
  }
}, [error])

return <View ref={errorRef} accessible>{error && <Text>{error}</Text>}</View>
```

- On screen transitions, focus moves to the first focusable element by default. For deep nav stacks, move focus to the header explicitly on mount.
- After form submission failure, move focus to the first error. Sighted users see the error; reader users need the focus to jump.
- Modals should move focus to the modal on open and back to the trigger on close. `@gorhom/bottom-sheet` handles this; hand-rolled modals don't.

### Touch targets and hitSlop

```tsx
<Pressable hitSlop={{ top: 12, bottom: 12, left: 12, right: 12 }}>
  <Icon name="close" size={16} />
</Pressable>
```

- iOS HIG: 44x44pt. Material Design: 48x48dp. RN enforces neither.
- **`hitSlop`** extends the touch area without changing visual size. Use for icon-only buttons where the icon is under 36pt.
- Don't pack two `hitSlop` regions within 44pt of each other — they overlap and the wrong one fires.

### Dynamic type

```tsx
<Text allowFontScaling maxFontSizeMultiplier={1.5}>
  Body text
</Text>

import { useWindowDimensions } from 'react-native'
const { fontScale } = useWindowDimensions()
const isLargeType = fontScale > 1.3
```

- **`allowFontScaling`** defaults to true — respect it. Turning it off makes your app unusable for users with low vision.
- **`maxFontSizeMultiplier`** caps the scale so layouts don't explode at 200%. Sensible range: 1.3–1.6 for body, 1.2 for headlines.
- If `fontScale > 1.3`, consider stacking horizontal layouts vertically. Don't truncate with ellipsis — that hides content.

### Reduce motion

```tsx
import { AccessibilityInfo } from 'react-native'

const [reduceMotion, setReduceMotion] = useState(false)

useEffect(() => {
  AccessibilityInfo.isReduceMotionEnabled().then(setReduceMotion)
  const sub = AccessibilityInfo.addEventListener('reduceMotionChanged', setReduceMotion)
  return () => sub.remove()
}, [])

const style = useAnimatedStyle(() => ({
  transform: [{
    translateY: reduceMotion
      ? withTiming(target, { duration: 0 })
      : withSpring(target)
  }]
}))
```

- Users with vestibular disorders enable this. Parallax, big slide transitions, and bounces trigger symptoms.
- **Never disable motion entirely** — just replace "delightful" animations with instant state changes. The user still needs to see the state transition.
- Shared-element transitions, long springs, and scale-in modals are the usual offenders. Fade-only or instant swap is the safe fallback.

### Color contrast

- WCAG AA: 4.5:1 for body text, 3:1 for large text (18pt+/14pt+ bold).
- WCAG AAA: 7:1 / 4.5:1. Aim here for text on tinted backgrounds.
- Test with a contrast checker (WebAIM, Stark) against the actual rendered hex — not the design spec. Dark mode + semi-transparent overlays often fail even when the light-mode version passes.

### Forms

```tsx
<View>
  <Text nativeID="emailLabel">Email</Text>
  <TextInput
    accessibilityLabelledBy="emailLabel"
    accessibilityLabel="Email"
    keyboardType="email-address"
    autoComplete="email"
    textContentType="emailAddress"
  />
  {error && (
    <Text accessibilityLiveRegion="polite" style={{ color: 'red' }}>
      {error}
    </Text>
  )}
</View>
```

- **`accessibilityLabelledBy`** (Android) + `accessibilityLabel` (iOS) — set both.
- **`accessibilityLiveRegion="polite"`** (Android) announces changes without interrupting. On iOS, use `AccessibilityInfo.announceForAccessibility`.
- Group related inputs with `accessibilityRole="radiogroup"` / `"tablist"`. The reader announces "2 of 4" position context.

### Testing in RNTL

```tsx
import { render, screen } from '@testing-library/react-native'

test('save button announces busy state while saving', () => {
  render(<PostForm isSaving />)
  const button = screen.getByRole('button', { name: 'Save draft' })
  expect(button).toHaveAccessibilityState({ disabled: true, busy: true })
})
```

- Prefer `getByRole` + `getByLabelText` over `getByText`. These match how reader users navigate.
- `toHaveAccessibilityState` and `toHaveAccessibilityValue` matchers catch state bugs.
- **RNTL won't catch focus order or announcement timing.** Manual VoiceOver / TalkBack testing is still required before release.

### Common mistakes

1. **Custom "button" on a View without role/label.** Reader reads "group" or nothing. Fix: always use Pressable with `accessibilityRole="button"`.
2. **Icon buttons without labels.** Reader says "button" with no hint what it does. Fix: `accessibilityLabel="Close"`.
3. **Disabled state via opacity only.** Reader still reports the button as active. Fix: set `accessibilityState.disabled` AND visually dim.
4. **Toast/snackbar shown without announcement.** Sighted users see it; reader users miss it. Fix: `AccessibilityInfo.announceForAccessibility`.
5. **Breaking `allowFontScaling`** to fit text on screen. Layout works; user can't read. Fix: redesign to accommodate scale, or cap with `maxFontSizeMultiplier`.
6. **Skipping manual VoiceOver testing.** RNTL can't catch "the back button isn't focused after open" bugs. Fix: 5-minute VoiceOver walkthrough before every release.

## Topic 14: Forms and TextInput

Forms in RN are where half of all app bugs live. Wrong keyboard type, broken autofill, double-submit on iOS, return key that does nothing on Android, field traversal that jumps to the wrong input. None of these are conceptually hard; they're just a long list of flags you have to know about.

### Keyboard type cheat sheet

```tsx
<TextInput keyboardType="email-address" />     // @ sign visible
<TextInput keyboardType="numeric" />            // numbers only
<TextInput keyboardType="decimal-pad" />        // numbers + decimal
<TextInput keyboardType="phone-pad" />          // digits + * #
<TextInput keyboardType="url" />                // . / .com visible
<TextInput keyboardType="number-pad" />         // digits only
<TextInput keyboardType="default" />            // everything
```

- **iOS only:** `ascii-capable`, `numbers-and-punctuation`, `twitter`, `web-search`.
- **Android only:** `visible-password`.
- **Don't** use `default` for email or phone. Users notice and it signals sloppy.
- **Numeric with minus sign:** use `keyboardType="numbers-and-punctuation"` on iOS; Android has no equivalent — add a "-/+" toggle button.

### Autofill (iOS + Android)

```tsx
<TextInput
  textContentType="emailAddress"    // iOS: drives Keychain / credential suggestion
  autoComplete="email"              // Android: drives Google autofill
  keyboardType="email-address"
  autoCapitalize="none"
  autoCorrect={false}
/>
```

- **Set both `textContentType` and `autoComplete`.** iOS reads `textContentType`, Android reads `autoComplete`. Skipping one disables autofill on that platform.
- **Common pairs:** `emailAddress` / `email`, `password` / `password`, `newPassword` / `password-new`, `oneTimeCode` / `sms-otp`, `givenName` / `name-given`, `postalCode` / `postal-code`, `telephoneNumber` / `tel`.
- **OTP autofill:** `textContentType="oneTimeCode"` (iOS auto-populates from SMS), `autoComplete="sms-otp"` (Android). Biggest single UX win on any login screen.
- **Passwords:** always `secureTextEntry`, `autoCapitalize="none"`, `autoCorrect={false}`. Use `textContentType="password"` for signin, `"newPassword"` for signup — the latter triggers iCloud Keychain's "save strong password" prompt.

### Field traversal (ref chaining)

```tsx
const emailRef = useRef<TextInput>(null)
const passwordRef = useRef<TextInput>(null)

<TextInput
  ref={emailRef}
  returnKeyType="next"
  onSubmitEditing={() => passwordRef.current?.focus()}
  blurOnSubmit={false}
/>
<TextInput
  ref={passwordRef}
  returnKeyType="done"
  onSubmitEditing={handleSubmit}
  secureTextEntry
/>
```

- **`returnKeyType="next"`** changes the keyboard's return key label to "Next". Must be paired with `onSubmitEditing` + `ref.focus()`.
- **`blurOnSubmit={false}`** on all fields except the last. Without it, the keyboard dismisses between fields and re-animates for each — jarring.
- **`returnKeyType="done"`** on the last field, with `onSubmitEditing={handleSubmit}`.
- **Android quirk:** `returnKeyType` values `"next"`, `"done"`, `"go"`, `"search"`, `"send"` work. iOS supports those plus `"default"`, `"route"`, `"yahoo"`, `"emergency-call"`, `"google"`, `"join"`.

### Secure inputs

```tsx
const [visible, setVisible] = useState(false)

<View style={{ flexDirection: 'row' }}>
  <TextInput
    secureTextEntry={!visible}
    autoCapitalize="none"
    autoCorrect={false}
    textContentType="password"
    autoComplete="password"
    clearButtonMode="while-editing"   // iOS
  />
  <Pressable onPress={() => setVisible(v => !v)}>
    <Text>{visible ? 'Hide' : 'Show'}</Text>
  </Pressable>
</View>
```

- **Toggling `secureTextEntry`** resets the text on Android in some RN versions. Test the toggle before shipping.
- **`clearButtonMode`** is iOS-only. Android needs a custom clear button.
- **Paste button visibility** is a known iOS irritant with `secureTextEntry={true}` — iOS hides it. Users long-press to paste. Document this for your support team.

### Validation patterns

```tsx
const [email, setEmail] = useState('')
const [emailTouched, setEmailTouched] = useState(false)
const emailError = emailTouched && !isValidEmail(email) ? 'Invalid email' : null

<TextInput
  value={email}
  onChangeText={setEmail}
  onBlur={() => setEmailTouched(true)}
/>
{emailError && <Text>{emailError}</Text>}
```

- **On blur, not on change.** Typing should never show errors — only blur (or submit attempt). Otherwise the user sees "Invalid" while typing the first character.
- **On submit, show ALL errors at once** + focus the first error input + announce via AccessibilityInfo.
- **Disable submit button only for cardinal errors** (empty required fields). Let the user tap submit to see the rest — greyed-out submit with no explanation is worse than a tap-to-reveal list.

### When to reach for a form library

Hand-rolled `useState` for 1–3 fields is fine. For anything bigger, use `react-hook-form` with the RN adapter.

```tsx
import { useForm, Controller } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'

const { control, handleSubmit, formState: { errors } } = useForm({
  resolver: zodResolver(postSchema),
  defaultValues: { title: '', body: '' },
})

<Controller
  control={control}
  name="title"
  render={({ field: { onChange, onBlur, value } }) => (
    <TextInput value={value} onChangeText={onChange} onBlur={onBlur} />
  )}
/>
```

- **Why react-hook-form:** uncontrolled by default (no re-render per keystroke), built-in validation, integrates with Zod resolver, handles field arrays, minimal bundle cost.
- **Why not Formik:** re-renders the entire form on each keystroke. Perceptible lag on slow devices with 10+ fields.
- **Zod is worth it here** — keeps validation logic mirrored with server schemas, and the resolver wiring is already done.

### Keyboard dismissal

```tsx
<ScrollView
  keyboardShouldPersistTaps="handled"
  keyboardDismissMode="interactive"
>
  {/* form fields */}
</ScrollView>
```

- **`keyboardShouldPersistTaps="handled"`** lets taps on buttons work while the keyboard is open. Default `"never"` dismisses the keyboard on any tap — often eats the tap entirely.
- **`keyboardDismissMode="on-drag"`** dismisses when the user scrolls. `"interactive"` (iOS only) lets the keyboard follow the scroll gesture.
- **For full-screen forms, use `react-native-keyboard-controller`** instead of `KeyboardAvoidingView`. It's worklet-based, no layout jank, handles keyboard-aware scrolling automatically. The built-in component is flaky on iOS and broken on Android for complex layouts.

### Quick reference

| Scenario | keyboardType | textContentType | autoComplete |
|----------|-------------|-----------------|--------------|
| Email | `email-address` | `emailAddress` | `email` |
| Password (login) | `default` | `password` | `password` |
| Password (new) | `default` | `newPassword` | `password-new` |
| OTP / 2FA code | `number-pad` | `oneTimeCode` | `sms-otp` |
| Phone | `phone-pad` | `telephoneNumber` | `tel` |
| Name | `default` | `name` | `name` |
| Postal code | `numeric` | `postalCode` | `postal-code` |
| URL | `url` | `URL` | `url` |
| Credit card number | `number-pad` | `creditCardNumber` | `cc-number` |

### Common mistakes

1. **No autofill.** Users retype emails and passwords on every login. Fix: set `textContentType` and `autoComplete` on every form.
2. **`keyboardType="default"` for email / numeric fields.** Users notice. Fix: use the right keyboardType.
3. **`blurOnSubmit` defaulting true on middle fields.** Keyboard dismisses and re-opens between fields. Fix: `blurOnSubmit={false}` on non-last fields.
4. **Validating on `onChangeText`.** Errors flicker while the user is still typing the first character. Fix: validate on blur or submit.
5. **`KeyboardAvoidingView` for non-trivial forms.** Broken on Android, flaky on iOS. Fix: `react-native-keyboard-controller`.
6. **Hand-rolled `useState` for 10+ fields.** Every keystroke re-renders the entire form. Fix: `react-hook-form`.

## Topic 15: Type-safe navigation params

expo-router's param story has two separate problems: (1) what you pass to `router.push`, (2) what you read with `useLocalSearchParams`. Both default to `string`. Fixing both is a 15-line exercise and saves hours of debugging.

### Typed routes (the easy part)

```ts
// app.config.ts
export default {
  expo: {
    experiments: { typedRoutes: true },
  },
}
```

Enables autocompletion on string literal hrefs:

```tsx
<Link href="/posts/123" />               // typed, autocomplete works
<Link href="/ppost/123" />               // TS error
router.push('/posts/123')                // typed
```

- **The generator** runs on `npx expo start` and writes to `.expo/types/router.d.ts`. Add `.expo/` to `.gitignore` but keep the types on disk locally.
- **Only covers the href string itself.** Dynamic segments typecheck against your file structure, but query params don't.

### useLocalSearchParams generics (the trap)

```tsx
// app/posts/[id].tsx
import { useLocalSearchParams } from 'expo-router'

export default function PostScreen() {
  const { id, tab } = useLocalSearchParams<{ id: string; tab?: 'comments' | 'likes' }>()
  // id: string | string[] (!)
}
```

- **The generic narrows the object keys, not the value types.** RN navigation always parses segments as strings, and arrays for repeated query params. `id` is typed as `string | string[]` regardless of what you wrote in the generic.
- **Numbers come back as strings.** `/posts/123?count=5` gives `{ id: '123', count: '5' }`.
- **Arrays:** `/posts/123?tag=a&tag=b` gives `{ tag: ['a', 'b'] }`. A generic that says `tag: string` is a lie.

### Object-form router.push

```tsx
// Better than string concatenation
router.push({
  pathname: '/posts/[id]',
  params: { id: post.id, tab: 'comments' },
})
```

- **Survives refactors** — rename the file and TS errors propagate.
- **Serializes non-string params for you** (numbers → strings).
- **Can't pass objects.** `params: { post: {...} }` silently stringifies to `[object Object]`. Either pass an ID and refetch, or stash in a store and pass a key.
- **Don't pass large state through params.** URLs on Android have length limits (~2000 chars in practice). Use a store or cache.

### Zod param validation at the screen boundary

```ts
// src/routes/schemas.ts
import { z } from 'zod'

export const postRouteSchema = z.object({
  id: z.string().uuid(),
  tab: z.enum(['comments', 'likes']).default('comments'),
})
```

```tsx
// app/posts/[id].tsx
import { useLocalSearchParams, useRouter } from 'expo-router'
import { postRouteSchema } from '@/routes/schemas'

export default function PostScreen() {
  const raw = useLocalSearchParams()
  const router = useRouter()
  const parsed = postRouteSchema.safeParse(raw)

  if (!parsed.success) {
    return <InvalidRoute onDismiss={() => router.back()} />
  }

  const { id, tab } = parsed.data   // id: string (uuid), tab: 'comments' | 'likes'
  return <PostView id={id} tab={tab} />
}
```

- **Catches deep links with garbage params.** A malformed universal link (`myapp://posts/null?tab=evil`) hits `safeParse` and bounces to a safe state instead of crashing in the render body.
- **Applies defaults.** `tab` defaults to `'comments'` if missing — no optional chaining all over the render.
- **Coerces numerics.** `z.coerce.number().int().min(1)` parses `'5'` → `5` and rejects `'abc'`.
- **One-line fix for the string-only problem** without writing a custom parser.

### Centralized route schema file (for larger apps)

```ts
// src/routes/schemas.ts
export const routes = {
  post: {
    path: '/posts/[id]' as const,
    params: z.object({ id: z.string().uuid(), tab: z.enum(['comments', 'likes']).optional() }),
  },
  profile: {
    path: '/profile/[userId]' as const,
    params: z.object({ userId: z.string().uuid() }),
  },
} as const

// Typed push helper
export function push<K extends keyof typeof routes>(
  key: K,
  params: z.input<typeof routes[K]['params']>
) {
  router.push({ pathname: routes[key].path, params: params as any })
}

// Usage
push('post', { id: post.id })
```

- **Single source of truth** for route shape. Screens use the same schema for parsing.
- **Overhead is ~30 lines** per 10 routes. Worth it on apps with 10+ routes and any deep linking.
- **Overkill for apps with 3 screens.** Use the inline `postRouteSchema` pattern above.

### Common mistakes

1. **Trusting the generic on `useLocalSearchParams`.** `const { id } = useLocalSearchParams<{ id: string }>()` — `id` is actually `string | string[]`. Fix: parse with Zod or `Array.isArray(id) ? id[0] : id`.
2. **Passing objects through params.** Stringifies to `[object Object]`. Fix: pass an ID, refetch; or stash in context/store.
3. **No fallback for invalid params.** Deep link with `?id=null` crashes on `uuid()` call in the render body. Fix: `safeParse` and `<InvalidRoute />` fallback.
4. **String-concat `router.push`.** `router.push(`/posts/${post.id}?tab=comments`)` dies on refactor. Fix: object form with `pathname` + `params`.
5. **Numbers passed as numbers.** `params: { count: 5 }` — on read, `count === '5'`. Fix: `z.coerce.number()` in the schema.

## Topic 16: Error boundaries and Sentry wiring

Topic 9 mentions Sentry once (with the deprecated `sentry-expo` name). This topic is the full treatment: error boundaries, Sentry setup, release tagging, and the OTA correlation that nobody talks about until production breaks.

### React error boundaries in RN
- Same pattern as web React — class component with `static getDerivedStateFromError(err)` and `componentDidCatch(err, info)`.
- Function component error boundaries don't exist; you need a class. Or use `react-error-boundary` (works on RN).
- Fallback UI must offer a retry: `setState({ error: null })` resets the boundary so children re-mount and try again.
- ALWAYS forward to Sentry from `componentDidCatch`: `Sentry.captureException(err, { contexts: { react: { componentStack: info.componentStack } } })`.

```tsx
class ErrorBoundary extends React.Component<Props, { error: Error | null }> {
  state = { error: null }
  static getDerivedStateFromError(error: Error) { return { error } }
  componentDidCatch(error: Error, info: React.ErrorInfo) {
    Sentry.captureException(error, { contexts: { react: { componentStack: info.componentStack } } })
  }
  render() {
    if (this.state.error) return <Fallback onRetry={() => this.setState({ error: null })} />
    return this.props.children
  }
}
```

### What error boundaries do NOT catch
- Event handlers (`onPress`, `onChangeText`) — wrap in try/catch and call `Sentry.captureException` manually.
- Async code (`useEffect`, promises, `setTimeout`) — same: explicit `captureException`.
- Server errors surfaced by TanStack Query — handle via `useQuery({ onError })` (deprecated in v5, use `QueryCache({ onError })` global handler) or render an error state from `query.error`.
- Errors thrown during SSR (N/A for native, but a trap if you also ship Expo Web).

### TanStack Query global error handler
```tsx
new QueryClient({
  queryCache: new QueryCache({
    onError: (error, query) => {
      if (query.state.data !== undefined) return  // background refetch failure — don't alarm
      Sentry.captureException(error, { tags: { queryKey: JSON.stringify(query.queryKey) } })
    },
  }),
})
```

### expo-router error boundaries
- Each route segment can export an `ErrorBoundary` from its `_layout.tsx` — catches render errors in that segment's children.
- Doesn't catch errors from siblings outside the segment, or root-level provider errors.
- Still wrap a custom `<ErrorBoundary>` ABOVE the router itself in your app entry, to catch anything that fails before the router mounts (font loading, auth providers, theme providers).

```tsx
// app/(tabs)/_layout.tsx — segment-level
export function ErrorBoundary({ error, retry }: ErrorBoundaryProps) {
  return <SegmentErrorScreen error={error} onRetry={retry} />
}
```

### Sentry setup for Expo (current path, NOT sentry-expo)
**`sentry-expo` is deprecated as of SDK 50. Use `@sentry/react-native` with the Expo config plugin.** The migration is real; new docs assume this path.

Install:
```bash
npx expo install @sentry/react-native
```

`app.config.ts`:
```ts
export default {
  plugins: [
    [
      '@sentry/react-native/expo',
      {
        url: 'https://sentry.io/',
        organization: process.env.SENTRY_ORG,
        project: process.env.SENTRY_PROJECT,
        // auth token via SENTRY_AUTH_TOKEN env var, NEVER inlined here
      },
    ],
  ],
}
```

`metro.config.js` — must use Sentry's config wrapper to attach Debug IDs to bundles:
```js
const { getSentryExpoConfig } = require('@sentry/react-native/metro')
module.exports = getSentryExpoConfig(__dirname)
```

Init in root `_layout.tsx`:
```tsx
import * as Sentry from '@sentry/react-native'

Sentry.init({
  dsn: process.env.EXPO_PUBLIC_SENTRY_DSN,
  environment: __DEV__ ? 'development' : 'production',
  tracesSampleRate: __DEV__ ? 1.0 : 0.1,
  profilesSampleRate: __DEV__ ? 1.0 : 0.1,
  enableAutoSessionTracking: true,
  sendDefaultPii: false,
  beforeSend,
})

export default Sentry.wrap(RootLayout)  // wraps app in Sentry's auto-instrumented boundary
```

### Source maps
- Handled automatically by the config plugin during EAS Build — the plugin runs `sentry-cli` post-build to upload bundles + maps with matching Debug IDs.
- `SENTRY_AUTH_TOKEN` must be set as an EAS Secret (`eas secret:create --name SENTRY_AUTH_TOKEN`).
- Verify in EAS Build logs: look for "Source maps uploaded to Sentry" near the end of the build.
- If maps don't upload: stack traces show numeric chunk IDs (`index.android.bundle:1:23456`) instead of real filenames. Useless.

### Release tagging & OTA correlation (CRITICAL)
The single most important thing for shipped Expo apps: tag every event with the OTA `updateId`. Without it you cannot tell whether a crash came from a bad OTA push or from the underlying binary.

```tsx
import * as Application from 'expo-application'
import * as Updates from 'expo-updates'
import * as Sentry from '@sentry/react-native'

Sentry.init({
  dsn: process.env.EXPO_PUBLIC_SENTRY_DSN,
  release: `${Application.applicationId}@${Application.nativeApplicationVersion}+${Application.nativeBuildVersion}`,
  dist: Application.nativeBuildVersion ?? undefined,
  // ...
})

// Tag the OTA update id and runtime version on every event in this session
if (Updates.updateId) Sentry.setTag('updateId', Updates.updateId)
if (Updates.runtimeVersion) Sentry.setTag('runtimeVersion', Updates.runtimeVersion)
Sentry.setTag('channel', Updates.channel ?? 'unknown')
Sentry.setTag('isEmbeddedLaunch', String(Updates.isEmbeddedLaunch))
```

Why each tag matters:
- `release` = `appId@version+buildNumber` — bucket by store binary. Without it, all errors collapse into one bucket and you can't tell new bugs from old ones.
- `dist` = build number — disambiguates two TestFlight builds with the same marketing version.
- `updateId` — the EAS Update group running. **A crash spike with the same updateId tag = bad OTA. Republish the previous group, see topic 9 rollback.**
- `runtimeVersion` — fingerprint of the underlying binary. Tells you which build the OTA is sitting on top of.
- `isEmbeddedLaunch` — `true` if running the JS bundled in the binary (no OTA applied yet); `false` if running an OTA. Crash on first launch (embedded) vs after an update is a very different bug.

### Breadcrumbs
- Auto-captured: `fetch`/XHR network requests, console statements, navigation events (with the expo-router integration), touch events.
- Manual: `Sentry.addBreadcrumb({ category: 'auth', message: 'login_attempt', level: 'info', data: { method: 'oauth' } })`.
- Limit: 100 per event by default — Sentry drops the oldest. Don't waste them on noise.
- Strip PII before adding. Email addresses, names, free-text inputs — never include in breadcrumb data.

### User context
```tsx
// On login
Sentry.setUser({ id: user.id })

// On logout
Sentry.setUser(null)
```
- ID only. **Never** email, name, phone, or any other PII. Sentry's user context follows the user across all events in the session.
- Server-side IP scrubbing: enable in Sentry project settings → Security & Privacy → "Prevent Storing of IP Addresses". Belt and suspenders — do it even if you don't think you're sending IPs.

### Performance tracing
- `tracesSampleRate`: `0.1` in prod (10% of transactions), `1.0` in dev. Higher than 0.1 burns quota fast on a popular app.
- Auto-instrumentation:
  - `routingInstrumentation: new Sentry.ReactNavigationInstrumentation()` — works with expo-router (it uses React Navigation under the hood). Wires every screen change as a transaction.
  - Fetch + XHR auto-traced — child spans on the navigation transaction.
- Manual transactions for key flows:
```tsx
const transaction = Sentry.startTransaction({ name: 'checkout.submit' })
try { await submitCheckout() } finally { transaction.finish() }
```

### beforeSend filter (noise reduction)
Sentry's free tier eats quota fast on noisy mobile clients. A `beforeSend` filter is mandatory.
```tsx
function beforeSend(event: Sentry.Event, hint: Sentry.EventHint) {
  const error = hint.originalException
  const message = error instanceof Error ? error.message : String(error ?? '')

  // Drop network errors when offline — expected, not actionable
  if (/Network request failed|Failed to fetch|TypeError: Network/.test(message)) return null
  // Drop user-cancelled image picker / auth flows
  if (/User cancell?ed|UserCancel/.test(message)) return null
  // Drop AbortError from cancelled fetches (route changes mid-flight)
  if (error instanceof Error && error.name === 'AbortError') return null
  // Drop non-error console.warn surfacing
  if (event.level === 'warning') return null

  return event
}
```

### Testing the wiring before ship
- Add a "Throw test error" button behind a `__DEV__` flag or a hidden long-press.
- Trigger it on a real device build (not Expo Go), verify the event lands in Sentry.
- Click into the event in the Sentry dashboard:
  - Stack frames must show real filenames (`app/(tabs)/index.tsx:42`), not `index.android.bundle:1:23456`. If numeric, source maps didn't upload.
  - `release`, `dist`, `updateId`, `runtimeVersion` tags must be populated.
  - User context must be set if you logged in before throwing.
- Test BOTH a fresh embedded launch (`isEmbeddedLaunch: true`) and after an OTA applies (`isEmbeddedLaunch: false`) — they're different code paths.

### Observability KPIs
- **Crash-free sessions rate** — target >99% for shipped consumer apps. Sentry computes this from session tracking (which `enableAutoSessionTracking: true` enables).
- **Crash-free users rate** — what fraction of unique users hit a crash. A 0.5% session rate can mean a 5% user rate if a few users crash repeatedly.
- **Time to first fix** after a spike — measure from spike alert to OTA republish. Should be minutes for non-native fixes (that's the whole point of EAS Update).
- **Quota burn rate** — Sentry charges per event. If `beforeSend` is wrong or `tracesSampleRate` too high, quota burns through mid-month. Set Sentry's spike protection.

### Common mistakes
- **Using deprecated `sentry-expo`** instead of `@sentry/react-native`. The old package is unmaintained as of Jan 2024.
- **No source maps uploaded** — symbolicated stack traces don't work, you waste hours staring at numeric chunks.
- **No `release` tag** — every error from every version buckets together. You can't tell a regression from a long-standing bug.
- **No `updateId` tag** — you ship a bad OTA, crashes spike, you can't tell whether to roll back the OTA or the binary.
- **Logging PII** in user context, breadcrumbs, or extras. GDPR exposure plus Sentry shows it to anyone with project access.
- **try/catch swallowing errors** without `captureException` — the bug lives in production forever, no dashboard signal.
- **No `beforeSend`** — quota burns through on `Network request failed` from users with bad Wi-Fi. Dashboard becomes noise.
- **Setting `tracesSampleRate: 1.0` in production** — turns Sentry into a logging firehose, hits quota in a day.
- **Forgetting to wrap the root layout** in `Sentry.wrap()` — auto-instrumentation never starts, expo-router transactions never fire.
- **Not testing on a release build** before shipping — Expo Go and dev builds behave differently from a production binary; some Sentry features (notably crash reporting from native fatals) only work in real builds.

## Topic 17: State management

Most React Native apps don't need a state management library. Context + TanStack Query handles the vast majority of real apps. The decision rule: **server state goes in TanStack Query, UI state goes in Context, persisted client-local state goes in MMKV/SecureStore with a thin hook.** Reach for Redux / Zustand / Jotai only when you hit a concrete ceiling — not preemptively.

### The default stack

```
┌────────────────────────────────────────────┐
│ TanStack Query  ← everything from the API  │
│   - posts, comments, user profile          │
│   - mutations, optimistic updates           │
│   - offline persistence                     │
├────────────────────────────────────────────┤
│ Context (split) ← UI state, auth, theme    │
│   - AuthContext                             │
│   - ThemeContext                            │
│   - ModalStackContext                       │
├────────────────────────────────────────────┤
│ MMKV / SecureStore ← persisted local state │
│   - draft text, last viewed feed            │
│   - tokens, encrypted creds                 │
└────────────────────────────────────────────┘
```

- **TanStack Query is the biggest win.** Most "state" in a CRUD app is server state. Query handles caching, deduping, invalidation, optimistic updates, and offline — for free. Don't put server data in Context.
- **Context is enough for genuine client state.** Auth token + user object, current theme, current locale, active modal — these are low-frequency, app-wide values.
- **Persistence is separate.** Don't store tokens in Context state alone — they evaporate on reload. SecureStore is the durable store; Context reads from it on boot.

### Split contexts by update frequency

The only way Context becomes a performance problem is putting everything in one.

```tsx
// BAD: one context, one provider, everything re-renders on any change
const AppContext = createContext({ user, theme, modals, filters, drafts })

// GOOD: split by update cadence
const AuthContext = createContext(null)       // changes on login/logout (rare)
const ThemeContext = createContext('light')   // changes on toggle (rare)
const ModalContext = createContext(null)      // changes on open/close (moderate)
const FilterContext = createContext(null)     // changes on type (frequent — don't use context)
```

- **Rare-change values (auth, theme, locale)** go in Context. A re-render on login is fine.
- **Frequent-change values (filter text, scroll position, draft input)** should NOT be in a wide Context. Either keep them local to the screen, or use `useSyncExternalStore` with an external store for cross-screen sharing.
- **One provider per concern.** Easier to test, easier to reason about, avoids cascading re-renders.

### The split-value / split-setter pattern

```tsx
// Avoid re-rendering consumers that only need the setter
const AuthStateContext = createContext<User | null>(null)
const AuthActionsContext = createContext<{ login; logout } | null>(null)

function AuthProvider({ children }) {
  const [user, setUser] = useState<User | null>(null)
  const actions = useMemo(() => ({
    login: (u: User) => setUser(u),
    logout: () => setUser(null),
  }), [])

  return (
    <AuthStateContext.Provider value={user}>
      <AuthActionsContext.Provider value={actions}>
        {children}
      </AuthActionsContext.Provider>
    </AuthStateContext.Provider>
  )
}

export function useUser() { return useContext(AuthStateContext) }
export function useAuthActions() {
  const ctx = useContext(AuthActionsContext)
  if (!ctx) throw new Error('useAuthActions outside AuthProvider')
  return ctx
}
```

- **Components that only call `logout()` don't re-render when `user` changes.** This is the biggest context perf win and costs 10 lines.
- **`useMemo` on the actions object** is essential — without it, the actions context changes identity every render.
- **The custom hook guards against "used outside provider"** — a 5-second bug to add, a 30-minute bug to debug.

### When Context is NOT enough

Three concrete ceilings:

1. **Frequent cross-screen updates to complex derived state.** E.g., a queue UI that re-renders on every mutation status change. Context causes the entire tree under the provider to re-render. Fix: `useSyncExternalStore` with a hand-rolled observable, or reach for a library.
2. **Deeply nested children that selectively subscribe to slices.** Context passes the whole value — selective subscription needs a store with a selector. Redux-toolkit or Zustand both do this cleanly.
3. **Time-travel debugging / undo-redo / devtools.** Redux-toolkit's devtools are unmatched. If your app has a genuine undo stack, this is the right tool.

The key word is **concrete**. "I might need it later" is not a ceiling. Ship with Context, upgrade when you have a reproducible re-render storm or a real feature that needs it.

### useSyncExternalStore for the middle case

```ts
// src/stores/syncQueue.ts
type Listener = () => void
let queue: string[] = []
const listeners = new Set<Listener>()

export const syncQueueStore = {
  subscribe(listener: Listener) {
    listeners.add(listener)
    return () => listeners.delete(listener)
  },
  getSnapshot() { return queue },
  enqueue(id: string) { queue = [...queue, id]; listeners.forEach(l => l()) },
  dequeue(id: string) { queue = queue.filter(q => q !== id); listeners.forEach(l => l()) },
}

export function useSyncQueue() {
  return useSyncExternalStore(syncQueueStore.subscribe, syncQueueStore.getSnapshot)
}
```

- **Lower-level than Context**, same role. Components that call `useSyncQueue()` re-render when the store changes; others don't.
- **No re-render cascades** — the root isn't wrapped in a provider, so updates are opt-in per hook call.
- **Native React primitive.** No new dependency, no library pinning, always compatible with React Concurrent.
- **Use for:** mutation queue UI, snackbar stack, network status badge, anything where a library feels like overkill.

### Redux-toolkit is not bad, it's just usually early

If you're building an app with:
- 20+ screens
- Multiple developers working independently
- Complex feature teams with separate slices
- Genuine undo/redo requirements
- A workflow where Redux devtools pay off

...then Redux-toolkit is fine. It's a small library with excellent devtools, strong conventions, and a huge support footprint. The mistake isn't using Redux — it's using Redux on day 1 for a 5-screen app where Context would have worked.

```ts
// If you do use RTK, use RTK Query — don't reinvent TanStack Query
import { createApi, fetchBaseQuery } from '@reduxjs/toolkit/query/react'

export const api = createApi({
  reducerPath: 'api',
  baseQuery: fetchBaseQuery({ baseUrl: 'https://api.example.com' }),
  endpoints: builder => ({
    getPosts: builder.query<Post[], void>({ query: () => '/posts' }),
  }),
})
```

- **RTK Query is basically TanStack Query-in-Redux.** If you're already on RTK, use it. Don't pair RTK with TanStack Query — pick one data layer.
- **Zustand / Jotai** are fine libraries; they just solve a problem most apps don't have. Skip unless you hit a specific Context performance issue.

### Does offline change the answer?

No. Offline is solved by **persistence + mutation replay** (Topic 12), not by a state library.

- **TanStack Query + PersistQueryClientProvider** already queues mutations and replays them on reconnect. Adding Redux on top doesn't help.
- **Context survives reloads via MMKV hydration.** `useState(() => storage.getString('user'))` on mount is fine for auth.
- **The only thing that gets harder offline** is conflict resolution, and that's a server-protocol problem (ETags, LWW, tombstones), not a client-store problem.

**Escalation rule:** if you're reaching for Redux because of offline, you're solving the wrong problem. Add `PersistQueryClientProvider` first. If that doesn't cover it, reach for WatermelonDB (local-first DB with sync protocol). A state library is the wrong layer.

### Anti-patterns

1. **Putting server data in Context.** Loses caching, deduping, invalidation. Fix: TanStack Query.
2. **One giant `AppContext`.** Entire tree re-renders on every update. Fix: split by concern.
3. **Redux on day 1 for a 5-screen app.** Ships on time, but dev velocity is cut in half by boilerplate. Fix: Context + TanStack Query.
4. **Mixing RTK Query and TanStack Query.** Two cache systems, two invalidation stories, doubled bundle. Fix: pick one.
5. **Storing auth token in Context only.** Evaporates on reload. Fix: SecureStore + Context hydrates from it on boot.
6. **Frequent-update values (text input, scroll position) in app-wide Context.** Re-render storm. Fix: keep local, or `useSyncExternalStore`.
7. **Zustand for a single flag.** Fine library, wrong granularity. Fix: `useState` or Context.

### Quick reference

| State type | Tool |
|------------|------|
| Server data (posts, users, comments) | TanStack Query |
| Auth user + token | Context + SecureStore |
| Theme, locale, feature flags | Context + MMKV |
| Current screen form values | `useState` + `react-hook-form` |
| Draft text across screens | MMKV + `useSyncExternalStore` |
| Modal / dialog stack | Context (split state/actions) |
| Toast / snackbar queue | `useSyncExternalStore` |
| Mutation queue UI | TanStack Query `useIsMutating` |
| Undo/redo history | Redux-toolkit |
| Cross-feature, complex derived state | Redux-toolkit or Zustand |

## Topic 18: Deep linking, Universal Links, App Links

Deep linking is easy to get 70% right and nearly impossible to get 100% right without actually testing on devices. The 30% that breaks: cold-start vs warm-start handling, universal link routing after iOS prompts for permission, Android App Link verification failing silently, and OAuth redirect loops.

### Scheme setup

```ts
// app.config.ts
export default {
  expo: {
    scheme: 'myapp',                      // myapp://posts/123
    ios: {
      associatedDomains: ['applinks:example.com', 'applinks:www.example.com'],
    },
    android: {
      intentFilters: [
        {
          action: 'VIEW',
          autoVerify: true,
          data: [
            { scheme: 'https', host: 'example.com' },
            { scheme: 'https', host: 'www.example.com' },
          ],
          category: ['BROWSABLE', 'DEFAULT'],
        },
      ],
    },
  },
}
```

- **Custom scheme (`myapp://`)** works everywhere but isn't verified — any app can claim it. Fine for dev + internal flows, not for production entry points.
- **Universal Links (iOS) / App Links (Android)** use HTTPS URLs and require server-side verification. These are the "right" entry points from Safari, email, and search results.
- **`associatedDomains`** must match exactly. `applinks:example.com` does NOT cover `www.example.com`. Add both.
- **`autoVerify: true`** on Android is what makes the OS verify `assetlinks.json` on install. Skip it and the OS shows a chooser dialog instead of launching the app.

### Server-side verification files

**iOS — `apple-app-site-association`** (hosted at `https://example.com/.well-known/apple-app-site-association`):

```json
{
  "applinks": {
    "apps": [],
    "details": [
      {
        "appID": "TEAMID.com.example.myapp",
        "paths": ["/posts/*", "/users/*", "NOT /admin/*"]
      }
    ]
  }
}
```

- **Must be served over HTTPS**, content-type `application/json`, no redirect, no extension.
- **Must be at `/.well-known/apple-app-site-association`** (and optionally also at `/apple-app-site-association` — some older clients hit that path).
- **`appID` format:** `<Team ID>.<Bundle ID>`. Team ID is in your Apple Developer account. Get it wrong and iOS silently falls back to opening Safari.
- **Cache:** iOS caches this for ~7 days. Fixes don't propagate immediately — test devices need delete+reinstall or a wait.

**Android — `assetlinks.json`** (hosted at `https://example.com/.well-known/assetlinks.json`):

```json
[
  {
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
      "namespace": "android_app",
      "package_name": "com.example.myapp",
      "sha256_cert_fingerprints": ["14:6D:E9:..."]
    }
  }
]
```

- **`sha256_cert_fingerprints`** must match the signing key Android actually uses. **With EAS Build + Play App Signing, use the Play Console upload cert AND the Google app signing cert** — not your local debug keystore.
- **Verify with:** `https://digitalassetlinks.googleapis.com/v1/statements:list?source.web.site=https://example.com&relation=delegate_permission/common.handle_all_urls`. Returns the parsed statement or an error. Use this before shipping.
- **Verification is one-shot at install time.** If the file isn't there when the user installs, the OS gives up and shows the chooser forever — even after you publish the file. Users have to reinstall.

### expo-router auto deep linking

expo-router wires paths to files automatically.

```
app/
  posts/
    [id].tsx          → myapp://posts/123 opens PostScreen with id=123
    [id]/
      comments.tsx    → myapp://posts/123/comments
  (tabs)/
    feed.tsx          → myapp://feed
```

- **No manual linking config.** The file structure IS the route table.
- **Dynamic segments map to params.** `[id]` becomes `useLocalSearchParams().id`.
- **Query params pass through.** `myapp://posts/123?tab=comments` → `{ id: '123', tab: 'comments' }`.
- **Group routes `(tabs)`** don't appear in URLs. `app/(tabs)/feed.tsx` is `myapp://feed`, not `myapp://(tabs)/feed`.

### Cold start vs warm state

```tsx
import * as Linking from 'expo-linking'
import { useEffect } from 'react'

function useDeepLinkHandler() {
  useEffect(() => {
    // Cold start: app was killed, link opens it
    Linking.getInitialURL().then(url => {
      if (url) handleDeepLink(url)
    })

    // Warm state: app is already running
    const sub = Linking.addEventListener('url', ({ url }) => {
      handleDeepLink(url)
    })
    return () => sub.remove()
  }, [])
}
```

- **`getInitialURL()`** is the cold-start path. Returns the URL that launched the app, or `null` if the user tapped the icon.
- **`addEventListener('url', ...)`** is the warm-start path. Fires when the app is foregrounded by a link while already running.
- **expo-router handles both for its own routes.** You only need the manual handler if you have side effects (analytics, auth token exchange, custom logic) tied to deep link arrival.
- **Don't handle both AND rely on expo-router** — you'll double-navigate. Pick one layer.

### OAuth with expo-auth-session

```tsx
import * as AuthSession from 'expo-auth-session'
import * as WebBrowser from 'expo-web-browser'

WebBrowser.maybeCompleteAuthSession()  // MUST be called at module scope

const redirectUri = AuthSession.makeRedirectUri({ scheme: 'myapp', path: 'auth' })
// Dev: exp://192.168.1.1:8081/--/auth
// Standalone: myapp://auth

const [request, response, promptAsync] = AuthSession.useAuthRequest(
  {
    clientId: process.env.EXPO_PUBLIC_OAUTH_CLIENT_ID!,
    scopes: ['openid', 'profile', 'email'],
    redirectUri,
  },
  { authorizationEndpoint: 'https://auth.example.com/authorize' }
)
```

- **`maybeCompleteAuthSession()`** at module scope handles the redirect back. Miss this and the browser window never closes on successful auth.
- **`makeRedirectUri({ scheme })`** produces dev-friendly URIs in Expo Go + standalone URIs in release. Don't hardcode.
- **Redirect URI must match EXACTLY** what's registered with the OAuth provider. Mismatches → silent failure or "redirect_uri_mismatch" error in the browser.
- **Use PKCE.** Default in `expo-auth-session`. Don't disable.

### Testing deep links

```bash
# iOS simulator
xcrun simctl openurl booted "myapp://posts/123"
xcrun simctl openurl booted "https://example.com/posts/123"

# Android emulator / device
adb shell am start -W -a android.intent.action.VIEW -d "myapp://posts/123"
adb shell am start -W -a android.intent.action.VIEW -d "https://example.com/posts/123"
```

- **Custom scheme test first.** If `myapp://posts/123` doesn't work, universal links definitely won't. Rule out the router before blaming the cert.
- **Universal Link cold-open test:** kill the app, tap a real link in Notes.app or Messages.app. `xcrun simctl openurl` doesn't exercise the universal link path — it falls through to the scheme.
- **App Link verification status:** `adb shell pm get-app-links com.example.myapp`. Shows verified domains + verification state. `legacy_failure` = `assetlinks.json` not reachable at install time.

### Common mistakes

1. **`applinks:example.com` without `applinks:www.example.com`.** www subdomain links open Safari instead of the app. Fix: register both.
2. **`assetlinks.json` with wrong SHA-256.** EAS re-signs apps with Play's cert. Debug keystore fingerprint doesn't match. Fix: use Play Console's "App signing" page cert.
3. **Handling both `Linking.addEventListener` AND expo-router auto-routing.** Double navigation. Fix: pick one layer per link.
4. **Not testing cold start.** `getInitialURL` returns `null` in Expo Go dev reloads. Ship with a cold-start bug. Fix: test via real-device cold tap + `xcrun simctl`.
5. **Hardcoded OAuth redirect.** Works in dev, 404s in release. Fix: `AuthSession.makeRedirectUri({ scheme })`.
6. **Universal link cache.** iOS caches `apple-app-site-association` for a week. Your fix doesn't propagate. Fix: uninstall + reinstall on test devices; document the cache in your release notes.
7. **Missing `autoVerify: true` on Android.** OS shows a chooser on first tap forever. Fix: set it, re-publish `assetlinks.json`, reinstall.
8. **Invalid params crashing the screen.** Deep link opens `/posts/null`, `useLocalSearchParams().id` is `'null'` as a string. Fix: Zod validate at the screen boundary (Topic 15).

## Topic 19: Component composition

React Native UI code gets ugly fast when every screen is a 600-line component with conditional rendering for every state. The way out is composition — small primitives that combine, not giant components with twenty props. Four patterns carry most of the weight.

### Compound components

The component tree describes the structure; consumers wire it up.

```tsx
// src/components/Sheet.tsx
import { createContext, useContext, useState } from 'react'
import { Modal, Pressable, View, Text } from 'react-native'

const SheetContext = createContext<{ open: boolean; setOpen: (v: boolean) => void } | null>(null)

function useSheet() {
  const ctx = useContext(SheetContext)
  if (!ctx) throw new Error('Sheet subcomponents must be used within Sheet.Root')
  return ctx
}

function Root({ children }: { children: React.ReactNode }) {
  const [open, setOpen] = useState(false)
  return <SheetContext.Provider value={{ open, setOpen }}>{children}</SheetContext.Provider>
}

function Trigger({ children }: { children: React.ReactNode }) {
  const { setOpen } = useSheet()
  return <Pressable onPress={() => setOpen(true)}>{children}</Pressable>
}

function Content({ children }: { children: React.ReactNode }) {
  const { open, setOpen } = useSheet()
  return (
    <Modal visible={open} animationType="slide" onRequestClose={() => setOpen(false)}>
      <View style={{ flex: 1, padding: 16 }}>{children}</View>
    </Modal>
  )
}

function Header({ children }: { children: React.ReactNode }) {
  return <Text style={{ fontSize: 20, fontWeight: '600' }}>{children}</Text>
}

function Close({ children }: { children: React.ReactNode }) {
  const { setOpen } = useSheet()
  return <Pressable onPress={() => setOpen(false)}>{children}</Pressable>
}

export const Sheet = { Root, Trigger, Content, Header, Close }
```

```tsx
// Usage
<Sheet.Root>
  <Sheet.Trigger><Text>Open</Text></Sheet.Trigger>
  <Sheet.Content>
    <Sheet.Header>Edit post</Sheet.Header>
    <PostForm />
    <Sheet.Close><Text>Cancel</Text></Sheet.Close>
  </Sheet.Content>
</Sheet.Root>
```

- **Why compound over `<Sheet title="..." actions={...} content={...} />`:** props explode as features grow. Compound components let consumers put children in the right slot.
- **Shared state lives in a context scoped to `Root`.** The `useSheet` hook throws if used outside — the five-second guard that saves thirty minutes.
- **Dot notation export (`Sheet.Root`)** keeps imports clean. Treeshaking still works because each piece is a named export under the hood.

### Slot props (named children)

For cases where you want named slots without a full compound API:

```tsx
type ScreenProps = {
  headerLeft?: React.ReactNode
  headerRight?: React.ReactNode
  title: string
  children: React.ReactNode
}

function Screen({ headerLeft, headerRight, title, children }: ScreenProps) {
  return (
    <View style={{ flex: 1 }}>
      <View style={{ flexDirection: 'row', alignItems: 'center', padding: 16 }}>
        <View>{headerLeft}</View>
        <Text style={{ flex: 1, textAlign: 'center' }}>{title}</Text>
        <View>{headerRight}</View>
      </View>
      <View style={{ flex: 1 }}>{children}</View>
    </View>
  )
}

// Usage
<Screen
  title="Feed"
  headerLeft={<BackButton />}
  headerRight={<NotificationBell />}
>
  <FeedList />
</Screen>
```

- **Simpler than compound** — no context, no separate pieces.
- **Breaks down past ~3 slots.** If you have 5+ named slots, compound is clearer.

### Custom hooks for stateful logic

Logic extraction — the UI stays dumb, state lives in a hook.

```tsx
// src/hooks/usePostDraft.ts
import { useEffect, useState } from 'react'
import { MMKV } from 'react-native-mmkv'

const storage = new MMKV()

export function usePostDraft(key: string) {
  const [draft, setDraft] = useState(() => storage.getString(`draft:${key}`) ?? '')

  useEffect(() => {
    if (draft) storage.set(`draft:${key}`, draft)
    else storage.delete(`draft:${key}`)
  }, [draft, key])

  const clear = () => setDraft('')
  return { draft, setDraft, clear }
}
```

```tsx
function PostEditor({ postId }: { postId: string }) {
  const { draft, setDraft, clear } = usePostDraft(postId)
  return (
    <View>
      <TextInput value={draft} onChangeText={setDraft} />
      <Button title="Clear" onPress={clear} />
    </View>
  )
}
```

- **The hook owns persistence.** The component is unaware.
- **Reusable across screens.** The list screen and the edit screen both see the same draft.
- **Testable without rendering.** `renderHook(() => usePostDraft('abc'))` exercises the logic in isolation.

### Render props / function-as-children (sparingly)

Useful when consumers need to invert control over rendering.

```tsx
function Query<T>({ queryKey, queryFn, children }: {
  queryKey: unknown[]
  queryFn: () => Promise<T>
  children: (state: { data?: T; isLoading: boolean; error?: Error }) => React.ReactNode
}) {
  const query = useQuery({ queryKey, queryFn })
  return <>{children(query)}</>
}

// Usage
<Query queryKey={['posts']} queryFn={() => api.getPosts()}>
  {({ data, isLoading, error }) => {
    if (isLoading) return <Spinner />
    if (error) return <Text>{error.message}</Text>
    return <FeedList posts={data!} />
  }}
</Query>
```

- **Rarely the best answer.** Custom hooks replace most render props these days. Use only when you need JSX composition that a hook can't express.
- **Common legitimate use:** rendering N copies where each depends on shared parent state (e.g., `<Draggable>{({ x, y }) => ...}</Draggable>`).

### Polymorphic `as` prop

```tsx
type ButtonProps<E extends React.ElementType> = {
  as?: E
  children: React.ReactNode
} & Omit<React.ComponentProps<E>, 'children'>

function Button<E extends React.ElementType = typeof Pressable>({
  as,
  children,
  ...rest
}: ButtonProps<E>) {
  const Component = as ?? Pressable
  return <Component {...rest}><Text>{children}</Text></Component>
}

// Usage
<Button onPress={handle}>Save</Button>                          // Pressable
<Button as={Link} href="/profile">Profile</Button>              // Link
```

- **Use sparingly.** Polymorphic components have rough TypeScript ergonomics. A plain `LinkButton` component is often clearer than `<Button as={Link}>`.
- **react-native-reusables and NativeWind's `cssInterop`** both use this pattern — if you're adopting them, you'll see it a lot. Otherwise, write plain components.

### Building reusable primitives

```tsx
// src/ui/Text.tsx
import { Text as RNText, TextProps, StyleSheet } from 'react-native'

type Variant = 'body' | 'caption' | 'heading' | 'title'

export function Text({
  variant = 'body',
  style,
  ...rest
}: TextProps & { variant?: Variant }) {
  return <RNText style={[styles[variant], style]} {...rest} />
}

const styles = StyleSheet.create({
  body: { fontSize: 16, color: '#111' },
  caption: { fontSize: 12, color: '#666' },
  heading: { fontSize: 20, fontWeight: '600' },
  title: { fontSize: 24, fontWeight: '700' },
})
```

- **Wrapping `<Text>` is cheap.** Every screen benefits from consistent typography.
- **`style` prop still works** — arrays merge, user overrides win.
- **Variants are not Tailwind.** Use NativeWind if you want utility-class styling; otherwise stick to `variant` enums + StyleSheet.

### When to split a component

Heuristics that hold up in practice:

- **>400 lines** — split. Almost always a sign of mixed concerns.
- **>5 useState hooks** — extract to a custom hook.
- **JSX returning 3+ top-level branches** (`if (loading) ... else if (error) ... else`) — extract a `ScreenState` wrapper (see Topic 23).
- **Props list over 10** — consumer can't reason about it. Split into compound or slot-based.
- **Copy-pasted twice** — extract on the second copy. Wait for the third if unsure.

### Common mistakes

1. **Passing 15 props to one component.** Symptom of missing composition. Fix: compound components or slot props.
2. **Deeply nested conditional rendering in the return body.** `if (loading) ... else if (error) ... else if (!data.length) ... else ...`. Fix: `ScreenState` wrapper (Topic 23).
3. **Logic-heavy components.** Multiple `useState`, `useEffect`, derived state in one screen. Fix: extract to custom hooks.
4. **Premature `as` prop.** A flexible polymorphic component before you have two concrete variants. Fix: write `LinkButton` + `Button`, converge later.
5. **Compound components without a context guard.** `useSheet` outside `Sheet.Root` returns `null` and crashes later in a mystery place. Fix: `throw` in the hook if context is missing.
6. **Rendering invisible spacer Views for layout.** NativeWind's `gap-*` or StyleSheet `gap` handle this now. Fix: upgrade RN ≥ 0.71 and use `gap`.

## Topic 20: Internationalization with expo-localization

Localization in RN splits into two libraries: `expo-localization` detects the device locale + timezone, and a translation library (`i18n-js`, `lingui`, `react-intl`) owns the actual strings. `expo-localization` alone does NOT translate anything — this is the #1 source of confusion.

### expo-localization for device info

```ts
import * as Localization from 'expo-localization'

Localization.getLocales()
// [
//   { languageTag: 'en-US', languageCode: 'en', regionCode: 'US', currencyCode: 'USD', ... },
//   { languageTag: 'es-MX', languageCode: 'es', regionCode: 'MX', currencyCode: 'MXN', ... },
// ]

Localization.getCalendars()
// [{ calendar: 'gregorian', timeZone: 'America/Los_Angeles', uses24hourClock: false, ... }]
```

- **`getLocales()`** returns the ordered list of user-preferred locales. First entry is the primary.
- **`getCalendars()`** returns calendar + time zone + 12/24 hour preference. Use `timeZone` for date display; don't assume device time zone from elsewhere.
- **React to changes:** users can change language without reinstalling the app. Subscribe and rehydrate i18n if you want to support runtime locale switching.

### i18n-js for strings

```ts
// src/i18n/index.ts
import { I18n } from 'i18n-js'
import * as Localization from 'expo-localization'

import en from './locales/en.json'
import es from './locales/es.json'
import ja from './locales/ja.json'

export const i18n = new I18n({ en, es, ja })
i18n.defaultLocale = 'en'
i18n.enableFallback = true
i18n.locale = Localization.getLocales()[0]?.languageCode ?? 'en'

export const t = (key: string, options?: object) => i18n.t(key, options)
```

```json
// src/i18n/locales/en.json
{
  "greeting": "Hello, {{name}}!",
  "posts": {
    "count": {
      "one": "1 post",
      "other": "{{count}} posts"
    }
  }
}
```

```tsx
t('greeting', { name: 'Anna' })      // "Hello, Anna!"
t('posts.count', { count: 0 })        // "0 posts"
t('posts.count', { count: 1 })        // "1 post"
t('posts.count', { count: 5 })        // "5 posts"
```

- **`enableFallback: true`** falls back to the default locale if a key is missing. Without it, missing keys render as `[missing "key" translation]` in production.
- **Interpolation:** `{{name}}` syntax, safely handled (no innerHTML risk — we're in RN, not web).
- **Pluralization:** nested `{ one, other, zero, two, few, many }` keys. Use `count` option; `i18n-js` picks the right plural rule per locale.

### Intl.* APIs for formatting

Built-in, no libraries needed. RN includes `Intl` on Hermes in SDK 52+.

```ts
// Dates
new Intl.DateTimeFormat('en-US', { dateStyle: 'medium' }).format(new Date())
// "Apr 13, 2026"

new Intl.DateTimeFormat('ja-JP', { dateStyle: 'full', timeStyle: 'short' }).format(new Date())
// "2026年4月13日月曜日 14:32"

// Numbers
new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(1234.56)
// "$1,234.56"

new Intl.NumberFormat('de-DE', { style: 'currency', currency: 'EUR' }).format(1234.56)
// "1.234,56 €"

// Relative time
new Intl.RelativeTimeFormat('en', { numeric: 'auto' }).format(-1, 'day')
// "yesterday"

// List formatting
new Intl.ListFormat('en', { style: 'long', type: 'conjunction' }).format(['a', 'b', 'c'])
// "a, b, and c"
```

- **Prefer `Intl.*` over date-fns / numeral / custom code.** Native, locale-aware, zero bundle cost.
- **`Intl.RelativeTimeFormat`** replaces "2 days ago" helpers. Handles negation and pluralization automatically.
- **Locale for `Intl`** should come from `Localization.getLocales()[0]?.languageTag`, not `languageCode`. "en" works but "en-US" gets region-specific formatting.
- **Hermes includes `Intl` in SDK 52+** but only small-icu by default. If you need full CJK support, enable full-icu via config plugin.

### RTL support

```ts
import { I18nManager } from 'react-native'
import * as Updates from 'expo-updates'

const isRTL = ['ar', 'he', 'fa', 'ur'].includes(i18n.locale)
if (I18nManager.isRTL !== isRTL) {
  I18nManager.allowRTL(true)
  I18nManager.forceRTL(isRTL)
  // MUST reload after changing — RN caches layout direction at bundle start
  Updates.reloadAsync()
}
```

- **RTL is per-bundle-load.** Changing it requires an app restart. `Updates.reloadAsync()` does this cleanly.
- **Most layouts just work.** Flexbox `row` auto-reverses in RTL. Use `start` / `end` instead of `left` / `right` everywhere (`paddingStart`, `marginEnd`, `textAlign: 'left'` → `textAlign: 'start'`).
- **Hard-coded `transform: [{ translateX }]`** does NOT auto-reverse. Use `I18nManager.isRTL ? -x : x`.
- **Reanimated RTL gotcha:** Reanimated values are raw pixels — they don't know about `I18nManager`. Any gesture or animation using `translateX` needs manual RTL adjustment.

### Bundling translations

```ts
// Eager require for <10 locales
i18n.translations = {
  en: require('./locales/en.json'),
  es: require('./locales/es.json'),
}

// Dynamic import for 30+ locales
async function loadLocale(lang: string) {
  const translations = await import(`./locales/${lang}.json`)
  i18n.translations[lang] = translations.default
}
```

- **Eagerly require** for <10 locales. Bundling 10 JSON files adds ~50KB.
- **Dynamic import** for 30+ locales. Requires Metro resolver config for the glob.
- **Don't fetch from the server** unless you have remote-config-like requirements. Every boot needs strings — network dependency is brittle.

### Common mistakes

1. **Using `expo-localization` to translate.** It only detects the locale. Translation needs `i18n-js` or similar. Fix: read the docs closely before shipping "localization support."
2. **Hardcoded `en-US` for `Intl.*`.** Dates appear as "Apr 13, 2026" to Japanese users. Fix: `Intl.DateTimeFormat(Localization.getLocales()[0].languageTag, ...)`.
3. **Missing `enableFallback: true`.** Missing keys render as `[missing "key.subkey" translation]` in production. Fix: enable fallback, write a CI script to flag missing keys.
4. **RTL tested in Safari only.** Actual RTL on device needs `forceRTL` + reload. Fix: test on a device with `I18nManager.forceRTL(true)` + `Updates.reloadAsync()`.
5. **String concatenation instead of interpolation.** `t('hello') + ' ' + name` breaks in languages with different word order. Fix: `t('greeting', { name })` with a template in the JSON.
6. **Reanimated gesture not flipped in RTL.** Swipe-to-delete goes the wrong way in Arabic. Fix: `const dir = I18nManager.isRTL ? -1 : 1` and multiply at the animation site.
7. **Date format strings (`'MM/DD/YYYY'`).** Non-US users see wrong order. Fix: `Intl.DateTimeFormat` with `dateStyle` preset.

## Topic 21: Background tasks

**Reality check: most apps don't need background tasks.** The iOS budget is strict (30s per run, OS decides when), Android's Doze mode kills your scheduling, and debugging is painful. Ship without them first; add only when you hit a real "must run while closed" requirement.

### When background tasks ARE worth it

- **Sync pending mutations on reconnect** when the app has been closed. User writes offline, closes the app, connects, opens the app — sync already happened.
- **Pre-fetch fresh content** on a schedule so the feed is ready when opened. News / feed apps with daily cadence.
- **Upload queued media** (photos, videos) while the app is backgrounded.
- **Periodic health checks** (remote config, feature flags, auth token refresh).

### When they are NOT worth it

- **"Real-time" anything.** Background tasks are scheduled by the OS; you have zero timing guarantees. iOS may run yours once a day or never.
- **Precise timing / countdown / alarms.** Use `expo-notifications` with scheduled local notifications instead.
- **Frequent polling.** OS throttles aggressively. Poll on foreground resume, not in background.
- **Anything the user expects to happen "now."** If they expect it, they'll tap the app — run it on foreground resume.

### expo-background-task (SDK 51+)

**`expo-background-fetch` is deprecated.** The replacement is `expo-background-task`, which uses iOS `BGTaskScheduler` and Android `WorkManager` under the hood.

```ts
// src/background/syncTask.ts
import * as BackgroundTask from 'expo-background-task'
import * as TaskManager from 'expo-task-manager'

const TASK_NAME = 'sync-pending-mutations'

TaskManager.defineTask(TASK_NAME, async () => {
  try {
    await syncPendingMutations()
    return BackgroundTask.BackgroundTaskResult.Success
  } catch (err) {
    Sentry.captureException(err, { tags: { task: TASK_NAME } })
    return BackgroundTask.BackgroundTaskResult.Failed
  }
})

export async function registerSyncTask() {
  const status = await BackgroundTask.getStatusAsync()
  if (status !== BackgroundTask.BackgroundTaskStatus.Available) return

  await BackgroundTask.registerTaskAsync(TASK_NAME, {
    minimumInterval: 15 * 60,   // seconds — OS treats as a hint, not a guarantee
  })
}
```

- **`defineTask`** must be called at module scope (top of a file imported at app start), NOT inside a component. Otherwise the registered task handler is undefined when the OS tries to run it.
- **Return `Success`, `Failed`, or `NoData`** — the OS uses this to decide how often to schedule you.
- **`minimumInterval`** is a hint. iOS runs roughly every few hours at best, often daily. Android runs more aggressively but Doze mode can suspend for up to a day.
- **30 second iOS budget.** Your handler must finish within 30s or iOS kills it and penalizes future scheduling. Keep work minimal: batched network calls, no heavy processing.

### app.config.ts setup

```ts
export default {
  expo: {
    plugins: [
      [
        'expo-background-task',
        { backgroundModes: ['fetch'] },  // iOS background mode
      ],
    ],
    ios: {
      infoPlist: {
        BGTaskSchedulerPermittedIdentifiers: ['sync-pending-mutations'],
      },
    },
  },
}
```

- **`BGTaskSchedulerPermittedIdentifiers`** must list every task name. Miss one → the task never runs in release, works fine in dev. Common shipping bug.
- **`backgroundModes: ['fetch']`** enables the iOS capability. Without it, the task is silently dropped.
- **Android doesn't need config** beyond the library install — `WorkManager` handles scheduling without manifest changes.

### Constraints and survival rules

- **No UI work.** No rendering, no navigation, no React state. The app may not even be in memory — you're running in a raw JS environment.
- **No long operations.** Target <15s wall time on iOS to leave buffer. Any single operation >5s is suspicious.
- **No user interaction.** No prompts, no confirms. If the task needs user input, it's not a background task — schedule a notification.
- **Idempotency is mandatory.** Background tasks may be killed mid-run and retried later. Design for "ran twice by accident" without side effects.
- **No guarantees around wake frequency.** Don't use it for anything time-sensitive. Schedule is a hint.

### Debugging

```bash
# iOS — force a background task to run NOW (simulator or device via Xcode debugger)
# In Xcode: Debug → Simulate Background Fetch
# LLDB: e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"sync-pending-mutations"]

# Android — force a WorkManager job to run
adb shell dumpsys jobscheduler             # find your job ID
adb shell cmd jobscheduler run -f <package> <jobId>
```

- **iOS:** Xcode → Debug → Simulate Background Fetch triggers a run. Otherwise you wait for iOS, which may take hours.
- **Android:** `adb shell cmd jobscheduler run` forces a WorkManager job. Job IDs are auto-assigned, inspect via `dumpsys jobscheduler`.
- **Log to persistent storage, not console.** Background task logs don't show in Metro. Write to a file or MMKV, read on next foreground for debugging.

### The "just use foreground sync" alternative

Nine times out of ten, this is cleaner than background tasks:

```tsx
// app/_layout.tsx
import { AppState } from 'react-native'
import { onlineManager, useQueryClient } from '@tanstack/react-query'

useEffect(() => {
  const sub = AppState.addEventListener('change', (state) => {
    if (state === 'active' && onlineManager.isOnline()) {
      queryClient.resumePausedMutations()
      queryClient.invalidateQueries({ refetchType: 'active' })
    }
  })
  return () => sub.remove()
}, [])
```

- **Runs when the user opens the app.** No OS scheduling, no permissions, no debugging pain.
- **Covers 80% of "sync on resume" cases.** Users open the app within minutes of a network change — the experience is indistinguishable from true background sync for most workflows.
- **Free.** Zero config, zero plugins, zero EAS surprises.

### Common mistakes

1. **Using `expo-background-fetch`.** Deprecated as of SDK 51. Fix: migrate to `expo-background-task`.
2. **Registering the task inside a component.** Handler is undefined when OS runs it. Fix: `defineTask` at module scope.
3. **Missing `BGTaskSchedulerPermittedIdentifiers`.** Works in dev, silently fails in release. Fix: list every task ID in `app.config.ts`.
4. **Long-running tasks.** iOS kills at 30s and throttles future runs. Fix: batch, parallelize, <15s target.
5. **Assuming scheduled interval is real.** "Every 15 min" is a hint. Actual runs: iOS every few hours at best, sometimes daily, sometimes never. Fix: design for "ran once per day" and any bonus runs are gravy.
6. **No idempotency.** Same task retries → duplicate side effects. Fix: idempotency key per work item.
7. **Reaching for background tasks instead of foreground resume sync.** Often solves the wrong problem. Fix: run sync on `AppState.change → active` first, measure, escalate only if genuinely insufficient.

## Topic 22: Testing Reanimated animations

Reanimated worklets run on the UI thread, outside the Jest JS environment. Tests that touch an animated component fail with cryptic errors unless you set up the mock correctly. The trick isn't testing the animation mid-flight — it's asserting the final state after a `runAllTimers` flush.

### Jest setup

```js
// jest.config.js
module.exports = {
  preset: 'jest-expo',
  setupFiles: ['./jest-setup.js'],
  setupFilesAfterEach: ['@testing-library/react-native/extend-expect'],
}
```

```js
// jest-setup.js
import 'react-native-gesture-handler/jestSetup'
import 'react-native-reanimated/mock'

// Silence worklet warnings during tests
jest.mock('react-native-reanimated/lib/reanimated2/js-reanimated', () => ({}))
global.__reanimatedWorkletInit = jest.fn()
```

- **`react-native-reanimated/mock`** replaces worklet primitives with synchronous JS stubs. Animated values, `useAnimatedStyle`, and `withTiming` all become no-ops that return final values immediately.
- **`react-native-gesture-handler/jestSetup`** mocks gesture handlers. Without it, any Reanimated component using `Gesture.Pan()` crashes the test.
- **`jest-expo` preset** handles most of the Expo-specific mocking. You still need the two imports above.

### Testing final state (the right way)

```tsx
// AnimatedButton.tsx
import Animated, { useSharedValue, useAnimatedStyle, withTiming } from 'react-native-reanimated'

export function AnimatedButton({ pressed }: { pressed: boolean }) {
  const opacity = useSharedValue(1)

  useEffect(() => {
    opacity.value = withTiming(pressed ? 0.5 : 1, { duration: 200 })
  }, [pressed])

  const style = useAnimatedStyle(() => ({ opacity: opacity.value }))

  return <Animated.View style={style} testID="button" />
}
```

```tsx
// AnimatedButton.test.tsx
import { render } from '@testing-library/react-native'

test('opacity animates to 0.5 when pressed', () => {
  const { getByTestId, rerender } = render(<AnimatedButton pressed={false} />)
  rerender(<AnimatedButton pressed />)
  // Reanimated mock resolves to final state synchronously
  expect(getByTestId('button')).toHaveAnimatedStyle({ opacity: 0.5 })
})
```

- **`toHaveAnimatedStyle`** comes from `@testing-library/react-native`. Asserts against the resolved final value, not any mid-flight frame.
- **Don't try to assert intermediate frames.** The mock doesn't simulate timing — `withTiming(0.5, { duration: 200 })` resolves to `0.5` instantly in tests.
- **Real device testing** is the only way to verify timing / easing / feel. Unit tests verify the logic gets to the right final state; device testing verifies the animation feels right.

### Fake timers for delayed animations

```tsx
test('hides tooltip after 2 seconds', () => {
  jest.useFakeTimers()
  const { getByTestId, queryByTestId } = render(<Tooltip visible />)
  expect(getByTestId('tooltip')).toBeTruthy()

  jest.advanceTimersByTime(2000)
  expect(queryByTestId('tooltip')).toBeNull()

  jest.useRealTimers()
})
```

- **Use `jest.advanceTimersByTime`** to flush Reanimated callbacks and `setTimeout`-based dismissal logic.
- **Always pair `useFakeTimers` with `useRealTimers` in cleanup** — otherwise tests after this one hang.
- **Use `jest.useFakeTimers({ doNotFake: ['nextTick'] })`** if you see "Exceeded timeout of 5000 ms" errors. Reanimated mocks rely on microtasks for some state updates.

### Testing gesture handlers

```tsx
import { fireGestureHandler } from 'react-native-gesture-handler/jest-utils'
import { State } from 'react-native-gesture-handler'

test('swipe right dismisses card', () => {
  const onDismiss = jest.fn()
  const { getByTestId } = render(<SwipeableCard onDismiss={onDismiss} />)
  const gesture = getByTestId('card').props.gestureHandlerRef

  fireGestureHandler(gesture, [
    { state: State.BEGAN, x: 0 },
    { state: State.ACTIVE, x: 200 },
    { state: State.END, x: 300 },
  ])

  expect(onDismiss).toHaveBeenCalled()
})
```

- **`fireGestureHandler`** is the only supported way to drive a gesture in tests. `fireEvent.press` doesn't trigger Reanimated gestures.
- **State sequence matters.** `BEGAN → ACTIVE → END` for completed gestures, `BEGAN → ACTIVE → CANCELLED` for interrupted ones. Missing the final state leaves the gesture "hanging" and subsequent assertions fail silently.

### What you CAN'T test in Jest

- **Frame-by-frame timing, easing curves, spring physics.** The mock is synchronous; it doesn't simulate `requestAnimationFrame`.
- **Layout measurements.** Measurement APIs (`measure`, `getRelativeCoords`) return stubbed zeros in Jest.
- **Actual rendering.** Jest runs in jsdom — no UI thread, no native views, no pixel output.
- **`useFrameCallback`.** Doesn't fire under the mock.

For these: use Detox (E2E on real devices / simulators) or Maestro. Unit tests are for logic; device tests are for visuals.

### When NOT to test an animation

- **Decorative animations** (fades, subtle transitions) aren't worth unit testing. The cost > the coverage.
- **Prefer testing the component's behavior** ("shows error message on submit") over its visuals ("opacity animates from 0 to 1").
- **Test what breaks when someone else refactors:** state transitions, callback firing, final rendered result. Not timing curves.

### Common mistakes

1. **No Reanimated mock.** Tests crash with "cannot read property 'value' of undefined." Fix: `import 'react-native-reanimated/mock'` in jest setup.
2. **Asserting mid-animation state.** The mock resolves instantly — there IS no mid-state. Fix: assert final state after rerender.
3. **Forgetting `useRealTimers` in afterEach.** Subsequent tests hang or time out. Fix: explicit cleanup.
4. **Driving gestures with `fireEvent`.** Doesn't trigger gesture handlers. Fix: `fireGestureHandler` from `jest-utils`.
5. **Testing every animation.** Noise > signal for decorative effects. Fix: test behavior and state transitions, not timing curves.
6. **Missing gesture handler `jestSetup` import.** Tests with gestures crash in weird places. Fix: `import 'react-native-gesture-handler/jestSetup'`.
7. **Running Reanimated tests in parallel with shared worklet state.** Flaky tests that pass in isolation. Fix: Jest's default isolation + module reset if you see this.

## Topic 23: Screen component structure pattern

Screens are where the rest of the app converges: routing, data fetching, mutations, forms, error handling, loading states, navigation. Without a pattern, screens become 600-line grab bags. With one, they become thin coordinators that delegate to layered building blocks.

### The four layers

```
┌────────────────────────────────────────────────┐
│ Screen       app/posts/new.tsx                 │ ← routing, params, top-level state
│   - reads params via useLocalSearchParams       │
│   - orchestrates data loading + navigation      │
│   - renders <ScreenState> + composition         │
├────────────────────────────────────────────────┤
│ Hook         src/hooks/useCreatePost.ts         │ ← domain state + mutation
│   - wraps TanStack Query mutation               │
│   - owns optimistic updates, cache invalidation │
│   - returns { mutate, isPending, error }        │
├────────────────────────────────────────────────┤
│ Component    src/components/PostForm.tsx       │ ← presentation + form state
│   - no API calls, no navigation                 │
│   - takes values + onSubmit as props            │
│   - fully testable in isolation                 │
├────────────────────────────────────────────────┤
│ Service      src/services/posts.ts              │ ← API surface
│   - fetch / axios calls                         │
│   - request / response types                    │
│   - no React, no state                          │
└────────────────────────────────────────────────┘
```

- **Services** know about the network. No React, no state, no components. Pure functions that return promises.
- **Hooks** wrap services with TanStack Query. They own domain state (mutation status, optimistic updates, cache keys).
- **Components** are presentational. They take values + callbacks as props and render UI. No API calls, no `router.push`, no `useQuery`.
- **Screens** are coordinators. They read params, call hooks, handle navigation, and compose components.

This is the same layering as `react-typescript-patterns`, adapted to RN. The only difference is `app/` replaces `pages/` and there's no SSR layer.

### Concrete example: creating a post

**Service (`src/services/posts.ts`):**

```ts
import { api } from '@/lib/api'

export type CreatePostInput = { title: string; body: string }
export type Post = { id: string; title: string; body: string; createdAt: string }

export const postsService = {
  async create(input: CreatePostInput): Promise<Post> {
    const res = await api.post('/posts', input)
    return res.data
  },
  async list(): Promise<Post[]> {
    const res = await api.get('/posts')
    return res.data
  },
}
```

**Query keys (`src/queries/postKeys.ts`):**

```ts
export const postKeys = {
  all: ['posts'] as const,
  lists: () => [...postKeys.all, 'list'] as const,
  detail: (id: string) => [...postKeys.all, 'detail', id] as const,
}
```

**Hook (`src/hooks/useCreatePost.ts`):**

```ts
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { router } from 'expo-router'
import * as Sentry from '@sentry/react-native'
import { postsService, CreatePostInput } from '@/services/posts'
import { postKeys } from '@/queries/postKeys'

export function useCreatePost() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (input: CreatePostInput) => postsService.create(input),
    onSuccess: post => {
      queryClient.invalidateQueries({ queryKey: postKeys.lists() })
      router.replace(`/posts/${post.id}`)
    },
    onError: err => {
      Sentry.captureException(err, { tags: { mutation: 'createPost' } })
    },
  })
}
```

**Component (`src/components/PostForm.tsx`):**

```tsx
import { useForm, Controller } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'

const postSchema = z.object({
  title: z.string().min(1, 'Title is required').max(120),
  body: z.string().min(10, 'Body must be at least 10 characters'),
})

type PostFormValues = z.infer<typeof postSchema>

type PostFormProps = {
  defaultValues?: Partial<PostFormValues>
  onSubmit: (values: PostFormValues) => void
  isSubmitting?: boolean
}

export function PostForm({ defaultValues, onSubmit, isSubmitting }: PostFormProps) {
  const { control, handleSubmit, formState: { errors } } = useForm<PostFormValues>({
    resolver: zodResolver(postSchema),
    defaultValues: { title: '', body: '', ...defaultValues },
  })

  return (
    <View style={{ gap: 16 }}>
      <Controller
        control={control}
        name="title"
        render={({ field }) => (
          <TextInput
            value={field.value}
            onChangeText={field.onChange}
            onBlur={field.onBlur}
            placeholder="Title"
          />
        )}
      />
      {errors.title && <Text>{errors.title.message}</Text>}

      <Controller
        control={control}
        name="body"
        render={({ field }) => (
          <TextInput
            value={field.value}
            onChangeText={field.onChange}
            onBlur={field.onBlur}
            placeholder="Body"
            multiline
          />
        )}
      />
      {errors.body && <Text>{errors.body.message}</Text>}

      <Button
        title={isSubmitting ? 'Saving...' : 'Save'}
        onPress={handleSubmit(onSubmit)}
        disabled={isSubmitting}
      />
    </View>
  )
}
```

**Screen (`app/posts/new.tsx`):**

```tsx
import { useCreatePost } from '@/hooks/useCreatePost'
import { PostForm } from '@/components/PostForm'
import { ScreenState } from '@/components/ScreenState'

export default function NewPostScreen() {
  const { mutate, isPending, error } = useCreatePost()

  return (
    <ScreenState error={error}>
      <PostForm onSubmit={mutate} isSubmitting={isPending} />
    </ScreenState>
  )
}
```

Notice what the screen DOESN'T do: no `fetch`, no form state, no navigation side effects (the hook owns it), no error rendering (the `ScreenState` owns it). It's a ~10-line coordinator.

### ScreenState component

A reusable wrapper for the three states every screen has: loading, error, content.

```tsx
// src/components/ScreenState.tsx
type ScreenStateProps = {
  isLoading?: boolean
  error?: Error | null
  isEmpty?: boolean
  emptyMessage?: string
  children: React.ReactNode
}

export function ScreenState({
  isLoading,
  error,
  isEmpty,
  emptyMessage = 'Nothing here yet',
  children,
}: ScreenStateProps) {
  if (isLoading) {
    return (
      <View style={{ flex: 1, justifyContent: 'center' }}>
        <ActivityIndicator />
      </View>
    )
  }

  if (error) {
    return (
      <View style={{ flex: 1, justifyContent: 'center', padding: 24 }}>
        <Text style={{ fontSize: 16, fontWeight: '600' }}>Something went wrong</Text>
        <Text style={{ color: '#666', marginTop: 4 }}>{error.message}</Text>
      </View>
    )
  }

  if (isEmpty) {
    return (
      <View style={{ flex: 1, justifyContent: 'center' }}>
        <Text>{emptyMessage}</Text>
      </View>
    )
  }

  return <>{children}</>
}
```

- **Eliminates the `if (loading) … else if (error) … else if (!data.length) … else` staircase** that turns a screen into an unreadable mess.
- **Extend as your design system grows:** add skeletons, tailored error illustrations, retry buttons. The screen doesn't change.
- **Not a replacement for error boundaries.** This handles async errors from queries / mutations. Error boundaries catch render-phase bugs.

### Reading route params in the screen

```tsx
// app/posts/[id]/edit.tsx
import { useLocalSearchParams, useRouter } from 'expo-router'
import { postRouteSchema } from '@/routes/schemas'
import { usePost } from '@/hooks/usePost'
import { useUpdatePost } from '@/hooks/useUpdatePost'
import { PostForm } from '@/components/PostForm'
import { ScreenState } from '@/components/ScreenState'

export default function EditPostScreen() {
  const params = postRouteSchema.safeParse(useLocalSearchParams())
  const router = useRouter()

  if (!params.success) {
    router.back()
    return null
  }

  const { id } = params.data
  const post = usePost(id)
  const update = useUpdatePost(id)

  return (
    <ScreenState isLoading={post.isLoading} error={post.error ?? update.error}>
      <PostForm
        defaultValues={post.data}
        onSubmit={update.mutate}
        isSubmitting={update.isPending}
      />
    </ScreenState>
  )
}
```

- **Param validation at the top.** Invalid params bounce back before hitting the data layer.
- **Queries and mutations both live in the screen.** The form component doesn't know about either.
- **Loading AND error states merged.** Pass the first non-null error — `ScreenState` handles the rest.

### File structure

```
app/                          ← routes only
  _layout.tsx
  (tabs)/
    _layout.tsx
    feed.tsx
  posts/
    [id].tsx
    [id]/edit.tsx
    new.tsx

src/
  services/                   ← API clients, no React
    posts.ts
    users.ts
  queries/                    ← query key factories
    postKeys.ts
    userKeys.ts
  hooks/                      ← domain hooks (useCreatePost, usePost, useAuth)
    useCreatePost.ts
    usePost.ts
    usePosts.ts
  components/                 ← presentational components
    PostForm.tsx
    PostCard.tsx
    ScreenState.tsx
  routes/
    schemas.ts                ← Zod schemas for route params
  lib/                        ← client setup
    api.ts
    queryClient.ts
    sentry.ts
```

- **`app/` contains routes only.** Anything not a route (components, hooks, services) lives in `src/`. Keeps the routing surface small and scannable.
- **Hooks are where the logic lives.** Screens call hooks; components take props. If you're writing `useMutation` in a screen, extract it.
- **Services are frameworkless.** Swap `fetch` for `axios`, or React Query for something else, without touching services.

### Size heuristics

- **Screen > 150 lines** — extract logic to hooks and composition to components.
- **Hook > 100 lines** — split into multiple hooks or move work to services.
- **Component > 400 lines** — split by region (header, body, footer) or compound-component it.
- **Service > 200 lines per domain** — split by resource (`postsService`, `commentsService`, `usersService`).

Don't pre-optimize. The heuristic is "when you hit it, split." Splitting earlier adds ceremony without payoff.

### Common mistakes

1. **API calls in screen body.** `fetch('/posts').then(...)` directly in `useEffect`. Fix: extract to a service + hook.
2. **Form state in the screen.** The screen re-renders on every keystroke. Fix: form state in a presentational component + `react-hook-form`.
3. **Navigation side effects inside leaf components.** `router.push` inside a `<Button>` five levels deep. Fix: callback props up to the screen, or put the `router.push` in the hook's `onSuccess`.
4. **No `ScreenState` wrapper.** Every screen duplicates the loading / error / empty branches. Fix: one `ScreenState` shared by all.
5. **Hook that does three things.** `usePostAndRelatedComments` — split into `usePost` and `useComments`.
6. **Query keys inline.** `useQuery({ queryKey: ['posts', id], ... })` scattered across files. Typo: `['post', id]`. Cache miss. Fix: `postKeys.detail(id)` from a factory.
7. **Screen that imports a service directly.** Skips TanStack Query → no caching, no retries, no offline. Fix: always go through a hook.

