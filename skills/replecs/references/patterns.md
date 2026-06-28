# Patterns & Integration

## Standard Server/Client Pipeline

### Server Loop

```ts
import Replecs from "@rbxts/replecs-extended";
import { Players } from "@rbxts/services";

const server = replicator.server;
server.init();

// Handshake
Players.PlayerAdded.Connect((player) => {
  // Player is auto-registered via init()
  // Send handshake, wait for client ready...
});

zap.WaitForServer.SetCallback((player) => {
  if (server.is_player_ready(player)) {
    return $multi(undefined, undefined);
  }
  server.mark_player_ready(player);
  return server.get_full(player);
});

// Replication loop (run in a system at e.g. 20Hz reliable, 30Hz unreliable)
const RELIABLE_INTERVAL = 1 / 20;
const UNRELIABLE_INTERVAL = 1 / 30;
let reliableClock = os.clock();
let unreliableClock = os.clock();

function REPLICATION_SYSTEM() {
  const now = os.clock();

  if (now - reliableClock >= RELIABLE_INTERVAL) {
    reliableClock = now;
    for (const [player, buf, variants] of server.collect_updates()) {
      zap.OnReliableUpdates.Fire(player, buf, variants);
    }
    // Also collect and send ownership grants
    for (const [player, buf, variants] of server.collect_ownership_grant()) {
      zap.OnOwnershipGrant.Fire(player, buf, variants);
    }
  }

  if (now - unreliableClock >= UNRELIABLE_INTERVAL) {
    unreliableClock = now;
    for (const [player, buf, variants] of server.collect_unreliable()) {
      zap.OnUnreliableUpdates.Fire(player, buf, variants);
    }
  }
}
```

### Client Loop

```ts
import Replecs from "@rbxts/replecs-extended";

const client = replicator.client;
client.init();

// Join handshake
const [buf, variants] = zap.WaitForServer.Call();

client.handle_global((id) => ref(`global-${id}`) as Entity);

if (buf) {
  client.apply_full(buf, variants as defined[][]);
}

// Replication loop
function REPLICATION_SYSTEM() {
  for (const [, buf, variants] of reliable_updates) {
    client.apply_updates(buf, variants);
  }
  for (const [, buf, variants] of unreliable_updates) {
    client.apply_unreliable(buf, variants);
  }
  for (const [, buf, variants] of ownership_grants) {
    client.apply_ownership_grant(buf, variants);
  }
}
```

---

## Client-Side Prediction with Ownership

```ts
import { pair } from "@rbxts/jecs";

// Server: grant ownership of position to the player's entity
const playerEntity = getPlayerEntity(player);
world.set(playerEntity, pair(Replecs.Owned, Position), player);

// Client: predict movement locally
function MOVEMENT_SYSTEM() {
  if (!client.has_ownership(playerEntity, Position)) return;

  const currentPos = world.get(playerEntity, Position)!;
  const newPos = currentPos.add(velocity.mul(dt));

  // request_set writes locally for prediction AND buffers for server replication
  client.request_set(playerEntity, Position, newPos, true); // unreliable
}

// Client: send ownership updates at fixed rate
function OWNERSHIP_SEND_SYSTEM() {
  for (const [buf, variants] of client.collect_ownership_unreliable()) {
    zap.OnOwnershipUnreliable.Fire(buf, variants);
  }
}

// Server: receive and apply
zap.OnOwnershipUnreliable.SetCallback((player, buf, variants) => {
  server.apply_ownership_unreliable(buf, player, variants);
});
```

---

## Entity Spawning Pattern

```ts
import { pair } from "@rbxts/jecs";

// Server: create and configure entity
const entity = world.entity();
world.add(entity, Replecs.Networked);
world.set(entity, Position, initialPos);
world.set(entity, Health, 100);

// Track specific components
world.add(entity, pair(Replecs.Reliable, Position));
world.add(entity, pair(Replecs.Reliable, Health));

// Optional: serdes for bandwidth (set directly on component, NOT via pair)
world.set(Position, Replecs.Serdes, {
  /* ... */
});
```

---

## Per-Component Player Filtering

```ts
import { pair } from "@rbxts/jecs";

const entity = world.entity();
world.add(entity, Replecs.Networked); // visible to all

// Public component: everyone sees it
world.add(entity, pair(Replecs.Reliable, Name));

// Private component: only the owner sees it
world.set(
  entity,
  pair(Replecs.Reliable, SecretData),
  new Map([[ownerPlayer, true]]),
);

// Team component: only team members see it
const teamFilter = new Map<Player, boolean>();
for (const p of getTeamPlayers("Red")) {
  teamFilter.set(p, true);
}
world.set(entity, pair(Replecs.Reliable, TeamInfo), teamFilter);
```

