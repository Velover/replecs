import type { Entity, Id, InferComponent, Pair, Tag, World } from "@rbxts/jecs";

declare namespace Replecs {
  export type SerdesTable<T = any> =
    | {
        bytespan?: number;
        includes_variants?: false;
        serialize: (value: T) => buffer;
        deserialize: (buffer: buffer) => T;
      }
    | {
        bytespan?: number;
        includes_variants: true;
        serialize: (value: T) => LuaTuple<[buffer, defined[] | undefined]>;
        deserialize: (buffer: buffer, blobs: defined[] | undefined) => T;
      };

  export interface OwnershipValidator<T = any> {
    validate: (value: T) => boolean;
  }

  type MemberFilterMap = Map<Player, boolean>;
  type MemberFilter = Player | MemberFilterMap | undefined;
  type Member = unknown;

  export interface SharedInfo<T> {
    lookup: Record<string, T>;
    keys: string[];
    indexes: [T];
    members: Map<T, number>;
  }
  export interface HandleContext {
    entity_id: number;
    component: <T>(component: Entity<T>) => T;
    target: (relation: Id, index?: number) => Entity | undefined;
    pair_value: <T>(relation: Id<T>, target: Entity) => T | undefined;
    has_pair: (relation: Id, target: Entity) => boolean;

    entity: (server_entity: number) => Entity | undefined;
    has: (tag: Entity) => boolean;
  }
  export interface CustomId {
    identifier: string;
    handle_callback: (ctx: HandleContext) => Entity;
    handle(handler: (ctx: HandleContext) => Entity): void;
  }

  export interface Shared {
    components: SharedInfo<Entity>;
    custom_ids: SharedInfo<CustomId>;
    serdes: Map<Entity, SerdesTable>;
  }
  interface HandshakeSerdesInfo {
    includes_variants?: boolean;
    bytespan?: number;
  }

  export interface HandshakeInfo {
    components: Record<string, boolean>;
    custom_ids: Record<string, boolean>;
    serdes: Record<string, HandshakeSerdesInfo>;
  }

  export interface Components {
    shared: Tag;
    networked: Entity<MemberFilter>;
    reliable: Entity<MemberFilter>;
    unreliable: Entity<MemberFilter>;
    relation: Entity<MemberFilter>;
    throttle: Entity<number | undefined>;
    owned: Entity<MemberFilter>;

    serdes: Entity<SerdesTable>;
    validator: Entity<OwnershipValidator>;
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
    Validator: Entity<OwnershipValidator>;
    Custom: Entity;
    CustomHandler: Entity<(value: any) => Entity>;
    Global: Entity<number>;
  }

  export interface ClientImp {
    set_serdes<T extends Id>(
      component: T,
      serdes: SerdesTable<InferComponent<T>>,
    ): void;
    remove_serdes(component: Id): void;
    set_throttle(component: Entity, interval: number): void;
  }

  export interface Client extends ClientImp {
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

