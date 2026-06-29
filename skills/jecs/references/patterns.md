---
name: patterns
description: |
  Use when looking for practical jecs patterns for component lifecycle,
  cleanup, resource management, and common integration recipes
---

# Jecs Patterns

Practical patterns for component lifecycle, resource cleanup, and common
recipes.

## Component Lifecycle: Add → Change → Remove

The core cycle. Use hooks or signals to react at each stage.

```ts
const Position = world.component<Vector3>();
const Health = world.component<number>();

// Signals — preferred for external observers
const unsub_added = world.added(Position, (entity, id, value) => {
  print(`Position added to ${entity}: ${value}`);
});

const unsub_changed = world.changed(Health, (entity, id, value) => {
  print(`Health changed on ${entity}: ${value}`);
});

const unsub_removed = world.removed(Position, (entity, id, deleted) => {
  if (deleted) return; // entity being deleted, skip
  print(`Position removed from ${entity}`);
});
```

---

## Instance Cleanup via OnRemove Hook

The pattern for attaching a Roblox Instance to a component and destroying it
when the component is removed. This is the most common cleanup use case.

```ts
import { Entity, Id, OnAdd, OnRemove } from "@rbxts/jecs";

const Model = world.component<Model>();
const Part = world.component<BasePart>();

// OnAdd: parent the instance to workspace when component is set
world.set(Model, OnAdd, (entity: Entity, id: Id<Model>, model: Model) => {
  model.Parent = game.Workspace;
});

// OnRemove: destroy the instance when component is removed
world.set(Model, OnRemove, (entity: Entity, id: Id<Model>, deleted?: true) => {
  // deleted === true means the entity itself is being deleted.
  // Either way we should destroy the model.
  const model = world.get(entity, Model);
  model?.Destroy();
});
```

**Why check `deleted`?** During entity deletion, all components are removed and
each OnRemove fires. If you need to do extra cleanup on the _entity_ (like
removing other components), bail out when `deleted` is true — the entity is
going away anyway:

```ts
const VisualPart = world.component<BasePart>();
const Highlight = world.component<Highlight>();

world.set(VisualPart, OnRemove, (entity, id, deleted) => {
  if (deleted) {
    // Entity being deleted — don't touch other components,
    // they'll be cleaned up too
    return;
  }

  // Normal removal — clean up related state
  const highlight = world.get(entity, Highlight);
  if (highlight) highlight.Destroy();
  world.remove(entity, Highlight);
});
```

---

## Combined Cleanup: Multiple Related Resources

When an entity has several dependent resources, clean them all up together.

```ts
const NPC = world.component<Model>();
const HealthBar = world.component<BillboardGui>();
const Hitbox = world.component<BasePart>();

world.set(NPC, OnRemove, (entity, id, deleted) => {
  if (deleted) return; // entity going away, all cleaned up

  // Destroy dependent resources
  const bar = world.get(entity, HealthBar);
  bar?.Destroy();
  world.remove(entity, HealthBar);

  const hitbox = world.get(entity, Hitbox);
  hitbox?.Destroy();
  world.remove(entity, Hitbox);
});
```

**Alternative — use signals** if you need multiple independent systems to
react to the same removal (hooks only allow one per component):

```ts
const NPC = world.component<Model>();

// System 1: clean up visual
world.removed(NPC, (entity, id, deleted) => {
  if (deleted) return;
  const model = world.get(entity, Model);
  model?.Destroy();
});

// System 2: clean up AI state
world.removed(NPC, (entity, id, deleted) => {
  if (deleted) return;
  removeFromAIPathfinding(entity);
});
```

---

## Entity Deletion Patterns

### Delete entity (triggers all OnRemove hooks)

```ts
// All OnRemove hooks fire with deleted=true
world.delete(entity);
```

### Remove single component (triggers that component's OnRemove)

```ts
// OnRemove fires with deleted=undefined
world.remove(entity, Position);
```

### Clear all components (keeps entity alive)

```ts
// All OnRemove hooks fire with deleted=true (same as delete)
world.clear(entity);
```

---

## Cascade Deletion with Relationships

Use `OnDeleteTarget` + `Delete` to auto-delete children when parent is removed.

```ts
import { ChildOf, Delete, OnDeleteTarget, pair } from "@rbxts/jecs";

// ChildOf already has (OnDeleteTarget, Delete) built in
const parent = world.entity();
const child1 = world.entity();
const child2 = world.entity();

world.add(child1, pair(ChildOf, parent));
world.add(child2, pair(ChildOf, parent));

// Deleting parent cascades to children — their OnRemove hooks fire first
world.delete(parent);
// child1 and child2 are also deleted
```

### Custom cascade relationship

```ts
const InScene = world.component();
world.add(InScene, pair(OnDeleteTarget, Delete));

const scene = world.entity();
const prop1 = world.entity();
world.add(prop1, pair(InScene, scene));

// Deleting scene deletes all props in it
world.delete(scene);
```

### Safe relationship cleanup (remove ref, keep entity)

