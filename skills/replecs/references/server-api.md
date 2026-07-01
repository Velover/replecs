# Server API Reference

## Initialization

```ts
const server = Replecs.create_server(world);
// or
const lib = Replecs.create(world);
const server = lib.server;
```

### `server.init(world?: World)`

Initializes the server replicator. Hooks into jecs observers for all replication components. Automatically connects `PlayerAdded`/`PlayerRemoving` on Roblox. Must be called once before any other server methods.

### `server.destroy()`

Unhooks all observers and disconnects events. The server can no longer be used after this.

---

## Entity Tracking

### `server.set_networked(entity, filter?: MemberFilter, keep?: boolean)`

Marks an entity as networked. If already networked, updates the player filter. This is required before tracking individual components — components can only be replicated on networked entities.

When changing the filter on an already-networked entity:

- `keep=false` (default): players removed from the filter receive entity deletion packets
- `keep=true`: removed players keep the entity on their client; tracked internally for later cleanup

```ts
server.set_networked(entity); // all players
server.set_networked(entity, new Map([[p1, true]])); // specific players
server.set_networked(entity, (player) => player.Team === "Red"); // function filter
server.set_networked(entity, new Map([[p1, true]]), true); // keep=true: excluded players retain entity
```

### `server.set_reliable(entity, component, filter?: MemberFilter, keep?: boolean)`

Tracks a component for **reliable** replication. Changes are delta-tracked and only sent when the value actually changes. If already tracked, updates the filter.

When changing the filter:

- `keep=false` (default): removed players receive component deletion packets
- `keep=true`: removed players keep the component data; tracked for later cleanup

Works with: regular components, tags, and pairs.

```ts
server.set_reliable(entity, Health); // reliable component
server.set_reliable(entity, IsAlive); // tag (boolean)
server.set_reliable(entity, MyPair, filter); // with filter
server.set_reliable(entity, Health, new Map([[p1, true]]), true); // keep=true
```

### `server.set_unreliable(entity, component, filter?: MemberFilter, keep?: boolean)`

Tracks a component for **unreliable** replication. The current value is sent every frame (snapshot), regardless of whether it changed. Automatically splits packets at the 1KB boundary.

```ts
server.set_unreliable(entity, Position);
server.set_unreliable(entity, Velocity, filter);
```

### `server.set_pair(entity, id, filter?: MemberFilter, keep?: boolean)`

Tracks a jecs pair for replication. The pair **must exist in the world before calling `set_pair`**, because Replecs snapshots the current value for the initial sync.

```ts
import { pair } from "@rbxts/jecs";

// ✅ Correct: add to world first, then register for replication
world.add(entity, pair(ChildOf, parent));
server.set_pair(entity, pair(ChildOf, parent));

// ❌ Wrong: set_pair before world.add — initial value is missing
server.set_pair(entity, pair(ChildOf, parent));
world.add(entity, pair(ChildOf, parent));
```

### `server.set_relation(entity, relation, filter?: MemberFilter, keep?: boolean)`

Tracks a jecs relation (and all its targets) for replication.

```ts
server.set_relation(entity, ChildOf);
```

### `server.set_throttle(component, interval)`

Shorthand for setting replication throttle on a component. Registers a component for rate-limited replication, buffering changes and flushing at the specified interval.

```ts
import { pair } from "@rbxts/jecs";

// Full form (via ECS)
world.set(Score, pair(Replecs.Throttle, Score), 1 / 20);

// Shorthand
server.set_throttle(Score, 1 / 20); // 20Hz
```

### `server.stop_networked(entity, keep?: boolean)`

Stops replicating an entity. If `keep` is true, does not send entity deletion to clients (they keep the stale data). Cleans up throttle buffers and ownership for the entity.

### `server.stop_reliable(entity, component, keep?: boolean)`

Stops tracking a component for reliable replication. If `keep` is true, does not send removal to clients.

### `server.stop_unreliable(entity, component, keep?: boolean)`

Stops tracking a component for unreliable replication.

### `server.stop_pair(entity, id)`

Stops tracking a pair.

### `server.stop_relation(entity, relation, keep?: boolean)`

Stops tracking a relation.

---

## Custom IDs

### `server.set_custom(entity, handler: Entity | CustomId)`

Registers a custom ID handler for an entity. This allows clients to resolve the entity using a custom strategy instead of raw entity IDs.

```ts
server.set_custom(entity, MyCustomId);
```

### `server.remove_custom(entity)`

Removes the custom ID registration for an entity.

### `server.register_custom_id(custom_id: CustomId)`

Registers a custom ID definition globally. Required for handshake compatibility.

---

## Serdes

### `server.set_serdes<T>(component: Component<T>, serdes: Serdes<T>)`

Registers a serializer/deserializer for a component. Can also be done via the ECS:

```ts
// Set serdes directly on the component entity (NOT via pair)
world.set(component, Replecs.Serdes, {
  bytespan: 12, // optional: fixed byte size
  includes_variants: false, // optional: if true, serialize returns [buffer, variants]
  serialize: (value) => {
    /* ... */ return buf;
  },
  deserialize: (buf, variants?) => {
    /* ... */ return value;
  },
});
```

