# Components Reference

## The `Components` Table

Replecs provides a set of special components used to configure replication behavior. These are available on both server and client via `replicator.components` or directly from the `Replecs` module when using pre-registration.

| Component                          | Type                       | Purpose                                                                |
| ---------------------------------- | -------------------------- | ---------------------------------------------------------------------- |
| `shared` / `Shared`                | `Tag`                      | Marks a component as shared (included in handshake)                    |
| `networked` / `Networked`          | `Entity<MemberFilter?>`    | Marks an entity as networked with optional player filter               |
| `reliable` / `Reliable`            | `Entity<MemberFilter?>`    | Pairs with a component to track it for reliable replication            |
| `unreliable` / `Unreliable`        | `Entity<MemberFilter?>`    | Pairs with a component for unreliable replication                      |
| `relation` / `Relation`            | `Entity<MemberFilter?>`    | Pairs with a relation for relation replication                         |
| `throttle` / `Throttle`            | `Entity<number?>`          | Pairs with a component to rate-limit replication (interval in seconds) |
| `owned` / `Owned`                  | `Entity<MemberFilter?>`    | Pairs with a component to grant client ownership                       |
| `serdes` / `Serdes`                | `Entity<SerdesTable>`      | Set on a component to register custom serialization (not a pair)       |
| `custom` / `Custom`                | `Entity`                   | Pairs with a custom ID for entity identification                       |
| `custom_handler` / `CustomHandler` | `Entity<(val) -> Entity?>` | Pairs with a component for custom ID resolution                        |
| `global` / `Global`                | `Entity<number>`           | Assigns a small global ID (0–245) to an entity                         |
| `__alive_tracking__`               | `Entity`                   | Internal: tracks entity lifecycle for cleanup                          |

Both lowercase and PascalCase variants exist. They refer to the same underlying jecs entity.

---

## Using Pair Syntax

Most replication configuration uses jecs pair syntax:

```ts
import { pair } from "@rbxts/jecs";

// Track a component for reliable replication
world.add(entity, pair(Replecs.Reliable, MyComponent));

// Set a player filter
world.set(
  entity,
  pair(Replecs.Reliable, MyComponent),
  new Map([[player1, true]]),
);

// Throttle at 20Hz
world.set(MyComponent, pair(Replecs.Throttle, MyComponent), 1 / 20);

// Grant ownership to player
world.set(entity, pair(Replecs.Owned, MyPosition), player);

// Register serdes (set directly on the component entity, NOT via pair)
world.set(MyComponent, Replecs.Serdes, {
  serialize: (value) => {
    /* ... */ return buf;
  },
  deserialize: (buf) => {
    /* ... */ return value;
  },
});
```

---

## Serdes Table

```ts
type SerdesTable<T> = {
  bytespan?: number; // fixed byte size (skips length prefix)
  includes_variants?: boolean; // if true, serialize returns [buffer, blobs[]]
  serialize: (value: T) => buffer; // or LuaTuple<[buffer, defined[] | undefined]> if includes_variants
  deserialize: (buffer: buffer) => T; // or (buffer: buffer, blobs: defined[] | undefined) => T if includes_variants
  ownership_validate?: (raw_value: T) => boolean; // validate client ownership updates
};
```

### Fixed-size serdes (most efficient)

```ts
world.set(MyVector3, Replecs.Serdes, {
  bytespan: 12,
  serialize: (v: Vector3) => {
    const buf = buffer.create(12);
    buffer.writef32(buf, 0, v.X);
    buffer.writef32(buf, 4, v.Y);
    buffer.writef32(buf, 8, v.Z);
    return buf;
  },
  deserialize: (buf: buffer) => {
    return new Vector3(
      buffer.readf32(buf, 0),
      buffer.readf32(buf, 4),
      buffer.readf32(buf, 8),
    );
  },
});
```

### Variable-size serdes (VLQ length prefix)

```ts
world.set(MyString, Replecs.Serdes, {
  // no bytespan = variable size, length is auto-prefixed
  serialize: (s: string) => buffer.fromstring(s),
  deserialize: (buf: buffer) => buffer.tostring(buf),
});
```

### Variant serdes (for complex types with external references)

```ts
world.set(MyEntityRef, Replecs.Serdes, {
  includes_variants: true,
  serialize: (ref) => {
    return $multi(buffer.create(0), [ref]); // value stored in variants array
  },
  deserialize: (buf, blobs) => {
    return (blobs as defined[])[0] as Entity;
  },
});
```

### Ownership validation

```ts
world.set(MyPosition, Replecs.Serdes, {
	bytespan: 12,
	serialize: /* ... */,
	deserialize: /* ... */,
	ownership_validate: (pos: Vector3) => {
		// Reject positions too far from origin (anti-cheat)
		return pos.Magnitude < 10000;
	},
});
```

---

## Custom IDs

Custom IDs provide stable entity identification that survives entity ID remapping between server and client.

```ts
import { pair } from "@rbxts/jecs";

const PlayerEntity = Replecs.create_custom_id("player_entity");

// On server, register with handler
PlayerEntity.handle((ctx) => {
  // ctx provides:
  //   ctx.entity_id    — the server entity ID
  //   ctx.component(c) — get component value
  //   ctx.target(rel, index?) — get relation target
  //   ctx.pair_value(rel, target) — get pair value
  //   ctx.has_pair(rel, target) — check pair
  //   ctx.entity(server_id) — resolve server entity ID
  //   ctx.has(tag) — check tag
  return ctx.entity(ctx.entity_id);
});

// Register on both sides
server.register_custom_id(PlayerEntity);
client.register_custom_id(PlayerEntity);

// Assign to entity on server
server.set_custom(entity, PlayerEntity);
// or via ECS:
world.add(entity, pair(Replecs.Custom, PlayerEntity));
```

---

## Global IDs

Small integer IDs (0–245) for commonly-referenced entities. These are resolved on the client via the global handler.

```ts
// Server: assign global ID
world.set(singletonEntity, Replecs.Global, 1);

// Client: register global handler
client.handle_global((id) => {
  if (id === 1) {
    return gameStateEntity;
  }
  return undefined!;
});
```
