---
name: replecs
description: >
  Expert guidance for ReplecsExtended — a feature-rich, buffer-based ECS replication library for Roblox built on jecs.
  Covers server/client initialization, entity tracking, component replication (reliable/unreliable), player filtering via bitmask masking,
  custom IDs, serdes, ownership grants, throttling, hooks/overrides, relations, handshake verification, and client-side interpolation.
  USE WHEN: writing or debugging code that uses ReplecsExtended; setting up server/client replication pipelines;
  implementing player filtering, ownership, throttle, custom IDs, or serdes for jecs components;
  understanding how Replecs packet serialization, masking, or entity ID remapping works;
  implementing jitter-compensating interpolation buffers for lerping replicated values.
  DO NOT USE FOR: general jecs ECS questions unrelated to replication; networking layer implementation (e.g. Zap/Remotes).
---

# ReplecsExtended Skill

## Overview

ReplecsExtended is a fast, buffer-based ECS replication library for Roblox built on top of **jecs** (`@rbxts/jecs`). It provides:

- **Per-entity, per-component** replication with granular player filtering
- **Reliable** (delta-tracked) and **unreliable** (snapshot) replication paths
- **Bitmask-based masking** for efficient per-player component filtering
- **Custom IDs** for stable entity identification across server/client
- **Serdes** (serializers/deserializers) for custom component value encoding
- **Ownership** — granting clients authority over specific components
- **Throttle** — rate-limiting replication of specific components
- **Relations** — replicating jecs relationships and pair values
- **Handshake** — server/client shared state verification
- **Interpolation** — jitter-compensating snapshot buffer for smooth client-side lerping

## Architecture

```
┌─────────────────────────────────────────────────┐
│                   jecs World                     │
│  (entities, components, tags, pairs, relations)  │
└──────────────────────┬──────────────────────────┘
                       │ observers/hooks
          ┌────────────┴────────────┐
          ▼                         ▼
   ┌─────────────┐          ┌─────────────┐
   │   Server    │  buffer  │   Client    │
   │  Replicator │ ───────→ │  Replicator │
   │             │          │             │
   │ • tracking  │          │ • entity ID │
   │ • masking   │          │   remapping │
   │ • serialize │          │ • deserialize│
   │ • filtering │          │ • hooks     │
   │ • throttle  │          │ • ownership │
   │ • ownership │          │ • command   │
   └─────────────┘          │   buffers   │
                            │ • interp    │
                            └─────────────┘
```

## Quick Start

### 1. Shared: Create the replicator

```ts
import Replecs from "@rbxts/replecs-extended";
import { World } from "@rbxts/jecs";

const world = new World();
const replicator = Replecs.create(world);
// replicator.server (server-side)
// replicator.client (client-side)
// replicator.components (shared component definitions)
```

### 2. Define components & serdes

```ts
import { World } from "@rbxts/jecs";
import Replecs from "@rbxts/replecs-extended";

const world = new World();
const Position = world.component<CFrame>();

// Register serdes for bandwidth-efficient encoding
world.set(Position, replicator.components.serdes, {
  bytespan: 12,
  serialize: (cf: CFrame) => {
    const buf = buffer.create(12);
    buffer.writef32(buf, 0, cf.X);
    buffer.writef32(buf, 4, cf.Y);
    buffer.writef32(buf, 8, cf.Z);
    return buf;
  },
  deserialize: (buf: buffer) => {
    return new CFrame(
      buffer.readf32(buf, 0),
      buffer.readf32(buf, 4),
      buffer.readf32(buf, 8),
    );
  },
});
```

### 3. Server: Initialize & track entities

```ts
const server = replicator.server;
server.init();

// Mark entity as networked (all players see it)
server.set_networked(entity);

// Track specific components for replication
server.set_reliable(entity, Position); // reliable, delta-tracked
server.set_unreliable(entity, Velocity); // unreliable, snapshot each frame

// With player filtering
server.set_reliable(
  entity,
  Health,
  new Map([
    [player1, true],
    [player2, true],
  ]),
);
```

