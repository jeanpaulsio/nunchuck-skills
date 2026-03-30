---
name: ux-patterns
description: Hard-won UI/UX patterns from production -- scroll architecture, touch targets, mobile layout, modals, loading states. Focus on things that break silently.
---

# UX Patterns

Patterns learned from 30+ mobile fix commits, 7 scroll architecture iterations, and a ScaleToFit component that got thrown away. These are the things that break silently and waste hours debugging.

## Scroll Architecture

### The Root Problem

Multiple scroll containers on a page fight each other. The user scrolls and nothing happens, or the wrong thing scrolls, or the page feels "trapped." This is the #1 layout bug on mobile.

### The Solution: One Scroll Container Per Route

```
WRONG: Nested scroll containers
┌─────────────────────────┐
│ [Header - scrolls]      │
│ ┌─────────────────────┐ │
│ │ [Sidebar - scrolls] │ │
│ │ ┌─────────────────┐ │ │
│ │ │ [Content scrolls]│ │ │  ← Three scroll containers
│ │ └─────────────────┘ │ │
│ └─────────────────────┘ │
└─────────────────────────┘

RIGHT: Fixed shell, one scroll region
┌─────────────────────────┐
│ [Header - fixed]        │
│ ┌────┬────────────────┐ │
│ │    │                │ │
│ │ S  │  Content       │ │
│ │ i  │  (only this    │ │  ← One scroll container
│ │ d  │   scrolls)     │ │
│ │ e  │                │ │
│ └────┴────────────────┘ │
└─────────────────────────┘
```

### Mobile vs Desktop: Different Strategies

Mobile needs natural document flow. Desktop needs fixed viewport with scrollable panels. Trying to use one strategy for both causes pain.

```tsx
// The divergent layout pattern
<div className="flex min-h-screen flex-col md:h-screen md:flex-row md:overflow-hidden">
  {/* Mobile: sticky header, document scroll */}
  <div className="sticky top-0 z-20 ... md:hidden">Header</div>

  {/* Desktop: fixed sidebar */}
  <div className="hidden md:block md:w-[220px] md:shrink-0">Sidebar</div>

  {/* Content: document flow on mobile, overflow scroll on desktop */}
  <main className="flex-1 md:overflow-y-auto [scrollbar-gutter:stable]">
    {children}
  </main>
</div>
```

