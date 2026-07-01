local replecs = require "@replecs"
local player_masking = require "@replecs/masking"
local utils = require "@replecs/utils"

local jecs = require "@pkg/jecs"
local testlib = require "./testlib"

local plan = testlib.plan()
local expect = testlib.expect

local TEST, CASE = plan.TEST, plan.CASE
local SKIP, FOCUS = plan.SKIP, plan.FOCUS
local BEFORE_EACH, AFTER_EACH = plan.BEFORE_EACH, plan.AFTER_EACH
local CHECK = assert

type Entity<T = any> = jecs.Entity<T>

type MemberData = {
	world: jecs.World,
	client: replecs.Client,
	components: { jecs.Entity },
	tags: { jecs.Entity },
}

TEST("bitmasking", function()
	CASE("should automatically expand", function()
		local mask = utils.bitmask.create(10)
		mask:set(5)

		CHECK(mask:get(5) == true)
		mask:set(100)
		CHECK(mask:get(100) == true)
		CHECK(mask:get(32) == false)
		CHECK(mask:get(5) == true)
	end)

	CASE("should get and set bits", function()
		local mask = utils.bitmask.create(100)
		mask:set(5)
		mask:set(33)
		mask:set(65)

		CHECK(mask:get(5) == true)
		CHECK(mask:get(33) == true)
		CHECK(mask:get(65) == true)
		CHECK(mask:get(10) == false)

		mask:clear(33)
		CHECK(mask:get(5) == true)
		CHECK(mask:get(33) == false)
		CHECK(mask:get(65) == true)
	end)

	CASE("should correctly shift bits", function()
		local mask = utils.bitmask.create(100)
		mask:set(5)
		mask:set(40)
		mask:set(65)

		local left = mask:lshift(3)
		local right = mask:rshift(2)

		CHECK(left:get(5 + 3) == true)
		CHECK(left:get(40 + 3) == true)
		CHECK(left:get(65 + 3) == true)
		CHECK(left:get(65) == false)

		CHECK(right:get(5 - 2) == true)
		CHECK(right:get(40 - 2) == true)
		CHECK(right:get(65 - 2) == true)
		CHECK(right:get(65) == false)
	end)

	CASE("should correctly perform bitwise operations", function()
		local mask1 = utils.bitmask.create(100)
		local mask2 = utils.bitmask.create(100)

		mask1:set(5)
		mask1:set(10)
		mask1:set(20)
		mask1:set(40)
		mask1:set(65)

		mask2:set(10)
		mask2:set(40)
		mask2:set(50)

		local band = mask1:band(mask2)
		CHECK(band:get(5) == false)
		CHECK(band:get(10) == true)
		CHECK(band:get(20) == false)
		CHECK(band:get(40) == true)
		CHECK(band:get(50) == false)
		CHECK(band:get(65) == false)

		local bor = mask1:bor(mask2)
		CHECK(bor:get(5) == true)
		CHECK(bor:get(10) == true)
		CHECK(bor:get(20) == true)
		CHECK(bor:get(40) == true)
		CHECK(bor:get(50) == true)
		CHECK(bor:get(65) == true)
		CHECK(bor:get(100) == false)

		local bxor = mask1:bxor(mask2)
		CHECK(bxor:get(5) == true)
		CHECK(bxor:get(10) == false)
		CHECK(bxor:get(20) == true)
		CHECK(bxor:get(40) == false)
		CHECK(bxor:get(50) == true)
		CHECK(bxor:get(65) == true)
		CHECK(bxor:get(100) == false)
	end)

	CASE("should return same string, independant of buffer capacity", function()
		local small = utils.bitmask.create(32)
		local medium = utils.bitmask.create(128)
		local big = utils.bitmask.create(1024)
		local empty = utils.bitmask.create(1024)

		small:set(0)
		small:set(10)
		medium:set(0)
		medium:set(10)
		big:set(0)
		big:set(10)

		CHECK(small:tostring() == medium:tostring())
		CHECK(small:tostring() == big:tostring())
		CHECK(medium:tostring() == big:tostring())
		CHECK(empty:tostring() == "")
	end)
end)

local function register_members(masking: player_masking.MaskingController)
	local member0 = "member0"
	local member1 = "member1"
	local member2 = "member2"
	local member3 = "member3"

	masking:register_client(member0)
	masking:register_client(member1)
	masking:register_client(member2)
	masking:register_client(member3)
	return member0, member1, member2, member3
end

local function mask_hash(members: { number })
	local bitmask = utils.bitmask.create(20)
	for _, member in members do
		bitmask:set(member)
	end
	return bitmask:tostring()
end

local function active_all_members(masking: player_masking.MaskingController)
	for member in masking.client_indexes do
		masking:activate_client(member)
	end
end

TEST("mask generators", function()
	local masking: player_masking.MaskingController = nil :: any

	BEFORE_EACH(function()
		masking = player_masking.create()
	end)

	CASE("should compute an include generator", function()
		local m0, m1, m2, m3 = register_members(masking)
		local generator = masking:create_include_generator {
			[m0] = true,
			[m1] = true,
			[m2] = true,
			[m3] = true,
		}
		local check_mask = ""
		local called = 0

		generator.subscribed = function()
			called += 1
			CHECK(generator.result:tostring() == check_mask)
		end
		generator:run_subscribed()
		check_mask = mask_hash { 0 }
		masking:activate_client(m0)
		check_mask = mask_hash { 0, 3 }
		masking:activate_client(m3)
	end)

	CASE("should compute an exclude generator", function()
		local m0, m1, m2, m3 = register_members(masking)
		local generator = masking:create_exclude_generator {
			[m2] = true,
			[m1] = true,
		}

		local check_mask = ""
		local called = 0
		generator.subscribed = function()
			called += 1
			CHECK(generator.result:tostring() == check_mask)
		end
		check_mask = mask_hash { 0 }
		masking:activate_client(m0)
		check_mask = mask_hash { 0, 3 }
		masking:activate_client(m3)
		masking:activate_client(m2)
		masking:activate_client(m1)
		CHECK(called == 4)
	end)

	CASE("should destroy a generator", function()
		local m0, m1, m2, m3 = register_members(masking)

		local generator = masking:create_exclude_generator {
			[1] = true,
		}
		local called = 0
		generator.subscribed = function()
			called += 1
		end
		masking:activate_client(m0)
		generator:destroy()
		masking:activate_client(m1)
		masking:activate_client(m2)
		masking:activate_client(m3)
		CHECK(called == 1)
	end)
end)