    // Simplified: bare component → auto-registers under both reliable & unreliable
    hook<T>(
      action: "changed",
      component: Id<T>,
      callback: (entity: Entity, id: Id<T>, value: T, added: boolean) => void,
    ): () => void;
    hook<T>(
      action: "removed",
      component: Id<T>,
      callback: (entity: Entity, id: Id<T>) => void,
    ): () => void;
    // Legacy: explicit pair still works
    hook<T>(
      action: "changed",
      relation: Pair<MemberFilter, T>,
      callback: (entity: Entity, id: Id<T>, value: T, added: boolean) => void,
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

    // Simplified: bare component → auto-registers under both reliable & unreliable
    override<T>(
      action: "changed",
      component: Id<T>,
      callback: (entity: Entity, id: Id<T>, value: T, added: boolean) => void,
    ): () => void;
    override<T>(
      action: "removed",
      component: Id<T>,
      callback: (entity: Entity, id: Id<T>) => void,
    ): () => void;
    // Legacy: explicit pair still works
    override<T>(
      action: "changed",
      relation: Pair<MemberFilter, T>,
      callback: (entity: Entity, id: Id<T>, value: T, added: boolean) => void,
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

  export interface ServerImp {
    set_networked(entity: Entity, filter?: MemberFilter): void;
    set_reliable(
      entity: Entity,
      component: Entity,
      filter?: MemberFilter,
    ): void;
    set_unreliable(
      entity: Entity,
      component: Entity,
      filter?: MemberFilter,
    ): void;
    set_pair(entity: Entity, id: Pair, filter?: MemberFilter): void;
    set_relation(entity: Entity, relation: Entity, filter?: MemberFilter): void;
    set_owner(entity: Entity, component: Entity, player: Player): void;
    set_throttle(component: Entity, interval: number): void;

    stop_networked(entity: Entity, keep?: boolean): void;
    stop_reliable(entity: Entity, component: Entity, keep?: boolean): void;
    stop_unreliable(entity: Entity, component: Entity, keep?: boolean): void;
    stop_pair(entity: Entity, id: Pair): void;
    stop_relation(entity: Entity, relation: Entity, keep?: boolean): void;

    set_custom(entity: Entity, handler: Entity | CustomId): void;
    remove_custom(entity: Entity): void;

    set_serdes<T extends Id>(
      component: T,
      serdes: SerdesTable<InferComponent<T>>,
    ): void;
    remove_serdes(component: Id): void;
    set_validator<T extends Id>(
      component: T,
      validator: OwnershipValidator<InferComponent<T>>,
    ): void;
    remove_validator(component: Id): void;
  }

  export interface Server extends ServerImp {
    world: World;
    inited?: boolean;

    init(world?: World): void;
    destroy(): void;

    encode_component(component: Entity): number;
    decode_component(encoded: number): Entity | undefined;
    get_shared_count(): number;

    register_custom_id(custom_id: CustomId): void;

    get_full(
      player: Player,
    ): LuaTuple<[buffer, defined[][] | undefined, buffer?, defined[][]?]>;
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

  export interface InterpolatorConfig {
    max_snapshots?: number;
    base_delay?: number;
    jitter_smoothing?: number;
  }

  export interface Interpolator {
    /** Register a lerp function for a component type. */
    register<T>(component: Entity<T>, lerp: (a: T, b: T, t: number) => T): void;

    /** Push a new snapshot. Call from a hook/override callback. */
    push<T>(entity: Entity, component: Entity<T>, value: T, time: number): void;

    /** Get the interpolated value. Returns undefined if no snapshots exist. */
    get<T>(entity: Entity, component: Entity<T>): T | undefined;

    /** Remove all buffered state for an entity. */
    remove_entity(entity: Entity): void;

    /** Remove buffered state for a specific component on an entity. */
    remove_component(entity: Entity, component: Entity): void;

    /** Returns base_delay + current jitter. */
    get_delay(): number;
  }

  export interface ReplecsLib {
    client: Client;
    server: Server;

    after_replication(callback: () => void): void;
    register_custom_id(custom_id: CustomId): void;

    set_serdes<T extends Id>(
      component: T,
      serdes: SerdesTable<InferComponent<T>>,
    ): void;
    remove_serdes(component: Id): void;
    set_validator<T extends Id>(
      component: T,
      validator: OwnershipValidator<InferComponent<T>>,
    ): void;
    remove_validator(component: Id): void;
    set_throttle(component: Entity, interval: number): void;
  }

  export interface Replecs extends Components {
    VERSION: string;

    create: (world?: World) => ReplecsLib;
    create_server: (world?: World) => Server;
    create_client: (world?: World) => Client;
    create_custom_id: (
      identifier: string,
      handler?: (ctx: HandleContext) => Entity,
    ) => CustomId;
    create_interpolation: (config?: InterpolatorConfig) => Interpolator;
  }
}

declare const Replecs: Replecs.Replecs;

export = Replecs;