### 4. Server: Collect & send updates

```ts
// Collect reliable updates (call periodically, e.g. 20 Hz)
for (const [player, buf, variants] of server.collect_updates()) {
  SendReliableToPlayer(player, buf, variants);
}

// Collect unreliable updates (call periodically, e.g. 30 Hz)
for (const [player, buf, variants] of server.collect_unreliable()) {
  SendUnreliableToPlayer(player, buf, variants);
}
```

### 5. Client: Initialize & receive

```ts
const client = replicator.client;
client.init();

// On join, apply full snapshot from server
const [buf, variants] = WaitForFullSnapshot();
client.apply_full(buf, variants);

// Apply ongoing updates
client.apply_updates(buf, variants); // reliable
client.apply_unreliable(buf, variants); // unreliable
```

## Key Concepts

### Packet Types

| Type              | ID  | Description                                 |
| ----------------- | --- | ------------------------------------------- |
| `full`            | 1   | Complete snapshot for new/joining players   |
| `entity`          | 2   | Full state of a single entity               |
| `updates`         | 3   | Delta-tracked reliable changes              |
| `unreliable`      | 4   | Snapshot of unreliable components           |
| `ownership`       | 5   | Client→Server ownership updates             |
| `ownership_grant` | 6   | Server→Client ownership grant notifications |

### Component Types (internal tracking)

| Type                 | ID  | Description            |
| -------------------- | --- | ---------------------- |
| `tag`                | 1   | Boolean tag (no value) |
| `component`          | 2   | Component with value   |
| `pair_tag`           | 3   | Pair as tag            |
| `pair_component`     | 4   | Pair with value        |
| `relation`           | 5   | Relation tag           |
| `relation_component` | 6   | Relation with value    |
| `unreliable`         | 7   | Unreliable component   |
| `unreliable_pair`    | 8   | Unreliable pair        |

### Entity ID Remapping

Server entity IDs are remapped on the client to avoid conflicts with locally-created entities. Use:

- `client.get_server_entity(client_entity)` → server ID
- `client.get_client_entity(server_id)` → client entity
- `client.register_entity(entity, server_id)` → manual mapping
- `client.handle_global(handler)` → resolve global IDs (0–245)

### Filtering (Masking)

Components can be filtered per-player using bitmask-based masking:

```ts
// Only replicate to specific players
server.set_reliable(entity, MyComponent, new Map([[player1, true]]));

// Change filter dynamically
server.set_reliable(entity, MyComponent, new Map([[player2, true]]));

// Function filter
server.set_reliable(entity, MyComponent, (player) => player.Team === "Red");
```

### Ownership

Grant clients authority over specific components:

```ts
import { pair } from "@rbxts/jecs";

// Server: grant ownership (shorthand)
server.set_owner(entity, Position, player);

// Or manually:
world.set(entity, pair(Replecs.Owned, Position), player);

// Server: send grants
for (const [player, buf, variants] of server.collect_ownership_grant()) {
  SendToPlayer(player, buf, variants);
}

// Client: apply grants
client.apply_ownership_grant(buf, variants);

// Client: check ownership & request changes
if (client.has_ownership(entity, Position)) {
  client.request_set(entity, Position, newPos);
}

// Client: collect & send updates back
for (const [buf, variants] of client.collect_ownership()) {
  SendToServer(buf, variants);
}

// Server: apply client ownership updates
server.apply_ownership(buf, player, variants);
```

**Mutual exclusion**: The server cannot modify a component that is owned by a client. Ownership must be removed first.

**Important**: `set_owner` must be called **after** setting the component value. Once ownership is granted, the server is blocked from writing to that component:

```ts
// ✅ Correct order
server.set_networked(entity);
server.set_reliable(entity, Position);
world.set(entity, Position, initialCFrame); // set value first
server.set_owner(entity, Position, player); // then grant ownership

// ❌ Wrong order — server world:set would be blocked by ownership
server.set_owner(entity, Position, player);
world.set(entity, Position, initialCFrame); // silently blocked!
```