TEST("member bitmasking", function()
	local masking: player_masking.MaskingController = nil :: any
	local world: jecs.World = nil :: any

	BEFORE_EACH(function()
		masking = player_masking.create() :: player_masking.MaskingController
		world = jecs.world()
	end)

	local function SANITY_CHECKS()
		-- heuristic sanity checks
		local entity_masks: { [jecs.Entity]: boolean } = {}

		for hash, storage in masking.storages do
			local real_active_count = 0

			for entity, actives in storage.active do
				if actives.is_entity_mask then
					local lookup = masking.lookups.entities[entity]
					if lookup.storage_group ~= storage then
						error "marked mask entity does not match the lookup"
					end

					real_active_count += 1
					if entity_masks[entity] then
						error "duplicated base entity mask"
					end
					entity_masks[entity] = true
				elseif actives.component_count > 0 then
					real_active_count += 1
				end

				local real_component_count = 0
				for component_type, components in actives.components do
					for component in components do
						real_component_count += 1
					end
				end
				CHECK(real_component_count == actives.component_count)
			end
			CHECK(real_active_count == storage.active_count)
		end

		for hash, storage in masking.storages do
			for entity, components in storage.shared_with do
				for component_type, components in components do
					for component in components do
						local lookup = masking.lookups.entities[entity].filtered_components[component_type][component]
						CHECK(lookup.storage_group == storage)
					end
				end
			end
		end
	end

	local function check_entity_mask(entity: jecs.Entity, hash: string)
		local storage = masking.storages[hash]
		local lookup = masking.lookups.entities[entity]

		CHECK(lookup ~= nil)
		CHECK(lookup.storage_group == storage)

		CHECK(storage.active[entity] ~= nil)
		CHECK((storage.active[entity].is_entity_mask :: any) ~= nil)

		for check_hash, check_storage in masking.storages do
			if hash == check_hash then
				continue
			end

			if check_storage.active[entity] then
				CHECK(check_storage.active[entity].is_entity_mask == false)
			end
		end
	end
	local function check_component_mask(entity: jecs.Entity, component: jecs.Entity, hash: string)
		local storage = masking.storages[hash]
		local lookup = masking.lookups.entities[entity].filtered_components[1][component]

		CHECK(lookup ~= nil)
		CHECK(lookup.storage_group == storage)

		CHECK(storage.active[entity] ~= nil)
		CHECK(storage.active[entity].components[1][component] ~= nil)

		CHECK(storage.shared_with[entity] ~= nil)
		CHECK(storage.shared_with[entity][1][component] ~= nil)

		for check_hash, check_storage in masking.storages do
			if hash == check_hash then
				continue
			end

			if check_storage.active[entity] then
				CHECK(check_storage.active[entity].components[1][component] == nil)
			end
			if check_storage.shared_with[entity] then
				CHECK(check_storage.shared_with[entity][1][component] == nil)
			end
		end
	end

	local function check_component_is_merged(entity: jecs.Entity, component: jecs.Entity, hash: string)
		local entity_lookup = masking.lookups.entities[entity :: any]
		if not entity_lookup then
			error "entity lookup not found"
		end

		CHECK(entity_lookup.storage_group == masking.storages[hash])

		CHECK(entity_lookup.filtered_components[1][component] == nil)
		CHECK(entity_lookup.storage_group.active[entity].components[1][component] ~= nil)
		CHECK(entity_lookup.storage_group.active[entity].is_entity_mask == true)

		for _, check_storage in masking.storages do
			if check_storage.shared_with[entity] then
				CHECK(check_storage.shared_with[entity][1][component] == nil)
			end
		end
	end

	local function check_component_is_not_active(entity: jecs.Entity, component: jecs.Entity)
		local entity_lookup = masking.lookups.entities[entity]
		if entity_lookup then
			CHECK(entity_lookup.filtered_components[1][component] == nil)
		end

		for hash, check_storage in masking.storages do
			if check_storage.shared_with[entity] then
				CHECK(check_storage.shared_with[entity][1][component] == nil)
			end
			for _, actives in check_storage.active do
				for check_component in actives.components[1] do
					if check_component == component then
						error("component found in active storage" .. ": " .. hash)
					end
				end
			end
		end
	end

	local function check_entity_is_not_active(entity: jecs.Entity)
		CHECK(masking.lookups.entities[entity] == nil)

		for hash, check_storage in masking.storages do
			if check_storage.active[entity] then
				error("entity found in active storage" .. ": " .. hash)
			end
			if check_storage.shared_with[entity] then
				error("entity found in shared storage" .. ": " .. hash)
			end
			if check_storage.changes.added[entity] then
				error "entity addition found in lookup changes"
			end
			if check_storage.changes.changed[entity] then
				error "changes table for entity found in storage"
			end
		end
	end

	CASE("should use an entity filter", function()
		local member0, member1, member2 = register_members(masking)
		local entity = world:entity()
		masking:start_entity(entity, {
			[member0] = true,
			[member2] = true,
		})
		check_entity_mask(entity, "")
		active_all_members(masking)
		check_entity_mask(entity, mask_hash { 0, 2 })

		local entity2 = world:entity()
		masking:start_entity(entity2, {
			[member0] = false,
			[member2] = false,
		})
		check_entity_mask(entity2, mask_hash { 1, 3 })

		SANITY_CHECKS()
	end)
	--FOCUS()
	CASE("should change an entity filter", function()
		local member0, member1, member2 = register_members(masking)
		active_all_members(masking)

		local entity = world:entity()
		masking:start_entity(entity, {
			[member0] = true,
			[member2] = true,
		})
		check_entity_mask(entity, mask_hash { 0, 2 })
		masking:set_entity(entity, {
			[member0] = false,
			[member2] = false,
		})
		check_entity_mask(entity, mask_hash { 1, 3 })
		masking:set_entity(entity, nil)
		check_entity_mask(entity, mask_hash { 0, 1, 2, 3 })

		SANITY_CHECKS()
	end)

	CASE("should use the replicated filter with no explicit filter", function()
		local member0, member1, member2, member3 = register_members(masking)
		local entity = world:entity()
		masking:start_entity(entity, nil)
		check_entity_mask(entity, "")
		masking:activate_client(member0)
		check_entity_mask(entity, mask_hash { 0 })
		masking:activate_client(member1)
		check_entity_mask(entity, mask_hash { 0, 1 })
		masking:activate_client(member3)
		check_entity_mask(entity, mask_hash { 0, 1, 3 })

		SANITY_CHECKS()
	end)

	CASE("should use a component filter", function()
		local member0, member1, member2 = register_members(masking)
		active_all_members(masking)

		local entity = world:entity()
		local component = world:component()
		masking:start_entity(entity, {
			[member0] = true,
			[member1] = true,
			[member2] = true,
		})
		masking:start_component(entity, component, 1, {
			[member0] = true,
			[member1] = true,
		})
		check_component_mask(entity, component, mask_hash { 0, 1 })

		SANITY_CHECKS()
	end)
	CASE("should use a single member filter for entity", function()
		local member0, member1, member2 = register_members(masking)
		active_all_members(masking)

		local entity = world:entity()

		masking:start_entity(entity, member2)
		check_entity_mask(entity, mask_hash { 2 })
		masking:set_entity(entity, {
			[member0] = true,
			[member1] = true,
		})
		check_entity_mask(entity, mask_hash { 0, 1 })

		SANITY_CHECKS()
	end)
	CASE("should a single member filter for component", function()
		local member0, member1, member2 = register_members(masking)
		active_all_members(masking)

		local entity = world:entity()
		local component = world:component()

		masking:start_entity(entity, {
			[member0] = true,
			[member1] = true,
			[member2] = true,
		})
		masking:start_component(entity, component, 1, member1)
		check_component_mask(entity, component, mask_hash { 1 })
		masking:set_entity(entity, member2)
		check_component_mask(entity, component, "")

		SANITY_CHECKS()
	end)
	CASE("should change a component filter", function()
		local member0, member1, member2, member3 = register_members(masking)
		active_all_members(masking)

		local entity = world:entity()
		local component = world:component()
		masking:start_entity(entity, {
			[member0] = true,
			[member1] = true,
			[member2] = true,
			[member3] = true,
		})
		masking:start_component(entity, component, 1, {
			[member0] = true,
			[member1] = true,
		})
		check_component_mask(entity, component, mask_hash { 0, 1 })
		masking:set_component(entity, component, 1, {
			[member2] = true,
		})
		check_component_mask(entity, component, mask_hash { 2 })
		masking:set_component(entity, component, 1, {
			[member2] = false,
		})
		check_component_mask(entity, component, mask_hash { 0, 1, 3 })

		SANITY_CHECKS()
	end)
	CASE("should use the entity filter if no component filter is given", function()
		local member0, member1, member2 = register_members(masking)
		active_all_members(masking)

		local entity = world:entity()
		local component = world:component()
		masking:start_entity(entity, {
			[member0] = true,
			[member1] = true,
			[member2] = true,
		})
		masking:start_component(entity, component, 1, nil)
		check_component_is_merged(entity, component, mask_hash { 0, 1, 2 })
		masking:set_entity(entity, {
			[member0] = true,
		})
		check_component_is_merged(entity, component, mask_hash { 0 })
		masking:set_entity(entity, nil)
		check_component_is_merged(entity, component, mask_hash { 0, 1, 2, 3 })

		SANITY_CHECKS()
	end)

	CASE("should run band in the entity bitmask for a component filter", function()
		local member0, member1, member2 = register_members(masking)
		active_all_members(masking)

		local entity = world:entity()
		local component = world:component()
		masking:start_entity(entity, {
			[member0] = true,
			[member2] = true,
		})

		masking:start_component(entity, component, 1, {
			[member0] = true,
			[member1] = true,
		})
		check_component_mask(entity, component, mask_hash { 0 })
		masking:set_entity(entity, {
			[member0] = true,
			[member1] = true,
			[member2] = true,
		})
		check_component_mask(entity, component, mask_hash { 0, 1 })

		SANITY_CHECKS()
	end)

	CASE("should postpone a component if entity is not active", function()
		local member0, member1, member2 = register_members(masking)
		active_all_members(masking)

		local entity = world:entity()
		local component = world:component()

		masking:start_component(entity, component, 1, {
			[member0] = true,
			[member1] = true,
		})
		check_component_is_not_active(entity, component)
		CHECK(masking.lookups.postponed[entity][1][component] ~= nil)

		masking:set_component(entity, component, 1, {
			[member0] = true,
		})
		masking:start_entity(entity, {
			[member0] = true,
			[member1] = true,
			[member2] = true,
		})
		check_component_mask(entity, component, mask_hash { 0 })

		SANITY_CHECKS()
	end)

	CASE("should merge component with entity when the filter gets removed", function()
		local member0, member1, member2 = register_members(masking)
		active_all_members(masking)

		local entity = world:entity()
		local component = world:component()

		masking:start_entity(entity, {
			[member0] = true,
			[member1] = true,
			[member2] = true,
		})
		masking:start_component(entity, component, 1, {
			[member0] = true,
			[member1] = true,
		})
		check_component_mask(entity, component, mask_hash { 0, 1 })
		masking:set_component(entity, component, 1, nil)
		check_component_is_merged(entity, component, mask_hash { 0, 1, 2 })

		SANITY_CHECKS()
	end)

	CASE("should separate a component when a filter gets added when it wasnt added", function()
		local member0, member1, member2 = register_members(masking)
		active_all_members(masking)

		local entity = world:entity()
		local component = world:component()
		masking:start_entity(entity, {
			[member0] = true,
			[member1] = true,
			[member2] = true,
		})

		masking:set_component(entity, component, 1, nil)
		masking:set_component(entity, component, 1, {
			[member0] = true,
			[member1] = true,
		})
		check_component_mask(entity, component, mask_hash { 0, 1 })
		masking:set_component(entity, component, 1, nil)
		check_component_is_merged(entity, component, mask_hash { 0, 1, 2 })

		-- testing forcing to merge to the same mask
		masking:set_component(entity, component, 1, {
			[member0] = true,
			[member1] = true,
			[member2] = true,
		})
		check_component_mask(entity, component, mask_hash { 0, 1, 2 })

		SANITY_CHECKS()
	end)

	CASE("should merge components and entities when they share same mask", function()
		local member0, member1, member2 = register_members(masking)
		active_all_members(masking)

		local entity = world:entity()
		local component = world:component()

		masking:start_entity(entity, {
			[member0] = true,
			[member1] = true,
			[member2] = true,
		})
		masking:start_component(entity, component, 1, {
			[member0] = true,
			[member1] = true,
		})
		check_component_mask(entity, component, mask_hash { 0, 1 })
		masking:set_component(entity, component, 1, {
			[member0] = true,
			[member1] = true,
			[member2] = true,
		})
		check_entity_mask(entity, mask_hash { 0, 1, 2 })
		check_component_mask(entity, component, mask_hash { 0, 1, 2 })

		SANITY_CHECKS()
	end)

	CASE("should dissect components from entities when they no longer share same mask", function()
		local member0, member1, member2 = register_members(masking)
		active_all_members(masking)

		local entity = world:entity()
		local component = world:component()

		masking:start_entity(entity, {
			[member0] = true,
			[member1] = true,
		})
		masking:start_component(entity, component, 1, {
			[member0] = true,
			[member1] = true,
		})
		check_entity_mask(entity, mask_hash { 0, 1 })
		check_component_mask(entity, component, mask_hash { 0, 1 })

		-- separate the bitmasks
		masking:set_component(entity, component, 1, {
			[member0] = true,
		})
		check_component_mask(entity, component, mask_hash { 0 })
		check_entity_mask(entity, mask_hash { 0, 1 })

		-- combine again
		masking:set_component(entity, component, 1, {
			[member0] = true,
			[member1] = true,
		})
		check_component_mask(entity, component, mask_hash { 0, 1 })
		check_entity_mask(entity, mask_hash { 0, 1 })

		-- separate them by changing the entity instead
		masking:set_entity(entity, {
			[member0] = true,
			[member1] = true,
			[member2] = true,
		})
		check_entity_mask(entity, mask_hash { 0, 1, 2 })
		check_component_mask(entity, component, mask_hash { 0, 1 })

		SANITY_CHECKS()
	end)

	CASE("should stop an entity", function()
		local member0, member1, member2 = register_members(masking)
		active_all_members(masking)

		local entity = world:entity()
		local component = world:component()

		masking:start_entity(entity, {
			[member0] = true,
			[member1] = true,
			[member2] = true,
		})
		masking:start_component(entity, component, 1, {
			[member0] = true,
			[member1] = true,
		})
		check_component_mask(entity, component, mask_hash { 0, 1 })
		masking:stop_entity(entity)
		check_component_is_not_active(entity, component)
		check_entity_is_not_active(entity)

		SANITY_CHECKS()
	end)

	CASE("should stop a component", function()
		local member0, member1, member2 = register_members(masking)
		active_all_members(masking)
		local entity = world:entity()
		local component = world:component()

		masking:start_entity(entity, {
			[member0] = true,
			[member1] = true,
			[member2] = true,
		})
		masking:start_component(entity, component, 1, {
			[member0] = true,
			[member1] = true,
		})
		check_component_mask(entity, component, mask_hash { 0, 1 })
		masking:stop_component(entity, component, 1)
		check_component_is_not_active(entity, component)

		masking:start_component(entity, component, 1, {
			[member0] = true,
			[member1] = true,
			[member2] = true,
		})
		check_component_mask(entity, component, mask_hash { 0, 1, 2 })
		check_entity_mask(entity, mask_hash { 0, 1, 2 })
		masking:stop_component(entity, component, 1)
		check_component_is_not_active(entity, component)
		check_entity_mask(entity, mask_hash { 0, 1, 2 })

		SANITY_CHECKS()
	end)

	CASE("should postpone a component with no filter", function()
		local member0, member1, member2 = register_members(masking)
		active_all_members(masking)

		local entity = world:entity()
		local component1 = world:component()
		local component2 = world:component()

		masking:start_component(entity, component1, 1, nil)
		masking:start_component(entity, component2, 1, nil)

		masking:start_entity(entity, {
			[member0] = true,
			[member1] = true,
			[member2] = true,
		})
		check_component_is_merged(entity, component1, mask_hash { 0, 1, 2 })
		check_component_is_merged(entity, component2, mask_hash { 0, 1, 2 })

		SANITY_CHECKS()
	end)

	CASE("should be able to apply the same filter to an entity", function()
		local member0, member1 = register_members(masking)
		active_all_members(masking)

		local entity = world:entity()
		local component = world:component()
		masking:start_entity(entity, {
			[member0] = true,
			[member1] = true,
		})
		masking:start_component(entity, component, 1, {
			[member0] = true,
			[member1] = true,
		})
		check_entity_mask(entity, mask_hash { 0, 1 })
		masking:set_entity(entity, {
			[member0] = true,
			[member1] = true,
		})
		check_entity_mask(entity, mask_hash { 0, 1 })
		check_component_mask(entity, component, mask_hash { 0, 1 })

		SANITY_CHECKS()
	end)

	CASE("should be able to apply the same filter to a component", function()
		local member0, member1, member2 = register_members(masking)
		active_all_members(masking)

		local entity = world:entity()
		local component = world:component()
		masking:start_entity(entity, {
			[member0] = true,
			[member1] = true,
			[member2] = true,
		})
		masking:start_component(entity, component, 1, {
			[member0] = true,
			[member1] = true,
		})
		check_component_mask(entity, component, mask_hash { 0, 1 })
		masking:set_component(entity, component, 1, {
			[member0] = true,
			[member1] = true,
		})
		check_component_mask(entity, component, mask_hash { 0, 1 })
		masking:set_component(entity, component, 1, nil)
		check_component_is_merged(entity, component, mask_hash { 0, 1, 2 })
		masking:set_component(entity, component, 1, nil)
		check_component_is_merged(entity, component, mask_hash { 0, 1, 2 })

		SANITY_CHECKS()
	end)
	CASE("should merge two masks correctly", function()
		local member0, member1, member2 = register_members(masking)
		active_all_members(masking)

		local entity1 = world:entity()
		local entity2 = world:entity()
		local component1 = world:component()
		local component2 = world:component()

		masking:start_entity(entity1, {
			[member0] = true,
			[member1] = true,
			[member2] = true,
		})
		masking:start_entity(entity2, {
			[member0] = true,
			--[member1] = true,
			[member2] = true,
		})
		masking:start_component(entity2, component1, 1, {
			[member0] = true,
			[member1] = true,
			[member2] = true,
		})
		masking:start_component(entity1, component2, 1, {
			[member0] = true,
		})

		masking:unregister_client(member1)
		masking:compact_members()

		local compacted_hash = mask_hash { masking.client_indexes[member0], masking.client_indexes[member2] }
		check_entity_mask(entity1, compacted_hash)
		check_entity_mask(entity2, compacted_hash)

		masking:unregister_client(member2)
		masking:compact_members()

		local compacted_hash2 = mask_hash { masking.client_indexes[member0] }
		check_entity_mask(entity1, compacted_hash2)
		check_entity_mask(entity2, compacted_hash2)

		check_component_mask(entity2, component1, compacted_hash2)
		check_component_mask(entity1, component2, compacted_hash2)

		SANITY_CHECKS()
	end)
	--FOCUS()
	CASE("should postpone all components when an entity stops", function()
		local member0, member1, member2, member3 = register_members(masking)
		active_all_members(masking)
		local entity = world:entity()
		local component1 = world:component()
		local component2 = world:component()
		local component3 = world:component()
		local component4 = world:component()

		masking:start_entity(entity, {
			[member0] = true,
			[member1] = true,
			[member2] = true,
		})
		masking:start_component(entity, component1, 1, nil)
		masking:start_component(entity, component2, 1, {
			[member0] = true,
			[member1] = true,
		})
		masking:start_component(entity, component3, 1, {
			[member0] = true,
			[member1] = true,
			[member2] = true,
		})
		masking:start_component(entity, component4, 1, {
			[member0] = true,
			[member3] = true,
		})
		masking:stop_entity(entity)
		masking:start_entity(entity, {
			[member0] = true,
			[member1] = true,
			[member2] = true,
		})

		check_component_is_merged(entity, component1, mask_hash { 0, 1, 2 })
		check_component_mask(entity, component2, mask_hash { 0, 1 })
		check_component_mask(entity, component3, mask_hash { 0, 1, 2 })
		check_component_mask(entity, component4, mask_hash { 0 })

		SANITY_CHECKS()
	end)
	CASE("it should allow aliases to be used", function()
		local member0, member1, member2 = register_members(masking)
		active_all_members(masking)
		local entity = world:entity()
		local component = world:component()
		masking.client_aliases["m0"] = member0
		masking.client_aliases["m1"] = member1

		masking:start_entity(entity, {
			m0 = true,
			m1 = true,
			[member2] = true,
		})
		masking:start_component(entity, component, 1, {
			m0 = false,
		})

		check_entity_mask(entity, mask_hash { 0, 1, 2 })
		check_component_mask(entity, component, mask_hash { 1, 2 })
		masking:set_entity(entity, {
			m1 = false,
		})
		check_entity_mask(entity, mask_hash { 0, 2, 3 })
		check_component_mask(entity, component, mask_hash { 2, 3 })

		SANITY_CHECKS()
	end)
end)

