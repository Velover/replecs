# Ownership System

## Overview

The ownership system allows the server to grant clients authority over specific components. When a client owns a component, it can send value updates back to the server, which are applied to the world and broadcast to other clients.

This is ideal for:

- Player-controlled movement (client-side prediction)
- High-frequency position updates (unreliable ownership)
- Any case where the client is the authoritative source for a value

## How It Works

```
Server                          Client
  │                               │
  │  1. Grant ownership           │
  │  world:set(entity,            │
  │    jecs.pair(Owned, Pos),     │
  │    player)                    │
  │                               │
  │  2a. get_full() includes      │
  │      grants (join path)       │
  │──── buf, vars, grant? ───────→│
  │                               │  3a. apply_full + apply_grant
  │                               │
  │  2b. collect_ownership_grant()│
  │      (ongoing, bitmask-filtered)
  │──── buf, variants ──────────→ │
  │                               │  3b. apply_ownership_grant()
  │                               │
  │                               │  4. Check & request
  │                               │  if client:has_ownership(e, Pos)
  │                               │    client:request_set(e, Pos, v)
  │                               │    → sets world immediately
  │                               │    → buffers for replication
  │                               │
  │                               │  5. Collect updates
  │  ←── buf, variants ──────────│  for buf, variants in
  │                               │    client:collect_ownership()
  │  6. Apply ownership update    │
  │  server:apply_ownership(      │
  │    buf, player, variants)     │
  │                               │
  │  7. Value replicated to       │
  │     other clients via         │
  │     normal collect_updates()  │
```

## Granting Ownership

### Via ECS (recommended)

```ts
import { pair } from "@rbxts/jecs";

// Grant ownership of Position component to player
world.set(entity, pair(Replecs.Owned, Position), player);

// Revoke ownership
world.remove(entity, pair(Replecs.Owned, Position));
```

When you set an `(Owned, component)` pair, the server:

1. Records the ownership entry
2. Marks the player as dirty in `ownership_dirty`
3. The dirty mark causes `collect_ownership_grant()` to yield a packet for that player

Ownership grants are also included in `get_full()` for the joining player. Both `get_full()` and `collect_ownership_grant()` respect bitmask visibility — only entities the player can see (based on the masking system) are included in grants.

### With Player Filtering

The `Owned` component supports member filters like other components:

```ts
import { pair } from "@rbxts/jecs";

// Only grant to specific players (unusual but supported)
world.set(entity, pair(Replecs.Owned, Position), new Map([[player1, true]]));
```

## Mutual Exclusion

**The server cannot modify a component that is owned by a client.** All server write paths (`allocate_component_change`, `allocate_tag_addition`, etc.) check ownership via `check_ownership_mutual_exclusion()`:

```ts
import { pair } from "@rbxts/jecs";

// This will log a warning and return early:
world.set(entity, Position, newValue); // BLOCKED if Position is client-owned

// To modify owned components, remove ownership first:
world.remove(entity, pair(Replecs.Owned, Position));
world.set(entity, Position, newValue); // OK now
world.set(entity, pair(Replecs.Owned, Position), player); // re-grant
```

## Ownership Validation

The `validator` component validates client ownership updates server-side. It is **separate from serdes** — you can use it with or without custom serialization:

```ts
// Validator only — no serdes needed, uses default variant wire encoding
world.set(Health, Replecs.Validator, (value: number) => value >= 0 && value <= 100);

// Validator + serdes — custom serialization with separate validation
world.set(Position, Replecs.Serdes, {
	bytespan: 12,
	serialize: /* ... */,
	deserialize: /* ... */,
});
world.set(Position, Replecs.Validator, (value: Vector3) => value.Magnitude < 10000);

// Shorthand (server-only)
server.set_validator(Health, (v) => v >= 0 && v <= 100);
```

Validation is applied **after** deserialization (if serdes is present) or on the raw variant value (if no serdes). If validation fails, the update is silently dropped.

Validators are **server-only** — they do not need to be set on the client and are not included in the handshake.

## Reliable vs Unreliable

Reliability is determined by **how the component is registered on the server** (via `set_reliable` or `set_unreliable`), not by the client at send time. The client always sends ownership updates through a single channel, and the server routes based on the component's track type:

