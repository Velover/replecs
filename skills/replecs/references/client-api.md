# Client API Reference

## Initialization

```ts
const client = Replecs.create_client(world);
// or
const lib = Replecs.create(world);
const client = lib.client;
```

### `client.init(world?: World)`

Initializes the client replicator. Hooks into jecs observers for serdes and alive tracking. Must be called once before any other client methods.

### `client.destroy()`

Unhooks all observers. The client can no longer be used after this.

---

## Receiving Updates

### `client.apply_full(buf, variants?)`

Applies a full snapshot from the server. Used during the initial join handshake. Creates all entities, sets all components, and builds the entity ID mapping.

```ts
const [buf, variants] = WaitForFullSnapshot();
client.apply_full(buf, variants);
```

### `client.apply_updates(buf, variants?)`

Applies reliable update packets from the server. Processes entity additions, component changes, component removals, pair changes, relation changes, and entity deletions. Delta-tracked — only writes values that actually changed.

```ts
OnReliableReceived((buf, variants) => {
  client.apply_updates(buf, variants);
});
```

### `client.apply_unreliable(buf, variants?)`

Applies unreliable update packets. Only writes values for components the entity already has (does not add new components). If hooks/overrides are registered for the component, they are called.

```ts
OnUnreliableReceived((buf, variants) => {
  client.apply_unreliable(buf, variants);
});
```

### `client.apply_entity(buf, variants?)`

Applies a full entity state packet (from `server.collect_entity`).

---

## Ownership (Client-Side)

### `client.apply_ownership_grant(buf, variants?)`

Processes an ownership grant packet from the server. Clears previous grants and replaces with new ones. Grants are stored per-entity, per-component.

### `client.has_ownership(entity, component): boolean`

Returns whether this client has ownership of a specific component on an entity.

```ts
if (client.has_ownership(entity, Position)) {
  client.request_set(entity, Position, newPos);
}
```

### `client.request_set<T>(entity, component, value, unreliable?)`

Requests a value change for a component the client owns. **Immediately writes the value to the local world** for instant client-side prediction, and also buffers it for replication to the server.

The optional `unreliable` parameter determines which buffer (and therefore which zap event) the update is queued into:

- **`false` (default)**: buffered into `ownership_buffer`, collected via `collect_ownership()`, sent over the reliable channel
- **`true`**: buffered into `ownership_unreliable_buffer`, collected via `collect_ownership_unreliable()`, sent over the unreliable channel

The raw value is stored and serialized at collect time (when `collect_ownership` / `collect_ownership_unreliable` is called), ensuring correct variant ordering. Throttle is **not** applied to ownership updates — values are always buffered immediately.

The server does not need separate handlers — a single `server.apply_ownership()` routes internally based on the component's registered track type (`set_reliable` / `set_unreliable`).

```ts
// Sets the value in the local world AND buffers for reliable replication
client.request_set(entity, Position, newPos);

// Buffers for unreliable replication instead
client.request_set(entity, Position, newPos, true);
```

### `client.collect_ownership(): () => [buffer, variants]`

Iterator that serializes and yields **reliable** ownership updates. Clears the buffer after yielding. Send via the reliable zap event.

```ts
for (const [buf, variants] of client.collect_ownership()) {
  zap.OnOwnershipReliable.Fire(buf, variants);
}
```

### `client.collect_ownership_unreliable(): () => [buffer, variants]`

Iterator that serializes and yields **unreliable** ownership updates. Clears the buffer after yielding. Send via the unreliable zap event.

```ts
for (const [buf, variants] of client.collect_ownership_unreliable()) {
  zap.OnOwnershipUnreliable.Fire(buf, variants);
}
```

---

## Hooks & Overrides

### `client.hook(action, relation, callback): Disconnect`

Registers a hook that fires when a replicated value changes/is removed. The value is also written to the world.

