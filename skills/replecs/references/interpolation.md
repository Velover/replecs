# Interpolation Buffer

## Overview

The interpolation module (`Replecs.create_interpolation`) provides a jitter-compensating snapshot buffer for lerping replicated component values on the client. It's a standalone utility — not coupled to the replication pipeline — designed to be fed via hooks/overrides.

**Key design points:**

- Pre-allocated ring buffers per entity/component
- Jitter tracking with fast-attack / slow-decay
- Pull-based: call `get()` each frame to retrieve the interpolated value
- No state machines, no correction/prediction — just interpolation

## Creating an Interpolator

```ts
import Replecs from "@rbxts/replecs-extended";

// With defaults
const interp = Replecs.create_interpolation();

// With config
const interp = Replecs.create_interpolation({
  max_snapshots: 8, // ring buffer size per entity/component (default: 8)
  base_delay: 0.1, // minimum render delay in seconds (default: 0)
  jitter_smoothing: 0.1, // decay rate for jitter buffer (default: 0.1)
});
```

### Config

| Field              | Default | Description                                                                                                   |
| ------------------ | ------- | ------------------------------------------------------------------------------------------------------------- |
| `max_snapshots`    | `8`     | Ring buffer capacity per entity/component. Higher = more memory but more history to interpolate.              |
| `base_delay`       | `0`     | Minimum render delay in seconds. Set to roughly the replication interval (e.g. `0.05` for 20Hz).              |
| `jitter_smoothing` | `0.1`   | How fast jitter shrinks when packets arrive on time. Higher = faster recovery. Attack (growth) is ~5× faster. |

---

## API

### `interp.register<T>(component, lerpFn)`

Register a lerp function for a component type. If not registered, `get()` returns the newest raw value without interpolation.

```ts
interp.register(Position, (a: CFrame, b: CFrame, t: number) => {
  return a.Lerp(b, t);
});

interp.register(Health, (a: number, b: number, t: number) => {
  return a + (b - a) * t;
});
```

### `interp.push<T>(entity, component, value, time)`

Push a new snapshot for an entity/component. Call this from a hook or override callback.

- `time` should be a monotonic timestamp (e.g. `os.clock()`)
- Updates jitter tracking internally

```ts
// Via hook (value is also written to the world automatically)
client.hook("changed", Position, (entity, id, value, added) => {
  interp.push(entity, Position, value, os.clock());
});

// Via override (you handle writing the value)
client.override("changed", Position, (entity, id, value, added) => {
  interp.push(entity, Position, value, os.clock());
  world.set(entity, Position, value); // write manually
});
```

### `interp.get<T>(entity, component, now?): T | undefined`

Get the interpolated value for an entity/component. Returns `nil` if no snapshots exist.

- `now` (optional): the current time in the same domain as push timestamps. If omitted, defaults to `os.clock()`.
- Internally computes `render_time = now - (base_delay + jitter)`, finds two bracketing snapshots, and lerps between them. If `render_time` is past the newest snapshot, returns the newest value directly.

```ts
// Default: uses os.clock() automatically
function INTERPOLATION_SYSTEM() {
  for (const [entity, pos] of world.query(Position)) {
    const interpolated = interp.get(entity, Position);
    if (interpolated !== undefined) {
      // Apply to visual representation
      part.CFrame = interpolated;
    }
  }
}

// Custom time: useful for fixed-timestep simulations or testing
const simTime = os.clock() - startTime;
const interpolated = interp.get(entity, Position, simTime);
```

### `interp.remove_entity(entity)`

Remove all buffered state for an entity. Call when an entity is deleted or leaves the client's scope.

```ts
client.hook("deleted", entity, (entity) => {
  interp.remove_entity(entity);
});
```

### `interp.remove_component(entity, component)`

Remove buffered state for a specific component on an entity. Also cleans up the entity entry if no components remain.

```ts
// Bare component covers all channels
client.hook("removed", Position, (entity, id) => {
  interp.remove_component(entity, Position);
});
```

### `interp.get_delay(): number`

Returns `base_delay + jitter`. Useful for debugging or displaying network conditions.