TEST("storage moving", function()
	CASE("it should move component additions", function() end)
	CASE("it should move component changes", function() end)
	CASE("it should move component removals", function() end)
	CASE("it should move tag changes", function() end)
	CASE("it should move tag removals", function() end)
	CASE("it should move relation changes", function() end)
	CASE("it should move relation removals", function() end)
	CASE("it should move relation value changes", function() end)
	CASE("it should move relation value removals", function() end)
end)

TEST("bitmask deltas", function() end)

TEST("replecs server", function() end)

TEST("replecs client", function() end)

local function create_test_components(test_world: jecs.World)
	local components = {} :: { jecs.Entity<any> }
	for i = 1, 6 do
		local component = test_world:component()
		test_world:add(component, replecs.shared)
		test_world:set(component, jecs.Name, "component" .. i)

		table.insert(components, component)
	end

	return components
end

local function filter(members: { [any]: boolean }): { [Player]: boolean }
	return members :: any
end

local function create_test_tags(test_world: jecs.World)
	local tags = {} :: { jecs.Entity }
	for i = 1, 6 do
		local tag = test_world:entity()
		test_world:add(tag, replecs.shared)
		test_world:set(tag, jecs.Name, "tag" .. i)

		table.insert(tags, tag)
	end

	return tags
end

TEST("custom ids", function()
	local s_world: jecs.World = nil :: any
	local c_world: jecs.World = nil :: any
	local server: replecs.Server = nil :: any
	local client: replecs.Client = nil :: any

	BEFORE_EACH(function()
		s_world = jecs.world()
		c_world = jecs.world()
		server = replecs.create_server(s_world)
		client = replecs.create_client(c_world)
	end)
	AFTER_EACH(function()
		server:destroy()
		client:destroy()
	end)

	CASE("should use custom ids", function()
		local created_entity: jecs.Entity? = nil
		local called = 0

		local custom = replecs.create_custom_id("custom", function()
			created_entity = c_world:entity()
			called += 1
			return created_entity
		end)

		local plr = newproxy()

		client:register_custom_id(custom)
		server:register_custom_id(custom)

		server:init()
		client:init()
		server.masking:register_client(plr)
		server.masking:activate_client(plr)

		local e1 = s_world:entity()
		server:set_custom(e1, custom)
		server:set_networked(e1)
		local e2 = s_world:entity()
		server:set_networked(e2)

		local buf, var = server:get_full(plr)
		client:apply_full(buf, var)

		CHECK(called == 1)
		CHECK(client:get_client_entity(e1 :: any) == created_entity)
		CHECK(client:get_client_entity(e2 :: any) ~= created_entity)
	end)
	CASE("should find component in buffer", function()
		local foo_entity: Entity? = nil
		local baz_entity: Entity? = nil

		local s_components = create_test_components(s_world)
		local c_components = create_test_components(c_world)

		local custom = replecs.create_custom_id("custom", function(ctx)
			local entity = c_world:entity()
			if ctx.component(c_components[1]) == "foo" then
				foo_entity = entity
				return entity
			else
				baz_entity = entity
				return entity
			end
		end)

		local plr = newproxy()

		client:register_custom_id(custom)
		server:register_custom_id(custom)

		server:init()
		client:init()

		server.masking:register_client(plr)
		server.masking:activate_client(plr)

		local s_foo = s_world:entity()
		s_world:set(s_foo, s_components[1], "foo")

		server:set_custom(s_foo, custom)
		server:set_reliable(s_foo, s_components[1])
		server:set_networked(s_foo)

		local s_baz = s_world:entity()
		s_world:set(s_baz, s_components[1], "baz")

		server:set_custom(s_baz, custom)
		server:set_reliable(s_baz, s_components[1])
		server:set_networked(s_foo)

		local buf, variants = server:get_full(plr)
		client:apply_full(buf, variants)

		CHECK(client:get_client_entity(s_foo :: any) == foo_entity)
		CHECK(client:get_client_entity(s_baz :: any) == baz_entity)
	end)
	CASE("should add targets of customids to buffers", function()
		local created_entity: Entity

		local s_tags = create_test_tags(s_world)
		local c_tags = create_test_tags(c_world)

		local custom = replecs.create_custom_id("custom", function()
			created_entity = c_world:entity()
			return created_entity
		end)

		local plr = newproxy()

		client:register_custom_id(custom)
		server:register_custom_id(custom)

		server:init()
		client:init()

		server.masking:register_client(plr)
		server.masking:activate_client(plr)

		local s_target = s_world:entity()
		server:set_custom(s_target, custom)
		server:set_networked(s_target)

		local s_entity = s_world:entity()
		s_world:add(s_entity, jecs.pair(s_tags[1], s_target))
		server:set_relation(s_entity, s_tags[1])
		server:set_networked(s_entity)

		local buf, variants = server:get_full(plr)
		client:apply_full(buf, variants)

		local c_entity = client:get_client_entity(s_entity :: any) :: Entity
		CHECK(c_entity ~= nil)

		CHECK(c_world:has(c_entity, jecs.pair(c_tags[1], created_entity)))
	end)
	CASE("should recursively process custom id targets when applying buffers", function()
		local created_target: Entity
		local created_custom: Entity

		local s_tags = create_test_tags(s_world)
		local c_tags = create_test_tags(c_world)

		local custom = replecs.create_custom_id("custom", function()
			created_custom = c_world:entity()
			return created_custom
		end)
		local target_custom = replecs.create_custom_id("target_custom", function()
			created_target = c_world:entity()
			return created_target
		end)

		local plr = newproxy()

		client:register_custom_id(custom)
		server:register_custom_id(custom)
		client:register_custom_id(target_custom)
		server:register_custom_id(target_custom)

		server:init()
		client:init()

		server.masking:register_client(plr)
		server.masking:activate_client(plr)

		local s_target = s_world:entity()
		server:set_custom(s_target, target_custom)
		server:set_networked(s_target)

		local s_entity = s_world:entity()
		s_world:add(s_entity, jecs.pair(s_tags[1], s_target))
		server:set_custom(s_entity, custom)
		server:set_relation(s_entity, s_tags[1])
		server:set_networked(s_entity)

		local buf, variants = server:get_full(plr)
		client:apply_full(buf, variants)

		local c_entity = client:get_client_entity(s_entity :: any) :: Entity
		CHECK(c_entity ~= nil)

		CHECK(c_entity == created_custom)
		CHECK(c_world:target(c_entity, c_tags[1]) == created_target)
	end)
	CASE("should get target from context", function()
		local s_tags = create_test_tags(s_world)
		local c_tags = create_test_tags(c_world)

		local plr = newproxy()

		server:init()
		client:init()

		server.masking:register_client(plr)
		server.masking:activate_client(plr)

		local s_target = s_world:entity()
		server:set_networked(s_target)

		local custom = replecs.create_custom_id("custom", function(ctx: replecs.HandleContext)
			if ctx.target(c_tags[1]) == client:get_client_entity(s_target :: any) then
				return c_world:entity()
			else
				error "invalid target"
			end
		end)

		client:register_custom_id(custom)
		server:register_custom_id(custom)

		local s_entity = s_world:entity()
		s_world:add(s_entity, jecs.pair(s_tags[1], s_target))
		server:set_custom(s_entity, custom)
		server:set_relation(s_entity, s_tags[1])
		server:set_networked(s_entity)

		local buf, variants = server:get_full(plr)
		client:apply_full(buf, variants)
	end)
	CASE("should get unprocessed customid target from context", function()
		local s_tags = create_test_tags(s_world)
		local c_tags = create_test_tags(c_world)

		local plr = newproxy()

		server:init()
		client:init()

		server.masking:register_client(plr)
		server.masking:activate_client(plr)

		local target_entity: Entity
		local callstack: { number } = {}

		local target_custom = replecs.create_custom_id("target_custom", function()
			table.insert(callstack, 2)
			target_entity = c_world:entity()
			return target_entity
		end)

		local custom = replecs.create_custom_id("custom", function(ctx: replecs.HandleContext)
			table.insert(callstack, 1)
			if ctx.target(c_tags[1]) == target_entity then
				table.insert(callstack, 3)
				return c_world:entity()
			else
				error "invalid target"
			end
		end)

		client:register_custom_id(custom)
		server:register_custom_id(custom)
		client:register_custom_id(target_custom)
		server:register_custom_id(target_custom)

		local s_target = s_world:entity()
		server:set_custom(s_target, target_custom)
		server:set_networked(s_target)

		local s_entity = s_world:entity()
		s_world:add(s_entity, jecs.pair(s_tags[1], s_target))
		server:set_custom(s_entity, custom)
		server:set_relation(s_entity, s_tags[1])
		server:set_networked(s_entity)

		local buf, variants = server:get_full(plr)
		client:apply_full(buf, variants)
		expect(callstack).to.be.equal { 1, 2, 3 }
	end)
end)

