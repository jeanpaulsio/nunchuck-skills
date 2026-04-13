---
name: react-native-expo-patterns
description: Deep reference for React Native / Expo patterns -- Expo Router v7, screen structure, TanStack Query with offline persistence, native modules, NativeWind styling, forms, accessibility, Reanimated animations, performance, deep linking, Sentry wiring, EAS Build/Submit/Update, testing, and platform gotchas. Grounded in Expo SDK 55+ and React Native 0.83+ with the New Architecture.
origin: nunchuck-skills (built from research on Expo SDK 55+)
---

# React Native / Expo Patterns

A deep reference for building React Native apps with Expo. Covers the patterns that matter for production: routing, data fetching with offline support, native capabilities, styling, forms, accessibility, animations, deep linking, error tracking, testing, and the EAS release pipeline.

A code review agent lives at `agents/react-native-reviewer.md`. The `/react-native-review` slash command runs it over staged changes.

## Table of Contents

1. [Project Setup](#1-project-setup)
2. [Expo Router v7](#2-expo-router-v7)
3. [Screen Structure Pattern](#3-screen-structure-pattern)
4. [Component Composition](#4-component-composition)
5. [Styling, Layout & Keyboard](#5-styling-layout--keyboard)
6. [Forms & TextInput](#6-forms--textinput)
7. [Accessibility](#7-accessibility)
8. [Data Fetching & Offline](#8-data-fetching--offline)
9. [State Management](#9-state-management)
10. [Native Capabilities](#10-native-capabilities)
11. [Animations & Gestures](#11-animations--gestures)
12. [Performance](#12-performance)
13. [Deep Linking](#13-deep-linking)
14. [Internationalization](#14-internationalization)
15. [Background Tasks](#15-background-tasks)
16. [Error Handling & Sentry](#16-error-handling--sentry)
17. [Testing](#17-testing)
18. [Release Pipeline (EAS)](#18-release-pipeline-eas)
19. [Platform Gotchas](#19-platform-gotchas)
20. [Quick Reference](#20-quick-reference)

---

## 1. Project Setup

Expo SDK 55+, React Native 0.83+, React 19, Node 20.19+. The New Architecture (Fabric + TurboModules) is the default -- don't disable it unless a dependency forces you to.

```bash
npx create-expo-app@latest --template tabs
```

### app.config.ts

Prefer `app.config.ts` over `app.json` for access to env vars and conditional config.

```ts
import type { ExpoConfig } from 'expo/config'

export default (): ExpoConfig => ({
  name: 'MyApp',
  slug: 'myapp',
  scheme: 'myapp',
  version: '1.0.0',
  runtimeVersion: { policy: 'fingerprint' },
  newArchEnabled: true,
  ios: {
    supportsTablet: true,
    bundleIdentifier: 'com.example.myapp',
    associatedDomains: ['applinks:myapp.com'],
  },
  android: {
    package: 'com.example.myapp',
  },
  plugins: [
    'expo-router',
    'expo-secure-store',
    ['@sentry/react-native/expo', { url: 'https://sentry.io/' }],
  ],
  experiments: { typedRoutes: true },
})
```

Key fields:

- `scheme` -- required for deep linking, OAuth redirects, and `Linking.openURL`
- `runtimeVersion: { policy: 'fingerprint' }` -- auto-invalidates OTA updates when native code changes
- `newArchEnabled: true` -- explicit is better than the default drifting under you
- `experiments.typedRoutes: true` -- turns on expo-router's type-checked `href` strings

### Environment Variables

```
# .env (git-ignored)
EXPO_PUBLIC_API_URL=https://api.example.com
```

Only variables prefixed with `EXPO_PUBLIC_` are bundled into the app. Everything else stays on the build server. **Never put secrets in `EXPO_PUBLIC_*`** -- they ship in the JS bundle, visible to anyone who unpacks the IPA or APK.

### Common Mistakes

- Missing `scheme` → OAuth and deep links fail silently
- `runtimeVersion: "1.0.0"` hardcoded → OTA updates drift from binaries, causing crashes after native changes land
- API keys in `EXPO_PUBLIC_*` → the key ships in the bundle
- `npm install expo-camera` instead of `npx expo install expo-camera` → version mismatch with the SDK

---

## 2. Expo Router v7

File-based routing. Every file in `app/` becomes a route.

```
app/
  _layout.tsx           # root <Stack>
  index.tsx             # /
  (tabs)/               # route group -- no URL segment
    _layout.tsx         # <Tabs>
    index.tsx           # /
    profile.tsx         # /profile
  posts/
    [id].tsx            # /posts/:id
    [id]/
      edit.tsx          # /posts/:id/edit
  +not-found.tsx        # 404 fallback
```

Route groups `(name)` organize files without adding URL segments. Use them to separate auth flows from tabbed layouts.

### Layouts

```tsx
// app/_layout.tsx
import { Stack } from 'expo-router'
import { SafeAreaProvider } from 'react-native-safe-area-context'

export default function RootLayout() {
  return (
    <SafeAreaProvider>
      <Stack screenOptions={{ headerShown: false }}>
        <Stack.Screen name="(tabs)" />
        <Stack.Screen name="modal" options={{ presentation: 'modal' }} />
      </Stack>
    </SafeAreaProvider>
  )
}
```

### Typed Routes

Enable `experiments: { typedRoutes: true }`. Then `href` strings are type-checked at build time.

```tsx
import { Link } from 'expo-router'

<Link href="/posts/123">Post</Link>                     // ✓
<Link href="/psots/123">Post</Link>                     // ✗ type error
<Link href={`/posts/${id}` as const}>Post</Link>        // ✓ template literal needs `as const`
```

### Navigation

```tsx
import { useRouter } from 'expo-router'

const router = useRouter()

router.push('/posts/123')             // adds to stack
router.replace('/login')              // replaces current route
router.back()                         // pops the stack
router.setParams({ filter: 'new' })   // updates params without navigating
```

### Type-Safe Params

`useLocalSearchParams<T>()` is **not** safe. The generic is unenforced -- the runtime value can be `string | string[] | undefined` regardless of how you type it.

```tsx
// WRONG: TypeScript says id is a string, runtime disagrees
const { id } = useLocalSearchParams<{ id: string }>()
fetch(`/api/posts/${id}`)  // crashes if id is ['1', '2']
```

Validate at the screen boundary with Zod:

```tsx
import { z } from 'zod'
import { useLocalSearchParams, Redirect } from 'expo-router'

const ParamsSchema = z.object({
  id: z.string().regex(/^\d+$/),
})

export default function PostScreen() {
  const raw = useLocalSearchParams()
  const parsed = ParamsSchema.safeParse(raw)

  if (!parsed.success) return <Redirect href="/+not-found" />

  const { id } = parsed.data  // guaranteed string
  return <PostDetail id={id} />
}
```

### Common Mistakes

- Trusting the generic on `useLocalSearchParams` → crashes at runtime when the param is a list
- Template literal `href` without `as const` → type error on typed routes
- `router.push` when you mean `router.replace` after login → back button returns to login
- Forgetting `+not-found.tsx` → expo-router falls through to an unstyled 404

---

## 3. Screen Structure Pattern

Four layers per feature: **Services → Hooks → Components → Screens**. Screens are thin orchestrators.

```
features/posts/
  services/
    posts.ts            # API calls, pure functions
  hooks/
    usePosts.ts         # TanStack Query wrapper
    useCreatePost.ts    # mutation wrapper
  components/
    PostList.tsx        # presentational
    PostItem.tsx
    PostListEmpty.tsx
  screens/
    PostListScreen.tsx  # orchestration
```

Services are pure functions — no React. Hooks wrap TanStack Query. Components are presentational (props in, callbacks out). Screens orchestrate.

### Screens -- Orchestration

```tsx
// screens/PostListScreen.tsx
import { useRouter } from 'expo-router'
import { usePosts } from '../hooks/usePosts'
import { ScreenState } from '@/components/ScreenState'

export default function PostListScreen() {
  const router = useRouter()
  const query = usePosts({ status: 'published' })

  return (
    <ScreenState query={query} empty={<PostListEmpty />}>
      {(posts) => (
        <PostList
          posts={posts}
          onPressItem={(id) => router.push(`/posts/${id}` as const)}
        />
      )}
    </ScreenState>
  )
}
```

### ScreenState Wrapper

Every screen handles loading, error, and empty states. Extract into a reusable wrapper:

```tsx
// components/ScreenState.tsx
import type { UseQueryResult } from '@tanstack/react-query'

type Props<T> = {
  query: UseQueryResult<T>
  empty?: React.ReactNode
  children: (data: T) => React.ReactNode
}

export function ScreenState<T>({ query, empty, children }: Props<T>) {
  if (query.isPending) return <LoadingView />
  if (query.isError) {
    return <ErrorView error={query.error} onRetry={() => query.refetch()} />
  }
  const data = query.data
  if (!data || (Array.isArray(data) && data.length === 0)) {
    return <>{empty ?? <EmptyView />}</>
  }
  return <>{children(data)}</>
}
```

### Common Mistakes

- Calling `useQuery` inside presentational components → impossible to test the presentation in isolation
- Inline `if (isLoading)` checks on every screen → copy-paste bugs, inconsistent UX
- Screens that render full JSX trees instead of delegating → 400+ line files that are hard to navigate

---

## 4. Component Composition

Compound components, slot props, and custom hooks. Same ideas as web React, different primitives.

### Compound Components with Context Guard

```tsx
import { createContext, useContext } from 'react'
import { View, type ViewProps } from 'react-native'

type CardContextValue = { variant: 'default' | 'outlined' }
const CardContext = createContext<CardContextValue | null>(null)

function useCardContext() {
  const ctx = useContext(CardContext)
  if (!ctx) throw new Error('Card.* must be used inside <Card>')
  return ctx
}

export function Card({
  variant = 'default',
  children,
  ...rest
}: { variant?: 'default' | 'outlined' } & ViewProps) {
  return (
    <CardContext.Provider value={{ variant }}>
      <View className={variant === 'outlined' ? 'border' : 'shadow'} {...rest}>
        {children}
      </View>
    </CardContext.Provider>
  )
}

Card.Header = function CardHeader({ children }: { children: React.ReactNode }) {
  useCardContext()  // throws if not nested
  return <View className="border-b p-4">{children}</View>
}

Card.Body = function CardBody({ children }: { children: React.ReactNode }) {
  useCardContext()
  return <View className="p-4">{children}</View>
}
```

Usage:

```tsx
<Card variant="outlined">
  <Card.Header><Text className="text-lg font-semibold">Title</Text></Card.Header>
  <Card.Body><Text>Body content</Text></Card.Body>
</Card>
```

The context guard means `<Card.Header />` used standalone throws immediately with a clear message, instead of rendering silently broken.

### Slot Props (`asChild`)

When a button should wrap an existing interactive child (e.g., `<Link>`), render the child directly instead of nesting pressables:

```tsx
import { cloneElement, isValidElement } from 'react'

type Props = {
  asChild?: boolean
  children: React.ReactNode
  onPress?: () => void
}

export function Button({ asChild, children, onPress }: Props) {
  if (asChild && isValidElement(children)) {
    return cloneElement(children, { onPress })
  }
  return (
    <Pressable onPress={onPress} className="rounded-lg bg-blue-500 px-4 py-2">
      {children}
    </Pressable>
  )
}
```

```tsx
<Button asChild>
  <Link href="/profile">Profile</Link>
</Button>
```

### Custom Hooks -- One Concern Each

```tsx
// GOOD
function useDebouncedValue<T>(value: T, ms: number): T { /* ... */ }
function useKeyboardVisible(): boolean { /* ... */ }
function useAppStateActive(): boolean { /* ... */ }

// BAD -- multiple responsibilities
function usePostsWithFiltersAndSortAndSelection() { /* ... */ }
```

If the name has "and" in it, split it.

### Common Mistakes

- Compound components without context guard → children render silently broken when moved out
- Inventing a new prop API instead of accepting `children` → every prop is a tax
- Hooks returning an object with 12 fields → callers destructure two, the rest re-render for nothing

---

## 5. Styling, Layout & Keyboard

NativeWind v4 (Tailwind for React Native) + `react-native-safe-area-context` + `react-native-keyboard-controller`.

### NativeWind Setup

```bash
npx expo install nativewind tailwindcss@3 react-native-css-interop
```

```js
// tailwind.config.js
module.exports = {
  content: ['./app/**/*.{ts,tsx}', './src/**/*.{ts,tsx}'],
  presets: [require('nativewind/preset')],
  theme: { extend: {} },
}
```

```ts
// nativewind-env.d.ts -- enables className on all RN components
/// <reference types="nativewind/types" />
```

```js
// babel.config.js
module.exports = function (api) {
  api.cache(true)
  return {
    presets: [['babel-preset-expo', { jsxImportSource: 'nativewind' }], 'nativewind/babel'],
  }
}
```

Usage:

```tsx
<View className="flex-1 items-center justify-center bg-white">
  <Text className="text-lg font-semibold text-gray-900">Hello</Text>
</View>
```

### Safe Areas

iOS has a notch. Android has a gesture bar and punch-hole cameras. Use `react-native-safe-area-context` -- don't hardcode `paddingTop: 44`.

```tsx
// app/_layout.tsx
import { SafeAreaProvider } from 'react-native-safe-area-context'

<SafeAreaProvider>
  <Stack />
</SafeAreaProvider>
```

In screens, prefer `useSafeAreaInsets()` for fine-grained control:

```tsx
import { useSafeAreaInsets } from 'react-native-safe-area-context'

function Header() {
  const insets = useSafeAreaInsets()
  return <View style={{ paddingTop: insets.top }} className="bg-white" />
}
```

Or use `<SafeAreaView edges={['top']}>` as a shortcut.

### Keyboard Handling

`react-native-keyboard-controller` solves most layout issues with one wrapper. Put it at the root.

```tsx
import { KeyboardProvider } from 'react-native-keyboard-controller'

<KeyboardProvider>
  <Stack />
</KeyboardProvider>
```

For scrollable forms:

```tsx
import { KeyboardAwareScrollView } from 'react-native-keyboard-controller'

<KeyboardAwareScrollView
  bottomOffset={20}
  className="flex-1"
  keyboardShouldPersistTaps="handled"
>
  <TextInput /* ... */ />
</KeyboardAwareScrollView>
```

Do **not** use React Native's `KeyboardAvoidingView`. It needs different `behavior` per platform, breaks on Android, and fights with navigation headers.

### Common Mistakes

- Hardcoded `paddingTop: 44` instead of safe area insets → content under the notch on newer iPhones
- `KeyboardAvoidingView` → use `react-native-keyboard-controller` instead
- `flex: 1` inside a `ScrollView` child → nothing renders (ScrollView gives children infinite height)
- `Platform.OS === 'ios'` branches scattered through JSX → consolidate with `Platform.select` at the top

---

## 6. Forms & TextInput

`react-hook-form` + `zod` + `@hookform/resolvers/zod`. Password manager integration needs `textContentType` (iOS) **and** `autoComplete` (Android).

```tsx
import { Controller, useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'

const Schema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
})
type FormValues = z.infer<typeof Schema>

export function LoginForm() {
  const passwordRef = useRef<TextInput>(null)
  const { control, handleSubmit, formState: { errors } } = useForm<FormValues>({
    resolver: zodResolver(Schema),
    defaultValues: { email: '', password: '' },
  })

  return (
    <>
      <Controller
        control={control}
        name="email"
        render={({ field }) => (
          <TextInput
            value={field.value}
            onChangeText={field.onChange}
            onBlur={field.onBlur}
            placeholder="Email"
            keyboardType="email-address"
            autoCapitalize="none"
            autoCorrect={false}
            textContentType="emailAddress"
            autoComplete="email"
            returnKeyType="next"
            onSubmitEditing={() => passwordRef.current?.focus()}
            blurOnSubmit={false}
          />
        )}
      />
      {errors.email && <Text className="text-red-500">{errors.email.message}</Text>}

      <Controller
        control={control}
        name="password"
        render={({ field }) => (
          <TextInput
            ref={passwordRef}
            value={field.value}
            onChangeText={field.onChange}
            placeholder="Password"
            secureTextEntry
            textContentType="password"
            autoComplete="current-password"
            returnKeyType="done"
            onSubmitEditing={handleSubmit(onSubmit)}
          />
        )}
      />
      {errors.password && <Text className="text-red-500">{errors.password.message}</Text>}

      <Button onPress={handleSubmit(onSubmit)} title="Sign in" />
    </>
  )
}
```

### Password Manager Hints

| Purpose          | iOS `textContentType`   | Android `autoComplete` |
|------------------|-------------------------|------------------------|
| New password     | `newPassword`           | `new-password`         |
| Current password | `password`              | `current-password`     |
| Email            | `emailAddress`          | `email`                |
| OTP / 2FA        | `oneTimeCode`           | `sms-otp`              |
| Name             | `name`                  | `name`                 |
| Phone            | `telephoneNumber`       | `tel`                  |

Without these, iOS and Android skip autofill and users type everything manually.

### Return Key Chains

Wire `returnKeyType` + `onSubmitEditing` + `blurOnSubmit={false}` to move focus between inputs. The last field uses `returnKeyType="done"` and submits the form.

### Common Mistakes

- `textContentType` without `autoComplete` → autofill works on iOS, silently absent on Android
- `blurOnSubmit` left as default on non-final inputs → keyboard dismisses between fields
- Not passing `onBlur` to `Controller` → react-hook-form doesn't know when to validate
- Inline validation firing on every keystroke → keyboard lag on Android

---

## 7. Accessibility

`accessibilityRole`, `accessibilityLabel`, `accessibilityState`, and `AccessibilityInfo` for announcements and focus.

### Pressables

```tsx
<Pressable
  accessible
  accessibilityRole="button"
  accessibilityLabel="Save post"
  accessibilityHint="Saves the current post to drafts"
  accessibilityState={{ disabled: !isDirty, busy: isSaving }}
  onPress={handleSave}
  disabled={!isDirty || isSaving}
>
  <Text>Save</Text>
</Pressable>
```

- `accessibilityLabel` -- short, describes what it is
- `accessibilityHint` -- longer, describes what happens on activation
- `accessibilityState` -- drives screen reader output ("disabled", "busy", "selected")

### Grouping

Wrap a card in `<View accessible>` to make the whole card a single screen reader target:

```tsx
<View accessible accessibilityLabel={`Post: ${title}, by ${author}, ${likes} likes`}>
  <Text className="text-lg font-semibold">{title}</Text>
  <Text>{author}</Text>
  <Text>{likes} likes</Text>
</View>
```

Without `accessible`, VoiceOver reads each `<Text>` separately -- noisy and out of order.

### Announcements

```tsx
import { AccessibilityInfo } from 'react-native'

AccessibilityInfo.announceForAccessibility('Post saved')
```

Use for transient status changes that don't have a visible element, or where the visible element isn't obvious to screen reader users.

### Programmatic Focus

```tsx
import { AccessibilityInfo, findNodeHandle } from 'react-native'

const errorRef = useRef<View>(null)

useEffect(() => {
  if (hasError) {
    const node = findNodeHandle(errorRef.current)
    if (node) AccessibilityInfo.setAccessibilityFocus(node)
  }
}, [hasError])

<View ref={errorRef}>
  <Text>{errorMessage}</Text>
</View>
```

Move VoiceOver focus to the error after a form submission failure. Visual focus rings don't exist on mobile, so this is the only way to point users to the problem.

### Reduce Motion

```tsx
import { useReducedMotion } from 'react-native-reanimated'

const reduceMotion = useReducedMotion()

const style = useAnimatedStyle(() => ({
  transform: [{ scale: reduceMotion ? 1 : withSpring(scale.value) }],
}))
```

### Common Mistakes

- Missing `accessibilityLabel` on icon buttons → VoiceOver reads nothing
- `onPress` on a `<View>` without `accessibilityRole="button"` → screen readers don't know it's interactive
- `disabled` without `accessibilityState={{ disabled: true }}` → screen reader still says "double tap to activate"
- Announcing every state change → screen reader users get interrupted constantly

---

## 8. Data Fetching & Offline

TanStack Query v5 with `PersistQueryClientProvider` for offline persistence.

### Query Client Setup

```ts
// lib/queryClient.ts
import { QueryClient } from '@tanstack/react-query'
import { createAsyncStoragePersister } from '@tanstack/query-async-storage-persister'
import AsyncStorage from '@react-native-async-storage/async-storage'

export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      gcTime: 1000 * 60 * 60 * 24, // 24h -- required for persistence to survive a restart
      staleTime: 1000 * 60,        // 1 minute
      networkMode: 'offlineFirst', // serve cache, then fetch
      retry: 2,
    },
    mutations: {
      networkMode: 'offlineFirst', // queue while offline
    },
  },
})

export const persister = createAsyncStoragePersister({
  storage: AsyncStorage,
  throttleTime: 1000,
})
```

`gcTime` must be longer than the time users might be offline, or TanStack evicts the cache before persistence can save it.

### Online & Focus Managers

Wire `onlineManager` to `NetInfo` and `focusManager` to `AppState`:

```ts
// lib/online.ts
import NetInfo from '@react-native-community/netinfo'
import { onlineManager, focusManager } from '@tanstack/react-query'
import { AppState } from 'react-native'

onlineManager.setEventListener((setOnline) => {
  return NetInfo.addEventListener((state) => {
    setOnline(!!state.isConnected)
  })
})

AppState.addEventListener('change', (status) => {
  focusManager.setFocused(status === 'active')
})
```

Refetches now fire when the user brings the app back to the foreground.

### Provider

```tsx
// app/_layout.tsx
import { PersistQueryClientProvider } from '@tanstack/react-query-persist-client'
import { queryClient, persister } from '@/lib/queryClient'
import '@/lib/online'

export default function RootLayout() {
  return (
    <PersistQueryClientProvider
      client={queryClient}
      persistOptions={{ persister, maxAge: 1000 * 60 * 60 * 24 }}
    >
      <Stack />
    </PersistQueryClientProvider>
  )
}
```

### Query Key Factory

One factory per feature. No string literals scattered through the code.

```ts
// features/posts/hooks/postKeys.ts
export const postKeys = {
  all: ['posts'] as const,
  lists: () => [...postKeys.all, 'list'] as const,
  list: (filters: Filters) => [...postKeys.lists(), filters] as const,
  details: () => [...postKeys.all, 'detail'] as const,
  detail: (id: string) => [...postKeys.details(), id] as const,
}
```

Invalidation stays precise:

```ts
queryClient.invalidateQueries({ queryKey: postKeys.lists() })        // all lists
queryClient.invalidateQueries({ queryKey: postKeys.detail(id) })     // one post
```

### Optimistic Updates

```ts
const mutation = useMutation({
  mutationFn: updatePost,
  onMutate: async (updated) => {
    await queryClient.cancelQueries({ queryKey: postKeys.detail(updated.id) })
    const previous = queryClient.getQueryData(postKeys.detail(updated.id))
    queryClient.setQueryData(postKeys.detail(updated.id), updated)
    return { previous }
  },
  onError: (_err, updated, context) => {
    if (context?.previous) {
      queryClient.setQueryData(postKeys.detail(updated.id), context.previous)
    }
  },
  onSettled: (_data, _err, updated) => {
    queryClient.invalidateQueries({ queryKey: postKeys.detail(updated.id) })
  },
})
```

### Common Mistakes

- `gcTime` shorter than offline duration → cache evicted before persistence saves it
- No `onlineManager` wiring → queries retry forever on a plane
- String literal query keys → invalidation breaks as soon as anyone typos
- `onError` without restoring previous data → optimistic UI lies when mutations fail

---

## 9. State Management

Match the tool to the scope:

| Scope                       | Tool                                 |
|-----------------------------|--------------------------------------|
| Server state                | TanStack Query                       |
| Local component state       | `useState` / `useReducer`            |
| Cross-component, low-freq   | Context (split by update frequency)  |
| Cross-component, high-freq  | Zustand or Jotai                     |
| External subscribed store   | `useSyncExternalStore`               |

Start with the simplest thing that works. Most screens need nothing beyond `useState` and TanStack Query.

### Split Contexts by Update Frequency

A common mistake is one giant context holding state + actions. Every consumer re-renders on every update.

```tsx
// WRONG: one context, everyone re-renders
const AppContext = createContext({ user, setUser, theme, setTheme, cart, setCart })
```

Split state from actions:

```tsx
const UserContext = createContext<User | null>(null)
const UserActionsContext = createContext<{ setUser: (u: User) => void } | null>(null)

export function UserProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<User | null>(null)
  const actions = useMemo(() => ({ setUser }), [])

  return (
    <UserActionsContext.Provider value={actions}>
      <UserContext.Provider value={user}>{children}</UserContext.Provider>
    </UserActionsContext.Provider>
  )
}

export const useUser = () => useContext(UserContext)
export const useUserActions = () => {
  const ctx = useContext(UserActionsContext)
  if (!ctx) throw new Error('useUserActions must be used inside UserProvider')
  return ctx
}
```

Components that only dispatch don't re-render when state changes. Components that only read state don't re-render when actions are recreated.

### Zustand for Broad Shared State

When many features share mutable state and Context would cause re-render cascades:

```ts
import { create } from 'zustand'

type Store = {
  drawerOpen: boolean
  toggleDrawer: () => void
}

export const useUIStore = create<Store>((set) => ({
  drawerOpen: false,
  toggleDrawer: () => set((s) => ({ drawerOpen: !s.drawerOpen })),
}))

// Component only subscribes to the slice it reads
const drawerOpen = useUIStore((s) => s.drawerOpen)
```

### Common Mistakes

- One giant `AppContext` → every state change re-renders the tree
- Server data in Zustand → you lose cache invalidation, refetching, and optimistic updates
- Context value `{ user, setUser }` created inline → new object every render, all consumers re-render
- Redux for a two-screen app → ceremony without benefit

---

## 10. Native Capabilities

Expo modules cover most needs. Install with `npx expo install` so you get the version that matches your SDK -- never `npm install` for native modules.

| Capability           | Module                                         |
|----------------------|------------------------------------------------|
| Camera               | `expo-camera`                                  |
| Image picker         | `expo-image-picker`                            |
| File system          | `expo-file-system`                             |
| Secure KV storage    | `expo-secure-store` (Keychain / Keystore)      |
| Async KV storage     | `@react-native-async-storage/async-storage`    |
| Haptics              | `expo-haptics`                                 |
| Location             | `expo-location`                                |
| Notifications        | `expo-notifications`                           |
| Biometrics           | `expo-local-authentication`                    |
| Clipboard            | `expo-clipboard`                               |
| Sharing              | `expo-sharing`                                 |
| Status bar           | `expo-status-bar`                              |
| Linking              | `expo-linking`                                 |

### Permissions

Always check before using. Declare the permission string in `app.config.ts`.

```tsx
import * as ImagePicker from 'expo-image-picker'
import { Alert, Linking } from 'react-native'

async function pickPhoto() {
  const { status, canAskAgain } = await ImagePicker.requestMediaLibraryPermissionsAsync()

  if (status !== 'granted') {
    Alert.alert(
      'Photos access required',
      canAskAgain
        ? 'Please grant access to pick a photo.'
        : 'Enable photos access in Settings.',
      canAskAgain
        ? [{ text: 'OK' }]
        : [
            { text: 'Cancel', style: 'cancel' },
            { text: 'Open Settings', onPress: () => Linking.openSettings() },
          ],
    )
    return
  }

  const result = await ImagePicker.launchImageLibraryAsync({ quality: 0.8 })
  if (!result.canceled) {
    // use result.assets[0].uri
  }
}
```

When `canAskAgain` is false, the OS won't show the prompt again -- you must send the user to Settings.

### Usage Strings in app.config.ts

```ts
ios: {
  infoPlist: {
    NSCameraUsageDescription: 'Take photos to attach to posts',
    NSPhotoLibraryUsageDescription: 'Select photos from your library',
    NSLocationWhenInUseUsageDescription: 'Show nearby posts on the map',
  },
},
android: {
  permissions: ['CAMERA', 'READ_MEDIA_IMAGES', 'ACCESS_FINE_LOCATION'],
},
```

Missing `NS*UsageDescription` strings cause App Store rejection on upload.

### Secure Storage

```ts
import * as SecureStore from 'expo-secure-store'

await SecureStore.setItemAsync('auth-token', token)
const token = await SecureStore.getItemAsync('auth-token')
await SecureStore.deleteItemAsync('auth-token')
```

Backed by Keychain on iOS and EncryptedSharedPreferences on Android. Use for auth tokens, refresh tokens, and anything sensitive. **Never put tokens in `AsyncStorage`** -- it's plaintext.

### Common Mistakes

- `npm install expo-camera` instead of `npx expo install expo-camera` → version mismatch, build fails
- Missing usage strings → App Store rejection
- Auth tokens in `AsyncStorage` → readable by anyone with device access
- Ignoring `canAskAgain` → users stuck with no way to grant permission

---

## 11. Animations & Gestures

Reanimated 3 runs animations on the UI thread via worklets. Gesture Handler provides gestures. They work together.

### Setup

```bash
npx expo install react-native-reanimated react-native-gesture-handler
```

```js
// babel.config.js
module.exports = {
  presets: ['babel-preset-expo'],
  plugins: ['react-native-reanimated/plugin'],  // MUST be last
}
```

Wrap the app root with `GestureHandlerRootView`:

```tsx
// app/_layout.tsx
import { GestureHandlerRootView } from 'react-native-gesture-handler'

<GestureHandlerRootView style={{ flex: 1 }}>
  <Stack />
</GestureHandlerRootView>
```

Without it, gestures silently fail on Android.

### Shared Values & Animated Styles

```tsx
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withSpring,
} from 'react-native-reanimated'

function Box() {
  const offset = useSharedValue(0)

  const style = useAnimatedStyle(() => ({
    transform: [{ translateX: offset.value }],
  }))

  return (
    <>
      <Animated.View style={[style, { width: 80, height: 80, backgroundColor: 'blue' }]} />
      <Button
        title="Move"
        onPress={() => {
          offset.value = withSpring(offset.value === 0 ? 100 : 0)
        }}
      />
    </>
  )
}
```

Shared values live on the UI thread. Reading `.value` outside a worklet works but can be stale -- prefer setting them in event handlers or `runOnUI(() => { ... })`.

### Gestures

```tsx
import { Gesture, GestureDetector } from 'react-native-gesture-handler'
import Animated, { useSharedValue, useAnimatedStyle, withSpring } from 'react-native-reanimated'

function DraggableCard() {
  const x = useSharedValue(0)
  const y = useSharedValue(0)

  const pan = Gesture.Pan()
    .onChange((e) => {
      x.value += e.changeX
      y.value += e.changeY
    })
    .onEnd(() => {
      x.value = withSpring(0)
      y.value = withSpring(0)
    })

  const style = useAnimatedStyle(() => ({
    transform: [{ translateX: x.value }, { translateY: y.value }],
  }))

  return (
    <GestureDetector gesture={pan}>
      <Animated.View style={[style, styles.card]} />
    </GestureDetector>
  )
}
```

### runOnJS

To call a JS function from a worklet (e.g., a callback after an animation completes):

```tsx
import { runOnJS } from 'react-native-reanimated'

const pan = Gesture.Pan().onEnd(() => {
  'worklet'
  runOnJS(onDragComplete)(x.value)
})
```

### Common Mistakes

- `react-native-reanimated/plugin` not last in Babel config → worklets don't compile
- Missing `GestureHandlerRootView` → Android gestures silently fail
- Calling `setState` inside a gesture handler → blocks the UI thread, defeats the point
- Reading `.value` in render → React doesn't track shared values, UI goes stale

---

## 12. Performance

Three levers: virtualize long lists, use native image caching, and keep the JS thread unblocked during transitions.

### FlashList

`@shopify/flash-list` outperforms `FlatList` dramatically on long lists. Same API plus an `estimatedItemSize`.

```tsx
import { FlashList } from '@shopify/flash-list'

<FlashList
  data={posts}
  renderItem={({ item }) => <PostItem post={item} />}
  keyExtractor={(item) => item.id}
  estimatedItemSize={80}
/>
```

Provide a reasonable `estimatedItemSize`. FlashList uses it to size the recycling pool -- a ballpark value is fine, exact doesn't matter.

### expo-image

Replaces React Native's `Image`. Handles memory+disk caching, blur placeholders, and smooth transitions.

```tsx
import { Image } from 'expo-image'

<Image
  source={uri}
  placeholder={{ blurhash: 'LEHV6nWB2yk8pyo0adR*.7kCMdnj' }}
  contentFit="cover"
  cachePolicy="memory-disk"
  transition={200}
  style={{ width: 100, height: 100 }}
/>
```

Use `cachePolicy="memory-disk"` so images survive app restarts. Use blurhash placeholders so lists don't flash gray during scroll.

### Memo List Items

```tsx
export const PostItem = React.memo(function PostItem({ post, onPress }: Props) {
  return (
    <Pressable onPress={() => onPress(post.id)}>
      <Text>{post.title}</Text>
    </Pressable>
  )
})
```

Wrap handlers in `useCallback` so prop identity is stable:

```tsx
const handlePress = useCallback((id: string) => {
  router.push(`/posts/${id}` as const)
}, [router])
```

Without stable props, `React.memo` is useless.

### InteractionManager

Defer expensive work until after the navigation transition:

```tsx
import { InteractionManager } from 'react-native'

useEffect(() => {
  const task = InteractionManager.runAfterInteractions(() => {
    processHeavyData()
  })
  return () => task.cancel()
}, [])
```

The animation stays at 60fps because JS isn't churning on data during the transition.

### Common Mistakes

- `FlatList` for 500+ items → stutters, memory grows. Use `FlashList`.
- React Native `Image` for lists → no caching, layout jank on scroll. Use `expo-image`.
- New `onPress` closure each render → `React.memo` does nothing
- Heavy work in screen mount → navigation transition stutters

---

## 13. Deep Linking

Three mechanisms:

- **Custom scheme** (`myapp://`) -- always works, but URLs are ugly and don't function on the web
- **Universal Links** (iOS) -- `https://myapp.com/post/123` opens the app when installed, falls back to the web
- **App Links** (Android) -- same idea, with `autoVerify: true`

### Config

```ts
// app.config.ts
export default (): ExpoConfig => ({
  scheme: 'myapp',
  ios: {
    bundleIdentifier: 'com.example.myapp',
    associatedDomains: ['applinks:myapp.com'],
  },
  android: {
    package: 'com.example.myapp',
    intentFilters: [
      {
        action: 'VIEW',
        autoVerify: true,
        data: [{ scheme: 'https', host: 'myapp.com' }],
        category: ['BROWSABLE', 'DEFAULT'],
      },
    ],
  },
})
```

### Verification Files

Host these on your web domain -- they're how iOS and Android verify the app owns the domain:

- iOS: `https://myapp.com/.well-known/apple-app-site-association`
- Android: `https://myapp.com/.well-known/assetlinks.json`

Both must be served over HTTPS, with `Content-Type: application/json`, and cached carefully (iOS pulls AASA on install). Any typo in the bundle ID, team ID, or SHA-256 fingerprint silently breaks the whole flow.

### Handling Links in the App

expo-router auto-maps URLs to routes. `https://myapp.com/posts/123` opens `app/posts/[id].tsx` -- no manual URL parsing.

For non-route query params, `useURL()` gives you the raw URL:

```tsx
import * as Linking from 'expo-linking'

const url = Linking.useURL()

useEffect(() => {
  if (!url) return
  const { queryParams } = Linking.parse(url)
  // handle queryParams
}, [url])
```

### OAuth with expo-auth-session

```tsx
import * as WebBrowser from 'expo-web-browser'
import * as AuthSession from 'expo-auth-session'

WebBrowser.maybeCompleteAuthSession()  // must be called at module scope

function useGoogleAuth() {
  const redirectUri = AuthSession.makeRedirectUri({
    scheme: 'myapp',
    path: 'redirect',
  })

  const [request, response, promptAsync] = AuthSession.useAuthRequest(
    {
      clientId: '...',
      scopes: ['openid', 'profile', 'email'],
      redirectUri,
    },
    { authorizationEndpoint: 'https://accounts.google.com/o/oauth2/v2/auth' },
  )

  return { request, response, promptAsync }
}
```

### Common Mistakes

- AASA with wrong team ID → iOS silently falls back to opening the URL in Safari
- `autoVerify: true` without `assetlinks.json` → Android opens a chooser every time
- Missing `WebBrowser.maybeCompleteAuthSession()` → OAuth popup stays open forever
- Hardcoding `redirectUri` instead of `makeRedirectUri` → breaks in dev client

---

## 14. Internationalization

`expo-localization` detects the user's locale. `i18n-js` does translation. `Intl.*` handles number and date formatting.

```bash
npx expo install expo-localization
npm install i18n-js
```

### Setup

```ts
// lib/i18n.ts
import * as Localization from 'expo-localization'
import { I18n } from 'i18n-js'

import en from './translations/en.json'
import es from './translations/es.json'

export const i18n = new I18n({ en, es })

i18n.locale = Localization.getLocales()[0]?.languageTag ?? 'en'
i18n.enableFallback = true
i18n.defaultLocale = 'en'
```

`Localization.getLocales()` returns an ordered array from system settings. Use the first entry. Do **not** use `Localization.locale` -- it's deprecated.

### Usage

```tsx
import { i18n } from '@/lib/i18n'

<Text>{i18n.t('welcome')}</Text>
<Text>{i18n.t('greeting', { name })}</Text>
```

### Intl Formatting

React Native supports `Intl` natively on both platforms via Hermes. Use it for numbers and dates -- don't re-implement formatting in translation files.

```tsx
const price = new Intl.NumberFormat(i18n.locale, {
  style: 'currency',
  currency: 'USD',
}).format(amount)

const date = new Intl.DateTimeFormat(i18n.locale, {
  dateStyle: 'long',
}).format(new Date(createdAt))
```

### RTL

```tsx
import { I18nManager } from 'react-native'
import * as Localization from 'expo-localization'
import * as Updates from 'expo-updates'

async function applyRTL() {
  const isRTL = Localization.getLocales()[0]?.textDirection === 'rtl'

  if (isRTL !== I18nManager.isRTL) {
    I18nManager.forceRTL(isRTL)
    I18nManager.allowRTL(isRTL)
    await Updates.reloadAsync()  // REQUIRED -- layout doesn't flip without reload
  }
}
```

The `Updates.reloadAsync()` call is non-negotiable. Without it, `I18nManager.forceRTL(true)` sets a flag that takes effect on next launch -- the current screen stays LTR and looks broken.

### Common Mistakes

- `Localization.locale` → deprecated, returns stale values. Use `getLocales()[0].languageTag`.
- Hardcoding currency symbols in translations → breaks for other currencies
- `I18nManager.forceRTL` without `Updates.reloadAsync()` → doesn't apply until next cold start
- Concatenating translated strings → word order differs between languages

---

## 15. Background Tasks

`expo-background-task` runs JS when the OS lets the app do background work. Replaces the deprecated `expo-background-fetch`. iOS gives you roughly **30 seconds** of execution per run.

```bash
npx expo install expo-background-task expo-task-manager
```

### Define the Task

Tasks must be defined at module scope, before the app mounts. The OS may wake the app and run the task without ever mounting React.

```ts
// lib/backgroundTasks.ts
import * as BackgroundTask from 'expo-background-task'
import * as TaskManager from 'expo-task-manager'

const SYNC_TASK = 'sync-posts'

TaskManager.defineTask(SYNC_TASK, async () => {
  try {
    const synced = await syncPendingPosts()
    return synced > 0
      ? BackgroundTask.BackgroundTaskResult.Success
      : BackgroundTask.BackgroundTaskResult.NoData
  } catch (error) {
    console.error('Background sync failed', error)
    return BackgroundTask.BackgroundTaskResult.Failed
  }
})

export async function registerSyncTask() {
  const status = await BackgroundTask.getStatusAsync()
  if (status === BackgroundTask.BackgroundTaskStatus.Restricted) return

  await BackgroundTask.registerTaskAsync(SYNC_TASK, {
    minimumInterval: 60 * 15,  // 15 minutes -- OS decides actual timing
  })
}
```

Import this file at the top of `app/_layout.tsx` so the task is registered on cold start.

### app.config.ts

Declare the task identifier for iOS:

```ts
ios: {
  infoPlist: {
    BGTaskSchedulerPermittedIdentifiers: ['sync-posts'],
  },
},
```

Without this, iOS silently refuses to schedule the task.

### What You Can't Do in Background

- Long-running network requests (30s budget)
- Any UI work
- Access to secure storage protected by Face ID
- Anything that requires the user to be present

Stick to syncing queued writes, refreshing caches, and uploading pending data.

### Common Mistakes

- Defining the task inside a component → OS runs it before React mounts, `TaskManager` throws "task not found"
- No `BGTaskSchedulerPermittedIdentifiers` → iOS refuses to schedule with no error
- Doing more than 30s of work → iOS kills the task, future schedules get throttled

---

## 16. Error Handling & Sentry

`@sentry/react-native` with the Expo config plugin. The old `sentry-expo` package is deprecated -- don't use it.

### Install

```bash
npx expo install @sentry/react-native
```

```ts
// app.config.ts
plugins: [
  [
    '@sentry/react-native/expo',
    {
      url: 'https://sentry.io/',
      organization: 'myorg',
      project: 'myapp',
    },
  ],
],
```

### Metro Config

Sentry's source map upload needs a wrapped Metro config:

```js
// metro.config.js
const { getSentryExpoConfig } = require('@sentry/react-native/metro')
module.exports = getSentryExpoConfig(__dirname)
```

### Init

```tsx
// app/_layout.tsx
import * as Sentry from '@sentry/react-native'
import * as Updates from 'expo-updates'

Sentry.init({
  dsn: process.env.EXPO_PUBLIC_SENTRY_DSN,
  tracesSampleRate: __DEV__ ? 1.0 : 0.2,
  release: Updates.updateId ?? 'embedded',
  dist: Updates.runtimeVersion ?? undefined,
  enableAutoSessionTracking: true,
  beforeSend(event) {
    if (__DEV__) return null  // don't ship dev errors
    return event
  },
})

// Distinguish the embedded JS bundle from an OTA update
Sentry.setTag('isEmbeddedLaunch', String(Updates.isEmbeddedLaunch))

export default Sentry.wrap(function RootLayout() {
  return <Stack />
})
```

Key points:

- `release: Updates.updateId` -- correlates errors with the specific OTA update that caused them
- `isEmbeddedLaunch` tag -- distinguishes bugs in the binary from bugs introduced by an OTA update
- `Sentry.wrap` at the root -- auto-captures navigation, unhandled promises, and React errors
- `beforeSend` returning `null` in dev -- Sentry doesn't fill with dev noise

### Error Boundaries

expo-router exports `ErrorBoundary` per layout. Put one at the root:

```tsx
// app/_layout.tsx
export function ErrorBoundary({ error, retry }: ErrorBoundaryProps) {
  return (
    <View className="flex-1 items-center justify-center p-6">
      <Text className="text-lg font-semibold">Something went wrong</Text>
      <Text className="mt-2 text-gray-600">{error.message}</Text>
      <Button onPress={retry} title="Try again" />
    </View>
  )
}
```

This catches errors in the route tree. Errors outside the tree (e.g., inside a mutation's `onSuccess`) go through Sentry's global handler.

### Observability KPIs

Tag events with the data you'll actually query on:

- `release` -- the specific build
- `dist` -- runtime version (native code fingerprint)
- `isEmbeddedLaunch` -- embedded bundle vs OTA
- `locale` -- a common source of formatter crashes
- `connection` -- `NetInfo` type (wifi, cellular, none)

### Testing the Wiring

Before shipping, verify Sentry actually receives events. Add a temporary "crash test" button in a debug menu:

```tsx
<Button
  title="Crash (test)"
  onPress={() => { throw new Error('Test crash') }}
/>
```

Ship one crash, confirm it arrives with the expected tags, then remove the button.

### Common Mistakes

- Using `sentry-expo` → deprecated, source maps won't upload
- Not wrapping with `Sentry.wrap` → misses React errors and navigation breadcrumbs
- `release: '1.0.0'` hardcoded → can't tell which OTA caused a crash
- No `beforeSend` filter → dev errors pollute production issues

---

## 17. Testing

Jest + `jest-expo` preset + React Native Testing Library. Unit test services and hooks; integration test screens.

### Setup

```bash
npx expo install jest-expo jest @testing-library/react-native @testing-library/jest-native
```

```json
// package.json
{
  "scripts": { "test": "jest" },
  "jest": {
    "preset": "jest-expo",
    "setupFilesAfterEach": ["<rootDir>/jest.setup.ts"],
    "transformIgnorePatterns": [
      "node_modules/(?!(jest-)?react-native|@react-native|expo(nent)?|@expo|react-native-reanimated|react-native-gesture-handler|@shopify/flash-list)"
    ]
  }
}
```

```ts
// jest.setup.ts
import '@testing-library/jest-native/extend-expect'
import 'react-native-gesture-handler/jestSetup'

jest.mock('react-native-reanimated', () =>
  require('react-native-reanimated/mock'),
)

jest.spyOn(console, 'warn').mockImplementation(() => {})
```

### Component Tests

```tsx
// PostItem.test.tsx
import { render, screen, fireEvent } from '@testing-library/react-native'
import { PostItem } from './PostItem'

describe('PostItem', () => {
  const post = { id: '1', title: 'Hello', author: 'Jane' }

  it('renders title and author', () => {
    render(<PostItem post={post} onPress={jest.fn()} />)
    expect(screen.getByText('Hello')).toBeTruthy()
    expect(screen.getByText('Jane')).toBeTruthy()
  })

  it('calls onPress with post id', () => {
    const onPress = jest.fn()
    render(<PostItem post={post} onPress={onPress} />)
    fireEvent.press(screen.getByRole('button'))
    expect(onPress).toHaveBeenCalledWith('1')
  })
})
```

Query by accessibility role/label whenever possible. Query by test ID only when roles aren't available.

### Hook Tests

```tsx
import { renderHook, waitFor } from '@testing-library/react-native'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { usePosts } from './usePosts'

function wrapper({ children }: { children: React.ReactNode }) {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  })
  return <QueryClientProvider client={client}>{children}</QueryClientProvider>
}

it('fetches posts', async () => {
  const { result } = renderHook(() => usePosts({ status: 'published' }), { wrapper })
  await waitFor(() => expect(result.current.isSuccess).toBe(true))
  expect(result.current.data).toHaveLength(3)
})
```

### Mocking Native Modules

Only mock at the API boundary -- never your own code.

```ts
// __mocks__/expo-secure-store.ts
const store = new Map<string, string>()

export const setItemAsync = jest.fn(async (k: string, v: string) => {
  store.set(k, v)
})
export const getItemAsync = jest.fn(async (k: string) => store.get(k) ?? null)
export const deleteItemAsync = jest.fn(async (k: string) => {
  store.delete(k)
})
```

### Testing Reanimated

`react-native-reanimated/mock` replaces the native bridge with no-ops. Most of the time you don't assert animated styles -- you assert the *side effect* (e.g., "after swiping, the modal is gone"). Animation correctness is a visual-regression concern.

### Testing Gestures

```ts
import { fireGestureHandler, State } from 'react-native-gesture-handler/jest-utils'

it('dismisses card on swipe', () => {
  const onDismiss = jest.fn()
  render(<SwipeableCard onDismiss={onDismiss} />)

  fireGestureHandler('Pan', [
    { state: State.BEGAN, translationX: 0 },
    { state: State.ACTIVE, translationX: 200 },
    { state: State.END, translationX: 200 },
  ])

  expect(onDismiss).toHaveBeenCalled()
})
```

### Common Mistakes

- Missing `transformIgnorePatterns` entries → Jest chokes on ESM from `@expo`, `react-native`, etc.
- Mocking your own modules → you test the mock, not the code
- `fireEvent.click` instead of `fireEvent.press` → no such event on RN
- Querying by test ID when a role exists → tests don't verify accessibility

---

## 18. Release Pipeline (EAS)

Expo Application Services handles builds, submissions, and OTA updates.

### eas.json

```json
{
  "cli": { "version": ">= 10.0.0", "appVersionSource": "remote" },
  "build": {
    "development": {
      "developmentClient": true,
      "distribution": "internal",
      "channel": "development"
    },
    "preview": {
      "distribution": "internal",
      "channel": "preview",
      "ios": { "simulator": true }
    },
    "production": {
      "autoIncrement": true,
      "channel": "production"
    }
  },
  "submit": {
    "production": {
      "ios": {
        "appleId": "you@example.com",
        "ascAppId": "1234567890",
        "appleTeamId": "ABCD1234"
      },
      "android": {
        "serviceAccountKeyPath": "./secrets/google-play-key.json",
        "track": "internal"
      }
    }
  }
}
```

### Three Profiles

- **development** -- internal distribution, development client, connects to Metro
- **preview** -- internal distribution, production JS bundle, no Metro. Use for TestFlight and internal Android tracks.
- **production** -- store submission

### Build

```bash
eas build --profile production --platform all
```

Builds run on EAS servers. The CLI uploads credentials (or uses EAS-managed signing) and returns a download URL when done.

### Submit

```bash
eas submit --profile production --platform all
```

Uploads the latest build to App Store Connect and Google Play. For iOS you need an app-specific password or ASC API key. For Android you need a service account key JSON file.

### OTA Updates (EAS Update)

```bash
eas update --branch production --message "Fix typo on login screen"
```

Only JS and asset changes. Anything that touches native code (new library, config plugin, new permission) requires a full rebuild.

```ts
// app.config.ts
runtimeVersion: { policy: 'fingerprint' }
```

The `fingerprint` policy hashes your native code. When the fingerprint changes, Expo marks the OTA update as incompatible with old binaries -- users on the old binary don't receive it. This prevents the most common OTA disaster: pushing an update that references a native module users don't have.

### Channels vs Branches

- **Branch** -- a stream of updates (e.g., `production`, `preview`)
- **Channel** -- a build's default branch

A build with `channel: "production"` receives updates published to the `production` branch. You can move channels between branches without rebuilding -- useful for rollbacks.

```bash
eas channel:edit production --branch production-rollback
```

### Development Builds

```bash
eas build --profile development --platform ios
```

Install on a real device, then run `npx expo start --dev-client`. This gives you the full Expo SDK (including custom native modules) with Metro's hot reload.

Expo Go is fine for prototyping but can't include custom config plugins or arbitrary native modules. Real projects need dev builds.

### Common Mistakes

- `runtimeVersion: "1.0.0"` hardcoded → users crash after an OTA that references a native module they don't have
- Testing on Expo Go, shipping a dev build → behavior diverges, surprises in production
- OTA update with a native change → JS expects a module that doesn't exist in the binary, crash on load
- No `autoIncrement` → build numbers collide on the store

---

## 19. Platform Gotchas

The differences that bite you in production.

### iOS

- `Pressable` on small icons needs explicit `hitSlop={{ top: 8, left: 8, right: 8, bottom: 8 }}`
- Status bar color via `expo-status-bar`, not React Native's `StatusBar`
- `Linking.openURL` doesn't throw for invalid schemes -- check `canOpenURL` first
- Safe area insets are non-zero even without a notch (status bar height)

### Android

- Ripple effects need `android_ripple={{ color, borderless }}` on `Pressable`
- `BackHandler.addEventListener('hardwareBackPress', ...)` **must** be removed on unmount
- `elevation` for shadows -- iOS `shadow*` props do nothing on Android
- `Modal` has `onRequestClose` that must be wired for hardware back button to dismiss
- `WebView` doesn't inherit cookies from the app's HTTP client without setup

### Both

- `Text` nodes must be inside `<Text>`, never directly in `<View>` -- crashes with a cryptic error
- `FlatList`/`FlashList` inside a `ScrollView` -- one of them breaks. Use `ListHeaderComponent` / `ListFooterComponent`.
- `onPress` on nested `Pressable` bubbles to parent -- handle ordering carefully
- `Image` without dimensions → renders zero-sized

### Common Mistakes

- Testing only on iOS → Android-specific bugs (back button, elevation, ripple, gesture root) ship
- `Platform.OS === 'ios'` scattered through JSX → consolidate with `Platform.select` at the top of the component
- Assuming React Native has web text rendering → line breaks, kerning, and font fallbacks all differ

---

## 20. Quick Reference

| Mistake | Fix |
|---------|-----|
| `useLocalSearchParams<{id: string}>()` trusted as-is | Validate with Zod `safeParse` at the screen boundary |
| `runtimeVersion: "1.0.0"` hardcoded | `{ policy: 'fingerprint' }` |
| Missing `scheme` in app config | Deep links and OAuth redirects silently fail |
| `sentry-expo` package | `@sentry/react-native` + Expo config plugin |
| `expo-background-fetch` | `expo-background-task` (new 30s budget API) |
| `Localization.locale` | `Localization.getLocales()[0].languageTag` |
| `I18nManager.forceRTL(true)` alone | Call `Updates.reloadAsync()` after |
| `npm install expo-camera` | `npx expo install expo-camera` for matching version |
| Auth tokens in `AsyncStorage` | `expo-secure-store` (Keychain / Keystore) |
| `FlatList` for long lists | `@shopify/flash-list` with `estimatedItemSize` |
| React Native `Image` in lists | `expo-image` with `cachePolicy="memory-disk"` |
| `TextInput` without autofill hints | `textContentType` (iOS) **and** `autoComplete` (Android) |
| `Pressable` without `accessibilityLabel` | Every interactive element needs a label |
| `KeyboardAvoidingView` | `react-native-keyboard-controller`'s `KeyboardProvider` |
| `Text` rendered directly in `<View>` | Wrap in `<Text>` -- crashes otherwise |
| Hardcoded `paddingTop: 44` | `useSafeAreaInsets()` or `<SafeAreaView edges={['top']}>` |
| Missing `GestureHandlerRootView` | Wrap app root -- Android gestures fail silently without it |
| `react-native-reanimated/plugin` not last in Babel | Put it last -- worklets don't compile otherwise |
| `gcTime: 0` with persistence | Set `gcTime` longer than offline duration (24h default) |
| String literal query keys | Query key factory per feature |
| One giant `AppContext` | Split by update frequency; server state in TanStack Query |
| Context value `{ user, setUser }` created inline | `useMemo` the actions; split state from actions |
| `onPress` closure new every render | `useCallback` so `React.memo` list items actually work |
| `BackHandler` listener not removed | Memory leak and double-firing on Android |
| Mocking your own modules in tests | Mock at the API boundary only |
| Testing only on iOS | Android surfaces different bugs -- test both per PR |
| `NSCameraUsageDescription` missing | App Store rejects on upload |
| OTA update with a native change | `fingerprint` policy prevents the crash |
| `Sentry.init` without `release: Updates.updateId` | Can't correlate crashes with specific OTA updates |
| Inline `if (isLoading)` on every screen | Extract a `ScreenState` wrapper |
| Data fetching inside presentational components | Move to screens; presentational = props only |
| Task defined inside a React component | Define at module scope so the OS can run it pre-mount |