```ts
print("Current render delay:", interp.get_delay(), "seconds");
```

---

## How Jitter Compensation Works

The interpolator tracks the time between consecutive `push()` calls and maintains an adaptive jitter estimate:

1. **Fast attack**: When a packet arrives late (gap > average), jitter grows at ~0.5× the deviation. This quickly increases the render delay to absorb spikes.
2. **Slow decay**: When packets arrive on time, jitter shrinks at `jitter_smoothing`× the deviation (default 0.1). This prevents oscillation.
3. **Pushes within 1ms** of each other are ignored for jitter tracking (same packet, multiple components).

The effective render delay (`base_delay + jitter`) shifts `render_time` into the past, ensuring there are always (at least) two snapshots to interpolate between — even under variable network conditions.

---

## Common Patterns

### Standard Interpolation Setup

```ts
const interp = Replecs.create_interpolation({
  base_delay: 1 / 20, // match server reliable rate
  jitter_smoothing: 0.1,
});

// Register lerp functions
interp.register(Position, (a, b, t) => a.Lerp(b, t));
interp.register(Rotation, (a, b, t) => a.Slerp(b, t));

// Feed from hooks
client.hook(
  "changed",
  pair(Replecs.Reliable, Position),
  (entity, id, value) => {
    interp.push(entity, Position, value, os.clock());
  },
);

// Clean up
client.hook("deleted", entity, (entity) => {
  interp.remove_entity(entity);
});

// Render each frame
function INTERPOLATION_SYSTEM() {
  for (const [entity] of world.query(Position)) {
    const pos = interp.get(entity, Position);
    if (pos) {
      const part = world.get(entity, VisualPart) as BasePart;
      part.CFrame = pos;
    }
  }
}
```

### Unreliable Components (e.g. cosmetic)

For unreliable components, use an override so you control when the world is written:

```ts
interp.register(CosmeticPos, (a, b, t) => a.Lerp(b, t));

client.override(
  "changed",
  pair(Replecs.Unreliable, CosmeticPos),
  (entity, id, value) => {
    interp.push(entity, CosmeticPos, value, os.clock());
    world.set(entity, CosmeticPos, value);
  },
);
```

### Ownership and Interpolation

When a component is client-owned, the replication layer automatically skips overwriting the world value on stale roundtrips. Hooks don't fire for owned components, so you can feed interpolation from hooks without guarding:

```ts
// No ownership check needed — hook won't fire for the owner
client.hook(
  "changed",
  pair(Replecs.Unreliable, Position),
  (entity, id, value) => {
    interp.push(entity, Position, value, os.clock());
  },
);

// In the render system, the owner uses the raw predicted value,
// non-owners use interpolated
function INTERPOLATION_SYSTEM() {
  for (const [entity, rawPos] of world.query(Position)) {
    const pos = client.has_ownership(entity, Position)
      ? rawPos // owner: direct predicted value
      : (interp.get(entity, Position) ?? rawPos); // others: interpolated

    const part = world.get(entity, VisualPart) as BasePart;
    part.CFrame = pos;
  }
}
```

If you need to accept server values even when owned (e.g. server-authoritative correction), use an override instead:

```ts
client.override(
  "changed",
  pair(Replecs.Unreliable, Position),
  (entity, id, value) => {
    interp.push(entity, Position, value, os.clock());
    world.set(entity, Position, value); // write manually
  },
);
```

---

## Anti-Patterns

### ❌ Pushing without registering a lerp function

```ts
interp.push(entity, Position, value, os.clock());
interp.get(entity, Position); // returns newest raw value, no interpolation
// Fix: call interp.register(Position, lerpFn) first
```

### ❌ Not cleaning up deleted entities

```ts
// Entity gets deleted, but interp still holds stale buffers
// Fix: hook deletion
client.hook("deleted", entity, (entity) => {
  interp.remove_entity(entity);
});
```

### ❌ Using wall-clock time instead of monotonic

```ts
interp.push(entity, Position, value, tick()); // tick() can jump backwards
// Fix: use os.clock() — monotonic, high resolution
interp.push(entity, Position, value, os.clock());
```