TEST("server -> client replication", function()
	local world: jecs.World = nil :: any
	local server: replecs.Server = nil :: any

	BEFORE_EACH(function()
		world = jecs.world()
		server = replecs.create_server(world)
	end)

	AFTER_EACH(function()
		server:destroy()
	end)

	local function client_entity(member: MemberData, server_entity: jecs.Entity): jecs.Entity?
		local entity = member.client.server_ids[server_entity :: any]
		if entity and member.world:contains(entity) then
			return entity
		end
		return nil
	end

	local function client_component(member: MemberData, server_entity: jecs.Entity, component_index: number)
		local component = member.components[component_index]
		local entity = client_entity(member, server_entity)
		if entity then
			return member.world:get(entity, component)
		end
		return nil
	end
	local function client_has_component(member: MemberData, server_entity: jecs.Entity, component_index: number)
		local component = member.components[component_index]
		local entity = client_entity(member, server_entity)
		if entity then
			return member.world:has(entity, component)
		end
		return false
	end
	local function client_tag(member: MemberData, server_entity: jecs.Entity, tag_index: number): boolean?
		local tag = member.tags[tag_index]
		local entity = client_entity(member, server_entity)
		if entity then
			return member.world:has(entity, tag)
		end
		return false
	end

	local function client_relation_value(
		member: MemberData,
		server_entity: jecs.Entity,
		relation_index: number,
		target_server: jecs.Entity
	): any?
		local relation = member.components[relation_index]
		local target = client_entity(member, target_server)

		local entity = client_entity(member, server_entity)
		if entity and target then
			return member.world:get(entity, jecs.pair(relation, target))
		end
		return nil
	end

	local function client_pair_value(
		member: MemberData,
		server_entity: jecs.Entity,
		relation_index: number,
		target_index: number
	): any?
		local relation = member.components[relation_index]
		local target = member.tags[target_index]

		local entity = client_entity(member, server_entity)
		if entity and target then
			return member.world:get(entity, jecs.pair(relation, target))
		end
		return nil
	end

	local function client_relation(
		member: MemberData,
		server_entity: jecs.Entity,
		relation_index: number,
		target_server: jecs.Entity
	): boolean?
		local relation = member.tags[relation_index]
		local target = client_entity(member, target_server)

		local entity = client_entity(member, server_entity)
		if entity and target then
			return member.world:has(entity, jecs.pair(relation, target))
		end
		return false
	end

	local function client_pair(
		member: MemberData,
		server_entity: jecs.Entity,
		relation_index: number,
		target_index: number
	): boolean?
		local relation = member.tags[relation_index]
		local target = member.tags[target_index]

		local entity = client_entity(member, server_entity)
		if entity and target then
			return member.world:has(entity, jecs.pair(relation, target))
		end
		return nil
	end

	local function client_global_pair(
		member: MemberData,
		server_entity: jecs.Entity,
		relation: jecs.Entity,
		target_server: jecs.Entity
	): boolean
		local target = client_entity(member, target_server)
		local entity = client_entity(member, server_entity)
		if entity and target then
			return member.world:has(entity, jecs.pair(relation, target))
		end
		return false
	end

	local function create_members_data(count: number?)
		local members = {} :: { MemberData }
		local lookup = {}
		local worlds = {}
		local c_components = {}
		local c_tags = {}

		for i = 1, (count or 3) do
			local new_world = jecs.world()
			local components = create_test_components(new_world)
			local tags = create_test_tags(new_world)
			local replicator = replecs.create_client(new_world)

			local member_mt = {
				world = new_world,
				client = replicator,
				components = components,
				tags = tags,
			}
			local member = newproxy(true)
			getmetatable(member).__index = member_mt

			server.masking:register_client(member)
			table.insert(members, member :: MemberData)
			table.insert(worlds, new_world)
			table.insert(c_components, components)
			table.insert(c_tags, tags)
			lookup[member] = i
		end
		return members, worlds, c_components, c_tags, lookup
	end
	local function init_member_clients(members: { MemberData })
		for _, member in members do
			member.client:init()
		end
	end

	local function activate_members(members: { MemberData })
		for _, member in members do
			server.masking:activate_client(member)
		end
	end

	CASE("should send full components to all players", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data()
		activate_members(members)
		init_member_clients(members)

		local entity1 = world:entity()
		local entity2 = world:entity()

		server:set_networked(entity1)

		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "foo")

		server:set_networked(entity2)
		server:set_reliable(entity2, components[2])
		world:set(entity2, components[2], "bar")

		for _, member in members do
			local buf, variants = server:get_full(member :: any)
			local client = member.client
			client:apply_full(buf, variants)

			CHECK(client_entity(member, entity1) ~= nil)
			CHECK(client_component(member, entity1, 1) == "foo")
			CHECK(client_component(member, entity2, 2) == "bar")

			CHECK(client_component(member, entity1, 2) == nil)
			CHECK(client_component(member, entity2, 1) == nil)
		end
	end)

	CASE("should send full tags to all players", function()
		create_test_components(world)
		local tags = create_test_tags(world)
		server:init()

		local members = create_members_data()
		activate_members(members)
		init_member_clients(members)

		local entity1 = world:entity()
		local entity2 = world:entity()

		server:set_networked(entity1)
		server:set_reliable(entity1, tags[1])
		world:add(entity1, tags[1])

		server:set_networked(entity2)
		server:set_reliable(entity2, tags[2])
		world:add(entity2, tags[2])

		for _, member in members do
			local buf, variants = server:get_full(member :: any)
			member.client:apply_full(buf, variants)

			CHECK(client_entity(member, entity1) ~= nil)
			CHECK(client_entity(member, entity2) ~= nil)

			CHECK(client_tag(member, entity1, 1) == true)
			CHECK(client_tag(member, entity2, 2) == true)

			CHECK(client_tag(member, entity1, 2) == false)
			CHECK(client_tag(member, entity2, 1) == false)
		end
	end)

	CASE("should send full pairs with shared targets to all players", function()
		create_test_components(world)
		local tags = create_test_tags(world)
		server:init()

		local members = create_members_data()
		activate_members(members)
		init_member_clients(members)

		local entity1 = world:entity()
		local entity2 = world:entity()

		server:set_networked(entity1)
		server:set_networked(entity2)

		server:set_pair(entity1, jecs.pair(tags[1], tags[2]))
		world:add(entity1, jecs.pair(tags[1], tags[2]))
		world:add(entity1, jecs.pair(tags[1], tags[3]))

		server:set_pair(entity2, jecs.pair(tags[2], tags[3]))
		world:add(entity2, jecs.pair(tags[1], tags[2]))
		world:add(entity1, jecs.pair(tags[2], tags[1]))
		world:add(entity2, jecs.pair(tags[2], tags[3]))

		for _, member in members do
			local buf, variants = server:get_full(member :: any)
			member.client:apply_full(buf, variants)

			CHECK(client_entity(member, entity1) ~= nil)
			CHECK(client_entity(member, entity2) ~= nil)

			CHECK(client_pair(member, entity1, 1, 2) == true)
			CHECK(client_pair(member, entity1, 1, 3) == false)

			CHECK(client_pair(member, entity2, 1, 2) == false)
			CHECK(client_pair(member, entity2, 2, 1) == false)
			CHECK(client_pair(member, entity2, 2, 3) == true)
		end
	end)

	CASE("should send full pairs with networked targets to all players", function()
		create_test_components(world)
		local tags = create_test_tags(world)
		server:init()

		local members = create_members_data()
		activate_members(members)
		init_member_clients(members)

		local entity1 = world:entity()
		local entity2 = world:entity()

		local target1 = world:entity()
		local target2 = world:entity()

		server:set_networked(entity1)
		server:set_networked(entity2)
		server:set_networked(target1)
		server:set_networked(target2)

		world:add(entity1, jecs.pair(tags[1], target1))
		world:add(entity1, jecs.pair(tags[1], target2))
		server:set_pair(entity1, jecs.pair(tags[1], target1))

		world:add(entity2, jecs.pair(tags[1], target1))
		world:add(entity2, jecs.pair(tags[2], target1))
		world:add(entity2, jecs.pair(tags[2], target2))
		server:set_pair(entity2, jecs.pair(tags[2], target2))

		for _, member in members do
			local buf, variants = server:get_full(member :: any)
			member.client:apply_full(buf, variants)

			CHECK(client_entity(member, entity1) ~= nil)
			CHECK(client_entity(member, entity2) ~= nil)

			CHECK(client_relation(member, entity1, 1, target1) == true)
			CHECK(client_relation(member, entity1, 1, target2) == false)

			CHECK(client_relation(member, entity2, 1, target1) == false)
			CHECK(client_relation(member, entity2, 2, target1) == false)
			CHECK(client_relation(member, entity2, 2, target2) == true)
		end
	end)

	CASE("should send full pairs with values to all players", function()
		local components = create_test_components(world)
		local tags = create_test_tags(world)
		server:init()

		local members = create_members_data()
		activate_members(members)
		init_member_clients(members)

		local entity1 = world:entity()
		local entity2 = world:entity()

		server:set_networked(entity1)
		server:set_networked(entity2)

		world:set(entity1, jecs.pair(components[1], tags[1]), "yes")
		world:set(entity1, jecs.pair(components[1], tags[2]), "no")
		server:set_pair(entity1, jecs.pair(components[1], tags[1]))

		world:set(entity2, jecs.pair(components[1], tags[1]), "no")
		world:set(entity2, jecs.pair(components[2], tags[1]), "no")
		world:set(entity2, jecs.pair(components[2], tags[3]), "yes")
		server:set_pair(entity2, jecs.pair(components[2], tags[3]))

		print("NETWORKED IDS", entity1, entity2)
		print("STORAGE", server.storage)

		for _, member in members do
			local buf, variants = server:get_full(member :: any)
			print "GOT FULL"
			member.client:apply_full(buf, variants)

			print(client_entity(member, entity1) ~= nil)
			print(client_entity(member, entity2) ~= nil)

			print(client_pair_value(member, entity1, 1, 1) == "yes")
			print(client_pair_value(member, entity1, 1, 2) == nil)

			print(client_pair_value(member, entity2, 1, 1) == nil)
			print(client_pair_value(member, entity2, 2, 1) == nil)
			print(client_pair_value(member, entity2, 2, 3) == "yes")
		end
	end)

	CASE("should send full relations to all players", function()
		create_test_components(world)
		local tags = create_test_tags(world)
		server:init()

		local members = create_members_data()
		activate_members(members)
		init_member_clients(members)

		local entity1 = world:entity()
		local entity2 = world:entity()

		local target1 = world:entity()
		server:set_networked(target1)
		local target2 = world:entity()
		server:set_networked(target2)
		local target3 = world:entity()
		server:set_networked(target3)
		local target4 = world:entity()
		server:set_networked(target4)

		server:set_networked(entity1)
		server:set_relation(entity1, tags[1])
		server:set_relation(entity1, jecs.ChildOf)

		server:set_networked(entity2)
		server:set_relation(entity2, tags[2])

		world:add(entity1, jecs.pair(tags[1], target1))
		world:add(entity1, jecs.pair(tags[1], target2))
		world:add(entity1, jecs.pair(tags[1], target3))
		world:add(entity1, jecs.pair(jecs.ChildOf, target3))

		world:add(entity2, jecs.pair(tags[2], target3))
		world:add(entity2, jecs.pair(tags[2], target4))

		for _, member in members do
			local buf, variants = server:get_full(member :: any)
			member.client:apply_full(buf, variants)

			CHECK(client_entity(member, entity1) ~= nil)
			CHECK(client_entity(member, entity2) ~= nil)

			CHECK(client_relation(member, entity1, 1, target1) == true)
			CHECK(client_global_pair(member, entity1, jecs.ChildOf, target3) == true)
			CHECK(client_relation(member, entity1, 1, target2) == true)
			CHECK(client_relation(member, entity1, 1, target3) == true)
			CHECK(client_relation(member, entity2, 2, target3) == true)
			CHECK(client_relation(member, entity2, 2, target4) == true)

			CHECK(client_relation(member, entity1, 2, target3) == false)
			CHECK(client_relation(member, entity1, 2, target4) == false)
			CHECK(client_relation(member, entity1, 2, target1) == false)
			CHECK(client_relation(member, entity2, 1, target2) == false)
			CHECK(client_relation(member, entity2, 1, target3) == false)
		end
	end)

	CASE("should send full entity to players in filter", function()
		local components = create_test_components(world)
		create_test_tags(world)
		server:init()

		local members = create_members_data(4)
		activate_members(members)
		init_member_clients(members)

		local entity1 = world:entity()
		local entity2 = world:entity()

		server:set_networked(
			entity1,
			filter {
				[members[1]] = true,
				[members[2]] = true,
			}
		)

		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "foo")

		server:set_networked(
			entity2,
			filter {
				[members[3]] = true,
				[members[4]] = true,
			}
		)

		server:set_reliable(entity2, components[2])
		world:set(entity2, components[2], "bar")

		for _, member in members do
			local buf, variants = server:get_full(member :: any)
			member.client:apply_full(buf, variants)
		end

		CHECK(client_entity(members[1], entity1) ~= nil)
		CHECK(client_entity(members[2], entity1) ~= nil)
		CHECK(client_entity(members[1], entity2) == nil)
		CHECK(client_entity(members[2], entity2) == nil)

		CHECK(client_entity(members[3], entity2) ~= nil)
		CHECK(client_entity(members[4], entity2) ~= nil)
		CHECK(client_entity(members[3], entity1) == nil)
		CHECK(client_entity(members[4], entity1) == nil)

		CHECK(client_component(members[1], entity1, 1) == "foo")
		CHECK(client_component(members[2], entity1, 1) == "foo")
		CHECK(client_component(members[3], entity2, 2) == "bar")
		CHECK(client_component(members[4], entity2, 2) == "bar")
	end)
	CASE("should send full entity with component filters", function()
		local components = create_test_components(world)
		create_test_tags(world)
		server:init()

		local members = create_members_data(4)
		activate_members(members)
		init_member_clients(members)

		local entity1 = world:entity()
		local entity2 = world:entity()

		server:set_networked(entity1)
		server:set_reliable(
			entity1,
			components[1],
			filter {
				[members[1]] = true,
				[members[2]] = true,
				[members[3]] = true,
			}
		)
		world:set(entity1, components[1], "foo")

		server:set_networked(entity2)
		server:set_reliable(
			entity2,
			components[2],
			filter {
				[members[3]] = true,
				[members[4]] = true,
			}
		)
		world:set(entity2, components[2], "bar")

		for _, member in members do
			local buf, variants = server:get_full(member :: any)
			member.client:apply_full(buf, variants)
		end

		CHECK(client_component(members[1], entity1, 1) == "foo")
		CHECK(client_component(members[2], entity1, 1) == "foo")
		CHECK(client_component(members[3], entity1, 1) == "foo")

		CHECK(client_component(members[1], entity1, 2) == nil)
		CHECK(client_component(members[2], entity1, 2) == nil)
		CHECK(client_component(members[1], entity2, 1) == nil)
		CHECK(client_component(members[2], entity2, 1) == nil)

		CHECK(client_component(members[3], entity2, 2) == "bar")
		CHECK(client_component(members[4], entity2, 2) == "bar")
	end)
	CASE("should correctly send nil values in components", function()
		local components = create_test_components(world)
		create_test_tags(world)
		server:init()

		local members = create_members_data(4)
		activate_members(members)
		init_member_clients(members)

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], nil)

		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		CHECK(client_component(members[1], entity1, 1) == nil)
		CHECK(client_has_component(members[1], entity1, 1) == true)
	end)

	CASE("should allow custom serdes for component values", function()
		local serdes: replecs.Serdes = {
			serialize = function(value: vector)
				local buf = buffer.create(3)
				buffer.writeu8(buf, 0, value.x)
				buffer.writeu8(buf, 1, value.y)
				buffer.writeu8(buf, 2, value.z)
				return buf
			end,
			deserialize = function(buf: buffer)
				-- lets write it backwards to know this function was called
				return vector.create(buffer.readu8(buf, 2), buffer.readu8(buf, 1), buffer.readu8(buf, 0))
			end,
		}

		local components = create_test_components(world)
		world:set(components[1], replecs.serdes, serdes)
		--world:set(components[1], replecs.bytespan, 3)
		create_test_tags(world)
		server:init()

		local members = create_members_data(1)
		members[1].world:set(members[1].components[1], replecs.serdes, serdes)
		--members[1].world:set(members[1].components[1], replecs.bytespan, 3)
		activate_members(members)
		init_member_clients(members)

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], vector.create(10, 20, 30))

		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		CHECK(client_component(members[1], entity1, 1) == vector.create(30, 20, 10))
	end)

	CASE("should send component changes to all players", function()
		local components = create_test_components(world)
		create_test_tags(world)
		server:init()

		local members = create_members_data(2)
		activate_members(members)
		init_member_clients(members)

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "one")

		for _, member in members do
			local buf, variants = server:get_full(member :: any)
			member.client:apply_full(buf, variants)
		end

		world:set(entity1, components[1], "two")
		for player, buf, changes in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(buf, changes)
			CHECK(client_component(member, entity1, 1) == "two")
		end
		world:set(entity1, components[1], "three")
		world:set(entity1, components[1], "four")
		for player, buf, changes in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(buf, changes)
			CHECK(client_component(member, entity1, 1) == "four")
		end
	end)

	CASE("shoud send tag changes to all players", function()
		create_test_components(world)
		local tags = create_test_tags(world)
		server:init()

		local members = create_members_data(4)
		activate_members(members)
		init_member_clients(members)

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, tags[1])
		server:set_reliable(entity1, tags[2])
		server:set_reliable(entity1, tags[3])

		for _, member in members do
			local buf, variants = server:get_full(member :: any)
			member.client:apply_full(buf, variants)
		end

		world:add(entity1, tags[1])
		for player, buf, changes in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(buf, changes)
			CHECK(client_tag(member, entity1, 1) == true)
			CHECK(client_tag(member, entity1, 2) == false)
		end
		world:add(entity1, tags[2])
		for player, buf, changes in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(buf, changes)
			CHECK(client_tag(member, entity1, 1) == true)
			CHECK(client_tag(member, entity1, 2) == true)
		end

		world:remove(entity1, tags[1])
		for player, buf, changes in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(buf, changes)
			CHECK(client_tag(member, entity1, 1) == false)
			CHECK(client_tag(member, entity1, 2) == true)
		end

		world:remove(entity1, tags[2])

		world:add(entity1, tags[3])
		for player, buf, changes in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(buf, changes)
			CHECK(client_tag(member, entity1, 1) == false)
			CHECK(client_tag(member, entity1, 2) == false)
			CHECK(client_tag(member, entity1, 3) == true)
		end
	end)
	CASE("should send relation changes", function()
		create_test_components(world)
		local tags = create_test_tags(world)
		server:init()

		local members = create_members_data(2)
		activate_members(members)
		init_member_clients(members)

		local entity = world:entity()
		server:set_networked(entity)

		for _, member in members do
			local buf, variants = server:get_full(member :: any)
			member.client:apply_full(buf, variants)
		end

		for player, buf, changes in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(buf, changes)
		end

		for _ = 1, 10 do
			local target = world:entity()
			server:set_networked(target)
			server:set_relation(target, jecs.ChildOf)
			world:add(target, jecs.pair(jecs.ChildOf, entity))
		end
	end)
	CASE("should send relation changes to all players", function()
		create_test_components(world)
		local tags = create_test_tags(world)
		server:init()

		local members = create_members_data(4)
		activate_members(members)
		init_member_clients(members)

		local entity1 = world:entity()

		server:set_networked(entity1)
		server:set_relation(entity1, tags[1])
		server:set_relation(entity1, jecs.ChildOf)

		local r1 = world:entity()
		local r2 = world:entity()
		local r3 = world:entity()
		server:set_networked(r1)
		server:set_networked(r2)
		server:set_networked(r3)
		world:add(entity1, jecs.pair(tags[1], r1))

		for _, member in members do
			local buf, variants = server:get_full(member :: any)
			member.client:apply_full(buf, variants)
		end

		for player, buf, changes in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(buf, changes)
			CHECK(client_relation(member, entity1, 1, r1) == true)
			CHECK(client_relation(member, entity1, 1, r2) == false)
			CHECK(client_relation(member, entity1, 1, r2) == false)
		end
		world:add(entity1, jecs.pair(tags[1], r2))
		world:add(entity1, jecs.pair(jecs.ChildOf, r2))

		for player, buf, changes in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(buf, changes)
			CHECK(client_relation(member, entity1, 1, r1) == true)
			CHECK(client_relation(member, entity1, 1, r2) == true)
			CHECK(client_relation(member, entity1, 1, r3) == false)
			CHECK(client_global_pair(member, entity1, jecs.ChildOf, r2) == true)
		end
		world:remove(entity1, jecs.pair(tags[1], r1))
		world:add(entity1, jecs.pair(tags[1], r3))

		for player, buf, changes in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(buf, changes)
			CHECK(client_relation(member, entity1, 1, r1) == false)
			CHECK(client_relation(member, entity1, 1, r2) == true)
			CHECK(client_relation(member, entity1, 1, r3) == true)
		end
	end)

	CASE("should remove entity when networked component is removed", function()
		local components = create_test_components(world)
		create_test_tags(world)
		server:init()

		local members = create_members_data(2)
		activate_members(members)
		init_member_clients(members)

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "foo")

		for _, member in members do
			local buf, variants = server:get_full(member :: any)
			member.client:apply_full(buf, variants)
		end
		server:stop_networked(entity1)

		for player, buf, changes in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(buf, changes)
			CHECK(client_entity(member, entity1) == nil)
		end
		server:set_networked(entity1)
		server:stop_networked(entity1)
		for player, buf, changes in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(buf, changes)
			CHECK(client_entity(member, entity1) == nil)
		end
	end)

	CASE("should remove all data when component stops", function()
		local components = create_test_components(world)
		local tags = create_test_tags(world)
		server:init()

		local members = create_members_data(1)
		activate_members(members)
		init_member_clients(members)

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		server:set_reliable(entity1, tags[1])
		server:set_relation(entity1, tags[2])

		local r1 = world:entity()
		local r2 = world:entity()
		server:set_networked(r1)
		server:set_networked(r2)

		world:set(entity1, components[1], "foo")
		world:add(entity1, tags[1])
		world:add(entity1, jecs.pair(tags[2], r1))
		world:add(entity1, jecs.pair(tags[2], r2))

		for _, member in members do
			local buf, variants = server:get_full(member :: any)
			member.client:apply_full(buf, variants)
		end
		for player, buf, changes in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(buf, changes)
		end

		server:stop_reliable(entity1, components[1])
		for player, buf, changes in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(buf, changes)
			CHECK(client_entity(member, entity1) ~= nil)
			CHECK(client_has_component(member, entity1, 1) == false)
			CHECK(client_tag(member, entity1, 1) == true)
			CHECK(client_relation(member, entity1, 2, r1) == true)
			CHECK(client_relation(member, entity1, 2, r2) == true)
		end

		server:stop_reliable(entity1, tags[1])
		for player, buf, changes in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(buf, changes)
			CHECK(client_entity(member, entity1) ~= nil)
			CHECK(client_has_component(member, entity1, 1) == false)
			CHECK(client_tag(member, entity1, 1) == false)
			CHECK(client_relation(member, entity1, 2, r1) == true)
			CHECK(client_relation(member, entity1, 2, r2) == true)
		end

		server:stop_relation(entity1, tags[2])
		for player, buf, changes in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(buf, changes)
			CHECK(client_entity(member, entity1) ~= nil)
			CHECK(client_has_component(member, entity1, 1) == false)
			CHECK(client_tag(member, entity1, 1) == false)
			CHECK(client_relation(member, entity1, 2, r1) == false)
			CHECK(client_relation(member, entity1, 2, r2) == false)
		end
	end)

	CASE("should send pair value changes via collect_updates", function()
		local components = create_test_components(world)
		local tags = create_test_tags(world)
		server:init()

		local members = create_members_data(2)
		activate_members(members)
		init_member_clients(members)

		local entity1 = world:entity()
		server:set_networked(entity1)
		world:set(entity1, jecs.pair(components[1], tags[1]), "initial")
		server:set_pair(entity1, jecs.pair(components[1], tags[1]))

		for _, member in members do
			local buf, variants = server:get_full(member :: any)
			member.client:apply_full(buf, variants)
			CHECK(client_pair_value(member, entity1, 1, 1) == "initial")
		end

		-- flush additions so subsequent changes are tracked as updates
		for player, buf, changes in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(buf, changes)
		end

		world:set(entity1, jecs.pair(components[1], tags[1]), "updated")
		for player, buf, changes in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(buf, changes)
			CHECK(client_pair_value(member, entity1, 1, 1) == "updated")
		end
	end)

	CASE("should send entity with component filters via collect_entity", function()
		local components = create_test_components(world)
		create_test_tags(world)
		server:init()

		local members = create_members_data(4)
		activate_members(members)
		init_member_clients(members)

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "all")

		server:set_reliable(
			entity1,
			components[2],
			filter {
				[members[1]] = true,
				[members[2]] = true,
			}
		)
		world:set(entity1, components[2], "filtered")

		-- flush additions
		for player, buf, changes in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(buf, changes)
		end

		for player, buf, changes in server:collect_entity(entity1) do
			local member: MemberData = player :: any
			member.client:apply_entity(buf, changes)
		end

		CHECK(client_component(members[1], entity1, 2) == "filtered")
		CHECK(client_component(members[2], entity1, 2) == "filtered")
		CHECK(client_component(members[3], entity1, 2) == nil)
		CHECK(client_component(members[4], entity1, 2) == nil)
	end)
