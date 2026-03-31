---
name: react-typescript-patterns
description: Deep reference for React/TypeScript patterns -- React 19 hooks, Vike SSR, component composition, type safety, testing with Vitest/RTL, accessibility, data fetching with TanStack Query, CodeMirror integration, and performance. Grounded in patterns from a production Vike + React 19 app.
origin: claude-react-typescript (audited and rebuilt for nunchuck-skills)
---

# React / TypeScript Patterns

Production patterns for React 19 applications with TypeScript. Covers Vike (primary SSR framework), React Router, and Next.js App Router. Focused on patterns that are non-obvious or commonly gotten wrong.

> To run an automated review, use the **react-typescript-reviewer** agent or `/react-review`.

---

## Table of Contents

1. [React 19 Hooks](#react-19-hooks)
2. [TypeScript Patterns](#typescript-patterns)
3. [Component Composition](#component-composition)
4. [Hooks Deep Dive](#hooks-deep-dive)
5. [Vike Patterns](#vike-patterns)
6. [Data Fetching (TanStack Query)](#data-fetching)
7. [Testing (Vitest + RTL)](#testing)
8. [CodeMirror Integration](#codemirror-integration)
9. [Form Patterns](#form-patterns)
10. [Accessibility](#accessibility)
11. [Performance](#performance)
12. [State Management](#state-management)
13. [Next.js App Router](#nextjs-app-router)
14. [Quick Reference](#quick-reference)

---

## React 19 Hooks

### `use()` -- Unwrap Promises and Context

```tsx
// Create promise OUTSIDE the consuming component to avoid infinite Suspense loop
function UserPage({ userId }: { userId: string }) {
  const promiseRef = useRef<Promise<User> | null>(null)
  if (!promiseRef.current) {
    promiseRef.current = fetchUser(userId)
  }

  return (
    <Suspense fallback={<Skeleton />}>
      <UserProfile userPromise={promiseRef.current} />
    </Suspense>
  )
}

function UserProfile({ userPromise }: { userPromise: Promise<User> }) {
  const user = use(userPromise) // Suspends until resolved
  return <h1>{user.name}</h1>
}

// Conditional context read (impossible with useContext)
function ThemeText({ override }: { override?: boolean }) {
  const theme = override ? 'dark' : use(ThemeContext)
  return <span className={theme}>text</span>
}
```

**Common mistakes:**
- Creating the promise inside the consuming component (infinite Suspense loop)
- Forgetting Suspense boundary (unhandled suspension)
- Forgetting Error Boundary (unhandled rejection)

### `useActionState` -- Form Actions

Replaces `useState` + `useEffect` + `isLoading` pattern for form submission:

```tsx
async function submitForm(prev: FormState, formData: FormData): Promise<FormState> {
  const result = EmailSchema.safeParse(formData.get('email'))
  if (!result.success) return { error: result.error.flatten().fieldErrors, success: false }
  await api.subscribe(result.data)
  return { error: null, success: true }
}

function SubscribeForm() {
  const [state, action, pending] = useActionState(submitForm, { error: null, success: false })
  return (
    <form action={action}>
      <input name="email" type="email" aria-invalid={!!state.error?.email} />
      <button disabled={pending}>{pending ? 'Saving...' : 'Subscribe'}</button>
    </form>
  )
}
```

### `useFormStatus` -- Must Be in a Child Component

```tsx
// GOOD: Child reads parent form status
function SubmitButton({ label }: { label: string }) {
  const { pending } = useFormStatus()
  return <button type="submit" disabled={pending}>{pending ? 'Saving...' : label}</button>
}

// BAD: useFormStatus in same component as <form> -- always returns idle
function BrokenForm() {
  const { pending } = useFormStatus() // Won't work here!
  return <form action={action}><button disabled={pending}>Save</button></form>
}
```

### `useOptimistic` -- Instant UI Feedback

```tsx
function TodoList({ todos, addTodo }: Props) {
  const [optimisticTodos, addOptimistic] = useOptimistic(
    todos,
    (current: Todo[], newText: string) => [
      ...current,
      { id: crypto.randomUUID(), text: newText, pending: true },
    ]
  )

  async function handleAdd(formData: FormData) {
    const text = formData.get('text') as string
    addOptimistic(text) // Show immediately
    await addTodo(text) // Server confirms or reverts
  }

  return (
    <form action={handleAdd}>
      <input name="text" required />
      <ul>
        {optimisticTodos.map(t => (
          <li key={t.id} style={{ opacity: t.pending ? 0.5 : 1 }}>{t.text}</li>
        ))}
      </ul>
    </form>
  )
}
```

### `useId` -- Stable IDs for Accessibility

```tsx
function FormField({ label, error }: { label: string; error?: string }) {
  const id = useId()
  return (
    <div>
      <label htmlFor={id}>{label}</label>
      <input id={id} aria-invalid={!!error} aria-describedby={error ? `${id}-err` : undefined} />
      {error && <span id={`${id}-err`} role="alert">{error}</span>}
    </div>
  )
}
```

Don't use `useId` for list keys, CSS selectors, or external APIs. It generates opaque strings like `:r1:`.

### `ref` as a Regular Prop (React 19)

```tsx
// React 19: ref is just a prop. No more forwardRef.
function Input({ ref, ...props }: React.ComponentProps<'input'>) {
  return <input ref={ref} {...props} />
}
```

---

## TypeScript Patterns

### Discriminated Union Props

```tsx
type ButtonProps =
  | { variant: 'link'; href: string; onClick?: never }
  | { variant: 'button'; onClick: () => void; href?: never }
  | { variant: 'submit'; onClick?: never; href?: never }

function Button(props: ButtonProps) {
  switch (props.variant) {
    case 'link': return <a href={props.href}>Link</a>
    case 'button': return <button onClick={props.onClick}>Click</button>
    case 'submit': return <button type="submit">Submit</button>
  }
}
```

### Generic Components

```tsx
interface SelectProps<T> {
  options: T[]
  value: T
  onChange: (value: T) => void
  getLabel: (item: T) => string
  getKey: (item: T) => string
}

function Select<T>({ options, value, onChange, getLabel, getKey }: SelectProps<T>) {
  return (
    <select value={getKey(value)} onChange={e => {
      const selected = options.find(o => getKey(o) === e.target.value)
      if (selected) onChange(selected)
    }}>
      {options.map(o => <option key={getKey(o)} value={getKey(o)}>{getLabel(o)}</option>)}
    </select>
  )
}
```

### `as const satisfies` for Validated Immutable Objects

```tsx
const STATUS_MAP = {
  active: { label: 'Active', color: 'green' },
  inactive: { label: 'Inactive', color: 'gray' },
} as const satisfies Record<string, { label: string; color: string }>
// Values are narrow string literals AND structure is validated
```

### Strict Event Typing

```tsx
function handleChange(e: React.ChangeEvent<HTMLInputElement>) { setValue(e.target.value) }
function handleSubmit(e: React.FormEvent<HTMLFormElement>) { e.preventDefault() }
function handleKeyDown(e: React.KeyboardEvent<HTMLDivElement>) { if (e.key === 'Escape') close() }
```

### Parallel Schema Families (Types Pattern)

Mirror your backend schemas with separate frontend types per use case:

```tsx
// Full resource (detail view)
export interface Problem { id: string; title: string; description: string; solution_code: string; ... }
// List item (excludes expensive fields)
export interface ProblemListItem { id: string; title: string; difficulty: Difficulty; tags: string[] }
// Create payload
export interface ProblemCreate { title: string; difficulty: Difficulty; language: Language; ... }
// Update payload (all optional)
export interface ProblemUpdate { title?: string; difficulty?: Difficulty; ... }
```

---

## Component Composition

### Compound Components

```tsx
const AccordionContext = createContext<{ openItem: string | null; toggle: (id: string) => void } | null>(null)

function Accordion({ children }: { children: React.ReactNode }) {
  const [openItem, setOpenItem] = useState<string | null>(null)
  const toggle = (id: string) => setOpenItem(prev => prev === id ? null : id)
  return <AccordionContext value={{ openItem, toggle }}><div>{children}</div></AccordionContext>
}

function AccordionItem({ id, title, children }: { id: string; title: string; children: React.ReactNode }) {
  const ctx = use(AccordionContext)
  if (!ctx) throw new Error('Must be inside <Accordion>')
  const isOpen = ctx.openItem === id
  return (
    <div>
      <button onClick={() => ctx.toggle(id)} aria-expanded={isOpen}>{title}</button>
      {isOpen && <div>{children}</div>}
    </div>
  )
}
```

### When to Use Each Pattern

| Pattern | Use When | Avoid When |
|---------|----------|------------|
| Plain props | Simple data flow | Props exceed 3 levels |
| Compound components | Flexible related UI with shared state | Fixed layout, one-off |
| Slots (`header`, `footer` props) | Fixed layout with customizable areas | Dynamic slot count |
| Custom hooks | Reusable stateful logic without UI | Need to render specific JSX |

---

## Hooks Deep Dive

### useEffect Cleanup

```tsx
// AbortController for fetch
useEffect(() => {
  const controller = new AbortController()
  fetchData(id, { signal: controller.signal }).then(setData).catch(err => {
    if (err.name !== 'AbortError') setError(err)
  })
  return () => controller.abort()
}, [id])

// Timer cleanup
useEffect(() => {
  const interval = setInterval(tick, 1000)
  return () => clearInterval(interval)
}, [tick])
```

### useRef for Stable Callbacks (CodeMirror Pattern)

When a library creates its own closure (editor, chart, map), use refs to keep callbacks current without recreating the instance:

```tsx
const onChangeRef = useRef(onChange)
onChangeRef.current = onChange // Update every render

useEffect(() => {
  const editor = new EditorView({
    extensions: [
      EditorView.updateListener.of(update => {
        if (update.docChanged) onChangeRef.current?.(update.state.doc.toString())
      }),
    ],
    parent: containerRef.current!,
  })
  return () => editor.destroy()
}, []) // Empty deps -- editor created once, callback always current via ref
```

### useReducer for Complex State

Use when state has 3+ related fields, multiple action types, or next state depends on previous state:

```tsx
type Action =
  | { type: 'ADD'; text: string }
  | { type: 'TOGGLE'; id: string }
  | { type: 'SET_FILTER'; filter: 'all' | 'active' | 'completed' }

function todoReducer(state: TodoState, action: Action): TodoState {
  switch (action.type) {
    case 'ADD': return { ...state, todos: [...state.todos, { id: crypto.randomUUID(), text: action.text, completed: false }] }
    case 'TOGGLE': return { ...state, todos: state.todos.map(t => t.id === action.id ? { ...t, completed: !t.completed } : t) }
    case 'SET_FILTER': return { ...state, filter: action.filter }
  }
}
```

### SSR-Safe URL State Hook

```tsx
function useSearchParamState(key: string, defaultValue: string): [string, (v: string) => void] {
  const [value, setValue] = useState(() => {
    if (typeof window === 'undefined') return defaultValue
    return new URLSearchParams(window.location.search).get(key) ?? defaultValue
  })

  const setParam = useCallback((newValue: string) => {
    setValue(newValue)
    const url = new URL(window.location.href)
    if (newValue) url.searchParams.set(key, newValue)
    else url.searchParams.delete(key)
    history.replaceState({}, '', url) // replaceState, not pushState (no history pollution)
  }, [key])

  return [value, setParam]
}
```

---

## Vike Patterns

### File Structure

```
pages/
├── +config.ts                     # Global config (extends vike-react)
├── +Layout.tsx                    # Root layout
├── +Wrapper.tsx                   # Provider wrapper (QueryClient, theme)
├── +Head.tsx                      # Global <head> tags
├── _error/+Page.tsx               # Error page (404, 500)
├── app/
│   ├── +guard.ts                  # Auth check for all /app/* routes
│   ├── +Layout.tsx                # App layout (sidebar, nav)
│   ├── dashboard/+Page.tsx        # /app/dashboard
│   ├── problems/+Page.tsx         # /app/problems
│   └── decks/@id/+Page.tsx        # /app/decks/:id
└── auth/
    └── github/callback/+Page.tsx  # OAuth callback
```

### Guard Pattern (Auth)

```tsx
// pages/app/+guard.ts -- runs before data fetching
import { redirect } from 'vike/abort'

export function guard(pageContext: PageContext): void {
  const cookieStr = typeof window === 'undefined'
    ? (pageContext.headers?.cookie ?? '')
    : document.cookie

  // Check both tokens -- refresh can recover an expired access token
  if (!getCookie('access_token', cookieStr) && !getCookie('refresh_token', cookieStr)) {
    throw redirect('/')
  }
}
```

**Non-obvious:** Guards run server-side during SSR and client-side during navigation. Cookie access differs between the two (headers vs `document.cookie`).

### Layout with Auth Error Recovery

```tsx
export default function AppLayout({ children }: { children: React.ReactNode }) {
  const { urlPathname } = usePageContext()
  const isPublicRoute = urlPathname.startsWith('/app/profile/')

  const { data: user, isError, isLoading } = useQuery({
    queryKey: queryKeys.me,
    queryFn: getMe,
    retry: 1,
    staleTime: 5 * 60 * 1000,
    enabled: !isPublicRoute, // Don't fetch user on public pages (avoids 401)
  })

  // Auth error recovery -- redirect to login
  const isRedirecting = useRef(false)
  useEffect(() => {
    if (isError && !isPublicRoute && !isRedirecting.current) {
      isRedirecting.current = true
      logout()
      window.location.href = '/' // Hard navigation, not Vike navigate
    }
  }, [isError, isPublicRoute])

  if (isPublicRoute) return <main>{children}</main>
  if (isLoading || isError) return <LoadingScreen />
  return <LayoutWithSidebar>{children}</LayoutWithSidebar>
}
```

**Why `window.location.href`:** Vike's `navigate()` goes through the guard, which would redirect again. Hard navigation resets all client state cleanly.

### Wrapper for Providers (SSR-Safe)

```tsx
// pages/+Wrapper.tsx
export default function Wrapper({ children }: { children: React.ReactNode }) {
  // Create QueryClient per request to prevent cross-request data leaks during SSR
  const [queryClient] = useState(() => new QueryClient({
    defaultOptions: { queries: { staleTime: 5 * 60 * 1000 } },
  }))

  return (
    <QueryClientProvider client={queryClient}>
      {children}
    </QueryClientProvider>
  )
}
```

**Critical:** `useState(() => new QueryClient())` creates per-request. `const qc = new QueryClient()` at module scope leaks data between SSR requests.

### File Environment Conventions

```
+data.ts               # Server-only by default
+data.client.ts        # Client-only
+guard.server.ts       # Server-only (explicit)
credentials.server.ts  # Never sent to client (Vike enforces at build time)
```

### ClientOnly for Browser APIs

```tsx
import { ClientOnly } from 'vike-react/ClientOnly'

<ClientOnly fallback={<div className="h-64 animate-pulse bg-muted rounded" />}>
  <InteractiveChart />
</ClientOnly>
```

### Navigation Decision Matrix

| Situation | Use |
|-----------|-----|
| Inside `guard()` or `data()` | `throw redirect("/path")` from `vike/abort` |
| After form submission / event handler | `navigate("/path")` from `vike/client/router` |
| Show different page without URL change | `throw render("/path")` from `vike/abort` |
| Auth error recovery (stale state) | `window.location.href` (hard nav to reset everything) |

**Never use `window.location.href` for normal navigation.** It does a full page reload and loses all React state. The only exception is auth error recovery where you want to reset everything.

### Guard Must Be Isomorphic

Guards run server-side during SSR and client-side during navigation. Cookie access differs between the two:

```tsx
export function guard(pageContext: PageContext): void {
  const cookieStr = typeof window === 'undefined'
    ? (pageContext.headers?.cookie ?? '')  // server: read from request headers
    : document.cookie                       // client: read from document
  
  if (!getCookie('access_token', cookieStr)) {
    throw redirect('/')
  }
}
```

**Never use `+guard.client.ts` in SSR mode.** Server won't run it, so unauthenticated requests get through on first load.

---

## Data Fetching

### Query Key Factory

```tsx
export const queryKeys = {
  problems: {
    all: ['problems'] as const,
    list: (filters: Record<string, unknown>) => ['problems', filters] as const,
    detail: (id: string) => ['problem', id] as const,
  },
  decks: {
    all: ['decks'] as const,
    detail: (id: string) => ['deck', id] as const,
  },
  review: {
    all: ['review-queue'] as const,
  },
  me: ['me'] as const,
  dashboard: {
    stats: ['dashboard-stats'] as const,
  },
} as const
```

### Centralized Cache Invalidation

```tsx
// One function that knows the cascade
export function invalidateProblemsCache(qc: QueryClient) {
  return Promise.all([
    qc.invalidateQueries({ queryKey: queryKeys.problems.all }),
    qc.invalidateQueries({ queryKey: queryKeys.review.all }),
    qc.invalidateQueries({ queryKey: queryKeys.dashboard.stats }),
  ])
}

// Mutations use the helper
const mutation = useMutation({
  mutationFn: archiveProblems,
  onSuccess: () => invalidateProblemsCache(queryClient),
})
```

### Service Layer (Thin Functions, No Classes)

```tsx
// services/problems.ts
export async function listProblems(params?: {
  page?: number; difficulty?: Difficulty; is_archived?: boolean
}): Promise<PaginatedResponse<ProblemListItem>> {
  const { data } = await apiClient.get('/problems', { params })
  return data
}

export async function getProblem(id: string): Promise<Problem> {
  const { data } = await apiClient.get(`/problems/${id}`)
  return data
}
```

### Axios Interceptor for Token Refresh

```tsx
apiClient.interceptors.response.use(
  response => response,
  async error => {
    const original = error.config
    if (error.response?.status === 401 && !original._retry) {
      original._retry = true
      const refreshToken = getCookie('refresh_token')
      if (!refreshToken) return Promise.reject(error)

      const { data } = await axios.post('/api/auth/refresh', { refresh_token: refreshToken })
      setCookie('access_token', data.access_token, 30 * 60)
      original.headers.Authorization = `Bearer ${data.access_token}`
      return apiClient(original)
    }
    return Promise.reject(error)
  }
)
```

**The `_retry` flag prevents infinite retry loops** when the refresh token itself is expired.

---

## Testing

### Setup (Global Stubs)

```tsx
// tests/setup.ts
globalThis.ResizeObserver = class { observe() {} unobserve() {} disconnect() {} } as any
globalThis.IntersectionObserver = class { observe() {} unobserve() {} disconnect() {} } as any
Element.prototype.scrollIntoView = () => {}
```

### Mock Service Functions with vi.fn()

```tsx
// Always use vi.fn() wrappers (not hardcoded returns) so tests can override
const mockListProblems = vi.fn()
vi.mock('@/services/problems', () => ({
  listProblems: (...args: unknown[]) => mockListProblems(...args),
}))

// In test:
mockListProblems.mockResolvedValue({ items: [problem], total: 1 })
```

### QueryClient Wrapper

```tsx
function renderWithQuery(ui: React.ReactElement) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return render(<QueryClientProvider client={client}>{ui}</QueryClientProvider>)
}
```

### Testing Gotchas (From Production Experience)

**Module-scope constants defeat per-test mocking.** If a component evaluates `const X = someAPI` at import time, you can't change it per-test. Use `vi.hoisted()`:

```tsx
const captured = vi.hoisted(() => ({ value: null as string | null }))
vi.mock('@/lib/config', () => ({ getConfig: () => captured.value }))

test('with config A', () => { captured.value = 'A'; /* render */ })
test('with config B', () => { captured.value = 'B'; /* render */ })
```

**React Query v5 mutation context.** `mutationFn` receives `(variables, context)`. Use `mock.mock.calls[0][0]` instead of `toHaveBeenCalledWith`:

```tsx
expect(mockArchive.mock.calls[0][0]).toEqual(['id1', 'id2'])
```

**CodeMirror callbacks.** Editor is created in a mount-only `useEffect`. Capture callbacks via `vi.hoisted()`:

```tsx
const captured = vi.hoisted(() => ({
  keymaps: [] as Array<{ key: string; run: () => boolean }>,
}))

vi.mock('@codemirror/view', () => ({
  keymap: { of: (maps: typeof captured.keymaps) => { captured.keymaps = maps; return [] } },
}))

// Test: captured.keymaps.find(k => k.key === 'Ctrl-Enter')!.run()
```

**cmdk CommandPalette.** `Command.Item` doesn't fire `onSelect` on click. Mock the whole module:

```tsx
vi.mock('cmdk', () => ({
  Command: Object.assign(
    ({ children }: any) => <div>{children}</div>,
    { Item: ({ children, onSelect }: any) => <div role="option" onClick={() => onSelect?.()}>{children}</div> }
  ),
}))
```

**DnD Kit.** Capture `onDragEnd` and call directly:

```tsx
let capturedDragEnd: ((e: DragEndEvent) => void) | null = null
vi.mock('@dnd-kit/core', () => ({
  DndContext: ({ children, onDragEnd }: any) => { capturedDragEnd = onDragEnd; return children },
}))
// Test: capturedDragEnd!({ active: { id: 'p1' }, over: { id: 'p2' } })
```

**`mutateAsync` throws in tests.** Use `mutate` for error-heavy components, or suppress with `vi.spyOn(console, 'error')`.

**`null` vs `undefined`.** Types like `error?: string` accept `undefined` but reject `null` in strict mode. Match optionality exactly in mocks.

**Always run `tsc --noEmit` on test files.** Vitest ignores type errors at runtime.

---

## CodeMirror Integration

### Mount-Once Pattern

```tsx
useEffect(() => {
  const state = EditorState.create({
    doc: value,
    extensions: [
      basicSetup,
      langComp.current.of(getLangBundle(language)),
      keymap.of([
        { key: 'Ctrl-Enter', run: () => { onRunRef.current?.(); return true } },
      ]),
      EditorView.updateListener.of(update => {
        if (update.docChanged) onChangeRef.current?.(update.state.doc.toString())
      }),
    ],
  })

  const view = new EditorView({ state, parent: containerRef.current! })
  viewRef.current = view
  return () => view.destroy()
}, []) // Mount once -- props accessed via refs
```

### Compartments for Dynamic Config

```tsx
const themeComp = useRef(new Compartment())
const langComp = useRef(new Compartment())

// Swap theme without destroying editor
useEffect(() => {
  viewRef.current?.dispatch({
    effects: themeComp.current.reconfigure(getThemeExtension(isDark)),
  })
}, [isDark])
```

**Compartment refs must be per-instance.** Sharing across component instances breaks reconfiguration.

---

## Form Patterns

### Native Forms + useActionState + Zod (Default)

For most forms -- login, signup, CRUD -- native HTML + React 19 is enough:

```tsx
const Schema = z.object({ name: z.string().min(1), email: z.string().email() })

async function submit(prev: FormState, formData: FormData): Promise<FormState> {
  const result = Schema.safeParse(Object.fromEntries(formData))
  if (!result.success) return { errors: result.error.flatten().fieldErrors }
  await api.create(result.data)
  return { errors: null, success: true }
}
```

**When to use a form library:** Multi-step wizards, 20+ fields with cross-field deps, dynamic field arrays.

---

## Accessibility

```tsx
// Interactive elements: always use semantic HTML
<button onClick={handle}>Click</button>  // not <div onClick>

// If div is unavoidable:
<div role="button" tabIndex={0} onClick={handle}
  onKeyDown={e => (e.key === 'Enter' || e.key === ' ') && handle()}>Click</div>

// All clickable elements: cursor-pointer (never rely on browser default)
<button className="cursor-pointer">...</button>
<select className="cursor-pointer">...</select>

// useId for label/input pairing
const id = useId()
<label htmlFor={id}>Email</label>
<input id={id} />

// Images: always alt (empty string for decorative)
<img alt="User avatar" src={url} />
<img alt="" src={decorative} />  // screen readers skip decorative images
```

---

## Performance

### React Compiler Awareness

If React Compiler is enabled, manual `React.memo`, `useMemo`, `useCallback` are often unnecessary. Check before adding.

### Code Splitting

```tsx
const HeavyEditor = lazy(() => import('./components/CodeEditor'))

<Suspense fallback={<div className="h-64 animate-pulse" />}>
  <HeavyEditor />
</Suspense>
```

### Tree-Shakeable Imports

```tsx
// BAD: imports entire library
import _ from 'lodash'
// GOOD: import specific function
import debounce from 'lodash/debounce'
```

### Lift Constants to Module Scope

```tsx
// BAD: new array every render
function Component() {
  const options = ['a', 'b', 'c'] // recreated each render
  return <Select options={options} />
}

// GOOD: stable reference
const OPTIONS = ['a', 'b', 'c'] as const
function Component() {
  return <Select options={OPTIONS} />
}
```

---

## State Management

### Decision Tree

| Scenario | Solution |
|----------|----------|
| Server data (API responses) | TanStack Query |
| URL state (filters, search) | `useSearchParamState` or URL params |
| Form state | `useState` or `useActionState` |
| Local UI state (open/closed, selected) | `useState` |
| Complex local state (3+ related fields) | `useReducer` |
| Theme/preferences | Context + `useState` |
| Cross-component shared state | TanStack Query (if server) or Context (if client) |

**No Zustand, no Redux, no Jotai.** For most apps, React Query + local state covers everything. Add a state library only when Context re-renders become a measured problem.

---

## Next.js App Router

> Skip this section if not using Next.js.

### Server Components (Default)

```tsx
// app/dashboard/page.tsx -- no 'use client', runs on server
export default async function DashboardPage() {
  const stats = await db.query('SELECT count(*) FROM orders')
  return <div><h1>Dashboard</h1><StatsDisplay stats={stats} /><DashboardFilters /></div>
}
```

### Push `'use client'` to Leaf Components

```tsx
// BAD: entire page is client
'use client'
export default function Page() { ... }

// GOOD: only interactive parts are client
// page.tsx (server) renders <DashboardFilters /> (client leaf)
```

### Server Actions with Zod

```tsx
'use server'
export async function createPost(formData: FormData) {
  const parsed = PostSchema.safeParse({ title: formData.get('title'), content: formData.get('content') })
  if (!parsed.success) return { error: parsed.error.flatten().fieldErrors }
  await db.insert('posts', parsed.data)
  revalidatePath('/posts')
  return { success: true }
}
```

### Loading and Error UI

```tsx
// app/dashboard/loading.tsx -- automatic Suspense boundary
export default function Loading() {
  return <div className="animate-pulse"><div className="h-8 bg-muted rounded w-1/4 mb-4" /></div>
}

// app/dashboard/error.tsx -- automatic Error Boundary
'use client'
export default function Error({ error, reset }: { error: Error; reset: () => void }) {
  return <div role="alert"><p>{error.message}</p><button onClick={reset}>Retry</button></div>
}
```

---

## Quick Reference

| Mistake | Fix |
|---------|-----|
| `useFormStatus` in same component as `<form>` | Move to child component |
| Promise created inside `use()` consumer | Create in parent, pass as prop |
| Module scope `new QueryClient()` in SSR | `useState(() => new QueryClient())` |
| `navigate()` for auth error recovery | `window.location.href` (hard nav) |
| Lazy loading without Suspense boundary | Always wrap `lazy()` in `<Suspense>` |
| Compartment ref shared across instances | `useRef(new Compartment())` per component |
| `toHaveBeenCalledWith` on mutations | `mock.mock.calls[0][0]` (v5 context arg) |
| `fireEvent` for user interactions | `userEvent` (simulates real interactions) |
| `getByTestId` on interactive elements | `getByRole`, `getByLabelText` |
| Missing `cursor-pointer` on clickable elements | Add to all buttons, links, selects |
| Boolean toggle in URL state | `useSearchParamState` with `replaceState` |
| `console.log` left in production | Remove before merge |
