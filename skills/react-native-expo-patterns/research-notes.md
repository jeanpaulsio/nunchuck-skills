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