```ts
import { pair } from "@rbxts/jecs";

const disconnect = client.hook(
  "changed",
  pair(Replecs.Reliable, Position),
  (entity, id, value) => {
    print("Position updated:", entity, value);
  },
);

const disconnect2 = client.hook(
  "removed",
  pair(Replecs.Reliable, Position),
  (entity, id) => {
    print("Component removed:", entity, id);
  },
);

const disconnect3 = client.hook("deleted", entity, (entity) => {
  print("Entity deleted:", entity);
});
```

### `client.override(action, relation, callback): Disconnect`

Registers an override that fires when a replicated value changes/is removed. The value is **NOT** written to the world — you must do it manually. Useful for intercepting and transforming values.

```ts
import { pair } from "@rbxts/jecs";

const disconnect = client.override(
  "changed",
  pair(Replecs.Reliable, Position),
  (entity, id, value) => {
    // Custom handling - value is NOT auto-written
    world.set(entity, Position, customTransform(value));
  },
);
```

---

## Entity Lifecycle

### `client.added(callback): Disconnect`

Fires when a new entity is first seen during replication. Returns a disconnect function.

```ts
const disconnect = client.added((entity) => {
  print("New entity appeared:", entity);
});
```

### `client.after_replication(callback)`

Registers a callback that runs after the current replication batch completes. If not currently replicating, runs immediately.

```ts
client.after_replication(() => {
  // Safe to query world here
});
```

---

## Entity ID Mapping

### `client.get_server_entity(client_entity): number?`

Returns the server entity ID for a client entity.

### `client.get_client_entity(server_id): Entity?`

Returns the client entity for a server entity ID.

### `client.register_entity(entity, server_id)`

Manually maps a client entity to a server entity ID.

### `client.unregister_entity(entity)`

Removes the entity ID mapping.

### `client.handle_global(handler: (id: number) => Entity)`

Registers a handler for resolving global entity IDs (0–245). These are small IDs that can be used for commonly-referenced entities.

```ts
client.handle_global((id) => {
  return ref(`global-${id}`) as Entity;
});
```

---

## Custom IDs

### `client.register_custom_id(custom_id: CustomId)`

Registers a custom ID definition on the client. Required for handshake compatibility.

---

## Serdes

### `client.set_serdes<T>(component, serdes)`

Registers a serializer/deserializer for a component on the client side.

### `client.remove_serdes(component)`

Removes serdes for a component.

---

## Handshake

### `client.generate_handshake(): HandshakeInfo`

Generates a handshake info object.

### `client.verify_handshake(handshake): [boolean, string?]`

Verifies that a handshake from the server is compatible.

---

## Utility

### `client.encode_component(component): number`

Encodes a component to its shared index number.

### `client.decode_component(encoded): Entity`

Decodes a shared index number back to a component entity.

### `client.get_shared_count(): number`

Returns the total number of shared components.

---

## Properties

| Property                             | Type                                          | Description                                           |
| ------------------------------------ | --------------------------------------------- | ----------------------------------------------------- |
| `client.world`                       | `World`                                       | The jecs world                                        |
| `client.inited`                      | `boolean?`                                    | Init state                                            |
| `client.is_replicating`              | `boolean`                                     | True during `apply_*` calls                           |
| `client.components`                  | `Components`                                  | Shared component definitions                          |
| `client.shared`                      | `Shared`                                      | Resolved shared state                                 |
| `client.server_ids`                  | `{ [number]: Entity }`                        | Server ID → client entity mapping                     |
| `client.client_ids`                  | `{ [Entity]: number }`                        | Client entity → server ID mapping                     |
| `client.ownership_grants`            | `Map<Entity, Map<Component, boolean>>`        | Active ownership grants                               |
| `client.ownership_buffer`            | `Map<Entity, Map<Component, { value: any }>>` | Pending reliable ownership updates                    |
| `client.ownership_unreliable_buffer` | `Map<Entity, Map<Component, { value: any }>>` | Pending unreliable ownership updates                  |
| `client.command_buffers`             | `{ [Entity]: CommandBuffer }?`                | Active during replication (hooks see buffered writes) |

---

## Interpolation

See **[Interpolation](interpolation.md)** for the standalone interpolation buffer API (`Replecs.create_interpolation`), which provides jitter-compensating client-side lerping for replicated component values.