Server-only — serdes are not sent to the client. For ownership validation, see [Validators](#validators) below.

### `server.remove_serdes(component)`

Removes the serdes for a component.

---\n

## Validators

### `server.set_validator<T>(component: Component<T>, validator: OwnershipValidator<T>)`

Registers an ownership validator for a component. Can also be done via the ECS:

```ts
// Via ECS (set directly on the component entity, NOT via pair)
world.set(
  component,
  Replecs.Validator,
  (value: number) => value >= 0 && value <= 100,
);

// Via shorthand
server.set_validator(component, (value) => value >= 0 && value <= 100);
```

Validators work with or without serdes. When serdes is present, validation runs after deserialization. When no serdes, validation runs on the raw variant value. Server-only — not included in handshake.

### `server.remove_validator(component)`

Removes the validator for a component.

---

## Collection & Sending

### `server.get_full(player): [buffer, variants, grantBuf?, grantVariants?]`

Returns the full snapshot of all networked entities visible to a player. Use during the join handshake.

If the player has any ownership grants, they are returned as optional 3rd/4th values as a pre-built `ownership_grant` packet (bitmask-filtered — only entities the player can see are included). The `ownership_dirty` flag is **not** cleared, so `collect_ownership_grant()` can still send follow-up updates.

```ts
const [buf, variants, grantBuf, grantVariants] = server.get_full(player);
SendToPlayer(player, buf, variants);
if (grantBuf) {
  SendOwnershipGrant(player, grantBuf, grantVariants);
}
```

### `server.collect_updates(): () => [Player, buffer, variants]`

Iterator that yields per-player reliable update packets. Call periodically (e.g. 20Hz). Flushed throttle buffers are included if their interval has elapsed.

```ts
for (const [player, buf, variants] of server.collect_updates()) {
  SendReliable(player, buf, variants);
}
```

### `server.collect_unreliable(): () => [Player, buffer, variants]`

Iterator that yields per-player unreliable update packets. Call periodically (e.g. 30Hz). Automatically splits packets at 1KB boundary.

```ts
for (const [player, buf, variants] of server.collect_unreliable()) {
  SendUnreliable(player, buf, variants);
}
```

### `server.collect_entity(entity): () => [Player, buffer, variants]`

Iterator that yields full entity state packets for all players who can see the entity. Useful for forcing a full re-sync of a single entity.

```ts
for (const [player, buf, variants] of server.collect_entity(entity)) {
  SendToPlayer(player, buf, variants);
}
```

### `server.collect_ownership_grant(): () => [Player, buffer, variants]`

Iterator that yields ownership grant packets for players whose ownership has changed since last call. Only yields for dirty players. Grants are **bitmask-filtered** — only entities whose masking bitmask includes the player are sent. If a player has no visible owned entities, an empty grant (count=0) is sent to clear stale client-side grants.

```ts
for (const [player, buf, variants] of server.collect_ownership_grant()) {
  SendToPlayer(player, buf, variants);
}
```

---

## Ownership

### `server.apply_ownership(buf, player, variants?)`

Processes an ownership update from a client. Verifies the player owns the component, deserializes the value, and routes based on the component's registered track type:

- **Reliable components**: value is stored via delta tracking for reliable broadcast to other clients
- **Unreliable components**: value is set directly in the world and marked for unreliable broadcast

### `server.remove_client(player)`

Full client cleanup: unregisters from masking, removes all ownership entries for the player, cleans `ownership_dirty`. Called automatically on `PlayerRemoving`.

---

## Player Management

### `server.mark_player_ready(player)`

Activates a player in the masking controller. The player starts receiving replication updates. Must be called after the initial handshake (full snapshot).

### `server.is_player_ready(player): boolean`

Returns whether a player has been activated.

### `server.add_player_alias(client, alias)`

Adds an alias mapping for a player (e.g. for custom ID resolution).

### `server.remove_player_alias(alias)`

Removes an alias mapping.

---

## Handshake

### `server.generate_handshake(): HandshakeInfo`

Generates a handshake info object containing all registered components, custom IDs, and their serdes metadata.

### `server.verify_handshake(handshake): [boolean, string?]`

Verifies that a handshake from a client is compatible with the server's shared state.

---

## Utility

### `server.encode_component(component): number`

Encodes a component to its shared index number.

### `server.decode_component(encoded): Entity?`

Decodes a shared index number back to a component entity.

### `server.get_shared_count(): number`

Returns the total number of shared components.

---

## Properties

| Property                 | Type                                          | Description                                                       |
| ------------------------ | --------------------------------------------- | ----------------------------------------------------------------- |
| `server.world`           | `World`                                       | The jecs world                                                    |
| `server.inited`          | `boolean?`                                    | Init state: `false` = created, `true` = inited, `nil` = destroyed |
| `server.components`      | `Components`                                  | Shared component definitions                                      |
| `server.shared`          | `Shared`                                      | Resolved shared state (components, custom_ids, serdes)            |
| `server.throttle`        | `Map<Component, ThrottleEntry>`               | Active throttle entries                                           |
| `server.ownership`       | `Map<Entity, Map<Component, OwnershipEntry>>` | Active ownership grants                                           |
| `server.ownership_dirty` | `Set<Player>`                                 | Players with pending ownership changes                            |
