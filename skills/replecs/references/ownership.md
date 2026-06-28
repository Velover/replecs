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
  │  2. Collect grants            │
  │  for player, buf, variants    │
  │    in server:                 │
  │    collect_ownership_grant()  │
  │──── buf, variants ──────────→ │
  │                               │  3. Apply grants
  │                               │  client:apply_ownership_grant()
  │                               │
  │                               │  4. Check & request
  │                               │  if client:has_ownership(e, Pos)
  │                               │    client:request_set(e, Pos, v)│                               │    → sets world immediately
│                               │    → buffers for replication  │                               │
  │                               │  5. Collect updates
  │  ←── buf, variants ──────────│  for buf, variants in
  │                               │    client:collect_ownership()
  │  6. Apply ownership update    │
  │  server:apply_ownership_      │
  │    reliable(buf, player, v)   │
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

Serdes can define an `ownership_validate` function to reject invalid client updates:

```ts
// Set serdes directly on the component entity (NOT via pair)
world.set(Position, Replecs.Serdes, {
	bytespan: 12,
	serialize: /* ... */,
	deserialize: /* ... */,
	ownership_validate: (value: Vector3) => {
		return value.Magnitude < 10000;  // anti-cheat: reject far positions
	},
});
```

If validation fails, the update is silently dropped.

## Reliable vs Unreliable

|                  | Reliable                           | Unreliable                                       |
| ---------------- | ---------------------------------- | ------------------------------------------------ |
| Transport        | `collect_ownership()`              | `collect_ownership_unreliable()`                 |
| Server apply     | `apply_ownership_reliable()`       | `apply_ownership_unreliable()`                   |
| Buffer           | `ownership_buffer`                 | `ownership_unreliable_buffer`                    |
| Use case         | Infrequent but important updates   | High-frequency updates (e.g. position)           |
| Delivery         | Guaranteed, ordered                | Best-effort, may be dropped                      |
| Server broadcast | Via `collect_updates()` (reliable) | Via `collect_unreliable()` + `collect_updates()` |

**Unreliable ownership** writes the value to both storage AND the unreliable broadcast mask, so other clients see it through both reliable delta changes and unreliable snapshots.

## Player Leave Cleanup

When a player leaves, `server:remove_client(player)` is called automatically (via `PlayerRemoving`). This:

1. Calls `masking:unregister_client(player)` — removes from all bitmask filters
2. Iterates all `server.ownership` entries and removes any where `entry.player == player`
3. Cleans up empty entity ownership tables
4. Removes the player from `ownership_dirty`

This is **eager** cleanup (unlike masking which uses lazy cleanup) because stale ownership entries would **block the server from modifying those components** via `check_ownership_mutual_exclusion`.

## Client-Side Tracking

On the client, ownership state is tracked in three maps:

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
server.apply_ownership_reliable(buf, player, variants);
// Values are never applied to the world
```