**Why the split:** Nested scroll on mobile makes pages feel trapped (you scroll but nothing moves because you're inside a contained div). Mobile users expect the whole page to scroll like a native app. Desktop users expect a fixed sidebar with scrollable content.

### The min-h-0 Rule

This is the #1 scroll bug in flex layouts. Flex items default to `min-height: auto` (their content height). Without `min-h-0`, a flex child can never be smaller than its content, so `overflow-y-auto` does nothing.

```tsx
// BROKEN: Content overflows the viewport, no scroll
<div className="flex flex-1 flex-col">
  <main className="flex-1 overflow-y-auto">Long content</main>
</div>

// FIXED: min-h-0 allows the flex child to shrink below content height
<div className="flex min-h-0 flex-1 flex-col">
  <main className="min-h-0 flex-1 overflow-y-auto">Long content</main>
</div>
```

Every scrollable flex container in your app needs `min-h-0` on the flex parent or the scrolling child.

### Scrollbar Gutter

```tsx
<main className="overflow-y-auto [scrollbar-gutter:stable]">
```

Without `scrollbar-gutter:stable`, content shifts left when scrollbar appears (e.g., navigating from a short page to a long page). The gutter reserves space for the scrollbar even when it's not visible.

### Use dvh, Not vh

```tsx
// BAD: vh doesn't account for mobile address bar
<div className="h-screen">...</div>

// GOOD: dvh adjusts for mobile browser chrome
<div className="h-dvh">...</div>
```

On mobile Safari, `100vh` includes the area behind the address bar. When the address bar is visible, content overflows. `100dvh` (dynamic viewport height) adjusts automatically.

## Modal Scroll

### Don't Put overflow-y-auto on the Modal Container

```tsx
// WRONG: Scrollbar clips rounded corners, header scrolls away
<div className="max-h-[90vh] overflow-y-auto rounded-lg">
  <div>Header</div>
  <div>Long body content</div>
</div>

// RIGHT: Fixed header, scrollable body
<div className="flex max-h-[90dvh] flex-col overflow-hidden rounded-lg">
  <div className="shrink-0 border-b">Header (always visible)</div>
  <div className="overflow-y-auto">Long body content</div>
</div>
```

Use `max-h-[90dvh]` (not `vh`) for modals to account for mobile browser chrome.

## Touch Targets

### Minimum 36x36px (44x44px Preferred)

```tsx
// Symbol bar buttons: 36x36px minimum
<button className="flex h-9 min-w-[36px] items-center justify-center rounded cursor-pointer">
  {symbol}
</button>

// Icon buttons: explicit size
<button className="flex h-10 w-10 items-center justify-center cursor-pointer">
  <Icon size={16} />
</button>
```

Apple's HIG recommends 44x44pt. Material Design recommends 48x48dp. 36px is the absolute minimum for any tappable element.

### cursor-pointer on Everything Interactive

```tsx
<button className="cursor-pointer ...">Click</button>
<a className="cursor-pointer ...">Link</a>
<select className="cursor-pointer ...">Dropdown</select>
<div onClick={handle} className="cursor-pointer ...">Card</div>
```

Never rely on the browser's default cursor. Explicitly set `cursor-pointer` on every interactive element. This includes `<button>`, `<a>`, `<select>`, clickable `<div>`s, and icon buttons.

### Tap vs Scroll Detection on Mobile

Mobile keyboards and symbol bars need to distinguish taps from scroll gestures:

```tsx
const TAP_THRESHOLD = 8 // pixels

onPointerDown: record start position
onPointerUp: if distance < TAP_THRESHOLD, it's a tap; otherwise it's a scroll/drag
```

Don't use `onClick` for elements inside scrollable containers on mobile. The browser fires `onClick` even after a drag, which inserts symbols/characters when the user was just scrolling.

## Mobile Layout

### Mobile-First, Then Enhance

Build for the smallest screen first. Add complexity at wider breakpoints.

```tsx
// Default styles: mobile
// md: (768px): tablet/desktop
// lg: (1024px): wide desktop

<div className="px-4 md:px-6 lg:px-8">
  <div className="flex flex-col gap-4 md:flex-row md:gap-6">
    Content
  </div>
</div>
```

### Header Wrapping

```tsx
// Headers with action buttons: allow wrapping, prevent squishing
<div className="flex min-h-10 flex-wrap items-center justify-between gap-3">
  <h1 className="text-lg font-semibold">Page Title</h1>
  <a className="shrink-0 whitespace-nowrap">+ New Item</a>
</div>
```

- `flex-wrap`: title wraps below on narrow screens
- `shrink-0 whitespace-nowrap`: buttons never truncate or wrap internally
- `gap-3`: consistent spacing when wrapped

### Mobile Description Ceilings

When a page has a description + editor/content below, cap the description height on mobile:

```tsx
{isMobile ? (
  <div className="h-[30vh] shrink-0 overflow-auto border-b">
    <Description />
  </div>
) : (
  <ResizablePanel defaultSize={35} minSize={10}>
    <Description />
  </ResizablePanel>
)}
```

Without a height ceiling, long descriptions push the editor below the fold on mobile.

## Loading & Empty States

### Loading: Respect Reduced Motion

```tsx
<div role="status" className="flex items-center justify-center gap-2 py-12 text-muted-foreground">
  <Spinner size={20} />
  <span className="text-sm">Loading...</span>
</div>
```

Always include `role="status"` for screen readers. If using CSS animations, respect `prefers-reduced-motion`.

### Empty: Action-Oriented

```tsx
{items.length === 0 && (
  <div className="rounded-lg border p-12 text-center">
    <p className="text-sm font-medium">No problems yet</p>
    <p className="mt-1 text-xs text-muted-foreground">
      Add your first problem to start building your library
    </p>
    <a href="/new" className="mt-4 inline-flex items-center rounded-md bg-primary px-4 py-2 text-xs text-primary-foreground cursor-pointer">
      + Add Problem
    </a>
  </div>
)}
```

Empty states should tell the user what to do next, not just that something is empty.

## Form Inputs

### Enter-to-Submit Needs a Visual Hint

```tsx
<input placeholder="New section name" onKeyDown={e => e.key === 'Enter' && handleSubmit()} />
<span className="text-[10px] text-muted-foreground">Enter to save, Esc to cancel</span>
```

Users don't know an input is Enter-to-submit without a hint. Always show one.

## SVG: Use viewBox, Not JavaScript Measurement

```tsx
// WRONG: JavaScript measurement for scaling (7+ fix commits, then thrown away)
function ScaleToFit({ children }) {
  const [scale, setScale] = useState(1)
  useEffect(() => { /* measure DOM, calculate scale */ }, [])
  return <div style={{ transform: `scale(${scale})` }}>{children}</div>
}

// RIGHT: SVG viewBox scales natively
<svg viewBox={`0 0 ${width} ${height}`} className="block w-full" style={{ maxWidth: width }}>
  {content}
</svg>
```

SVG's `viewBox` handles responsive scaling with zero JavaScript. No flash of unscaled content, no layout jank, automatic mobile scaling. This replaced a component that took 7 fix commits and a revert to get right, then was deleted entirely.

## Z-Index Stack

Define a consistent z-index stack and stick to it:

```
z-0:  Content (default)
z-10: Sticky elements within content
z-20: Mobile sticky header
z-30: Fixed navigation (mobile nav overlay)
z-40: Floating action buttons
z-50: Modals, dialogs, overlays
```

Don't invent z-index values ad hoc. Pick a scale and document it.