end)

TEST("filter blacklist", function()
	local world: jecs.World = nil :: any
	local server: replecs.Server = nil :: any

	BEFORE_EACH(function()
		world = jecs.world()
		server = replecs.create_server(world)
	end)

	AFTER_EACH(function()
		server:destroy()
	end)

	local function create_members_data(count: number?)
		local members = {} :: { MemberData }
		for i = 1, (count or 3) do
			local new_world = jecs.world()
			local components = create_test_components(new_world)
			local tags = create_test_tags(new_world)
			local replicator = replecs.create_client(new_world)

			local member_mt = {
				world = new_world,
				client = replicator,
				components = components,
				tags = tags,
			}
			local member = newproxy(true)
			getmetatable(member).__index = member_mt

			server.masking:register_client(member)
			table.insert(members, member :: MemberData)
		end
		return members
	end

	local function client_entity(member: MemberData, server_entity: jecs.Entity): jecs.Entity?
		local entity = member.client.server_ids[server_entity :: any]
		if entity and member.world:contains(entity) then
			return entity
		end
		return nil
	end

	local function client_component(member: MemberData, server_entity: jecs.Entity, component_index: number)
		local component = member.components[component_index]
		local entity = client_entity(member, server_entity)
		if entity then
			return member.world:get(entity, component)
		end
		return nil
	end

	local function client_has_component(member: MemberData, server_entity: jecs.Entity, component_index: number)
		local component = member.components[component_index]
		local entity = client_entity(member, server_entity)
		if entity then
			return member.world:has(entity, component)
		end
		return false
	end

	local function full_sync(members: { MemberData }, server_entity: jecs.Entity)
		for _, member in members do
			local buf, variants = server:get_full(member :: any)
			member.client:apply_full(buf, variants)
		end
	end

	local function apply_updates(members: { MemberData })
		for player, buf, changes in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(buf, changes)
		end
	end

	CASE("blacklisted player no longer keeps orphaned entity (default keep=false)", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(2)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1, nil)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "value")

		full_sync(members, entity1)

		-- both members have the entity
		CHECK(client_entity(members[1], entity1) ~= nil)
		CHECK(client_entity(members[2], entity1) ~= nil)

		-- blacklist member1 (default keep=false)
		server:set_networked(entity1, { [members[2] :: any] = true })
		apply_updates(members)

		-- member1 now correctly receives entity deletion
		CHECK(client_entity(members[1], entity1) == nil)

		-- member2 still has it
		CHECK(client_entity(members[2], entity1) ~= nil)
	end)

	CASE("world:delete after blacklist correctly removes for all players", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(2)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1, nil)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "value")

		full_sync(members, entity1)

		-- blacklist member1 (default keep=false sends deletion)
		server:set_networked(entity1, { [members[2] :: any] = true })
		apply_updates(members)

		-- member1 correctly lost entity via filter deletion
		CHECK(client_entity(members[1], entity1) == nil)

		-- delete entity
		world:delete(entity1)
		apply_updates(members)

		-- member2 also correctly lost it
		CHECK(client_entity(members[2], entity1) == nil)
	end)

	CASE("stop_networked before blacklist sends deletion to blacklisted player", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(2)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1, nil)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "value")

		full_sync(members, entity1)

		-- stop BEFORE blacklisting
		server:stop_networked(entity1)
		server:set_networked(entity1, { [members[2] :: any] = true })

		-- process updates: member1 gets delete (from old storage), member2 gets delete+create
		apply_updates(members)

		-- member1 correctly lost the entity
		CHECK(client_entity(members[1], entity1) == nil)

		-- member2 was recreated with fresh data
		CHECK(client_entity(members[2], entity1) ~= nil)
		CHECK(client_component(members[2], entity1, 1) == "value")
	end)

	CASE("stop_networked + set_networked preserves components via postponed (separate frames)", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(3)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1, nil)
		server:set_reliable(entity1, components[1])
		server:set_reliable(entity1, components[2])
		world:set(entity1, components[1], "hello")
		world:set(entity1, components[2], "world")

		full_sync(members, entity1)

		-- stop in one frame
		server:stop_networked(entity1)
		apply_updates(members)

		-- all members lost the entity
		CHECK(client_entity(members[1], entity1) == nil)
		CHECK(client_entity(members[2], entity1) == nil)
		CHECK(client_entity(members[3], entity1) == nil)

		-- restart with blacklist in next frame
		server:set_networked(entity1, { [members[1] :: any] = true, [members[2] :: any] = true })
		apply_updates(members)

		-- member3 was not re-added
		CHECK(client_entity(members[3], entity1) == nil)

		-- member1 and member2 have the entity with both components (postponed restored)
		CHECK(client_entity(members[1], entity1) ~= nil)
		CHECK(client_component(members[1], entity1, 1) == "hello")
		CHECK(client_component(members[1], entity1, 2) == "world")

		CHECK(client_entity(members[2], entity1) ~= nil)
		CHECK(client_component(members[2], entity1, 1) == "hello")
		CHECK(client_component(members[2], entity1, 2) == "world")
	end)

	CASE("same-frame stop + start may delete-then-recreate for overlapping members", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(2)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1, nil)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		full_sync(members, entity1)

		-- stop and restart in same frame: cross-storage ordering is non-deterministic
		-- for overlapping members. Verify the server-side state is correct regardless.
		server:stop_networked(entity1)
		server:set_networked(entity1, nil)

		-- server should have the entity networked with the same components
		CHECK(server.track_info.networked[entity1] == true)
		CHECK(server.storage[entity1] ~= nil)
		CHECK(server.storage[entity1].components[components[1]] == "initial")
	end)

	CASE("deallocate_entity_stop is a no-op does not break blacklist flow", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(2)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1, nil)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "v1")

		full_sync(members, entity1)

		-- stop -> blacklist -> restart in same frame
		server:stop_networked(entity1)
		server:set_networked(entity1, { [members[2] :: any] = true })
		apply_updates(members)

		-- member1 was cleanly removed (deletion from old storage group)
		CHECK(client_entity(members[1], entity1) == nil)

		-- member2 was recreated
		CHECK(client_entity(members[2], entity1) ~= nil)
		CHECK(client_component(members[2], entity1, 1) == "v1")

		-- update value on server, should replicate to member2 only
		world:set(entity1, components[1], "v2")
		apply_updates(members)

		CHECK(client_component(members[2], entity1, 1) == "v2")
		-- member1 is still nil
		CHECK(client_entity(members[1], entity1) == nil)
	end)
