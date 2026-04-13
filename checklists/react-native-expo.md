---
name: react-native-expo-checklist
description: Pre-commit checklist for React Native / Expo projects
---

# React Native / Expo Checklist

## Pre-Commit (every time, no exceptions)

```bash
npm run lint
npm run typecheck    # tsc --noEmit
npm test
```

## Review (after implementation)

- [ ] Route params validated with Zod, not trusted from `useLocalSearchParams<T>()`
- [ ] Every screen handles loading, error, and empty states
- [ ] Long lists use `FlashList` with `estimatedItemSize`, not `FlatList`
- [ ] `TextInput` has `textContentType` (iOS) **and** `autoComplete` (Android)
- [ ] Interactive elements have `accessibilityLabel` and `accessibilityRole`
- [ ] Auth tokens in `expo-secure-store`, not `AsyncStorage`
- [ ] Query keys use the factory pattern
- [ ] Mutations invalidate the right caches
- [ ] Native modules installed with `npx expo install` (not `npm install`)
- [ ] New iOS permissions have `NS*UsageDescription` in `app.config.ts`
- [ ] Tested on a real Android device, not just iOS simulator
- [ ] Sentry `release` tag uses `Updates.updateId` (OTA correlation)
