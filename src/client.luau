--!optimize 2
--!native

local common = require "./common"
local types = require "./types"
local customid = require "./customid"
local utils = require "./utils"

local cursor = utils.cursor

local NIL_OWNERSHIP_VALUE = newproxy()

type Cursor = utils.Cursor
type CustomId = customid.CustomId

type Entity = common.Entity
type Component<T = any> = common.Component<T>
type World = common.World

type Array<T> = { T }
type Map<K, V> = { [K]: V }
type Set<T> = { [T]: boolean }
type Disconnect = () -> ()

type CommandBuffer = {
	tags: Set<Component>,
	components: Map<Component, { value: any }>,
	unreliable_components: Map<Component, { value: any }>,
	remove: Set<Component>,

	pairs_add: { [Component]: Set<Entity> },
	pairs_set: { [Component]: Map<Entity, { value: any }> },
	pairs_unprocessed: {
		[Component]: Map<Entity, {
			cursor: Cursor,
			variants: { any }?,
			processed_value: { value: any }?,
		}>,
	},
	pairs_remove: { [Component]: Set<Entity> },
	relations_clear: Set<Component>,
}

type HookMethod =
	& ((
		self: Client,
		action: "changed",
		relation: Component,
		callback: (entity: Entity, id: Component, value: any, added: boolean) -> ()
	) -> Disconnect)
	& ((
		self: Client,
		action: "removed",
		relation: Component,
		callback: (entity: Entity, id: Component) -> ()
	) -> Disconnect)
	& (self: Client, action: "deleted", entity: Entity, callback: (entity: Entity) -> ()) -> Disconnect

type ChangedHooksEntry = {
	overrides: boolean,
	callbacks: Array<(entity: Entity, id: Component, value: any, added: boolean) -> ()>,
}
type RemovedHooksEntry = {
	overrides: boolean,
	callbacks: Array<(entity: Entity, id: Component) -> ()>,
}
type DeletedHookEntry = {
	overrides: boolean,
	callbacks: Array<(entity: Entity) -> ()>,
}

type CustomIdMap = { [Entity]: CustomId | Entity }

export type ClientImp = {
	set_serdes: <T>(self: Client, id: Component<T>, serdes: types.Serdes<T>) -> (),
	remove_serdes: (self: Client, id: Component) -> (),
	set_throttle: (self: Client, component: Component, interval: number) -> (),
}

export type Client = ClientImp & {
	world: World,
	inited: boolean?,

	is_replicating: boolean,
	after_replication_callbacks: { () -> () },

	is_shared_dirty: boolean,
	requires_shared_lookup: { Entity },
	components: types.Components,
	shared: types.Shared,
	global_handler: ((id: number) -> Entity)?,
	server_ids: { [number]: Entity },
	client_ids: { [Entity]: number },
	command_buffers: { [Entity]: CommandBuffer }?,
	command_buffers_active: boolean,

	registered_custom_ids: { [CustomId]: boolean },
	component_serdes: Map<Component, types.Serdes>,

	ownership_grants: Map<Entity, Map<Component, boolean>>,
	ownership_buffer: Map<Entity, Map<Component, any>>,
	ownership_unreliable_buffer: Map<Entity, Map<Component, any>>,
	ownership_throttle: Map<
		Component,
		{ last_flush: number, interval: number, values: Map<Entity, any>, unreliable: Map<Entity, boolean> }
	>,

	init: (self: Client, world: World?) -> (),
	destroy: (self: Client) -> (),
	handle_global: (self: Client, handler: (id: number) -> Entity) -> (),
	get_server_entity: (self: Client, client_entity: Entity) -> number?,
	get_client_entity: (self: Client, server_entity: number) -> Entity?,

	register_entity: (self: Client, entity: Entity, server_entity: number) -> (),
	unregister_entity: (self: Client, entity: Entity) -> (),

	hooked: Array<() -> ()>,

	after_replication: (self: Client, callback: () -> ()) -> (),
	added: (self: Client, callback: (entity: Entity) -> ()) -> Disconnect,
	hook: HookMethod,
	override: HookMethod,
	addition_hooks: Array<(entity: Entity) -> ()>,
	network_hooks: {
		deleted: { [Entity]: DeletedHookEntry },
		changed: { [Component]: ChangedHooksEntry },
		removed: { [Component]: RemovedHooksEntry },
	},

	encode_component: (self: Client, component: Entity) -> number,
	decode_component: (self: Client, component: number) -> Entity,
	get_shared_count: (self: Client) -> number,

	register_custom_id: (self: Client, custom_id: CustomId) -> (),

	apply_full: (self: Client, buf: buffer, all_variants: { { any } }?) -> (),
	apply_entity: (self: Client, buf: buffer, all_variants: { { any } }?) -> (),
	apply_updates: (self: Client, buf: buffer, all_variants: { { any } }?) -> (),
	apply_unreliable: (self: Client, buf: buffer, all_variants: { { any } }?) -> (),

	apply_ownership_grant: (self: Client, buf: buffer, all_variants: { { any } }?) -> (),
	has_ownership: (self: Client, entity: Entity, component: Component) -> boolean,
	request_set: (self: Client, entity: Entity, component: Component, value: any, unreliable: boolean?) -> (),
	collect_ownership: (self: Client) -> () -> (buffer, { { any } }),
	collect_ownership_unreliable: (self: Client) -> () -> (buffer, { { any } }),

	generate_handshake: (self: Client) -> types.HandshakeInfo,
	verify_handshake: (self: Client, handshake: types.HandshakeInfo) -> (boolean, string?),
}

local client_replicator = {}
client_replicator.__index = client_replicator

local GLOBAL_ID_OFFSET = 10

local ENTITY_ID_TYPES = {
	entity = 1,
	custom_handler = 2,
	custom_id = 3,
	shared = 4,
}
local PACKET_TYPES = {
	full = 1,
	entity = 2,
	updates = 3,
	unreliable = 4,
	ownership = 5,
	ownership_grant = 6,
}

local ECS_NAME = common.ecs_name
local ECS_WILDCARD = common.wildcard
local PAIR = common.pair
local IS_PAIR = common.is_pair
local ITERATE_ALL_RELATIONS = common.iterate_all_relations
local WORLD_ENTITY = common.world_entity
local WORLD_ADD = common.world_add
local WORLD_SET = common.world_set
local WORLD_REMOVE = common.world_remove
local WORLD_GET = common.world_get
local WORLD_HAS = common.world_has
local WORLD_DELETE = common.world_delete

local HOOK_ADDED = common.hook_added
local HOOK_CHANGED = common.hook_changed
local HOOK_REMOVED = common.hook_removed

local function QUERY_CURRENT_COMPONENTS(client: Client)
	for component, serdes in client.world:query(client.components.serdes):iter() do
		client.component_serdes[component] = serdes
	end
end

local function get_or_create_entity(client: Client, server_id: number): Entity
	local world = client.world

	local server_entity = client.server_ids[server_id]
	if server_entity then
		return server_entity
	else
		local entity = WORLD_ENTITY(world)
		WORLD_ADD(world, entity, client.components.__alive_tracking__)

		client.server_ids[server_id] = entity
		client.client_ids[entity] = server_id

		for _, callback in client.addition_hooks do
			callback(entity)
		end

		return entity
	end
end

local function get_or_create_command_buffer(client: Client, entity: Entity): CommandBuffer
	local command_buffers = client.command_buffers

	if not command_buffers then
		error "attempted to use a command buffer without being active. (this should never happen)"
	end

	local command_buffer = command_buffers[entity :: any]
	if not command_buffer then
		command_buffer = {
			tags = {},
			components = {},
			unreliable_components = {},
			remove = {},
			pairs_add = {},
			pairs_set = {},
			pairs_unprocessed = {},
			pairs_remove = {},
			relations_clear = {},
		}
		command_buffers[entity :: any] = command_buffer
	end
	return command_buffer
end

