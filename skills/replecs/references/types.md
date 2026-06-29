# Types Reference

> These types mirror the declarations in `src/index.d.ts`. Import them from `@rbxts/replecs-extended`.

## Core Types (from @rbxts/jecs)

```ts
import type { Entity, Id, InferComponent, Pair, Tag, World } from "@rbxts/jecs";

// Entity<T> — a typed entity handle
// World — the jecs world
// Id<T> — an entity or pair identifier
// Pair<R, T> — a relationship pair
// Tag — an entity with no data
```

## Player Filtering

```ts
type MemberFilterMap = Map<Player, boolean>;
type MemberFilter = Player | MemberFilterMap | undefined;
type Member = unknown;
```

## Serdes

```ts
type SerdesTable<T = any> =
  | {
      bytespan?: number;
      includes_variants?: false;
      serialize: (value: T) => buffer;
      deserialize: (buffer: buffer) => T;
      ownership_validate?: (raw_value: T) => boolean;
    }
  | {
      bytespan?: number;
      includes_variants: true;
      serialize: (value: T) => LuaTuple<[buffer, defined[] | undefined]>;
      deserialize: (buffer: buffer, blobs: defined[] | undefined) => T;
      ownership_validate?: (raw_value: T) => boolean;
    };
```

## Components

```ts
interface Components {
  shared: Tag;
  networked: Entity<MemberFilter>;
  reliable: Entity<MemberFilter>;
  unreliable: Entity<MemberFilter>;
  relation: Entity<MemberFilter>;
  throttle: Entity<number | undefined>;
  owned: Entity<MemberFilter>;

  serdes: Entity<SerdesTable>;
  custom: Entity;
  custom_handler: Entity<(value: any) => Entity>;
  global: Entity<number>;

  Shared: Tag;
  Networked: Entity<MemberFilter>;
  Reliable: Entity<MemberFilter>;
  Unreliable: Entity<MemberFilter>;
  Relation: Entity<MemberFilter>;
  Throttle: Entity<number | undefined>;
  Owned: Entity<MemberFilter>;

  Serdes: Entity<SerdesTable>;
  Custom: Entity;
  CustomHandler: Entity<(value: any) => Entity>;
  Global: Entity<number>;
}
```

Both lowercase and PascalCase variants refer to the same underlying jecs entity.

## Shared State

```ts
interface SharedInfo<T> {
  lookup: Record<string, T>;
  keys: string[];
  indexes: [T];
  members: Map<T, number>;
}

interface Shared {
  components: SharedInfo<Entity>;
  custom_ids: SharedInfo<CustomId>;
}
```

## Handshake

```ts
interface HandshakeSerdesInfo {
  includes_variants?: boolean;
  bytespan?: number;
}

interface HandshakeInfo {
  components: Record<string, boolean>;
  custom_ids: Record<string, boolean>;
  serdes: Record<string, HandshakeSerdesInfo>;
}
```

## HandleContext (Custom IDs)

```ts
interface HandleContext {
  entity_id: number;
  component: <T>(component: Entity<T>) => T;
  target: (relation: Id, index?: number) => Entity | undefined;
  pair_value: <T>(relation: Id<T>, target: Entity) => T | undefined;
  has_pair: (relation: Id, target: Entity) => boolean;

  entity: (server_entity: number) => Entity | undefined;
  has: (tag: Entity) => boolean;
}
```

## CustomId

```ts
interface CustomId {
  identifier: string;
  handle_callback: (ctx: HandleContext) => Entity;
  handle(handler: (ctx: HandleContext) => Entity): void;
}
```

## Server Interface

```ts
interface Server extends ServerImp {
  world: World;
  inited?: boolean;

  init(world?: World): void;
  destroy(): void;

  encode_component(component: Entity): number;
  decode_component(encoded: number): Entity | undefined;
  get_shared_count(): number;

  register_custom_id(custom_id: CustomId): void;

  get_full(player: Player): LuaTuple<[buffer, defined[][] | undefined]>;
  collect_entity(
    entity: Entity,
  ): IterableFunction<LuaTuple<[Player, buffer, defined[][] | undefined]>>;
  collect_updates(): IterableFunction<
    LuaTuple<[Player, buffer, defined[][] | undefined]>
  >;
  collect_unreliable(): IterableFunction<
    LuaTuple<[Player, buffer, defined[][] | undefined]>
  >;
  collect_ownership_grant(): IterableFunction<
    LuaTuple<[Player, buffer, defined[][] | undefined]>
  >;

  apply_ownership(
    buf: buffer,
    player: Player,
    all_variants?: defined[][],
  ): void;

  mark_player_ready(player: Player): void;
  is_player_ready(player: Player): boolean;

  add_player_alias(client: Player, alias: defined): void;
  remove_player_alias(alias: defined): void;
  remove_client(player: Player): void;

  generate_handshake(): HandshakeInfo;
  verify_handshake(
    handshake: HandshakeInfo,
  ): LuaTuple<[true]> | LuaTuple<[false, string]>;
}

interface ServerImp {
  set_networked(entity: Entity, filter?: MemberFilter): void;
  set_reliable(entity: Entity, component: Entity, filter?: MemberFilter): void;
  set_unreliable(
    entity: Entity,
    component: Entity,
    filter?: MemberFilter,
  ): void;
  set_pair(entity: Entity, id: Pair, filter?: MemberFilter): void;
  set_relation(entity: Entity, relation: Entity, filter?: MemberFilter): void;

  stop_networked(entity: Entity, keep?: boolean): void;
  stop_reliable(entity: Entity, component: Entity, keep?: boolean): void;
  stop_unreliable(entity: Entity, component: Entity, keep?: boolean): void;
  stop_pair(entity: Entity, id: Pair): void;
  stop_relation(entity: Entity, relation: Entity, keep?: boolean): void;

  set_custom(entity: Entity, handler: Entity | CustomId): void;
  remove_custom(entity: Entity): void;

  set_serdes<T extends Id>(
    component: InferComponent<T>,
    serdes: SerdesTable<T>,
  ): void;
  remove_serdes(component: Id): void;
}
```