```ts
const EquippedBy = world.component();
world.add(EquippedBy, pair(OnDeleteTarget, Remove));

const sword = world.entity();
const player = world.entity();
world.add(sword, pair(EquippedBy, player));

// Deleting player removes the relationship, sword survives
world.delete(player);
```

---

## Querying Then Cleaning Up

Batch cleanup of entities matching a query.

```ts
const Dead = world.tag();
const Model = world.component<Model>();

// Mark entities as dead
function DAMAGE_SYSTEM() {
  for (const [entity, health] of world.query(Health)) {
    if (health <= 0) {
      world.add(entity, Dead);
    }
  }
}

// Clean up dead entities
function CLEANUP_SYSTEM() {
  for (const [entity] of world.query(Model).with(Dead)) {
    const model = world.get(entity, Model);
    model?.Destroy();
    world.delete(entity);
  }
}
```

---

## Singleton Cleanup

Singletons use the component ID as the entity key.

```ts
const GameState = world.component<{ running: boolean }>();

// Set singleton
world.set(GameState, GameState, { running: true });

// Remove singleton data
world.remove(GameState, GameState);
```

---

## Signal-Based Change Tracking with Cleanup

Combine `world.changed` and `world.removed` for external tracking systems.

```ts
interface ChangeRecord<T> {
  added: Map<Entity, T>;
  changed: Map<Entity, T>;
  removed: Set<Entity>;
}

function trackComponent<T>(component: Entity<T>): ChangeRecord<T> {
  const record: ChangeRecord<T> = {
    added: new Map(),
    changed: new Map(),
    removed: new Set(),
  };

  world.added(component, (entity, _, value) => {
    record.added.set(entity, value);
  });

  world.changed(component, (entity, _, value) => {
    record.changed.set(entity, value);
  });

  world.removed(component, (entity, _, deleted) => {
    record.removed.add(entity);
  });

  return record;
}

// Usage
const positionChanges = trackComponent(Position);

// After frame, process and clear
function flushChanges(): void {
  for (const [entity, value] of positionChanges.added) {
    // Handle added
  }

  for (const [entity] of positionChanges.removed) {
    // Handle removed — clean up related resources
  }

  positionChanges.added.clear();
  positionChanges.changed.clear();
  positionChanges.removed.clear();
}
```

---

## Wiring Hooks to Sync State

Sync one component's value to another (e.g. Position → CFrame on a Part).

```ts
const Position = world.component<Vector3>();
const Model = world.component<Model>();

world.set(Position, OnChange, (entity, id, position) => {
  const model = world.get(entity, Model);
  if (model) {
    model.PrimaryPart!.CFrame = new CFrame(position);
  }
});

world.set(Position, OnAdd, (entity, id, position) => {
  const model = world.get(entity, Model);
  if (model) {
    model.PrimaryPart!.CFrame = new CFrame(position);
  }
});
```

---

## Tags for State Machines

Use tags (no data) to represent states, with hooks for transitions.

```ts
const Alive = world.tag();
const Dead = world.tag();
const Health = world.component<number>();

// When Dead tag is removed (entity revived), clean up
world.set(Dead, OnRemove, (entity, id, deleted) => {
  if (deleted) return;
  // Entity revived — could reset health here
  world.set(entity, Health, 100);
});
```

---

## Archetype Cleanup

Call `world.cleanup()` periodically to free memory from empty archetypes,
especially after mass deletions or heavy relationship usage.

```ts
// Every ~15 seconds, or when archetype count is high
world.cleanup();
```

---

## Anti-Patterns

### ❌ Structural changes in OnRemove during entity deletion

```ts
world.set(Health, OnRemove, (entity, id, deleted) => {
  if (deleted) {
    // BAD: entity is being torn down, this is pointless/dangerous
    world.remove(entity, Dead);
    return;
  }
  // GOOD: normal removal, safe to make changes
  world.remove(entity, Dead);
});
```

**Fix:** Always check `deleted` flag in OnRemove.

### ❌ Using OnChange for external observation

```ts
// BAD: only one handler, blocks signals
world.set(Position, OnChange, (entity, id, value) => {
  updateUI(entity, value);
});

// GOOD: use signals for external observers
world.changed(Position, (entity, id, value) => {
  updateUI(entity, value);
});
```

**Fix:** Use hooks for constructor/destructor behavior. Use signals for
external observation.

### ❌ Not cleaning up Instances

```ts
// BAD: Instance leaks when component is removed
const Part = world.component<BasePart>();
world.set(entity, Part, new Instance("Part"));

// GOOD: always pair Instance components with OnRemove
world.set(Part, OnRemove, (entity, id, deleted) => {
  const part = world.get(entity, Part);
  part?.Destroy();
});
```

### ❌ Forgetting cleanup traits on relationships

```ts
// BAD: deleting target leaves dangling references
const Owns = world.component();
// No cleanup trait set

// GOOD: specify cleanup behavior
world.add(Owns, pair(OnDeleteTarget, Remove));
```

---

Source references:

- how_to/100_cleanup_traits.luau
- how_to/110_hooks.luau
- how_to/111_signals.luau
- how_to/041_entity_relationships.luau
- src/jecs.luau
