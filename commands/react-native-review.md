---
description: React Native / Expo code review with severity-based filtering
---

# React Native Review

1. Get changed files: `git diff --name-only -- '*.ts' '*.tsx' 'app.config.*' 'eas.json' 'babel.config.*' 'metro.config.*'`
2. Run the **react-native-reviewer** agent on changed files
3. Generate severity report with file locations and fixes
4. Block if CRITICAL or HIGH issues found