end)

TEST("filter deletions", function()
	local world: jecs.World = nil :: any
	local server: replecs.Server = nil :: any

	BEFORE_EACH(function()
		world = jecs.world()
		server = replecs.create_server(world)
	end)

	AFTER_EACH(function()
		server:destroy()
	end)

	local function create_members_data(count: number?)
		local members = {} :: { MemberData }
		for i = 1, (count or 3) do
			local new_world = jecs.world()
			local components = create_test_components(new_world)
			local tags = create_test_tags(new_world)
			local replicator = replecs.create_client(new_world)

			local member_mt = {
				world = new_world,
				client = replicator,
				components = components,
				tags = tags,
			}
			local member = newproxy(true)
			getmetatable(member).__index = member_mt

			server.masking:register_client(member)
			table.insert(members, member :: MemberData)
		end
		return members
	end

	local function client_entity(member: MemberData, server_entity: jecs.Entity): jecs.Entity?
		local entity = member.client.server_ids[server_entity :: any]
		if entity and member.world:contains(entity) then
			return entity
		end
		return nil
	end

	local function client_component(member: MemberData, server_entity: jecs.Entity, component_index: number)
		local component = member.components[component_index]
		local entity = client_entity(member, server_entity)
		if entity then
			return member.world:get(entity, component)
		end
		return nil
	end

	local function init_and_activate(members: { MemberData })
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end
	end

	local function full_sync(members: { MemberData })
		for _, member in members do
			local buf, variants = server:get_full(member :: any)
			member.client:apply_full(buf, variants)
		end
	end

	local function drain_updates(members: { MemberData })
		for player, buf, changes in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(buf, changes)
		end
	end

	CASE("should send entity deletion to removed players when keep=false (default)", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(3)
		init_and_activate(members)
		full_sync(members)

		local entity1 = world:entity()
		server:set_networked(
			entity1,
			filter {
				[members[1]] = true,
				[members[2]] = true,
				[members[3]] = true,
			}
		)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "hello")

		drain_updates(members)
		full_sync(members)

		-- All members should see entity
		CHECK(client_entity(members[1], entity1) ~= nil)
		CHECK(client_entity(members[2], entity1) ~= nil)
		CHECK(client_entity(members[3], entity1) ~= nil)

		-- Change filter: remove member3 (default keep=false)
		server:set_networked(
			entity1,
			filter {
				[members[1]] = true,
				[members[2]] = true,
			}
		)

		-- collect_updates should send entity deletion to member3
		drain_updates(members)

		-- member3 should no longer see entity
		CHECK(client_entity(members[3], entity1) == nil)
		-- members 1,2 should still see entity
		CHECK(client_entity(members[1], entity1) ~= nil)
		CHECK(client_entity(members[2], entity1) ~= nil)
		CHECK(client_component(members[1], entity1, 1) == "hello")
		CHECK(client_component(members[2], entity1, 1) == "hello")
	end)

	CASE("should NOT send deletion when keep=true, but track kept players", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(3)
		init_and_activate(members)
		full_sync(members)

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "secret")

		drain_updates(members)
		full_sync(members)

		CHECK(client_entity(members[1], entity1) ~= nil)
		CHECK(client_entity(members[2], entity1) ~= nil)
		CHECK(client_entity(members[3], entity1) ~= nil)

		-- Change filter with keep=true: exclude member3
		server:set_networked(
			entity1,
			filter {
				[members[1]] = true,
				[members[2]] = true,
			},
			true
		)

		-- collect_updates should NOT send entity deletion
		drain_updates(members)

		-- member3 should still see entity (no deletion sent)
		CHECK(client_entity(members[3], entity1) ~= nil)
		CHECK(client_component(members[3], entity1, 1) == "secret")
		-- members 1,2 should still see entity
		CHECK(client_entity(members[1], entity1) ~= nil)
		CHECK(client_entity(members[2], entity1) ~= nil)

		-- Check that kept_deletions has the entity for member3
		local kept = server.masking.lookups.kept_deletions
		CHECK(kept.entities[entity1] ~= nil)
	end)

	CASE("should flush kept deletions when entity is stopped (stop_networked without keep)", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(3)
		init_and_activate(members)
		full_sync(members)

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "data")

		drain_updates(members)
		full_sync(members)

		-- keep=true: exclude member3
		server:set_networked(
			entity1,
			filter {
				[members[1]] = true,
				[members[2]] = true,
			},
			true
		)

		drain_updates(members)

		-- member3 still sees entity
		CHECK(client_entity(members[3], entity1) ~= nil)

		-- Now stop_networked without keep (default): should send deletions to ALL
		-- including kept players
		server:stop_networked(entity1)

		drain_updates(members)

		-- All members should no longer see entity
		CHECK(client_entity(members[1], entity1) == nil)
		CHECK(client_entity(members[2], entity1) == nil)
		CHECK(client_entity(members[3], entity1) == nil)
	end)

	CASE("should discard kept deletions when entity is stopped with keep=true", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(3)
		init_and_activate(members)
		full_sync(members)

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "data")

		drain_updates(members)
		full_sync(members)

		-- keep=true: exclude member3
		server:set_networked(
			entity1,
			filter {
				[members[1]] = true,
				[members[2]] = true,
			},
			true
		)

		drain_updates(members)

		-- stop_networked with keep=true: no deletions sent
		server:stop_networked(entity1, true)

		drain_updates(members)

		-- member3 should still see entity (no deletion)
		CHECK(client_entity(members[3], entity1) ~= nil)
		-- members 1,2 should also still see entity
		CHECK(client_entity(members[1], entity1) ~= nil)
		CHECK(client_entity(members[2], entity1) ~= nil)
	end)

	CASE("should send component deletion to removed players via component filter", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(3)
		init_and_activate(members)
		full_sync(members)

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		server:set_reliable(
			entity1,
			components[2],
			filter {
				[members[1]] = true,
				[members[2]] = true,
				[members[3]] = true,
			}
		)
		world:set(entity1, components[1], "shared")
		world:set(entity1, components[2], "filtered")

		drain_updates(members)
		full_sync(members)

		CHECK(client_component(members[1], entity1, 2) == "filtered")
		CHECK(client_component(members[2], entity1, 2) == "filtered")
		CHECK(client_component(members[3], entity1, 2) == "filtered")

		-- Change component filter: remove member3 (keep=false)
		server:set_reliable(
			entity1,
			components[2],
			filter {
				[members[1]] = true,
				[members[2]] = true,
			}
		)

		drain_updates(members)

		-- member3 should lose component2 but keep component1 and entity
		CHECK(client_entity(members[3], entity1) ~= nil)
		CHECK(client_component(members[3], entity1, 1) == "shared")
		CHECK(client_component(members[3], entity1, 2) == nil)

		-- members 1,2 should still have both
		CHECK(client_component(members[1], entity1, 2) == "filtered")
		CHECK(client_component(members[2], entity1, 2) == "filtered")
	end)

	CASE("should clean up filter deletions on player removal", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(3)
		init_and_activate(members)
		full_sync(members)

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "data")

		drain_updates(members)
		full_sync(members)

		-- keep=true: exclude member3
		server:set_networked(
			entity1,
			filter {
				[members[1]] = true,
				[members[2]] = true,
			},
			true
		)

		drain_updates(members)

		-- Verify kept_deletions has data for member3
		local kept = server.masking.lookups.kept_deletions
		CHECK(kept.entities[entity1] ~= nil)

		-- Remove member3 (simulating player leaving)
		server.masking:unregister_client(members[3] :: any)

		-- kept_deletions bitmask should have member3's bit cleared
		-- Since this was the only kept player, the bitmask should be empty
		local kept_after = server.masking.lookups.kept_deletions
		if kept_after.entities[entity1] then
			CHECK(kept_after.entities[entity1]:is_zero())
		end
	end)

	CASE("should clean up filter deletions on entity deletion", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(3)
		init_and_activate(members)
		full_sync(members)

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "data")

		drain_updates(members)
		full_sync(members)

		-- keep=true: exclude member3
		server:set_networked(
			entity1,
			filter {
				[members[1]] = true,
				[members[2]] = true,
			},
			true
		)

		drain_updates(members)

		-- Delete entity
		world:delete(entity1)

		-- Drain updates (deletions sent including flushed kept)
		drain_updates(members)

		-- All members should see entity deleted
		CHECK(client_entity(members[1], entity1) == nil)
		CHECK(client_entity(members[2], entity1) == nil)
		CHECK(client_entity(members[3], entity1) == nil)

		-- After cleanup, filter deletions should be empty for this entity
		CHECK(server.masking.lookups.filter_deletions.entities[entity1] == nil)
		CHECK(server.masking.lookups.filter_deletions.components[entity1] == nil)
		CHECK(server.masking.lookups.kept_deletions.entities[entity1] == nil)
		CHECK(server.masking.lookups.kept_deletions.components[entity1] == nil)
	end)

	CASE("no memory leak: repeated filter changes should not leak filter deletion data", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(3)
		init_and_activate(members)
		full_sync(members)

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "data")

		drain_updates(members)
		full_sync(members)

		-- Repeatedly change filter with keep=true then back
		for i = 1, 10 do
			-- Exclude member3 with keep=true
			server:set_networked(
				entity1,
				filter {
					[members[1]] = true,
					[members[2]] = true,
				},
				true
			)
			-- Re-include everyone
			server:set_networked(entity1)
			-- Drain updates to prevent buildup
			drain_updates(members)
		end

		-- No kept_deletions should remain (re-including clears them via fresh bitmask)
		-- filter_deletions should also be clean after drain
		local filter_del = server.masking.lookups.filter_deletions
		CHECK(filter_del.entities[entity1] == nil)
		CHECK(filter_del.components[entity1] == nil)
	end)

	CASE("no memory leak: player removal should clean all filter deletion bitmasks", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(3)
		init_and_activate(members)
		full_sync(members)

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "data")

		local entity2 = world:entity()
		server:set_networked(entity2)
		server:set_reliable(entity2, components[1])
		world:set(entity2, components[1], "data2")

		drain_updates(members)
		full_sync(members)

		-- Exclude member3 with keep=true on both entities
		server:set_networked(
			entity1,
			filter {
				[members[1]] = true,
				[members[2]] = true,
			},
			true
		)
		server:set_networked(
			entity2,
			filter {
				[members[1]] = true,
				[members[2]] = true,
			},
			true
		)

		drain_updates(members)

		-- Both entities should have kept_deletions
		CHECK(server.masking.lookups.kept_deletions.entities[entity1] ~= nil)
		CHECK(server.masking.lookups.kept_deletions.entities[entity2] ~= nil)

		-- Remove member3
		server.masking:unregister_client(members[3] :: any)

		-- Kept deletion bitmasks should have member3's bit cleared
		local kept = server.masking.lookups.kept_deletions
		if kept.entities[entity1] then
			CHECK(kept.entities[entity1]:is_zero())
		end
		if kept.entities[entity2] then
			CHECK(kept.entities[entity2]:is_zero())
		end
	end)

	CASE("no memory leak: entity delete + player leave combination", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(3)
		init_and_activate(members)
		full_sync(members)

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "data")

		drain_updates(members)
		full_sync(members)

		-- keep=true: exclude member3
		server:set_networked(
			entity1,
			filter {
				[members[1]] = true,
				[members[2]] = true,
			},
			true
		)

		drain_updates(members)

		-- Delete entity
		world:delete(entity1)
		drain_updates(members)

		-- Remove member3
		server.masking:unregister_client(members[3] :: any)

		-- All filter data should be cleaned
		CHECK(server.masking.lookups.filter_deletions.entities[entity1] == nil)
		CHECK(server.masking.lookups.filter_deletions.components[entity1] == nil)
		CHECK(server.masking.lookups.kept_deletions.entities[entity1] == nil)
		CHECK(server.masking.lookups.kept_deletions.components[entity1] == nil)

		-- Entity lookup should be gone
		CHECK(server.masking.lookups.entities[entity1] == nil)
		CHECK(server.storage[entity1] == nil)
	end)

	CASE("should re-include kept player and clear their kept deletion entry", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(3)
		init_and_activate(members)
		full_sync(members)

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "hello")

		drain_updates(members)
		full_sync(members)

		-- All members should see entity
		CHECK(client_entity(members[1], entity1) ~= nil)
		CHECK(client_entity(members[2], entity1) ~= nil)
		CHECK(client_entity(members[3], entity1) ~= nil)

		-- Exclude member3 with keep=true
		server:set_networked(
			entity1,
			filter {
				[members[1]] = true,
				[members[2]] = true,
			},
			true
		)

		-- kept_deletions should track member3
		CHECK(server.masking.lookups.kept_deletions.entities[entity1] ~= nil)

		-- Re-include all members
		server:set_networked(entity1)

		drain_updates(members)

		-- kept_deletions should be clean (re-including generates new bitmask that includes all)
		local kept = server.masking.lookups.kept_deletions
		if kept.entities[entity1] then
			CHECK(kept.entities[entity1]:is_zero())
		end

		-- All members should still see entity with correct data
		CHECK(client_entity(members[1], entity1) ~= nil)
		CHECK(client_entity(members[2], entity1) ~= nil)
		CHECK(client_entity(members[3], entity1) ~= nil)
		CHECK(client_component(members[1], entity1, 1) == "hello")
		CHECK(client_component(members[2], entity1, 1) == "hello")
		CHECK(client_component(members[3], entity1, 1) == "hello")

		-- Update value, all should receive it
		world:set(entity1, components[1], "updated")
		drain_updates(members)

		CHECK(client_component(members[1], entity1, 1) == "updated")
		CHECK(client_component(members[2], entity1, 1) == "updated")
		CHECK(client_component(members[3], entity1, 1) == "updated")
	end)

	CASE("should handle re-inclusion after keep=true stop then re-start", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(3)
		init_and_activate(members)
		full_sync(members)

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "before")

		drain_updates(members)
		full_sync(members)

		-- Exclude member3 with keep=true
		server:set_networked(
			entity1,
			filter {
				[members[1]] = true,
				[members[2]] = true,
			},
			true
		)

		drain_updates(members)

		-- Stop entity (flushes kept deletions -> filter deletions)
		-- member3 should receive deletion
		server:stop_networked(entity1)

		drain_updates(members)

		CHECK(client_entity(members[1], entity1) == nil)
		CHECK(client_entity(members[2], entity1) == nil)
		CHECK(client_entity(members[3], entity1) == nil)

		-- Re-start entity with all members
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "after")

		drain_updates(members)
		full_sync(members)

		-- All members should see entity with new data
		CHECK(client_entity(members[1], entity1) ~= nil)
		CHECK(client_entity(members[2], entity1) ~= nil)
		CHECK(client_entity(members[3], entity1) ~= nil)
		CHECK(client_component(members[1], entity1, 1) == "after")
		CHECK(client_component(members[2], entity1, 1) == "after")
		CHECK(client_component(members[3], entity1, 1) == "after")
	end)

	CASE("should clear filter_deletions when exclude (no keep) then immediately re-include", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(3)
		init_and_activate(members)
		full_sync(members)

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "v1")

		drain_updates(members)
		full_sync(members)

		CHECK(client_entity(members[3], entity1) ~= nil)

		-- Exclude member3 without keep (default)
		server:set_networked(
			entity1,
			filter {
				[members[1]] = true,
				[members[2]] = true,
			}
		)

		-- filter_deletions should have entity for member3
		CHECK(server.masking.lookups.filter_deletions.entities[entity1] ~= nil)

		-- Immediately re-include everyone (no drain in between)
		server:set_networked(entity1)

		-- filter_deletions should be cleared (member3 re-included)
		local fd = server.masking.lookups.filter_deletions
		if fd.entities[entity1] then
			CHECK(fd.entities[entity1]:is_zero())
		end

		-- Drain should produce no deletions
		drain_updates(members)

		-- All members should still see entity
		CHECK(client_entity(members[1], entity1) ~= nil)
		CHECK(client_entity(members[2], entity1) ~= nil)
		CHECK(client_entity(members[3], entity1) ~= nil)
		CHECK(client_component(members[3], entity1, 1) == "v1")
	end)

	CASE("should re-include player after exclude (no keep) + drain (deletion already sent)", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(3)
		init_and_activate(members)
		full_sync(members)

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "before")

		drain_updates(members)
		full_sync(members)

		-- Exclude member3 without keep
		server:set_networked(
			entity1,
			filter {
				[members[1]] = true,
				[members[2]] = true,
			}
		)

		-- Drain: deletion sent to member3
		drain_updates(members)

		-- member3 should no longer see entity
		CHECK(client_entity(members[3], entity1) == nil)
		CHECK(client_entity(members[1], entity1) ~= nil)
		CHECK(client_entity(members[2], entity1) ~= nil)

		-- Re-include all members
		server:set_networked(entity1)

		-- Drain: member3 should receive the entity again
		drain_updates(members)
		full_sync(members)

		-- All members should see entity with data
		CHECK(client_entity(members[1], entity1) ~= nil)
		CHECK(client_entity(members[2], entity1) ~= nil)
		CHECK(client_entity(members[3], entity1) ~= nil)
		CHECK(client_component(members[3], entity1, 1) == "before")

		-- Update value, all should receive it
		world:set(entity1, components[1], "after")
		drain_updates(members)

		CHECK(client_component(members[1], entity1, 1) == "after")
		CHECK(client_component(members[2], entity1, 1) == "after")
		CHECK(client_component(members[3], entity1, 1) == "after")
	end)

	CASE("should NOT send spurious deletion to re-included player on stop after keep=true re-include", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(3)
		init_and_activate(members)
		full_sync(members)

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "data")

		drain_updates(members)
		full_sync(members)

		-- Exclude member3 with keep=true
		server:set_networked(
			entity1,
			filter {
				[members[1]] = true,
				[members[2]] = true,
			},
			true
		)

		drain_updates(members)

		-- Re-include member3
		server:set_networked(entity1)

		drain_updates(members)

		-- Verify kept_deletions was cleaned for re-included player
		local kept = server.masking.lookups.kept_deletions
		if kept.entities[entity1] then
			CHECK(kept.entities[entity1]:is_zero())
		end

		-- member3 should still see entity
		CHECK(client_entity(members[3], entity1) ~= nil)

		-- Now stop without keep -- should only send deletion for entity-level stop
		-- NOT for the stale kept entry (which was cleaned)
		server:stop_networked(entity1)

		drain_updates(members)

		-- All should see entity deleted
		CHECK(client_entity(members[1], entity1) == nil)
		CHECK(client_entity(members[2], entity1) == nil)
		CHECK(client_entity(members[3], entity1) == nil)
	end)

	CASE("should re-include player after exclude (no keep) + drain and receive subsequent updates", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(3)
		init_and_activate(members)
		full_sync(members)

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "v1")

		drain_updates(members)
		full_sync(members)

		-- Exclude member3 without keep
		server:set_networked(
			entity1,
			filter {
				[members[1]] = true,
				[members[2]] = true,
			}
		)

		-- Drain: deletion sent
		drain_updates(members)
		CHECK(client_entity(members[3], entity1) == nil)

		-- Update value while member3 is excluded
		world:set(entity1, components[1], "v2")
		drain_updates(members)

		-- member1,2 should have v2
		CHECK(client_component(members[1], entity1, 1) == "v2")
		CHECK(client_component(members[2], entity1, 1) == "v2")

		-- Re-include all members
		server:set_networked(entity1)

		-- Drain + full sync so member3 gets the entity back
		drain_updates(members)
		full_sync(members)

		-- member3 should now have entity with latest value
		CHECK(client_entity(members[3], entity1) ~= nil)
		CHECK(client_component(members[3], entity1, 1) == "v2")

		-- Update value again, all should receive
		world:set(entity1, components[1], "v3")
		drain_updates(members)

		CHECK(client_component(members[1], entity1, 1) == "v3")
		CHECK(client_component(members[2], entity1, 1) == "v3")
		CHECK(client_component(members[3], entity1, 1) == "v3")
	end)

	CASE("should re-include player on component filter after keep=true exclusion", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(3)
		init_and_activate(members)
		full_sync(members)

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		server:set_reliable(
			entity1,
			components[2],
			filter {
				[members[1]] = true,
				[members[2]] = true,
				[members[3]] = true,
			}
		)
		world:set(entity1, components[1], "base")
		world:set(entity1, components[2], "filtered")

		drain_updates(members)
		full_sync(members)

		CHECK(client_component(members[3], entity1, 2) == "filtered")

		-- Exclude member3 from component filter with keep=true
		server:set_reliable(
			entity1,
			components[2],
			filter {
				[members[1]] = true,
				[members[2]] = true,
			},
			true
		)

		drain_updates(members)

		-- member3 still sees component (keep=true, no deletion sent)
		CHECK(client_component(members[3], entity1, 2) == "filtered")

		-- Re-include member3 in component filter
		server:set_reliable(
			entity1,
			components[2],
			filter {
				[members[1]] = true,
				[members[2]] = true,
				[members[3]] = true,
			}
		)

		drain_updates(members)

		-- Update component value
		world:set(entity1, components[2], "updated_filtered")
		drain_updates(members)

		-- All members should receive the update
		CHECK(client_component(members[1], entity1, 2) == "updated_filtered")
		CHECK(client_component(members[2], entity1, 2) == "updated_filtered")
		CHECK(client_component(members[3], entity1, 2) == "updated_filtered")
	end)
end)

local report = testlib.run(plan)
testlib.report(report)
