---
name: jecs
description:
  Use when building ECS-based games in Roblox with roblox-ts using jecs for
  entities, components, queries, relationships, hooks, cleanup traits,
  signals, and component lifecycle management
metadata:
  author: Christopher Buss
  version: "2026.1.29"
  source: Generated from https://github.com/Ukendio/jecs, scripts at
    https://github.com/christopher-buss/skills
---

> Based on jecs v0.9.0, generated 2026-01-29

High-performance Entity Component System for Luau/roblox-ts. Features entity
relationships, archetype storage, 800k entities at 60fps.

## Quick Start

```ts
import Jecs, { pair, ChildOf } from "@rbxts/jecs";

const world = Jecs.world();

// Components (typed, IDs 1–256)
const Position = world.component<Vector3>();
const Health = world.component<number>();

// Tags (no data, zero storage)
const Dead = Jecs.tag();

// Create entity and attach data
const entity = world.entity();
world.set(entity, Position, Vector3.zero);
world.set(entity, Health, 100);

// Query entities
for (const [e, pos, hp] of world.query(Position, Health)) {
  // e: Entity, pos: Vector3, hp: number
}

// Remove component
world.remove(entity, Position);

// Delete entity (triggers all OnRemove hooks, cascades relationships)
world.delete(entity);
```

## Component Lifecycle

### Hooks (constructors/destructors — one per component)

| Hook       | When                                | Signature                        |
| ---------- | ----------------------------------- | -------------------------------- |
| `OnAdd`    | Component added with value          | `(entity, id, value) => void`    |
| `OnChange` | Value updated (not initial)         | `(entity, id, value) => void`    |
| `OnRemove` | Component removed OR entity deleted | `(entity, id, deleted?) => void` |

```ts
import { OnAdd, OnRemove } from "@rbxts/jecs";

const Model = world.component<Model>();

// Clean up Instance when component removed
world.set(Model, OnRemove, (entity, id, deleted) => {
  if (deleted) return; // entity going away, skip
  world.get(entity, Model)?.Destroy();
});
```

### Signals (external observers — multiple listeners, disconnectable)

| Signal    | When              | Signature                        |
| --------- | ----------------- | -------------------------------- |
| `added`   | Component added   | `(entity, id, value) => void`    |
| `changed` | Value changed     | `(entity, id, value) => void`    |
| `removed` | Component removed | `(entity, id, deleted?) => void` |

```ts
const unsub = world.changed(Health, (entity, id, value) => {
  updateHealthBar(entity, value);
});
// later: unsub();
```

**Use hooks** for resource cleanup (destroy Instances, release memory).
**Use signals** when multiple systems need to observe the same event.

## Cleanup Traits

Control what happens when components or relationship targets are deleted.

| Pair                       | Effect                                        |
| -------------------------- | --------------------------------------------- |
| `(OnDelete, Remove)`       | Remove component from all entities (default)  |
| `(OnDelete, Delete)`       | Delete all entities with that component       |
| `(OnDeleteTarget, Remove)` | Remove relationship when target deleted       |
| `(OnDeleteTarget, Delete)` | Delete entities when target deleted (cascade) |

```ts
import { Delete, OnDeleteTarget, Remove, pair } from "@rbxts/jecs";

// Cascade: deleting parent deletes children (ChildOf has this built-in)
const parent = world.entity();
const child = world.entity();
world.add(child, pair(ChildOf, parent));
world.delete(parent); // child also deleted

// Safe: deleting owner removes reference, keeps entity
const OwnedBy = world.component();
world.add(OwnedBy, pair(OnDeleteTarget, Remove));
```

## Relationships

```ts
const Eats = world.component<{ amount: number }>();
const Apples = world.entity();

world.add(entity, pair(Eats, Apples));
world.set(entity, pair(Eats, Apples), { amount: 5 });

// Query with wildcard
for (const [e, data] of world.query(pair(Eats, Jecs.Wildcard))) {
  const food = world.target(e, Eats);
}

// Iterate all targets
let nth = 0;
let target = world.target(entity, Eats, nth);
while (target) {
  nth++;
  target = world.target(entity, Eats, nth);
}
```

## Core References

| Topic            | Description                                            | Reference                                  |
| ---------------- | ------------------------------------------------------ | ------------------------------------------ |
| World & Entities | World creation, entities, components, tags, singletons | [core-basics](references/core-basics.md)   |
| Queries          | Query system, filters (with/without), caching          | [core-queries](references/core-queries.md) |

## Features

| Topic                 | Description                                            | Reference                                                      |
| --------------------- | ------------------------------------------------------ | -------------------------------------------------------------- |
| Pairs & Relationships | Entity pairs, ChildOf, wildcards, relationship queries | [feature-pairs](references/feature-pairs.md)                   |
| Component Hooks       | OnAdd, OnChange, OnRemove lifecycle hooks              | [feature-hooks](references/feature-hooks.md)                   |
| Signals               | Multiple listeners with added/changed/removed signals  | [feature-signals](references/feature-signals.md)               |
| Cleanup Traits        | OnDelete, OnDeleteTarget, cascade deletion policies    | [feature-cleanup-traits](references/feature-cleanup-traits.md) |

## Best Practices

| Topic           | Description                                       | Reference                                                                      |
| --------------- | ------------------------------------------------- | ------------------------------------------------------------------------------ |
| Archetypes      | Archetype storage, transitions, fragmentation     | [best-practices-archetypes](references/best-practices-archetypes.md)           |
| Change Tracking | Delta detection, dirty flags, networking patterns | [best-practices-change-tracking](references/best-practices-change-tracking.md) |
| Patterns        | Component lifecycle, cleanup, resource management | [patterns](references/patterns.md)                                             |

## Advanced

| Topic        | Description                                 | Reference                                  |
| ------------ | ------------------------------------------- | ------------------------------------------ |
| Advanced API | Preregistration, bulk ops, TypeScript types | [advanced-api](references/advanced-api.md) |