---

## Throttled Components

```ts
import { pair } from "@rbxts/jecs";

// Register a component as throttled (20Hz)
const Score = world.component<number>();
world.set(Score, pair(Replecs.Throttle, Score), 1 / 20);

// Normal server code — changes are buffered automatically
world.set(playerEntity, Score, newScore);

// The buffered value is flushed during server.collect_updates()
// when the throttle interval has elapsed
```

---

## Relations Pattern

```ts
import { ChildOf, pair } from "@rbxts/jecs";

const Inventory = world.entity();

// Track relation for replication
world.set(parentEntity, pair(Replecs.Reliable, Inventory));
world.set(parentEntity, pair(Replecs.Relation, ChildOf));

// Add children — automatically replicated
world.add(childEntity, pair(ChildOf, parentEntity));
world.set(childEntity, pair(Inventory, parentEntity), { item: "sword" });
```

---

## Custom ID for Stable Entity References

```ts
import { pair } from "@rbxts/jecs";
import { Players } from "@rbxts/services";

// Define custom ID
const PlayerEntity = Replecs.create_custom_id("player_entity", (ctx) => {
  // Resolve by server entity ID
  return ctx.entity(ctx.entity_id);
});

// Register on both sides
server.register_custom_id(PlayerEntity);
client.register_custom_id(PlayerEntity);

// Assign to player entities on server
Players.PlayerAdded.Connect((player) => {
  const entity = world.entity();
  world.add(entity, pair(Replecs.Custom, PlayerEntity));
  world.add(entity, Replecs.Networked);
  // ...
});
```

---

## Serdes for CFrame (Position-Only)

```ts
import { pair } from "@rbxts/jecs";

world.set(Position, Replecs.Serdes, {
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

## Serdes for Color3

```ts
import { pair } from "@rbxts/jecs";

world.set(Color, Replecs.Serdes, {
  bytespan: 12,
  serialize: (c: Color3) => {
    const buf = buffer.create(12);
    buffer.writef32(buf, 0, c.R);
    buffer.writef32(buf, 4, c.G);
    buffer.writef32(buf, 8, c.B);
    return buf;
  },
  deserialize: (buf: buffer) => {
    return new Color3(
      buffer.readf32(buf, 0),
      buffer.readf32(buf, 4),
      buffer.readf32(buf, 8),
    );
  },
});
```

---

## Hook: Transform Replicated Values

```ts
import { pair } from "@rbxts/jecs";

// Scale all received positions by a factor
client.override(
  "changed",
  pair(Replecs.Reliable, Position),
  (entity, id, value) => {
    world.set(entity, Position, value.mul(2));
  },
);
```

## Hook: Entity Lifecycle

```ts
import { Entity } from "@rbxts/jecs";

// React to new entities
client.added((entity) => {
  // Create visual representation
  const part = new Instance("Part");
  part.Parent = game.Workspace;
  world.set(entity, VisualPart, part as unknown as Entity);
});

// React to entity deletion
client.hook("deleted", entity, (entity) => {
  const part = world.get(entity, VisualPart) as unknown as BasePart | undefined;
  if (part) part.Destroy();
});
```

---

## Anti-Patterns

### ❌ Forgetting `set_networked`

```ts
server.set_reliable(entity, Position); // ERROR: entity not networked
```

Components can only be tracked on networked entities.

### ❌ Modifying owned components on server

```ts
import { pair } from "@rbxts/jecs";

world.set(entity, pair(Replecs.Owned, Position), player);
world.set(entity, Position, someValue); // WARNING: blocked by mutual exclusion
```

### ❌ Missing `mark_player_ready`

```ts
// Player joins but never marked ready
server.get_full(player); // Works, but player won't receive ongoing updates
// Fix: call server.mark_player_ready(player) after sending full snapshot
```

### ❌ Not calling `init()`

```ts
const server = Replecs.create_server(world);
server.set_networked(entity); // May fail or behave unexpectedly
// Fix: call server.init() first
```

### ❌ Calling `collect_updates` without sending

```ts
for (const [player, buf, variants] of server.collect_updates()) {
  // Don't forget to send! Changes are consumed from the buffer.
  // If you don't send, the data is lost.
  SendToPlayer(player, buf, variants);
}
```