function client_replicator.entity_set(
	client: Client,
	entity: Entity,
	id: Component,
	value: any,
	changed_hooks: ChangedHooksEntry?
)
	if client.command_buffers_active then
		local command_buffer = get_or_create_command_buffer(client, entity)
		command_buffer.components[id] = { value = value }
	else
		-- skip replicated changes for owned components (owner already has latest)
		-- but allow initial sync (component doesn't exist yet) and overrides
		local entity_grants = client.ownership_grants[entity]
		local is_owned = entity_grants and entity_grants[id]
		local is_change = WORLD_HAS(client.world, entity, id)
		local has_override = changed_hooks and changed_hooks.overrides

		if is_owned and is_change and not has_override then
			return
		end

		local added = not is_change

		if changed_hooks then
			if not changed_hooks.overrides then
				WORLD_SET(client.world, entity, id, value)
			end
			for _, callback in changed_hooks.callbacks do
				callback(entity, id, value, added)
			end
		else
			WORLD_SET(client.world, entity, id, value)
		end
	end
end

function client_replicator.entity_add(client: Client, entity: Entity, tag: Entity, changed_hooks: ChangedHooksEntry?)
	if client.command_buffers_active then
		local command_buffer = get_or_create_command_buffer(client, entity)
		command_buffer.tags[tag] = true
	else
		-- skip replicated changes for owned tags (owner already has latest)
		-- but allow initial sync (tag doesn't exist yet) and overrides
		local entity_grants = client.ownership_grants[entity]
		local is_owned = entity_grants and entity_grants[tag]
		local is_change = WORLD_HAS(client.world, entity, tag)
		local has_override = changed_hooks and changed_hooks.overrides

		if is_owned and is_change and not has_override then
			return
		end

		local added = not is_change

		if changed_hooks then
			if not changed_hooks.overrides then
				WORLD_ADD(client.world, entity, tag)
			end
			for _, callback in changed_hooks.callbacks do
				callback(entity, tag, nil, added)
			end
		else
			WORLD_ADD(client.world, entity, tag)
		end
	end
end

function client_replicator.entity_set_unreliable(
	client: Client,
	entity: Entity,
	id: Entity,
	value: any,
	changed_hooks: ChangedHooksEntry?
)
	if client.command_buffers_active then
		local command_buffer = get_or_create_command_buffer(client, entity)
		command_buffer.unreliable_components[id] = { value = value }
	else
		if WORLD_HAS(client.world, entity, id) then
			client_replicator.entity_set(client, entity, id, value, changed_hooks)
		end
	end
end

function client_replicator.entity_set_pair(
	client: Client,
	entity: Entity,
	relation: Entity,
	target: Entity,
	value: any,
	changed_hooks: ChangedHooksEntry?
)
	if client.command_buffers_active then
		local command_buffer = get_or_create_command_buffer(client, entity)
		local pair_relation = command_buffer.pairs_set[relation]

		if pair_relation then
			pair_relation[target] = { value = value }
		else
			command_buffer.pairs_set[relation] = { [target] = { value = value } }
		end
	else
		client_replicator.entity_set(client, entity, PAIR(relation, target), value, changed_hooks)
	end
end

function client_replicator.entity_add_pair(
	client: Client,
	entity: Entity,
	relation: Entity,
	target: Entity,
	changed_hooks: ChangedHooksEntry?
)
	if client.command_buffers_active then
		local command_buffer = get_or_create_command_buffer(client, entity)
		local pair_relation = command_buffer.pairs_add[relation]

		if pair_relation then
			pair_relation[target] = true
		else
			command_buffer.pairs_add[relation] = { [target] = true }
		end
	else
		client_replicator.entity_add(client, entity, PAIR(relation, target), changed_hooks)
	end
end

function client_replicator.entity_set_postponed_pair(
	client: Client,
	entity: Entity,
	relation: Component,
	target: Entity,
	c: Cursor,
	variants: { any }?
): any
	if client.command_buffers_active then
		local commmand_buffer = get_or_create_command_buffer(client, entity)
		local pairs_unprocessed = commmand_buffer.pairs_unprocessed
		local pair_relation = pairs_unprocessed[relation]
		if pair_relation then
			pair_relation[target] = {
				cursor = c,
				variants = variants,
			}
		else
			pairs_unprocessed[relation] = {
				[target] = {
					cursor = c,
					variants = variants,
				},
			}
		end
		return nil
	else
		local pair_id, value = client_replicator.read_pair_value(client, relation, target, c, variants)
		-- TODO: respect hooks
		WORLD_SET(client.world, entity, pair_id, value)
		return value
	end
end

function client_replicator.entity_remove(client: Client, entity: Entity, id: Entity, removed_hooks: RemovedHooksEntry?)
	if client.command_buffers_active then
		local command_buffer = get_or_create_command_buffer(client, entity)
		command_buffer.remove[id] = true
	else
		if removed_hooks then
			for _, callback in removed_hooks.callbacks do
				callback(entity, id)
			end
			if not removed_hooks.overrides then
				WORLD_REMOVE(client.world, entity, id)
			end
		else
			WORLD_REMOVE(client.world, entity, id)
		end
	end

	-- clean up ownership data for this component on this entity
	local entity_grants = client.ownership_grants[entity]
	if entity_grants then
		entity_grants[id] = nil
	end
	local entity_buffer = client.ownership_buffer[entity]
	if entity_buffer then
		entity_buffer[id] = nil
	end
	local entity_unreliable_buffer = client.ownership_unreliable_buffer[entity]
	if entity_unreliable_buffer then
		entity_unreliable_buffer[id] = nil
	end
end

function client_replicator.entity_remove_pair(
	client: Client,
	entity: Entity,
	relation: Entity,
	target: Entity,
	removed_hooks: RemovedHooksEntry?
)
	if client.command_buffers_active then
		local command_buffer = get_or_create_command_buffer(client, entity)
		local pair_relation = command_buffer.pairs_remove[relation]

		if pair_relation then
			pair_relation[target] = true
		else
			command_buffer.pairs_remove[relation] = { [target] = true }
		end
	else
		client_replicator.entity_remove(client, entity, PAIR(relation, target), removed_hooks)
	end
end

function client_replicator.entity_clear_relation(
	client: Client,
	entity: Entity,
	relation: Entity,
	removed_hooks: RemovedHooksEntry?
)
	if client.command_buffers_active then
		local command_buffer = get_or_create_command_buffer(client, entity)
		command_buffer.relations_clear[relation] = true
	else
		local world = client.world
		if removed_hooks then
			ITERATE_ALL_RELATIONS(world, entity, relation, function(pair)
				for _, callback in removed_hooks.callbacks do
					callback(entity, pair)
				end
				if not removed_hooks.overrides then
					WORLD_REMOVE(world, entity, pair)
				end
			end)
		else
			ITERATE_ALL_RELATIONS(world, entity, relation, function(pair)
				WORLD_REMOVE(world, entity, pair)
			end)
		end
	end
end

local function read_variant_value(c: Cursor, serdes: types.Serdes?, variants: { any }?)
	if serdes then
		local bytespan = serdes.bytespan or cursor.read_vlq(c)

		local appended = cursor.read_buffer(c, bytespan)
		local serdes_variants: { any }? = nil

		if serdes.includes_variants then
			local start_variant = cursor.read_vlq(c)

			if start_variant > 0 then
				local size = cursor.read_vlq(c)
				serdes_variants = table.move(variants :: { any }, start_variant, start_variant + size - 1, 1, {})
			end
		end

		local output = serdes.deserialize(appended, serdes_variants :: any)
		return output
	else
		local variant_id = cursor.read_vlq(c)
		if variant_id == 0 then
			return nil
		end
		local value = (variants :: { any })[variant_id]
		return value
	end
end

function client_replicator.read_pair_value(
	client: Client,
	relation: Component,
	target: Entity,
	c: Cursor,
	variants: { any }?
)
	local pair_id = PAIR(relation, target)
	local pair_wildcard = PAIR(relation, ECS_WILDCARD)
	local serdes = client.component_serdes[pair_id] or client.component_serdes[pair_wildcard]
	local value = read_variant_value(c, serdes, variants)
	return pair_id, value
end

function client_replicator.read_component_value(
	client: Client,
	component: Component,
	c: Cursor,
	variants: { any }?
): any
	local serdes = client.shared.serdes[component]

	if serdes then
		local bytespan = serdes.bytespan or cursor.read_vlq(c)

		local appended = cursor.read_buffer(c, bytespan)
		local serdes_variants: { any }? = nil

		if serdes.includes_variants then
			local start_variant = cursor.read_vlq(c)

			if start_variant > 0 then
				local size = cursor.read_vlq(c)
				serdes_variants = table.move(variants :: { any }, start_variant, start_variant + size - 1, 1, {})
			end
		end

		local output = serdes.deserialize(appended, serdes_variants :: any)
		return output
	else
		local variant_id = cursor.read_vlq(c)
		if variant_id == 0 then
			return nil
		end
		local value = (variants :: { any })[variant_id]
		return value
	end
end

function client_replicator.read_component_id(client: Client, c: Cursor): Entity
	local shared_components = client.shared.components
	local shared_id = cursor.read_span(c, #shared_components.keys)
	local component = shared_components.indexes[shared_id]
	if not component then
		print("NON SHARED COMPONENT", shared_id, client.shared.components)
		error "received a non shared component"
	end
	return component
end

function client_replicator.resolve_global(client: Client, global_id: number): Entity
	if not client.global_handler then
		error "global id parser not set, consider using client:handle_global()"
	end
	local parsed = client.global_handler(global_id)
	return parsed
end

-- returns entity, server_id, id_type
function client_replicator.read_entity_id(client: Client, c: Cursor): (Entity?, number?, number?)
	local id_type = cursor.readu8(c)

	if id_type <= GLOBAL_ID_OFFSET then
		if
			id_type == ENTITY_ID_TYPES.entity
			or id_type == ENTITY_ID_TYPES.custom_id
			or id_type == ENTITY_ID_TYPES.custom_handler
		then
			local server_id = cursor.readu40(c)
			return client.server_ids[server_id], server_id, id_type
		elseif id_type == ENTITY_ID_TYPES.shared then
			return client_replicator.read_component_id(client, c), nil, id_type
		end
		error(`malformed entity type {id_type} ` .. cursor.readu32(c))
	else
		return client_replicator.resolve_global(client, id_type - GLOBAL_ID_OFFSET), nil, id_type
	end
end

local function read_vlq_bitmask(c: Cursor, mask: number, bit: number): number
	if utils.checkbit(mask, bit) then
		return cursor.read_vlq(c)
	else
		return 0
	end
end

function client_replicator.process_entity_id(
	client: Client,
	c: Cursor,
	custom_ids: CustomIdMap,
	process: (entity: Entity) -> ()
)
	local entity, server_id, id_type = client_replicator.read_entity_id(client, c)

	if entity then
		-- skip customid, keep cursor offset
		if id_type == ENTITY_ID_TYPES.custom_id then
			client_replicator.read_component_id(client, c)
		elseif id_type == ENTITY_ID_TYPES.custom_handler then
			cursor.readu8(c)
		end

		return process(entity)
	else
		if id_type == ENTITY_ID_TYPES.custom_id or id_type == ENTITY_ID_TYPES.custom_handler then
			if id_type == ENTITY_ID_TYPES.custom_id then
				local component_id = client_replicator.read_component_id(client, c)
				custom_ids[server_id :: any] = component_id
			elseif id_type == ENTITY_ID_TYPES.custom_handler then
				local shared_custom_id = cursor.readu8(c)
				local handler = client.shared.custom_ids.indexes[shared_custom_id]

				if not handler then
					common.log_error "attempted to use a custom id that wasn't registered"
				end
				custom_ids[server_id :: any] = handler
			end

			if client.command_buffers_active then
				-- negative id means it's a custom id,
				-- it needs to be translated first
				process(-server_id :: any)
			else
				client.command_buffers_active = true
				process(-server_id :: any)
				client.command_buffers_active = false
			end
		else
			local new_entity = get_or_create_entity(client, server_id :: number)
			process(new_entity)
		end
	end
end

function client_replicator.process_entity_relations(client: Client, entity: Entity, c: Cursor, custom_ids: CustomIdMap)
	local components = client.components
	local relation = client_replicator.read_component_id(client, c)
	local total_targets = cursor.read_vlq(c)
	local pair_hooks = client.network_hooks.changed[PAIR(components.relation, relation)]

	for _ = 1, total_targets do
		client_replicator.process_entity_id(client, c, custom_ids, function(target)
			client_replicator.entity_add_pair(client, entity, relation, target, pair_hooks)
		end)
	end
end

function client_replicator.process_entity_relation_values(
	client: Client,
	entity: Entity,
	c: Cursor,
	custom_ids: CustomIdMap,
	variants: { any }?
)
	local relation = client_replicator.read_component_id(client, c)
	local total_targets = cursor.read_vlq(c)
	local components = client.components
	local relation_hooks = client.network_hooks.changed[PAIR(components.relation, relation)]

	for _ = 1, total_targets do
		local value = client_replicator.read_component_value(client, relation, c, variants)
		client_replicator.process_entity_id(client, c, custom_ids, function(target)
			client_replicator.entity_set_pair(client, entity, relation, target, value, relation_hooks)
		end)
	end
end

function client_replicator.process_entity_pair_value(
	client: Client,
	entity: Entity,
	c: Cursor,
	custom_ids: CustomIdMap,
	variants: { any }?
)
	local relation = client_replicator.read_component_id(client, c)
	client_replicator.process_entity_id(client, c, custom_ids, function(target)
		if (target :: any) > 0 then
			local pointer_offset = cursor.read_vlq(c)
			local jump_offset = c.offset - pointer_offset

			local _, value = client_replicator.read_pair_value(client, relation, target, c, variants)
			client_replicator.entity_set_pair(client, entity, relation, target, value)

			c.offset = jump_offset
		else
			local frozen_cursor = cursor.from_offset(c.buffer, c.offset)

			local pointer_offset = cursor.read_vlq(c)
			c.offset -= pointer_offset

			client_replicator.entity_set_postponed_pair(client, entity, relation, target, frozen_cursor, variants)
		end
	end)
end

function client_replicator.process_entity_pair(client: Client, entity: Entity, c: Cursor, custom_ids: CustomIdMap)
	local relation = client_replicator.read_component_id(client, c)
	client_replicator.process_entity_id(client, c, custom_ids, function(target)
		-- TODO: respect hooks/overrides
		client_replicator.entity_add_pair(client, entity, relation, target)
	end)
end

function client_replicator.process_entity(
	client: Client,
	entity: Entity,
	c: Cursor,
	custom_ids: CustomIdMap,
	variants: { any }?
)
	local mask = cursor.readu8(c)
	local changed_hooks = client.network_hooks.changed
	local components = client.components

	local total_tags = read_vlq_bitmask(c, mask, 0)
	for _ = 1, total_tags do
		local tag = client_replicator.read_component_id(client, c)
		local tag_hooks = changed_hooks[PAIR(components.reliable, tag)]
		client_replicator.entity_add(client, entity, tag, tag_hooks)
	end

	local total_components = read_vlq_bitmask(c, mask, 1)
	for _ = 1, total_components do
		local component = client_replicator.read_component_id(client, c)
		local value = client_replicator.read_component_value(client, component, c, variants)
		local component_hooks = changed_hooks[PAIR(components.reliable, component)]
		client_replicator.entity_set(client, entity, component, value, component_hooks)
	end

	local total_pairs = read_vlq_bitmask(c, mask, 2)
	for _ = 1, total_pairs do
		client_replicator.process_entity_pair(client, entity, c, custom_ids)
	end

	local total_pair_values = read_vlq_bitmask(c, mask, 3)
	for _ = 1, total_pair_values do
		client_replicator.process_entity_pair_value(client, entity, c, custom_ids, variants)
	end

	local total_relations = read_vlq_bitmask(c, mask, 4)
	for _ = 1, total_relations do
		client_replicator.process_entity_relations(client, entity, c, custom_ids)
	end

	local total_relation_values = read_vlq_bitmask(c, mask, 5)
	for _ = 1, total_relation_values do
		client_replicator.process_entity_relation_values(client, entity, c, custom_ids, variants)
	end
end

function client_replicator.finish_replication(client: Client)
	client.is_replicating = false
	for _, callback in client.after_replication_callbacks do
		callback()
	end
	table.clear(client.after_replication_callbacks)
end

function client_replicator.resolve_dirty(client: Client)
	if client.is_shared_dirty then
		-- stylua: ignore
		client.shared = utils.resolved_shared(
			client.world,
			client.components,
			client.registered_custom_ids,
			client.component_serdes
		)
		client.is_shared_dirty = false
	end
end

local function check_packet_type(c: Cursor, expected_byte: number)
	local got_byte = cursor.readu8(c)
	if got_byte ~= expected_byte then
		local got_type: string? = nil
		local expected_type: string? = nil

		for packet_type, byte in PACKET_TYPES :: { [string]: number } do
			if byte == got_byte then
				got_type = packet_type
			elseif byte == expected_byte then
				expected_type = packet_type
			end
		end
		common.log_error(
			`packet type mismatch, expected: {expected_type or "(unknown)"} got: {got_type or "(unknown)"} instead`
		)
	end
end

function client_replicator.apply_command_buffer(
	client: Client,
	entity: Entity,
	command_buffer: CommandBuffer,
	request: (e: Entity, ...any) -> Entity?
)
	local components = client.components

	for tag in command_buffer.tags do
		local tag_hooks = client.network_hooks.changed[PAIR(components.reliable, tag)]
		client_replicator.entity_add(client, entity, tag, tag_hooks)
	end
	for component, value in command_buffer.components do
		local component_hooks = client.network_hooks.changed[PAIR(components.reliable, component)]
		client_replicator.entity_set(client, entity, component, value.value, component_hooks)
	end
	for component, value in command_buffer.unreliable_components do
		local component_hooks = client.network_hooks.changed[PAIR(components.unreliable, component)]
		client_replicator.entity_set(client, entity, component, value.value, component_hooks)
	end
	for component in command_buffer.remove do
		local component_hooks = client.network_hooks.removed[PAIR(components.reliable, component)]
		client_replicator.entity_remove(client, entity, component, component_hooks)
	end
	for relation, targets in command_buffer.pairs_add do
		local relation_hooks = client.network_hooks.changed[PAIR(components.relation, relation)]
		for target in targets do
			local client_target = request(target)
			if client_target then
				client_replicator.entity_add_pair(client, entity, relation, client_target, relation_hooks)
			end
		end
	end
	for relation, targets in command_buffer.pairs_set do
		local relation_hooks = client.network_hooks.changed[PAIR(components.relation, relation)]
		for target, value in targets do
			local client_target = request(target)
			if client_target then
				client_replicator.entity_set_pair(client, entity, relation, client_target, value.value, relation_hooks)
			end
		end
	end
	for relation, targets in command_buffer.pairs_unprocessed do
		-- TODO: respect hooks
		for target, unprocessed in targets do
			local client_target = request(target)
			if client_target then
				local processed_value = unprocessed.processed_value
				if processed_value then
					client_replicator.entity_set_pair(client, entity, relation, client_target, processed_value.value)
				else
					local value = client_replicator.entity_set_postponed_pair(
						client,
						entity,
						relation,
						client_target,
						unprocessed.cursor,
						unprocessed.variants
					)
					unprocessed.processed_value = { value = value }
				end
			end
		end
	end

	for relation, targets in command_buffer.pairs_remove do
		local relation_hooks = client.network_hooks.removed[PAIR(components.relation, relation)]
		for target in targets do
			local client_target = request(target)
			if client_target then
				client_replicator.entity_remove_pair(client, entity, relation, client_target, relation_hooks)
			end
		end
	end
	for relation in command_buffer.relations_clear do
		local relation_hooks = client.network_hooks.removed[PAIR(components.relation, relation)]
		client_replicator.entity_clear_relation(client, entity, relation, relation_hooks)
	end
end

function client_replicator.find_component_in_buffer(command_buffer: CommandBuffer, component: Entity): { value: any }?
	return command_buffer.components[component] or command_buffer.unreliable_components[component]
end

function client_replicator.find_has_in_buffer(command_buffer: CommandBuffer, tag: Entity): boolean
	return (command_buffer.tags[tag] ~= nil)
		or (command_buffer.components[tag] ~= nil)
		or (command_buffer.unreliable_components[tag] ~= nil)
end

function client_replicator.find_pair_in_buffer(
	command_buffer: CommandBuffer,
	relation: Entity,
	target: Entity,
	find: (unprocessed_entity: Entity) -> (Entity?, Entity)
): (boolean, any)
	local value_relations = command_buffer.pairs_set[relation]
	if value_relations then
		for buffer_target, value in value_relations do
			local found = find(buffer_target)
			if found == target then
				return true, value.value
			end
		end
	end

	local relations = command_buffer.pairs_add[relation]
	if relations then
		for buffer_target in relations do
			local found = find(buffer_target)
			if found == target then
				return true, nil
			end
		end
	end

	local unprocessed_relations = command_buffer.pairs_unprocessed[relation]
	if unprocessed_relations then
		for buffer_target, unprocessed in unprocessed_relations do
			local found = find(buffer_target)
			if found == target then
				local processed_value = unprocessed.processed_value
				return true, processed_value and processed_value.value
			end
		end
	end

	return false, nil
end

function client_replicator.find_target_in_buffer(
	command_buffer: CommandBuffer,
	relation: Entity,
	index: number?
): Entity?
	local i = 0

	local pairs = command_buffer.pairs_add[relation]
	if pairs then
		for target in pairs do
			if i == (index or 0) then
				return target
			end
			i += 1
		end
	end

	local pairs_values = command_buffer.pairs_set[relation]
	if pairs_values then
		for target in pairs_values do
			if i == (index or 0) then
				return target
			end
			i += 1
		end
	end

	local unprocessed_pairs = command_buffer.pairs_unprocessed[relation]
	if unprocessed_pairs then
		for target in unprocessed_pairs do
			if i == (index or 0) then
				return target
			end
			i += 1
		end
	end

	return nil
end

function client_replicator.finish_custom_ids(
	client: Client,
	custom_ids: CustomIdMap,
	command_buffers: { [Entity]: CommandBuffer }
)
	local world = client.world
	local funcs = {} -- this is so process can use create_context even if its defined after
	local processed: { [Entity]: boolean } = {}

	local function find(unprocessed_entity: Entity): (Entity?, Entity)
		-- negative entities means they are still server ids that haven't been processed yet
		if (unprocessed_entity :: any) > 0 then
			return unprocessed_entity, unprocessed_entity
		end
		local server_entity = -(unprocessed_entity :: any)
		local client_entity = client.server_ids[server_entity]
		if client_entity then
			return client_entity, server_entity
		end
		return nil, server_entity
	end

	local function process(unprocessed_entity: Entity, custom_handler: (CustomId | Entity)?): Entity?
		local client_entity, server_entity = find(unprocessed_entity)
		if client_entity then
			return client_entity
		end

		if processed[server_entity] then
			return nil
		end

		local new_entity: Entity? = nil
		local command_buffer = command_buffers[unprocessed_entity :: any]
		custom_handler = custom_handler or custom_ids[server_entity]

		if type(custom_handler) == "number" then
			local component: Entity = custom_handler :: any

			local handler = WORLD_GET(world, component, client.components.custom_handler)
			if not handler then
				return common.log_error(
					`received a custom id for a non custom component, consider adding custom_handler to component: {common.log_component(
						world,
						component
					)}`
				)
			end
			if command_buffer then
				local value = client_replicator.find_component_in_buffer(command_buffer, component)
				if value then
					new_entity = handler(value.value)
				else
					common.log_warn(`No component found for custom id handler: {common.log_component(world, component)}`)
					new_entity = handler(nil)
				end
			else
				common.log_warn(`No component found for custom id handler: {common.log_component(world, component)}`)
				new_entity = handler(nil)
			end
		else
			local handle_callback = (custom_handler :: CustomId).handle_callback
			if not handle_callback then
				return common.log_error(
					"no handler callback was set for custom id:",
					(custom_handler :: CustomId).identifier
				)
			end
			new_entity = handle_callback(funcs.create_context(unprocessed_entity))
		end

		if new_entity then
			WORLD_ADD(world, new_entity, client.components.__alive_tracking__)

			client.server_ids[server_entity :: any] = new_entity
			client.client_ids[new_entity] = server_entity :: any

			if command_buffer then
				client_replicator.apply_command_buffer(client, new_entity, command_buffer, process)
				command_buffers[unprocessed_entity] = nil
			end
		end

		processed[server_entity] = true
		return new_entity
	end

	local function create_context(unprocessed_entity: Entity)
		local command_buffer = command_buffers[unprocessed_entity]

		local function component(component: Entity): any
			if not command_buffer then
				return nil
			end
			local val = client_replicator.find_component_in_buffer(command_buffer, component)
			return val and val.value
		end
		local function target(relation: Entity, index: number?): Entity
			if not command_buffer then
				return nil :: any
			end
			local server_target = client_replicator.find_target_in_buffer(command_buffer, relation, index)
			if server_target then
				return process(server_target :: any) :: Entity
			end
			return nil :: any
		end
		local function pair_value(relation: Entity, target: Entity): any
			if not command_buffer then
				return nil :: any
			end
			local _, value = client_replicator.find_pair_in_buffer(command_buffer, relation, target, find)
			return value
		end
		local function has_pair(relation: Entity, target: Entity): boolean
			if not command_buffer then
				return nil :: any
			end
			local has = client_replicator.find_pair_in_buffer(command_buffer, relation, target, find)
			return has
		end
		local function has(tag: Entity): boolean
			if not command_buffer then
				return nil :: any
			end
			return client_replicator.find_has_in_buffer(command_buffer, tag)
		end
		local function entity(server_entity: number): Entity
			return process(-server_entity :: any) :: Entity
		end

		local context: customid.HandleContext = {
			entity_id = math.abs(unprocessed_entity :: any),
			has = has,
			component = component,
			target = target,
			pair_value = pair_value,
			has_pair = has_pair,
			entity = entity,
		}

		return context
	end
	funcs.create_context = create_context

	for entity, custom_handler in custom_ids do
		process(-(entity :: any), custom_handler)
	end

	for entity, command_buffer in command_buffers do
		if (entity :: any) < 0 then
			continue
		end
		client_replicator.apply_command_buffer(client, entity, command_buffer, process)
	end
end

function client_replicator.apply_full(client: Client, buf: buffer, all_variants: { { any } }?)
	client_replicator.resolve_dirty(client)
	client.is_replicating = true

	local c = cursor.from(buf)
	check_packet_type(c, PACKET_TYPES.full)

	local total_packets = cursor.read_vlq(c)
	local variant_start = (all_variants and #all_variants + 1) :: number

	local command_buffers: { [Entity]: CommandBuffer } = {}
	local custom_ids: CustomIdMap = {}

	client.command_buffers = command_buffers

	for a = 1, total_packets do
		local total_entities = cursor.read_vlq(c)
		local variants = all_variants and all_variants[variant_start - a]

		for _ = 1, total_entities do
			client_replicator.process_entity_id(client, c, custom_ids, function(entity)
				client_replicator.process_entity(client, entity, c, custom_ids, variants)
			end)
		end
	end

	client_replicator.finish_custom_ids(client, custom_ids, command_buffers)
	client_replicator.finish_replication(client)
end

function client_replicator.apply_entity(client: Client, buf: buffer, all_variants: { { any } })
	client_replicator.resolve_dirty(client)
	client.is_replicating = true

	local c = cursor.from(buf)
	check_packet_type(c, PACKET_TYPES.entity)

	local total_packets = cursor.read_vlq(c)
	local variant_start = (all_variants and #all_variants + 1) :: number

	local command_buffers: { [Entity]: CommandBuffer } = {}
	local custom_ids: CustomIdMap = {}

	client.command_buffers = command_buffers

	for a = 1, total_packets do
		local variants = all_variants and all_variants[variant_start - a]

		client_replicator.process_entity_id(client, c, custom_ids, function(entity)
			client_replicator.process_entity(client, entity, c, custom_ids, variants)
		end)
	end

	client_replicator.finish_custom_ids(client, custom_ids, command_buffers)
	client_replicator.finish_replication(client)
end

function client_replicator.apply_updates(client: Client, buf: buffer, all_variants: { { any } }?)
	client_replicator.resolve_dirty(client)
	client.is_replicating = true

	local c = cursor.from(buf)
	check_packet_type(c, PACKET_TYPES.updates)

	local world = client.world
	local components = client.components
	local total_packets = cursor.read_vlq(c)
	local variant_start = (all_variants and #all_variants + 1) :: number
	local changed_hooks = client.network_hooks.changed
	local removed_hooks = client.network_hooks.removed
	local deleted_hooks = client.network_hooks.deleted

	local command_buffers: { [Entity]: CommandBuffer } = {}
	local custom_ids: CustomIdMap = {}

	client.command_buffers = command_buffers

	for a = 1, total_packets do
		local variants = all_variants and all_variants[variant_start - a]
		local storage_mask = cursor.readu8(c)

		local total_added = read_vlq_bitmask(c, storage_mask, 0)
		for _ = 1, total_added do
			client_replicator.process_entity_id(client, c, custom_ids, function(entity)
				client_replicator.process_entity(client, entity, c, custom_ids, variants)
			end)
		end

		local total_components_added = read_vlq_bitmask(c, storage_mask, 1)
		for _ = 1, total_components_added do
			client_replicator.process_entity_id(client, c, custom_ids, function(entity)
				local added_mask = cursor.readu8(c)

				local total_tags = read_vlq_bitmask(c, added_mask, 0)
				for _ = 1, total_tags do
					local tag = client_replicator.read_component_id(client, c)
					local tag_hooks = changed_hooks[PAIR(components.reliable, tag)]
					client_replicator.entity_add(client, entity, tag, tag_hooks)
				end

				local total_components = read_vlq_bitmask(c, added_mask, 1)
				for _ = 1, total_components do
					local component = client_replicator.read_component_id(client, c)
					local value = client_replicator.read_component_value(client, component, c, variants)
					local component_hooks = changed_hooks[PAIR(components.reliable, component)]
					client_replicator.entity_set(client, entity, component, value, component_hooks)
				end

				local total_pairs = read_vlq_bitmask(c, added_mask, 2)
				for _ = 1, total_pairs do
					client_replicator.process_entity_pair(client, entity, c, custom_ids)
				end

				local total_pair_values = read_vlq_bitmask(c, added_mask, 3)
				for _ = 1, total_pair_values do
					client_replicator.process_entity_pair_value(client, entity, c, custom_ids, variants)
				end

				local total_relations = read_vlq_bitmask(c, added_mask, 4)
				for _ = 1, total_relations do
					client_replicator.process_entity_relations(client, entity, c, custom_ids)
				end

				local total_relation_values = read_vlq_bitmask(c, added_mask, 5)
				for _ = 1, total_relation_values do
					client_replicator.process_entity_relation_values(client, entity, c, custom_ids, variants)
				end
			end)
		end

		local total_changed = read_vlq_bitmask(c, storage_mask, 2)
		for _ = 1, total_changed do
			client_replicator.process_entity_id(client, c, custom_ids, function(entity)
				local changed_mask = cursor.readu8(c)

				local total_tagged = read_vlq_bitmask(c, changed_mask, 0)
				for _ = 1, total_tagged do
					local tag = client_replicator.read_component_id(client, c)
					local tag_hooks = changed_hooks[PAIR(components.reliable, tag)]
					client_replicator.entity_add(client, entity, tag, tag_hooks)
				end

				local total_components = read_vlq_bitmask(c, changed_mask, 1)
				for _ = 1, total_components do
					local component = client_replicator.read_component_id(client, c)
					local value = client_replicator.read_component_value(client, component, c, variants)
					local component_hooks = changed_hooks[PAIR(components.reliable, component)]
					client_replicator.entity_set(client, entity, component, value, component_hooks)
				end

				local total_removed = read_vlq_bitmask(c, changed_mask, 2)
				for _ = 1, total_removed do
					local component = client_replicator.read_component_id(client, c)
					local component_hooks = removed_hooks[PAIR(components.reliable, component)]
					client_replicator.entity_remove(client, entity, component, component_hooks)
				end

				local total_pairs_added = read_vlq_bitmask(c, changed_mask, 3)
				for _ = 1, total_pairs_added do
					client_replicator.process_entity_pair(client, entity, c, custom_ids)
				end

				local total_pairs_set = read_vlq_bitmask(c, changed_mask, 4)
				for _ = 1, total_pairs_set do
					client_replicator.process_entity_pair_value(client, entity, c, custom_ids, variants)
				end

				local total_pairs_removed = read_vlq_bitmask(c, changed_mask, 5)
				for _ = 1, total_pairs_removed do
					local relation = client_replicator.read_component_id(client, c)
					client_replicator.process_entity_id(client, c, custom_ids, function(target)
						-- TODO: respect hooks/overrides
						client_replicator.entity_remove_pair(client, entity, relation, target)
					end)
				end

				local total_relations_added = read_vlq_bitmask(c, changed_mask, 6)
				for _ = 1, total_relations_added do
					local relation = client_replicator.read_component_id(client, c)
					local total_targets = cursor.read_vlq(c)
					local pair_changed_hooks = changed_hooks[PAIR(components.relation, relation)]

					for _ = 1, total_targets do
						client_replicator.process_entity_id(client, c, custom_ids, function(target)
							client_replicator.entity_add_pair(client, entity, relation, target, pair_changed_hooks)
						end)
					end
				end

				local total_relation_values = read_vlq_bitmask(c, changed_mask, 7)
				for _ = 1, total_relation_values do
					local relation = client_replicator.read_component_id(client, c)
					local total_targets = cursor.read_vlq(c)
					local pair_changed_hooks = changed_hooks[PAIR(components.relation, relation)]

					for _ = 1, total_targets do
						local value = client_replicator.read_component_value(client, relation, c, variants)
						client_replicator.process_entity_id(client, c, custom_ids, function(target)
							client_replicator.entity_set_pair(client, entity, relation, target, value, pair_changed_hooks)
						end)
					end
				end

				-- using a normal vlq here sadly
				-- cause I ran out of bitmask space for this one :/
				local total_relations_removed = cursor.read_vlq(c)
				for _ = 1, total_relations_removed do
					local relation = client_replicator.read_component_id(client, c)
					local total_targets = cursor.read_vlq(c)
					local pair_removed_hooks = removed_hooks[PAIR(components.relation, relation)]

					for _ = 1, total_targets do
						client_replicator.process_entity_id(client, c, custom_ids, function(target)
							client_replicator.entity_remove_pair(client, entity, relation, target, pair_removed_hooks)
						end)
					end
				end
			end)
		end

		local total_component_deletions = read_vlq_bitmask(c, storage_mask, 3)
		for _ = 1, total_component_deletions do
			client_replicator.process_entity_id(client, c, custom_ids, function(entity)
				local total_components = cursor.read_vlq(c)
				for _ = 1, total_components do
					local component = client_replicator.read_component_id(client, c)
					local component_hooks = removed_hooks[PAIR(components.reliable, component)]
					client_replicator.entity_remove(client, entity, component, component_hooks)
				end

				local total_pairs = cursor.read_vlq(c)
				for _ = 1, total_pairs do
					local relation = client_replicator.read_component_id(client, c)
					client_replicator.process_entity_id(client, c, custom_ids, function(target)
						-- TODO: respect hooks/overrides
						client_replicator.entity_remove_pair(client, entity, relation, target)
					end)
				end

				local total_relations = cursor.read_vlq(c)
				for _ = 1, total_relations do
					local relation = client_replicator.read_component_id(client, c)
					local pair_hooks = removed_hooks[PAIR(components.relation, relation)]
					client_replicator.entity_clear_relation(client, entity, relation, pair_hooks)
				end
			end)
		end

		local total_deleted = read_vlq_bitmask(c, storage_mask, 4)
		for _ = 1, total_deleted do
			local entity, server_id = client_replicator.read_entity_id(client, c)
			if entity then
				local deleted_hook = deleted_hooks[entity]
				if deleted_hook then
					for _, callback in deleted_hook.callbacks do
						callback(entity)
					end
					if not deleted_hook.overrides then
						WORLD_DELETE(world, entity)
					end
				else
					WORLD_DELETE(world, entity)
				end
			end
			if server_id then
				client.server_ids[server_id] = nil
			end
		end
	end

	client_replicator.finish_custom_ids(client, custom_ids, command_buffers)
	client_replicator.finish_replication(client)
end

function client_replicator.apply_unreliable(client: Client, buf: buffer, all_variants: { { any } }?)
	client_replicator.resolve_dirty(client)
	client.is_replicating = true

	local c = cursor.from(buf)
	check_packet_type(c, PACKET_TYPES.unreliable)

	local components = client.components
	local total_packets = cursor.read_vlq(c)
	local variant_start = (all_variants and #all_variants + 1) :: number
	local changed_hooks = client.network_hooks.changed

	for a = 1, total_packets do
		local total_entities = cursor.read_vlq(c)
		local variants = all_variants and all_variants[variant_start - a]

		for _ = 1, total_entities do
			local entity = client_replicator.read_entity_id(client, c)
			local total_unreliable = cursor.read_vlq(c)

			if entity then
				for _ = 1, total_unreliable do
					local component = client_replicator.read_component_id(client, c)
					local value = client_replicator.read_component_value(client, component, c, variants)

					local unreliable_hooks = changed_hooks[PAIR(components.unreliable, component)]
					client_replicator.entity_set_unreliable(client, entity, component, value, unreliable_hooks)
				end
			else
				-- dont apply unreliable updates to entities that dont exist in the client yet
				-- but we still need to process the values to keep the cursor in the right place
				for _ = 1, total_unreliable do
					local component = client_replicator.read_component_id(client, c)
					client_replicator.read_component_value(client, component, c, variants)
				end
			end
		end
	end

	client_replicator.finish_replication(client)
end

function client_replicator.write_component_id(client: Client, c: Cursor, component: Entity)
	local shared_components = client.shared.components
	local encoded = shared_components.members[component]
	if not encoded then
		common.log_error(`attempted to write a non-shared component `, common.log_component(client.world, component))
		return
	end
	cursor.write_span(c, encoded, #shared_components.keys)
end

function client_replicator.write_variant_value(
	client: Client,
	c: Cursor,
	log_component: Component,
	serdes: types.Serdes?,
	value: any,
	variants: { any }
)
	if serdes then
		local output, serdes_variants = serdes.serialize(value)

		if serdes.includes_variants then
			if serdes_variants == nil then
				cursor.writeu8(c, 128)
			else
				local start_variants = #variants
				if #serdes_variants > 0 then
					table.move(serdes_variants, 1, #serdes_variants, #variants + 1, variants)
				end
				cursor.write_vlq(c, #serdes_variants)
				cursor.write_vlq(c, start_variants + 1)
			end
		elseif serdes_variants ~= nil then
			common.log_error(
				"serdes: serializer provided variants yet includes_variants is not set to true for component: ",
				common.log_component(client.world, log_component)
			)
		end

		local bytespan = serdes.bytespan
		cursor.write_buffer(c, output)
		if bytespan then
			if bytespan ~= buffer.len(output) then
				common.log_error(
					`bytespan: {bytespan} mismatch for buffer length: {buffer.len(output)} in component: `,
					common.log_component(client.world, log_component)
				)
			end
		else
			local len = buffer.len(output)
			cursor.write_vlq(c, len)
		end
	else
		if value == nil then
			cursor.writeu8(c, 128)
		else
			table.insert(variants, value :: any)
			cursor.write_vlq(c, #variants)
		end
	end
end

function client_replicator.write_component_value(
	client: Client,
	c: Cursor,
	component: Component,
	value: any,
	variants: { any }
)
	local serdes = client.component_serdes[component] or client.shared.serdes[component]
	client_replicator.write_variant_value(client, c, component, serdes, value, variants)
end

function client_replicator.write_entity_id(client: Client, c: Cursor, entity: Entity)
	local server_id = client.client_ids[entity]
	if server_id then
		cursor.writeu40(c, server_id)
		cursor.writeu8(c, ENTITY_ID_TYPES.entity)
	else
		-- shared component entity
		local shared_id = client.shared.components.members[entity]
		if shared_id then
			cursor.writeu8(c, shared_id)
			cursor.writeu8(c, ENTITY_ID_TYPES.shared)
		else
			common.log_error(`attempted to write an entity that has no server id or shared id: {entity}`)
		end
	end
end

function client_replicator.apply_ownership_grant(client: Client, buf: buffer, all_variants: { { any } }?)
	client_replicator.resolve_dirty(client)
	client.is_replicating = true

	local c = cursor.from(buf)
	check_packet_type(c, PACKET_TYPES.ownership_grant)

	-- clear old grants
	table.clear(client.ownership_grants)

	local total_packets = cursor.read_vlq(c)

	for _a = 1, total_packets do
		local total_grants = cursor.read_vlq(c)
		for _ = 1, total_grants do
			local entity, _server_id, _id_type = client_replicator.read_entity_id(client, c)
			local component = client_replicator.read_component_id(client, c)

			if entity then
				local entity_grants = client.ownership_grants[entity]
				if not entity_grants then
					entity_grants = {}
					client.ownership_grants[entity] = entity_grants
				end
				entity_grants[component] = true
			end
		end
	end

	client_replicator.finish_replication(client)
end

function client_replicator.has_ownership(client: Client, entity: Entity, component: Component): boolean
	local entity_grants = client.ownership_grants[entity]
	if not entity_grants then
		return false
	end
	return entity_grants[component] == true
end

function client_replicator.request_set(
	client: Client,
	entity: Entity,
	component: Component,
	value: any,
	unreliable: boolean?
)
	local entity_grants = client.ownership_grants[entity]
	if not entity_grants or not entity_grants[component] then
		common.log_warn(`cannot set component: entity does not have ownership grant for this component`)
		return
	end

	-- set locally for immediate client-side prediction
	WORLD_SET(client.world, entity, component, value)

	-- check throttle: buffer instead of sending immediately
	local throttle_entry = client.ownership_throttle[component]
	if throttle_entry then
		throttle_entry.values[entity] = if value == nil then NIL_OWNERSHIP_VALUE else value
		throttle_entry.unreliable[entity] = unreliable == true
		return
	end

	local target_buffer = if unreliable then client.ownership_unreliable_buffer else client.ownership_buffer
	local entity_buffer = target_buffer[entity]
	if not entity_buffer then
		entity_buffer = {}
		target_buffer[entity] = entity_buffer
	end
	entity_buffer[component] = if value == nil then NIL_OWNERSHIP_VALUE else value
end

local function collect_ownership_from_buffer(
	client: Client,
	source_buffer: Map<Entity, Map<Component, any>>,
	packet_type: number
): () -> (buffer, { { any } })
	client_replicator.resolve_dirty(client)
	local packets: Array<{ buffer: buffer, variants: { any } }> = {}
	local total_size = 0

	for entity, components_map in source_buffer do
		local c = cursor.new()
		local variants = {} :: Array<{ any }>
		local total_entries = 0

		for component, raw_value in components_map do
			local value = if raw_value == NIL_OWNERSHIP_VALUE then nil else raw_value
			-- write in LIFO order: value first, component_id, entity_id last
			client_replicator.write_component_value(client, c, component, value, variants)
			client_replicator.write_component_id(client, c, component)
			client_replicator.write_entity_id(client, c, entity)
			total_entries += 1
		end

		if total_entries > 0 then
			cursor.write_vlq(c, total_entries)
			local output = cursor.close(c)
			table.insert(packets, { buffer = output, variants = variants })
			total_size += buffer.len(output)
		end
	end

	table.clear(source_buffer)

	if #packets == 0 then
		return function()
			return nil :: any
		end
	end

	local combined = buffer.create(total_size + utils.vlq_span(#packets) + 1)
	local offset = 0
	local all_variants: { { any } } = {}

	for _, packet in packets do
		buffer.copy(combined, offset, packet.buffer)
		offset += buffer.len(packet.buffer)
		table.insert(all_variants, packet.variants)
	end

	-- write total packets and packet type
	local c_temp = { offset = offset, buffer = combined }
	cursor.write_vlq(c_temp, #packets)
	buffer.writeu8(combined, buffer.len(combined) - 1, packet_type)

	local done = false
	return function()
		if done then
			return nil :: any
		end
		done = true
		return combined, all_variants
	end
end

local function flush_ownership_throttle(client: Client)
	local now = os.clock()
	for component, throttle_entry in client.ownership_throttle do
		if now - throttle_entry.last_flush >= throttle_entry.interval then
			throttle_entry.last_flush = now
			for entity, raw_value in throttle_entry.values do
				local target_buffer = if throttle_entry.unreliable[entity]
					then client.ownership_unreliable_buffer
					else client.ownership_buffer
				local entity_buffer = target_buffer[entity]
				if not entity_buffer then
					entity_buffer = {}
					target_buffer[entity] = entity_buffer
				end
				entity_buffer[component] = raw_value
			end
			table.clear(throttle_entry.values)
			table.clear(throttle_entry.unreliable)
		end
	end
end

function client_replicator.collect_ownership(client: Client)
	flush_ownership_throttle(client)
	return collect_ownership_from_buffer(client, client.ownership_buffer, PACKET_TYPES.ownership)
end

function client_replicator.collect_ownership_unreliable(client: Client)
	flush_ownership_throttle(client)
	return collect_ownership_from_buffer(client, client.ownership_unreliable_buffer, PACKET_TYPES.ownership)
end

function client_replicator.set_serdes(client: Client, component: Component, serdes: types.Serdes)
	client.component_serdes[component] = serdes
	client.is_shared_dirty = true
end

function client_replicator.remove_serdes(client: Client, component: Component)
	client.component_serdes[component] = nil
	client.is_shared_dirty = true
end

function client_replicator.set_throttle(client: Client, component: Component, interval: number)
	client.ownership_throttle[component] = {
		last_flush = os.clock(),
		interval = interval,
		values = {},
		unreliable = {},
	}
end

-- TODO: Deserialize pairs in client

function client_replicator.init(client: Client, wrd: World?)
	if client.inited == true then
		return warn "attempted to init a client twice"
	end
	if client.inited == nil then
		return warn "attempted to re-init a destroyed client"
	end
	client.inited = true :: any

	local world = wrd or client.world
	client.world = world

	if not world then
		error "Providing a world is required to start replecs"
	end

	if not client.components then
		client.components = utils.create_components(utils.tag_factory(world), utils.component_factory(world))
		utils.add_component_names(client.components, function(component, name)
			common.add_name(world, component, name)
		end)
	end

	local components = client.components

	local function hook(unhook: () -> ())
		table.insert(client.hooked, unhook)
	end

	hook(HOOK_REMOVED(world, components.__alive_tracking__, function(entity)
		local server_id = client.client_ids[entity]
		if server_id then
			client.server_ids[server_id] = nil
			client.client_ids[entity] = nil
		end
		client.network_hooks.deleted[entity] = nil
		client.ownership_grants[entity] = nil
		client.ownership_buffer[entity] = nil
		client.ownership_unreliable_buffer[entity] = nil
		for _, throttle_entry in client.ownership_throttle do
			throttle_entry.values[entity] = nil
			throttle_entry.unreliable[entity] = nil
		end
	end))

	hook(HOOK_ADDED(world, components.serdes, function(component, _, serdes)
		client_replicator.set_serdes(client, component, serdes)
	end))
	hook(HOOK_CHANGED(world, components.serdes, function(component, _, serdes)
		client_replicator.set_serdes(client, component, serdes)
	end))
	hook(HOOK_REMOVED(world, components.serdes, function(component)
		client_replicator.remove_serdes(client, component)
	end))

	for _, component in client.requires_shared_lookup do
		hook(HOOK_ADDED(world, component, function()
			client.is_shared_dirty = true
		end))
		hook(HOOK_REMOVED(world, component, function()
			client.is_shared_dirty = true
		end))
	end

	QUERY_CURRENT_COMPONENTS(client)

	client.shared = utils.resolved_shared(world, components, client.registered_custom_ids, client.component_serdes)
end

function client_replicator.after_replication(client: Client, callback: () -> ())
	if client.is_replicating then
		table.insert(client.after_replication_callbacks, callback)
	else
		callback()
	end
end

function client_replicator.added(client: Client, callback: (entity: Entity) -> ())
	table.insert(client.addition_hooks, callback)
	return function()
		local index = table.find(client.addition_hooks, callback)
		if index then
			table.remove(client.addition_hooks, index)
		end
	end
end

local function add_hook_entry(client: Client, action: string, ...): ({ overrides: boolean }, () -> ())
	if action == "changed" or action == "removed" then
		local id = select(1, ...) :: Entity
		local callback = select(2, ...) :: (entity: Entity, id: Component, value: any, added: boolean) -> ()
		local hooks = action == "changed" and client.network_hooks.changed or client.network_hooks.removed

		-- Bare component → register under reliable + unreliable + relation pairs
		-- Pair → register under that pair only (backward compatible)
		local keys: { Entity }
		if IS_PAIR(id) then
			keys = { id }
		else
			keys = {
				PAIR(client.components.reliable, id),
				PAIR(client.components.unreliable, id),
				PAIR(client.components.relation, id),
			}
		end

		local entries_list: { ChangedHooksEntry } = {}

		for _, key in keys do
			local entries = hooks[key] :: ChangedHooksEntry
			if not entries then
				entries = {
					overrides = false,
					callbacks = {},
				}
				hooks[key] = entries
			end
			table.insert(entries_list, entries)
			table.insert(entries.callbacks, callback)
		end

		local function disconnect()
			for i, key in keys do
				local entries = entries_list[i]
				local callbacks = entries.callbacks
				local index = table.find(callbacks, callback)
				if index then
					table.remove(callbacks, index)
					if #callbacks == 0 then
						hooks[key] = nil
					end
				end
			end
		end
		return entries_list[1], disconnect
	elseif action == "deleted" then
		local entity = select(1, ...) :: Entity
		local callback = select(2, ...) :: (entity: Entity) -> ()
		local hooks = client.network_hooks.deleted
		local entries = hooks[entity]

		if not entries then
			entries = {
				overrides = false,
				callbacks = {},
			}
			hooks[entity] = entries
		end
		table.insert(entries.callbacks, callback)

		local function disconnect()
			local callbacks = entries.callbacks
			local index = table.find(callbacks, callback)
			if index then
				table.remove(callbacks, index)
				if #callbacks == 0 then
					hooks[entity] = nil
				end
			end
		end
		return entries, disconnect
	else
		error("invalid hook action: " .. action)
	end
end

function client_replicator.hook(client: Client, action: string, ...)
	local entry, disconnect = add_hook_entry(client, action, ...)
	entry.overrides = false
	return disconnect
end
function client_replicator.override(client: Client, action: string, ...)
	local entry, disconnect = add_hook_entry(client, action, ...)
	entry.overrides = true
	return disconnect
end

function client_replicator.encode_component(client: Client, component: Entity): number
	client_replicator.resolve_dirty(client)
	local encoded = client.shared.components.members[component]
	if not encoded then
		common.log_error(`attempted to encode a non-shared component `, common.log_component(client.world, component))
		return 0
	end
	return encoded
end

function client_replicator.decode_component(client: Client, encoded: number): Entity
	client_replicator.resolve_dirty(client)
	local component = client.shared.components.indexes[encoded]
	if not component then
		print("NON SHARED COMPONENT", encoded, client.shared.components)
		error "attemped to decode a non shared component"
	end
	return component
end

function client_replicator.get_shared_count(client: Client): number
	client_replicator.resolve_dirty(client)
	return #client.shared.components.keys
end

function client_replicator.get_server_entity(client: Client, client_entity: Entity): number?
	return client.client_ids[client_entity]
end

function client_replicator.get_client_entity(client: Client, client_entity: number): Entity?
	return client.server_ids[client_entity]
end

function client_replicator.register_entity(client: Client, entity: Entity, server_entity: number)
	client.server_ids[server_entity] = entity
	client.client_ids[entity] = server_entity
	WORLD_ADD(client.world, entity, client.components.__alive_tracking__)
end

function client_replicator.unregister_entity(client: Client, entity: Entity)
	local server_id = client.client_ids[entity]
	if server_id then
		client.server_ids[server_id] = nil
		client.client_ids[entity] = nil
	end
end

function client_replicator.register_custom_id(client: Client, custom_id: CustomId)
	client.registered_custom_ids[custom_id] = true
	client.is_shared_dirty = true
end

function client_replicator.generate_handshake(client: Client): types.HandshakeInfo
	client_replicator.resolve_dirty(client)
	return utils.generate_handshake(client.shared)
end

function client_replicator.verify_handshake(client: Client, handshake: types.HandshakeInfo): (boolean, string?)
	client_replicator.resolve_dirty(client)
	return utils.verify_handshake(client.shared, handshake, "server", "client")
end

function client_replicator.destroy(client: Client)
	if client.inited == nil then
		return warn "attempted to destroy a client twice"
	end
	client.inited = nil :: any
	for _, unhook in client.hooked do
		unhook()
	end
end

function client_replicator.handle_global(client: Client, handler: (id: number) -> Entity)
	client.global_handler = handler
end

local function create(world: World?, components: types.Components?): Client
	local self = {} :: Client

	if components then
		self.components = components
	elseif world then
		self.components = utils.create_components(utils.tag_factory(world), utils.component_factory(world))
		utils.add_component_names(self.components, function(component, name)
			common.add_name(world, component, name)
		end)
	end

	self.server_ids = {}
	self.client_ids = {}
	self.is_shared_dirty = false
	self.component_serdes = {}
	self.requires_shared_lookup = {
		self.components.shared,
		ECS_NAME,
	}
	self.global_handler = nil
	self.world = world :: any
	self.inited = false
	self.is_replicating = false
	self.hooked = {}
	self.registered_custom_ids = {}

	self.ownership_grants = {}
	self.ownership_buffer = {}
	self.ownership_unreliable_buffer = {}
	self.ownership_throttle = {}

	self.addition_hooks = {}
	self.network_hooks = {
		deleted = {},
		changed = {},
		removed = {},
	}
	self.after_replication_callbacks = {}

	return setmetatable(self, client_replicator) :: any
end

return {
	create = create,
	client_replicator = client_replicator,
}