### Throttle

Rate-limit replication of specific components:

```ts
import { pair } from "@rbxts/jecs";

// Full form (via ECS)
world.set(MyComponent, pair(Replecs.Throttle, MyComponent), 0.05);

// Shorthand
server.set_throttle(MyComponent, 0.05); // flushes every 0.05s = 20Hz

// Throttled components are buffered and flushed during collect_updates()
// Unreliable components bypass throttle entirely
```

### Custom IDs

Provide stable entity identification across server/client boundaries:

```ts
const MyCustomId = Replecs.create_custom_id("player_entity", (ctx) => {
  // ctx: HandleContext with helpers to resolve components, pairs, etc.
  return ctx.entity(ctx.entity_id); // resolve by server entity ID
});

server.set_custom(entity, MyCustomId);
server.register_custom_id(MyCustomId);
client.register_custom_id(MyCustomId);
```

### Hooks & Overrides

Client-side hooks for reacting to replicated data:

```ts
import { pair } from "@rbxts/jecs";

// Hook: called when value changes, value is also written to world
const disconnect = client.hook(
  "changed",
  pair(Replecs.Reliable, Position),
  (entity, id, value) => {
    print("Position changed:", entity, value);
  },
);

// Override: called when value changes, value is NOT written to world
const disconnect2 = client.override(
  "changed",
  pair(Replecs.Reliable, Position),
  (entity, id, value) => {
    // You handle writing the value yourself
    world.set(entity, Position, customTransform(value));
  },
);

// Removal hooks
client.hook("removed", pair(Replecs.Reliable, Position), (entity, id) => {});

// Entity deletion hooks
client.hook("deleted", entity, (entity) => {});
```

### Player Lifecycle

```ts
// Server: init handles PlayerAdded/PlayerRemoving automatically
server.init();

// Mark player ready (activates them in masking, starts receiving updates)
server.mark_player_ready(player);

// Check if ready
server.is_player_ready(player);

// Remove client (cleans up ownership + masking)
server.remove_client(player);

// Client: after_replication callback
client.after_replication(() => {
  // runs after current replication batch completes
});

// Client: added callback (fires when new entity is replicated)
const disconnect = client.added((entity) => {
  print("New entity:", entity);
});
```

### Relations

Replicate jecs relationships:

```ts
import { pair } from "@rbxts/jecs";

// Track relation
server.set_relation(entity, MyRelation);

// Track pair
server.set_pair(entity, pair(MyRelation, target));
```

### Handshake

Verify server/client shared state compatibility:

```ts
// Server
const handshake = server.generate_handshake();
// send handshake to client...

// Client
const [ok, err] = client.verify_handshake(handshake);
if (!ok) {
  warn("Handshake failed:", err);
}
```

## Interpolation (Client-Side)

For smooth client-side lerping with jitter compensation, ReplecsExtended provides a standalone interpolation buffer:

```ts
const interp = Replecs.create_interpolation({ base_delay: 0.05 });

// Register lerp functions
interp.register(Position, (a, b, t) => a.Lerp(b, t));

// Feed from hooks
client.hook(
  "changed",
  pair(Replecs.Reliable, Position),
  (entity, id, value) => {
    interp.push(entity, Position, value, os.clock());
  },
);

// Read each frame
const pos = interp.get(entity, Position);
```

See **[Interpolation](references/interpolation.md)** for the full API, jitter compensation details, and patterns.

## Reference Files

- **[Server API](references/server-api.md)** — Complete server-side API reference
- **[Client API](references/client-api.md)** — Complete client-side API reference
- **[Components](references/components.md)** — Component types, pairs, and the `Components` table
- **[Ownership](references/ownership.md)** — Ownership system deep-dive
- **[Masking & Filtering](references/masking-filtering.md)** — Bitmask masking, player filtering, compact_members
- **[Interpolation](references/interpolation.md)** — Jitter-compensating interpolation buffer API
- **[Patterns](references/patterns.md)** — Common patterns, anti-patterns, and integration examples