|                  | Reliable                                          | Unreliable                                        |
| ---------------- | ------------------------------------------------- | ------------------------------------------------- |
| Registration     | `server.set_reliable(entity, component)`          | `server.set_unreliable(entity, component)`        |
| Server routing   | Value stored in server storage via delta tracking | Value set directly in world; unreliable broadcast |
| Server broadcast | Via `collect_updates()` (reliable deltas)         | Via `collect_unreliable()` (per-tick snapshots)   |
| Use case         | Infrequent but important updates                  | High-frequency updates (e.g. position)            |
| Delivery         | Guaranteed, ordered                               | Best-effort, may be dropped                       |

**Unreliable ownership** sets the value directly in the world (via `world:set`) and marks it for unreliable broadcast. Other clients see it through `collect_unreliable()` snapshots.

## Player Leave Cleanup

When a player leaves, `server:remove_client(player)` is called automatically (via `PlayerRemoving`). This:

1. Calls `masking:unregister_client(player)` — removes from all bitmask filters
2. Iterates all `server.ownership` entries and removes any where `entry.player == player`
3. Cleans up empty entity ownership tables
4. Removes the player from `ownership_dirty`

This is **eager** cleanup (unlike masking which uses lazy cleanup) because stale ownership entries would **block the server from modifying those components** via `check_ownership_mutual_exclusion`.

## Client-Side Ownership Guard

When the server replicates a value back to the owning client (the roundtrip from `request_set` → server → broadcast), the client automatically **skips** overwriting the local value. This is handled in `entity_set` and `entity_add` at the replication layer.

The guard has three conditions — all must be true to skip:

1. **Client owns the component** (`ownership_grants[entity][component] == true`)
2. **Component already exists in the world** (not an initial sync)
3. **No override is registered** for this component

| Scenario                                   | World Write | Hook Callbacks | Override Callbacks |
| ------------------------------------------ | ----------- | -------------- | ------------------ |
| Initial sync (component doesn't exist yet) | ✅          | ✅             | ✅                 |
| Changed, not owned                         | ✅          | ✅             | ✅                 |
| Changed, owned, no override                | ❌ skip     | ❌ skip        | —                  |
| Changed, owned, has override               | ❌ skip     | ❌ skip        | ✅ fires           |

This means:

- **Hooks** never fire for owned component changes — the stale roundtrip is silently dropped.
- **Overrides** still fire, giving the override author control over whether to accept or reject the server value.
- **Initial syncs** always go through, so the world gets populated correctly on join.

```ts
// Hook: no guard needed — it won't fire for owned components
client.hook("changed", TurretAim, (entity, id, value, added) => {
  // This only runs for non-owners
  interp.push(entity, TurretAim, value, os.clock());
});

// Override: fires even for owned components — you decide what to do
client.override("changed", TurretAim, (entity, id, value, added) => {
  // Called even for owned components
  // Default: reject (don't write to world)
  // Or accept: world.set(entity, TurretAim, value);
});
```

## Client-Side Tracking

On the client, ownership state is tracked in two maps:

| Map                           | Type                                          | Purpose                           |
| ----------------------------- | --------------------------------------------- | --------------------------------- |
| `ownership_grants`            | `Map<Entity, Map<Component, boolean>>`        | Which components this client owns |
| `ownership_buffer`            | `Map<Entity, Map<Component, { value: any }>>` | Pending reliable updates          |
| `ownership_unreliable_buffer` | `Map<Entity, Map<Component, { value: any }>>` | Pending unreliable updates        |

When an entity is deleted (`__alive_tracking__` removed), all three maps are cleaned up for that entity.

## Anti-Patterns

### ❌ Server modifying owned components

```ts
import { pair } from "@rbxts/jecs";

world.set(entity, pair(Replecs.Owned, Position), player);
world.set(entity, Position, somePos); // WARNING: blocked by mutual exclusion
```

### ❌ Client requesting changes without ownership

```ts
client.request_set(entity, Position, newPos); // WARNING: "cannot set component: entity does not have ownership grant"
```

### ❌ Forgetting to collect and send ownership updates

```ts
client.request_set(entity, Position, newPos);
// Missing: for (const [buf, variants] of client.collect_ownership()) { Send(buf, variants); }
// Value will sit in buffer forever
```

### ❌ Not applying ownership updates on server

```ts
// Client sends ownership updates but server never calls:
server.apply_ownership(buf, player, variants);
```
