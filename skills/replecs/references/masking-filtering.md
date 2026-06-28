# Masking & Filtering

## Overview

Replecs uses a **bitmask-based masking system** to efficiently control which players see which entities and components. Each unique combination of player filters produces a storage group with its own bitmask. Players are assigned bit indices, and the bitmask encodes which players can see the contents of that storage group.

## Architecture

```
StorageGroup (unique filter combination)
├── bitmask: { bit[N] = true for each member }
├── members: [player1, player3, ...]
├── active: { [entity]: ActiveEntity }
├── changes: { added, added_components, changed }
└── deletions: { entities, components }

MaskingController
├── storages: [StorageGroup, ...]
├── client_indexes: { [Player]: number }  -- player → bit index
├── active_clients: { [Player]: boolean }
├── lookups: { entities: { [entity]: EntityLookup } }
└── compact_count: number
```

## How Filtering Works

### 1. Setting a Filter

When you call `server.set_reliable(entity, component, filter)`, the masking system:

1. Evaluates the filter to produce a set of players
2. Hashes the player set to find (or create) a matching `StorageGroup`
3. Assigns the entity + component to that storage group
4. If the component has a different filter from the entity's base filter, it gets its own filtered component storage

### 2. Filter Types

```ts
// No filter: all active players
server.set_networked(entity);

// Player map: explicit set of players
server.set_networked(
  entity,
  new Map([
    [player1, true],
    [player2, true],
  ]),
);

// Single player shorthand
server.set_networked(entity, player1);

// Function filter: evaluated per-player
server.set_networked(entity, (player) => player.Team === "Red");
```

Function filters are re-evaluated when the filter changes (via `set_*` with a new filter). They are not continuously re-evaluated.

### 3. Dynamic Filter Changes

Filters can be changed at any time:

```ts
// Initially visible to all
server.set_networked(entity);

// Later: restrict to specific players
server.set_networked(entity, new Map([[player1, true]]));
```

This triggers storage group migration — the entity moves between storage groups and the appropriate change packets are generated.

## Player Lifecycle

### Registration

When a player joins (via `PlayerAdded` or manual `register_client`):

1. A bit index is assigned
2. The player is registered in the masking controller
3. The player is **not active** yet — they don't receive updates

### Activation

When `server.mark_player_ready(player)` is called:

1. The player becomes active
2. They are added to all matching storage group member lists
3. They start appearing in `collect_updates()` and `collect_unreliable()` output

### Removal

When `server.remove_client(player)` is called:

1. `masking:unregister_client(player)` removes the player from client_indexes and active_clients
2. The bit index is freed
3. **Orphaned bits**: The player's bits in storage group bitmasks are NOT immediately cleared. They remain set but harmless because:
   - `is_client_valid(player)` returns false for removed players
   - `append_packet()` skips invalid players
   - `create_packet_iterator()` skips invalid players
4. **Lazy cleanup**: When enough players have left (`member_count >= compact_count`), `compact_members()` is called to remap all bit indices and reclaim orphaned bit positions

### `is_client_valid` Safety Net

All packet delivery paths check `is_client_valid(player)` before yielding a packet:

```ts
// In append_packet:
for (const member of members) {
  if (!utils.is_client_valid(member)) continue;
  // ... add to packets
}

// In create_packet_iterator:
let [player, data] = next(packets, iterated);
while (player !== undefined && !utils.is_client_valid(player)) {
  [player, data] = next(packets, player);
}
```

This ensures that even if orphaned bits exist, no packets are sent to removed players.

## Compact Members

When `member_count >= compact_count`, the masking controller runs `compact_members()`:

1. Collects all active (valid) players
2. Reassigns bit indices sequentially (0, 1, 2, ...)
3. Rebuilds all storage group bitmasks with the new indices
4. Resets `compact_count` to a higher threshold

This reclaims bit positions from removed players, preventing the bitmask from growing unbounded.

## Storage Group Isolation

Each unique filter combination gets its own storage group. This means:

- Entities with the same filter are grouped together
- `collect_updates()` iterates storage groups and builds per-player packets from the bitmask members
- A component with a different filter than its entity gets a separate filtered component storage

```ts
server.set_networked(entity); // all players → StorageGroup A
server.set_reliable(entity, Health); // inherits entity filter → StorageGroup A
server.set_reliable(entity, Secret, new Map([[admin, true]])); // different filter → StorageGroup B
```

## Performance Characteristics

- **Bitmask operations**: O(1) per player per storage group check
- **Packet building**: Per-storage-group, so entities with the same filter share packet buffers
- **No per-entity per-player iteration**: The masking system groups entities by filter, not by player
- **Compact**: Bitmasks grow only when new players join, and are compacted when players leave
- **Scale**: Tested with 50K entities with player filters at 60fps

## Unreliable Replication & Masking

Unreliable components are tracked in the same masking system but use a separate collection path:

1. `collect_unreliable()` iterates storage groups
2. For each entity, reads the current value from the world (snapshot, not delta)
3. Automatically splits packets at 1KB boundary using checkpoint/rollback
4. Uses the same bitmask for player filtering