## Client Interface

```ts
interface Client {
  world: World;
  inited?: boolean;
  is_replicating: boolean;
  after_replication_callbacks: [() => void];
  components: Components;

  init(world?: World): void;
  destroy(): void;
  handle_global(handler: (id: number) => Entity): void;
  get_server_entity(client_entity: Entity): number | undefined;
  get_client_entity(server_entity: number): Entity | undefined;

  register_entity(entity: Entity, server_entity: number): void;
  unregister_entity(entity: Entity): void;

  after_replication(callback: () => void): void;
  added(callback: (entity: Entity) => void): () => void;

  hook<T>(
    action: "changed",
    relation: Pair<MemberFilter, T>,
    callback: (entity: Entity, id: Id<T>, value: T) => void,
  ): () => void;
  hook<T>(
    action: "removed",
    relation: Pair<MemberFilter, T>,
    callback: (entity: Entity, id: Id<T>) => void,
  ): () => void;
  hook(
    action: "deleted",
    entity: Entity,
    callback: (entity: Entity) => void,
  ): () => void;

  override<T>(
    action: "changed",
    relation: Pair<MemberFilter, T>,
    callback: (entity: Entity, id: Id<T>, value: any) => void,
  ): () => void;
  override<T>(
    action: "removed",
    relation: Pair<MemberFilter, T>,
    callback: (entity: Entity, id: Id<T>) => void,
  ): () => void;
  override(
    action: "deleted",
    entity: Entity,
    callback: (entity: Entity) => void,
  ): () => void;

  encode_component(component: Entity): number;
  decode_component(encoded: number): Entity;
  get_shared_count(): number;

  register_custom_id(custom_id: CustomId): void;

  apply_updates(buf: buffer, all_variants?: defined[][]): void;
  apply_unreliable(buf: buffer, all_variants?: defined[][]): void;
  apply_full(buf: buffer, all_variants?: defined[][]): void;
  apply_entity(buf: buffer, all_variants?: defined[][]): void;

  apply_ownership_grant(buf: buffer, all_variants?: defined[][]): void;

  has_ownership(entity: Entity, component: Entity): boolean;
  request_set<T>(
    entity: Entity,
    component: Entity<T>,
    value: T,
    unreliable?: boolean,
  ): void;
  collect_ownership(): IterableFunction<
    LuaTuple<[buffer, defined[][] | undefined]>
  >;
  collect_ownership_unreliable(): IterableFunction<
    LuaTuple<[buffer, defined[][] | undefined]>
  >;

  generate_handshake(): HandshakeInfo;
  verify_handshake(
    handshake: HandshakeInfo,
  ): LuaTuple<[true]> | LuaTuple<[false, string]>;
}
```

## Replecs Top-Level

```ts
interface ReplecsLib {
  client: Client;
  server: Server;

  after_replication(callback: () => void): void;
  register_custom_id(custom_id: CustomId): void;

  set_serdes<T extends Id>(
    component: InferComponent<T>,
    serdes: SerdesTable<T>,
  ): void;
  remove_serdes(component: Id): void;
}

interface Replecs extends Components {
  VERSION: string;

  create: (world?: World) => ReplecsLib;
  create_server: (world?: World) => Server;
  create_client: (world?: World) => Client;
  create_custom_id: (
    identifier: string,
    handler?: (ctx: HandleContext) => Entity,
  ) => CustomId;
}
```

## Internal Constants (for reference)

```ts
// Packet types
enum PacketType {
  full = 1,
  entity = 2,
  updates = 3,
  unreliable = 4,
  ownership = 5,
  ownership_grant = 6,
}

// Component tracking types
enum ComponentType {
  tag = 1,
  component = 2,
  pair_tag = 3,
  pair_component = 4,
  relation = 5,
  relation_component = 6,
  unreliable = 7,
  unreliable_pair = 8,
}

// Entity ID types
enum EntityIdType {
  entity = 1,
  custom_handler = 2,
  custom_id = 3,
  shared = 4,
}
```
