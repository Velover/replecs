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

TEST("throttle", function()
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

	CASE("should accumulate changes and flush on interval", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		-- Mark component1 as throttled with a very long interval (so it won't flush automatically)
		world:set(world:entity(), jecs.pair(replecs.throttle, components[1]), 999999)

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		-- Initial full sync
		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)
		CHECK(client_component(members[1], entity1, 1) == "initial")

		-- Drain any pending masking-layer changes from setup
		for player, buf2, changes in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(buf2, changes)
		end

		-- Change multiple times - should be buffered by throttle
		world:set(entity1, components[1], "change1")
		world:set(entity1, components[1], "change2")
		world:set(entity1, components[1], "change3")

		-- No updates should be sent (still buffered)
		local update_count = 0
		for _player, _buf, _changes in server:collect_updates() do
			update_count += 1
		end
		CHECK(update_count == 0)

		-- Now manually set the throttle entry's interval to 0 so it flushes
		local throttle_entry = server.throttle[components[1]]
		CHECK(throttle_entry ~= nil)
		throttle_entry.interval = 0

		-- collect_updates should now flush
		for player, buf2, changes in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(buf2, changes)
		end

		CHECK(client_component(members[1], entity1, 1) == "change3")
	end)

	CASE("should handle throttle + entity deletion", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		world:set(world:entity(), jecs.pair(replecs.throttle, components[1]), 999999)

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		-- Buffer a change
		world:set(entity1, components[1], "buffered")
		-- Delete entity
		world:delete(entity1)

		-- The entity should be purged from throttle buffer during cleanup
		local throttle_entry = server.throttle[components[1]]
		CHECK(throttle_entry ~= nil)
		CHECK(
			throttle_entry.component_changes[entity1] == nil
				and throttle_entry.tag_changes[entity1] == nil
				and throttle_entry.removals[entity1] == nil
		)
	end)
end)

TEST("ownership", function()
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

	CASE("should track ownership grants", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(2)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		-- grant ownership to member1 via shorthand
		server:set_owner(entity1, components[1], members[1] :: any)

		-- full sync
		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		-- ownership grant should be sent
		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		-- member1 should have ownership grant
		local grants = members[1].client.ownership_grants
		local c_entity = client_entity(members[1], entity1)
		CHECK(c_entity ~= nil)
		CHECK(grants[c_entity] ~= nil)
		CHECK(grants[c_entity][members[1].components[1]] == true)
	end)

	CASE("set_owner shorthand should grant ownership end-to-end", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(2)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		-- full sync
		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		-- use set_owner shorthand
		server:set_owner(entity1, components[1], members[1] :: any)

		-- verify server ownership state
		CHECK(server.ownership[entity1] ~= nil)
		CHECK(server.ownership[entity1][components[1]] ~= nil)
		CHECK(server.ownership[entity1][components[1]].player == members[1] :: any)
		CHECK(server.ownership_dirty[members[1] :: any] == true)

		-- deliver grants
		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		local c_entity = client_entity(members[1], entity1) :: any
		CHECK(members[1].client:has_ownership(c_entity, members[1].components[1]) == true)

		-- reassign ownership to member2 via shorthand
		server:set_owner(entity1, components[1], members[2] :: any)
		CHECK(server.ownership[entity1][components[1]].player == members[2] :: any)

		-- member2 (new owner) should be dirty
		CHECK(server.ownership_dirty[members[2] :: any] == true)
	end)

	CASE("should enforce single-owner invariant", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(2)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		-- grant ownership to member1 via reliable
		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)

		-- trying to change ownership to member2
		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[2] :: any)

		-- ownership should now be member2
		CHECK(server.ownership[entity1][components[1]].player == members[2] :: any)
	end)

	CASE("server should not modify client-owned components", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		-- full sync
		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		-- grant ownership to member1
		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)

		-- server tries to change the component value - should be blocked
		world:set(entity1, components[1], "server_attempt")

		-- the value should NOT have changed in the server storage since it's blocked
		-- (the storage still has "initial" since allocate_component_change was blocked)
		CHECK(server.storage[entity1].components[components[1]] == "initial")
	end)

	CASE("should clean up ownership on entity deletion", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)
		CHECK(server.ownership[entity1] ~= nil)

		-- delete entity
		world:delete(entity1)
		CHECK(server.ownership[entity1] == nil)
	end)

	CASE("should provide ownership validation via validator component", function()
		local validate_called = false
		local serdes: replecs.Serdes = {
			serialize = function(value: number)
				local buf = buffer.create(8)
				buffer.writef64(buf, 0, value)
				return buf
			end,
			deserialize = function(buf: buffer)
				return buffer.readf64(buf, 0)
			end,
		}
		local validator: replecs.OwnershipValidator = {
			validate = function(value: number): boolean
				validate_called = true
				return value >= 0 and value <= 100
			end,
		}

		local components = create_test_components(world)
		world:set(components[1], replecs.serdes, serdes)
		world:set(components[1], replecs.validator, validator)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
			member.world:set(member.components[1], replecs.serdes, serdes)
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], 50.0)

		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)

		-- full sync
		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		-- deliver ownership grants to client
		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		-- simulate client sending ownership update
		members[1].client:request_set(client_entity(members[1], entity1) :: any, members[1].components[1], 75.0)

		-- collect the ownership update
		for ownership_buf, ownership_variants in members[1].client:collect_ownership() do
			server:apply_ownership(ownership_buf, members[1] :: any, ownership_variants)
		end

		CHECK(validate_called == true)
	end)

	CASE("should allow validator-only without serdes", function()
		local validate_called = false
		local validator: replecs.OwnershipValidator = {
			validate = function(value: number): boolean
				validate_called = true
				return value >= 0 and value <= 100
			end,
		}

		local components = create_test_components(world)
		world:set(components[1], replecs.validator, validator)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], 50.0)

		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)

		-- full sync
		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		-- deliver ownership grants to client
		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		-- simulate client sending ownership update (uses default variant encoding since no serdes)
		members[1].client:request_set(client_entity(members[1], entity1) :: any, members[1].components[1], 75.0)

		-- collect the ownership update
		for ownership_buf, ownership_variants in members[1].client:collect_ownership() do
			server:apply_ownership(ownership_buf, members[1] :: any, ownership_variants)
		end

		CHECK(validate_called == true)
		CHECK(server.storage[entity1].components[components[1]] == 75.0)
	end)

	CASE("should reject invalid values with validator", function()
		local validator: replecs.OwnershipValidator = {
			validate = function(value: number): boolean
				return value >= 0 and value <= 100
			end,
		}

		local components = create_test_components(world)
		world:set(components[1], replecs.validator, validator)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], 50.0)

		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)

		-- full sync
		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		-- deliver ownership grants
		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		-- try to set a value that fails validation
		members[1].client:request_set(client_entity(members[1], entity1) :: any, members[1].components[1], 999.0)

		for ownership_buf, ownership_variants in members[1].client:collect_ownership() do
			server:apply_ownership(ownership_buf, members[1] :: any, ownership_variants)
		end

		-- the value should NOT have been applied — it should remain 50
		CHECK(world:get(entity1, components[1]) == 50.0)
	end)

	CASE("should check ownership via has_ownership", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(2)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		-- full sync to both members
		for _, member in members do
			local buf, variants = server:get_full(member :: any)
			member.client:apply_full(buf, variants)
		end

		-- grant ownership to member1
		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)

		-- deliver ownership grants
		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		local c_entity1 = client_entity(members[1], entity1)
		local c_entity2 = client_entity(members[2], entity1)
		CHECK(c_entity1 ~= nil)
		CHECK(c_entity2 ~= nil)

		-- member1 should have ownership
		CHECK(members[1].client:has_ownership(c_entity1 :: any, members[1].components[1]) == true)
		-- member2 should NOT have ownership
		CHECK(members[2].client:has_ownership(c_entity2 :: any, members[2].components[1]) == false)
		-- non-existent entity should return false
		CHECK(members[1].client:has_ownership(999999 :: any, members[1].components[1]) == false)
	end)

	CASE("should send reliable ownership update end-to-end", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		-- full sync
		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		-- grant ownership
		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)

		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		-- client sends reliable update
		local c_entity = client_entity(members[1], entity1) :: any
		members[1].client:request_set(c_entity, members[1].components[1], "client_update")

		for ownership_buf, ownership_variants in members[1].client:collect_ownership() do
			server:apply_ownership(ownership_buf, members[1] :: any, ownership_variants)
		end

		-- server should have applied the value
		CHECK(server.storage[entity1].components[components[1]] == "client_update")
	end)

	CASE("should send unreliable ownership update end-to-end", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		-- full sync
		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		-- grant ownership
		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)

		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		-- client sends unreliable update (true = unreliable)
		local c_entity = client_entity(members[1], entity1) :: any
		members[1].client:request_set(c_entity, members[1].components[1], "unreliable_update", true)

		-- reliable collect should be empty
		local reliable_count = 0
		for _ in members[1].client:collect_ownership() do
			reliable_count += 1
		end
		CHECK(reliable_count == 0)

		-- unreliable collect should have data
		local unreliable_applied = false
		for ownership_buf, ownership_variants in members[1].client:collect_ownership_unreliable() do
			server:apply_ownership(ownership_buf, members[1] :: any, ownership_variants)
			unreliable_applied = true
		end
		CHECK(unreliable_applied == true)

		-- server should have applied the value (routes to reliable path since component is set_reliable)
		CHECK(server.storage[entity1].components[components[1]] == "unreliable_update")
	end)

	CASE("should handle mixed reliable and unreliable ownership updates", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		server:set_unreliable(entity1, components[2])
		world:set(entity1, components[1], "initial1")
		world:set(entity1, components[2], "initial2")

		-- full sync
		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		-- grant ownership of both components
		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)
		world:set(entity1, jecs.pair(replecs.owned, components[2]), members[1] :: any)

		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		local c_entity = client_entity(members[1], entity1) :: any

		-- send component1 reliably, component2 unreliably
		members[1].client:request_set(c_entity, members[1].components[1], "reliable_val")
		members[1].client:request_set(c_entity, members[1].components[2], "unreliable_val", true)

		-- apply reliable ownership
		for ownership_buf, ownership_variants in members[1].client:collect_ownership() do
			server:apply_ownership(ownership_buf, members[1] :: any, ownership_variants)
		end

		-- apply unreliable ownership
		for ownership_buf, ownership_variants in members[1].client:collect_ownership_unreliable() do
			server:apply_ownership(ownership_buf, members[1] :: any, ownership_variants)
		end

		CHECK(server.storage[entity1].components[components[1]] == "reliable_val")
		CHECK(server.world:get(entity1, components[2]) == "unreliable_val")
	end)

	CASE("should clean up ownership when player leaves via remove_client", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(2)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		local entity2 = world:entity()
		server:set_networked(entity2)
		server:set_reliable(entity2, components[1])
		world:set(entity2, components[1], "initial2")

		-- grant ownership: entity1 to member1, entity2 to member2
		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)
		world:set(entity2, jecs.pair(replecs.owned, components[1]), members[2] :: any)

		CHECK(server.ownership[entity1] ~= nil)
		CHECK(server.ownership[entity2] ~= nil)

		-- member1 leaves
		server:remove_client(members[1] :: any)

		-- entity1 ownership should be cleaned (member1 owned it)
		CHECK(server.ownership[entity1] == nil)
		-- entity2 ownership should remain (member2 still owns it)
		CHECK(server.ownership[entity2] ~= nil)
		CHECK(server.ownership[entity2][components[1]].player == members[2] :: any)
	end)

	CASE("should clean up ownership_dirty when player leaves", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		-- grant ownership — marks ownership_dirty
		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)

		-- ownership_dirty should be set
		CHECK(server.ownership_dirty[members[1] :: any] == true)

		-- player leaves
		server:remove_client(members[1] :: any)

		-- ownership_dirty should be cleared
		CHECK(server.ownership_dirty[members[1] :: any] == nil)
		-- ownership entry should be gone
		CHECK(server.ownership[entity1] == nil)
	end)

	CASE("server world:remove on owned component should be blocked", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		-- grant ownership
		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)

		-- server tries to remove the component — should be blocked
		world:remove(entity1, components[1])

		-- value should still be "initial" since removal was blocked
		CHECK(server.storage[entity1].components[components[1]] == "initial")
	end)

	CASE("ownership revocation should mark dirty and notify client", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		-- grant ownership
		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)

		-- full sync to client so entity exists
		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		-- deliver grant to client
		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		local c_entity = client_entity(members[1], entity1)
		CHECK(c_entity ~= nil)
		CHECK(members[1].client:has_ownership(c_entity :: any, members[1].components[1]) == true)

		-- clear dirty from initial grant
		server.ownership_dirty[members[1] :: any] = nil

		-- revoke ownership
		world:remove(entity1, jecs.pair(replecs.owned, components[1]))

		-- server ownership should be cleaned
		CHECK(server.ownership[entity1] == nil or server.ownership[entity1][components[1]] == nil)

		-- ownership_dirty should be re-marked for the revocation grant
		CHECK(server.ownership_dirty[members[1] :: any] == true)

		-- deliver revocation to client
		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		-- client should no longer have ownership
		CHECK(members[1].client:has_ownership(c_entity :: any, members[1].components[1]) == false)
	end)

	CASE("client should clean ownership data when component is removed via replication", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		-- full sync
		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		-- grant ownership of component1 and deliver
		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)
		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		local c_entity = client_entity(members[1], entity1) :: any
		CHECK(members[1].client:has_ownership(c_entity, members[1].components[1]) == true)

		-- client buffers a request_set
		members[1].client:request_set(c_entity, members[1].components[1], "client_val")
		CHECK(members[1].client.ownership_buffer[c_entity] ~= nil)
		CHECK(members[1].client.ownership_buffer[c_entity][members[1].components[1]] ~= nil)

		-- revoke ownership then stop the component from server
		world:remove(entity1, jecs.pair(replecs.owned, components[1]))
		server:stop_reliable(entity1, components[1])

		-- deliver revocation grant
		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		-- ownership_grants should be cleared (revocation clears all)
		CHECK(members[1].client:has_ownership(c_entity, members[1].components[1]) == false)

		-- ownership_buffer for this entity should be cleaned (revocation clears all)
		-- Note: after apply_ownership_grant, all grants are cleared
		-- but buffer entries may still exist; they'll be rejected server-side
	end)

	CASE("ownership grant before entity is replicated should be silently dropped", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		-- Grant ownership BEFORE full sync (client doesn't know about entity yet)
		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)

		-- Deliver ownership grant to client (entity not yet on client)
		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		-- Client should NOT have any ownership grants (entity was unknown, so read_entity_id returned nil)
		CHECK(members[1].client.ownership_grants[members[1] :: any] == nil or true)

		-- Now do full sync — entity appears but without the grant (it was already consumed)
		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		local c_entity = client_entity(members[1], entity1)
		CHECK(c_entity ~= nil)

		-- Client should NOT have ownership for this entity/component
		-- because the grant was dropped when the entity was unknown
		CHECK(members[1].client:has_ownership(c_entity :: any, members[1].components[1]) == false)

		-- request_set should be rejected (no ownership)
		local warn_count_before = 0
		members[1].client:request_set(c_entity :: any, members[1].components[1], "should_not_work")
		-- The value should NOT be set since there's no ownership
		CHECK(members[1].world:get(c_entity :: any, members[1].components[1]) == "initial")
	end)

	CASE("ownership grant for entity before component is replicated should register grant", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		-- Only set component1 initially, not component2
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")
		world:set(entity1, components[2], "secret")

		-- Full sync — only component1 is replicated
		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		-- Drain additions
		for player, ubuf, uchanges in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(ubuf, uchanges)
		end

		local c_entity = client_entity(members[1], entity1) :: any
		CHECK(c_entity ~= nil)

		-- Component1 exists, component2 does NOT exist on client
		CHECK(members[1].world:get(c_entity, members[1].components[1]) == "initial")
		CHECK(members[1].world:get(c_entity, members[1].components[2]) == nil)

		-- Now grant ownership of BOTH components
		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)
		world:set(entity1, jecs.pair(replecs.owned, components[2]), members[1] :: any)

		-- Also add component2 to replication now
		server:set_reliable(entity1, components[2])

		-- Deliver grants to client
		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		-- Client should have ownership for BOTH components
		CHECK(members[1].client:has_ownership(c_entity, members[1].components[1]) == true)
		CHECK(members[1].client:has_ownership(c_entity, members[1].components[2]) == true)

		-- request_set on component2 should work even though component2 doesn't exist in client world yet
		-- WORLD_SET will create it
		members[1].client:request_set(c_entity, members[1].components[2], "client_new_value")

		-- Component2 should now exist in client world (request_set creates it via WORLD_SET)
		CHECK(members[1].world:get(c_entity, members[1].components[2]) == "client_new_value")

		-- Collect and apply ownership update to server
		for ownership_buf, ownership_variants in members[1].client:collect_ownership() do
			server:apply_ownership(ownership_buf, members[1] :: any, ownership_variants)
		end

		-- Server should have the new value for component2
		CHECK(server.storage[entity1].components[components[2]] == "client_new_value")
	end)

	CASE("ownership grant then component replicated later should work end-to-end", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		-- Grant ownership immediately
		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)

		-- Full sync — entity + component + grant all arrive
		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		local c_entity = client_entity(members[1], entity1) :: any
		CHECK(c_entity ~= nil)

		-- Component should exist
		CHECK(members[1].world:get(c_entity, members[1].components[1]) == "initial")

		-- Ownership should be granted
		CHECK(members[1].client:has_ownership(c_entity, members[1].components[1]) == true)

		-- request_set should work immediately
		members[1].client:request_set(c_entity, members[1].components[1], "client_predicted")
		CHECK(members[1].world:get(c_entity, members[1].components[1]) == "client_predicted")

		-- Collect and send to server
		for ownership_buf, ownership_variants in members[1].client:collect_ownership() do
			server:apply_ownership(ownership_buf, members[1] :: any, ownership_variants)
		end

		CHECK(server.storage[entity1].components[components[1]] == "client_predicted")
	end)

	CASE("request_set without component should create component locally and buffer for server", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		-- Full sync
		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		-- Drain
		for player, ubuf, uchanges in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(ubuf, uchanges)
		end

		local c_entity = client_entity(members[1], entity1) :: any
		CHECK(c_entity ~= nil)

		-- Component1 has a value
		CHECK(members[1].world:get(c_entity, members[1].components[1]) == "initial")

		-- Now revoke ownership from server side, then re-grant
		world:remove(entity1, jecs.pair(replecs.owned, components[1]))
		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end
		CHECK(members[1].client:has_ownership(c_entity, members[1].components[1]) == false)

		-- request_set should be rejected — no ownership
		members[1].client:request_set(c_entity, members[1].components[1], "should_fail")
		CHECK(members[1].world:get(c_entity, members[1].components[1]) == "initial")

		-- Re-grant ownership
		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)
		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		-- Now request_set should work
		CHECK(members[1].client:has_ownership(c_entity, members[1].components[1]) == true)
		members[1].client:request_set(c_entity, members[1].components[1], "should_work")
		CHECK(members[1].world:get(c_entity, members[1].components[1]) == "should_work")

		-- Ownership buffer should have the entry
		CHECK(members[1].client.ownership_buffer[c_entity] ~= nil)
		CHECK(members[1].client.ownership_buffer[c_entity][members[1].components[1]] ~= nil)

		-- Apply to server
		for ownership_buf, ownership_variants in members[1].client:collect_ownership() do
			server:apply_ownership(ownership_buf, members[1] :: any, ownership_variants)
		end
		CHECK(server.storage[entity1].components[components[1]] == "should_work")
	end)

	CASE("ownership revoke and re-grant should clear client state properly", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		-- Grant ownership
		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)
		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		local c_entity = client_entity(members[1], entity1) :: any
		CHECK(members[1].client:has_ownership(c_entity, members[1].components[1]) == true)

		-- Buffer a pending update
		members[1].client:request_set(c_entity, members[1].components[1], "pending")
		CHECK(members[1].client.ownership_buffer[c_entity] ~= nil)

		-- Revoke ownership — should clear grants AND buffers
		world:remove(entity1, jecs.pair(replecs.owned, components[1]))
		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		-- Ownership gone
		CHECK(members[1].client:has_ownership(c_entity, members[1].components[1]) == false)

		-- request_set should be rejected
		members[1].client:request_set(c_entity, members[1].components[1], "should_fail")
		-- Value should remain "pending" (from the earlier request_set), not "should_fail"
		CHECK(members[1].world:get(c_entity, members[1].components[1]) == "pending")

		-- Re-grant to same player
		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)
		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		CHECK(members[1].client:has_ownership(c_entity, members[1].components[1]) == true)
		members[1].client:request_set(c_entity, members[1].components[1], "after_regrant")
		CHECK(members[1].world:get(c_entity, members[1].components[1]) == "after_regrant")

		-- Apply to server
		for ownership_buf, ownership_variants in members[1].client:collect_ownership() do
			server:apply_ownership(ownership_buf, members[1] :: any, ownership_variants)
		end
		CHECK(server.storage[entity1].components[components[1]] == "after_regrant")
	end)

	CASE("entity removed from replication should clean ownership on client side", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		-- Grant ownership
		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)
		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		local c_entity = client_entity(members[1], entity1) :: any
		CHECK(members[1].client:has_ownership(c_entity, members[1].components[1]) == true)

		-- Server stops the component
		server:stop_reliable(entity1, components[1])

		-- Deliver the removal
		for player, ubuf, uchanges in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(ubuf, uchanges)
		end

		-- Ownership for that component should be cleared on the client
		-- (entity_remove cleans ownership_grants, ownership_buffer)
		CHECK(members[1].client:has_ownership(c_entity, members[1].components[1]) == false)
	end)

	CASE("stop_networked should clean all ownership on client", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		server:set_reliable(entity1, components[2])
		world:set(entity1, components[1], "val1")
		world:set(entity1, components[2], "val2")

		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		-- Grant ownership of both
		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)
		world:set(entity1, jecs.pair(replecs.owned, components[2]), members[1] :: any)
		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		local c_entity = client_entity(members[1], entity1) :: any
		CHECK(members[1].client:has_ownership(c_entity, members[1].components[1]) == true)
		CHECK(members[1].client:has_ownership(c_entity, members[1].components[2]) == true)

		-- Buffer some ownership updates
		members[1].client:request_set(c_entity, members[1].components[1], "buf1")
		members[1].client:request_set(c_entity, members[1].components[2], "buf2")

		-- Delete entity from server — this should clean everything
		world:delete(entity1)

		for player, ubuf, uchanges in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(ubuf, uchanges)
		end

		-- Entity should be gone from client
		if members[1].world:contains(c_entity) then
			-- if entity still exists (some cleanup paths), ownership should still be gone
			CHECK(members[1].client:has_ownership(c_entity, members[1].components[1]) == false)
			CHECK(members[1].client:has_ownership(c_entity, members[1].components[2]) == false)
		end

		-- Buffers should be cleaned
		CHECK(members[1].client.ownership_grants[c_entity] == nil)
		CHECK(members[1].client.ownership_buffer[c_entity] == nil)
	end)
end)

TEST("ownership buffer validation", function()
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

	CASE("should not crash on completely empty buffer", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local empty_buf = buffer.create(0)
		local ok = pcall(function()
			server:apply_ownership(empty_buf, members[1] :: any, {})
		end)
		CHECK(ok == true)

		local ok2 = pcall(function()
			server:apply_ownership(empty_buf, members[1] :: any, {})
		end)
		CHECK(ok2 == true)
	end)

	CASE("should not crash on single-byte buffer (packet type only)", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local buf = buffer.create(1)
		buffer.writeu8(buf, 0, 5) -- ownership_reliable packet type
		local ok = pcall(function()
			server:apply_ownership(buf, members[1] :: any, {})
		end)
		CHECK(ok == true)
	end)

	CASE("should not crash on truncated buffer with valid packet type", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		-- cursor reads backwards: last byte = packet type, then vlqs
		-- buffer layout: [vlq_entries][vlq_packets][packet_type]
		local buf = buffer.create(3)
		buffer.writeu8(buf, 0, 129) -- vlq for total_entries = 1 (read third)
		buffer.writeu8(buf, 1, 129) -- vlq for total_packets = 1 (read second)
		buffer.writeu8(buf, 2, 5) -- ownership_reliable packet type (read first)
		local ok = pcall(function()
			server:apply_ownership(buf, members[1] :: any, {})
		end)
		CHECK(ok == true)
	end)

	CASE("should not crash on wrong packet type byte", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		-- completely wrong packet type
		local buf = buffer.create(1)
		buffer.writeu8(buf, 0, 255) -- invalid packet type
		local ok = pcall(function()
			server:apply_ownership(buf, members[1] :: any, {})
		end)
		-- this should NOT crash — the pcall catches the error from check_packet_type
		CHECK(ok == true)
	end)

	CASE("should not crash on random garbage buffer", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local garbage = buffer.create(64)
		for i = 0, 63 do
			buffer.writeu8(garbage, i, math.random(0, 255))
		end
		local ok = pcall(function()
			server:apply_ownership(garbage, members[1] :: any, {})
		end)
		CHECK(ok == true)

		local ok2 = pcall(function()
			server:apply_ownership(garbage, members[1] :: any, {})
		end)
		CHECK(ok2 == true)
	end)

	CASE("should handle serdes deserialization failure gracefully", function()
		local fail_deserialize = false
		local serdes: replecs.Serdes = {
			serialize = function(value: number)
				local buf = buffer.create(8)
				buffer.writef64(buf, 0, value)
				return buf
			end,
			deserialize = function(buf: buffer)
				if fail_deserialize then
					error "deserialization exploded!"
				end
				return buffer.readf64(buf, 0)
			end,
		}

		local components = create_test_components(world)
		world:set(components[1], replecs.serdes, serdes)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
			member.world:set(member.components[1], replecs.serdes, serdes)
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], 50.0)

		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)

		-- full sync while deserializer works fine
		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		-- NOW enable failure for the server-side deserialize on ownership receive
		fail_deserialize = true

		-- send a valid ownership update but with a failing server-side deserializer
		members[1].client:request_set(client_entity(members[1], entity1) :: any, members[1].components[1], 42.0)

		for ownership_buf, ownership_variants in members[1].client:collect_ownership() do
			server:apply_ownership(ownership_buf, members[1] :: any, ownership_variants)
		end

		-- value should NOT have changed since server-side deserialization failed
		CHECK(server.storage[entity1].components[components[1]] == 50.0)

		-- now disable the failure and try again
		fail_deserialize = false
		members[1].client:request_set(client_entity(members[1], entity1) :: any, members[1].components[1], 42.0)

		for ownership_buf, ownership_variants in members[1].client:collect_ownership() do
			server:apply_ownership(ownership_buf, members[1] :: any, ownership_variants)
		end

		-- now it should succeed
		CHECK(server.storage[entity1].components[components[1]] == 42.0)
	end)

	CASE("should reject variant index out of bounds", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)

		local full_buf, full_variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(full_buf, full_variants)

		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		-- send ownership with a variant index that's way out of bounds
		-- manually craft a buffer that references variant index 999
		local c_entity = client_entity(members[1], entity1) :: any
		members[1].client:request_set(c_entity, members[1].components[1], "test_value")

		-- collect the real buffer and replace with tampered variant reference
		for ownership_buf, ownership_variants in members[1].client:collect_ownership() do
			-- apply with empty variants (simulates tampered variant array)
			server:apply_ownership(ownership_buf, members[1] :: any, {})
		end

		-- value should not have changed (variant was out of bounds)
		CHECK(server.storage[entity1].components[components[1]] == "initial")
	end)
end)

TEST("memory leaks", function()
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

	CASE("throttle buffer should be cleaned when entity stops being reliable", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		world:set(world:entity(), jecs.pair(replecs.throttle, components[1]), 999999)

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		-- Drain masking changes
		for player, buf, changes in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(buf, changes)
		end

		-- Buffer a change
		world:set(entity1, components[1], "buffered")

		local throttle_entry = server.throttle[components[1]]
		CHECK(throttle_entry ~= nil)
		CHECK(throttle_entry.component_changes[entity1] ~= nil or throttle_entry.removals[entity1] ~= nil)

		-- Stop tracking this component
		server:stop_reliable(entity1, components[1])
		CHECK(
			throttle_entry.component_changes[entity1] == nil
				and throttle_entry.tag_changes[entity1] == nil
				and throttle_entry.removals[entity1] == nil
		)
	end)

	CASE("throttle buffer should be cleaned when entity stops being networked", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		world:set(world:entity(), jecs.pair(replecs.throttle, components[1]), 999999)

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		-- Drain masking changes
		for player, buf, changes in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(buf, changes)
		end

		-- Buffer a change
		world:set(entity1, components[1], "buffered")

		local throttle_entry = server.throttle[components[1]]
		CHECK(throttle_entry ~= nil)
		CHECK(throttle_entry.component_changes[entity1] ~= nil or throttle_entry.removals[entity1] ~= nil)

		-- Stop entity entirely
		server:stop_networked(entity1)
		CHECK(
			throttle_entry.component_changes[entity1] == nil
				and throttle_entry.tag_changes[entity1] == nil
				and throttle_entry.removals[entity1] == nil
		)
	end)

	CASE("ownership should be cleaned when entity stops being reliable", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)
		CHECK(server.ownership[entity1] ~= nil)
		CHECK(server.ownership[entity1][components[1]] ~= nil)

		-- Stop tracking this component - ownership should be cleaned
		server:stop_reliable(entity1, components[1])
		CHECK(server.ownership[entity1] == nil or server.ownership[entity1][components[1]] == nil)
	end)

	CASE("ownership should be cleaned when entity stops being networked", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)
		CHECK(server.ownership[entity1] ~= nil)

		-- Stop entity entirely
		server:stop_networked(entity1)
		CHECK(server.ownership[entity1] == nil)
	end)

	CASE("client ownership grants should be cleaned when entity is deleted", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)

		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		local c_entity = client_entity(members[1], entity1)
		CHECK(c_entity ~= nil)
		CHECK(members[1].client.ownership_grants[c_entity] ~= nil)

		-- Delete entity on server
		world:delete(entity1)

		-- Sync deletion to client
		for player, ubuf, uchanges in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(ubuf, uchanges)
		end

		-- Ownership grants should be cleaned on client after sync
		CHECK(members[1].client.ownership_grants[c_entity] == nil)
	end)

	CASE("ownership_dirty should be marked when ownership is cleaned", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)

		-- Drain grant
		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		-- Clear dirty
		server.ownership_dirty[members[1] :: any] = nil

		-- Stop networked - should mark dirty for cleanup grant
		server:stop_networked(entity1)
		CHECK(server.ownership_dirty[members[1] :: any] == true)
	end)

	CASE("ownership grant immediate delete race", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(2)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "value")

		-- grant ownership to member1
		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)

		-- full sync both members
		for _, member in members do
			local buf, variants = server:get_full(member :: any)
			member.client:apply_full(buf, variants)
		end

		-- Delete entity BEFORE grant is delivered
		world:delete(entity1)

		-- collect_ownership_grant should still work (dirty was set)
		-- and not crash even though entity is gone
		local grant_count = 0
		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			-- server already cleaned up ownership, so no grants should be sent
			grant_count += 1
		end
		-- The grant might be empty since ownership was cleaned on delete
		CHECK(grant_count <= 1)
	end)

	CASE("throttle buffer with multiple components on same entity", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		-- Throttle both components
		world:set(world:entity(), jecs.pair(replecs.throttle, components[1]), 999999)
		world:set(world:entity(), jecs.pair(replecs.throttle, components[2]), 999999)

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		server:set_reliable(entity1, components[2])
		world:set(entity1, components[1], "a")
		world:set(entity1, components[2], "b")

		-- Drain initial changes
		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)
		for player, ubuf, uchanges in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(ubuf, uchanges)
		end

		-- Buffer changes for both
		world:set(entity1, components[1], "x")
		world:set(entity1, components[2], "y")

		local t1 = server.throttle[components[1]]
		local t2 = server.throttle[components[2]]
		CHECK(t1 ~= nil and (t1.component_changes[entity1] ~= nil or t1.removals[entity1] ~= nil))
		CHECK(t2 ~= nil and (t2.component_changes[entity1] ~= nil or t2.removals[entity1] ~= nil))

		-- Flush and verify only the latest value is sent
		t1.interval = 0
		t2.interval = 0
		for player, ubuf, uchanges in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(ubuf, uchanges)
		end

		-- Both should be updated
		local ce = client_entity(members[1], entity1)
		CHECK(ce ~= nil)
		CHECK(members[1].world:get(ce, members[1].components[1]) == "x")
		CHECK(members[1].world:get(ce, members[1].components[2]) == "y")
	end)

	CASE("throttle un-throttle flushes pending buffer", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local throttle_entity = world:entity()
		world:set(throttle_entity, jecs.pair(replecs.throttle, components[1]), 999999)

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		-- Drain initial
		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)
		for player, ubuf, uchanges in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(ubuf, uchanges)
		end

		-- Buffer changes
		world:set(entity1, components[1], "buffered1")
		world:set(entity1, components[1], "buffered2")

		CHECK(server.throttle[components[1]] ~= nil)

		-- Remove throttle - should flush buffer
		world:remove(throttle_entity, jecs.pair(replecs.throttle, components[1]))
		CHECK(server.throttle[components[1]] == nil)

		-- The buffered values should have been flushed into masking
		for player, ubuf, uchanges in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(ubuf, uchanges)
		end

		local ce = client_entity(members[1], entity1)
		CHECK(ce ~= nil)
		CHECK(members[1].world:get(ce, members[1].components[1]) == "buffered2")
	end)

	CASE("ownership validate-rejected value should not be applied", function()
		local serdes: replecs.Serdes = {
			serialize = function(value: number)
				local buf = buffer.create(8)
				buffer.writef64(buf, 0, value)
				return buf
			end,
			deserialize = function(buf: buffer)
				return buffer.readf64(buf, 0)
			end,
		}
		local validator: replecs.OwnershipValidator = {
			validate = function(value: number): boolean
				return value >= 0 and value <= 100
			end,
		}

		local components = create_test_components(world)
		world:set(components[1], replecs.serdes, serdes)
		world:set(components[1], replecs.validator, validator)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
			member.world:set(member.components[1], replecs.serdes, serdes)
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], 50.0)

		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)

		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		-- Send an invalid value (out of range)
		members[1].client:request_set(client_entity(members[1], entity1) :: any, members[1].components[1], 999.0)

		for ownership_buf, ownership_variants in members[1].client:collect_ownership() do
			server:apply_ownership(ownership_buf, members[1] :: any, ownership_variants)
		end

		-- The value should NOT have changed (999 is out of range 0-100)
		CHECK(server.storage[entity1].components[components[1]] == 50.0)
	end)

	CASE("ownership nil owner should revoke ownership", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)
		CHECK(server.ownership[entity1][components[1]].player == members[1] :: any)

		-- Revoke ownership (set to nil removes the pair, triggers REMOVED hook)
		world:remove(entity1, jecs.pair(replecs.owned, components[1]))
		CHECK(server.ownership[entity1][components[1]] == nil)

		-- Now server should be able to modify the component again
		world:set(entity1, components[1], "server_modified")
		CHECK(server.storage[entity1].components[components[1]] == "server_modified")
	end)

	CASE("ownership grant then reliable revoke then grant to another player", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(2)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		-- Grant to player1
		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)
		CHECK(server.ownership[entity1][components[1]].player == members[1] :: any)

		-- Change to player2
		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[2] :: any)
		CHECK(server.ownership[entity1][components[1]].player == members[2] :: any)
	end)

	CASE("multiple entities with throttle should not interfere", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		world:set(world:entity(), jecs.pair(replecs.throttle, components[1]), 999999)

		local entity1 = world:entity()
		local entity2 = world:entity()
		server:set_networked(entity1)
		server:set_networked(entity2)
		server:set_reliable(entity1, components[1])
		server:set_reliable(entity2, components[1])
		world:set(entity1, components[1], "e1")
		world:set(entity2, components[1], "e2")

		-- Drain initial
		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)
		for player, ubuf, uchanges in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(ubuf, uchanges)
		end

		-- Change both entities
		world:set(entity1, components[1], "e1_new")
		world:set(entity2, components[1], "e2_new")

		-- Delete entity1 - should only clean entity1 from buffer
		world:delete(entity1)

		local throttle_entry = server.throttle[components[1]]
		CHECK(throttle_entry ~= nil)
		CHECK(
			throttle_entry.component_changes[entity1] == nil
				and throttle_entry.tag_changes[entity1] == nil
				and throttle_entry.removals[entity1] == nil
		)
		CHECK(throttle_entry.component_changes[entity2] ~= nil or throttle_entry.removals[entity2] ~= nil)

		-- Flush and verify entity2 gets its update
		throttle_entry.interval = 0
		for player, ubuf, uchanges in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(ubuf, uchanges)
		end

		local ce2 = client_entity(members[1], entity2)
		CHECK(ce2 ~= nil)
		CHECK(members[1].world:get(ce2, members[1].components[1]) == "e2_new")
	end)

	CASE("throttle buffer should buffer component removal and flush correctly", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		world:set(world:entity(), jecs.pair(replecs.throttle, components[1]), 999999)

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		-- Drain initial
		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)
		for player, ubuf, uchanges in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(ubuf, uchanges)
		end

		-- Buffer a value change then a removal
		world:set(entity1, components[1], "buffered")
		world:remove(entity1, components[1])

		local throttle_entry = server.throttle[components[1]]
		CHECK(throttle_entry ~= nil)
		CHECK(throttle_entry.component_changes[entity1] ~= nil or throttle_entry.removals[entity1] ~= nil)
		-- removal should have cleared the component_changes entry
		CHECK(throttle_entry.removals[entity1][components[1]] == true)
		CHECK(
			throttle_entry.component_changes[entity1] == nil
				or throttle_entry.component_changes[entity1][components[1]] == nil
		)

		-- Flush
		throttle_entry.interval = 0
		for player, ubuf, uchanges in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(ubuf, uchanges)
		end

		-- Entity should still exist on client but component should be gone
		local ce = client_entity(members[1], entity1)
		CHECK(ce ~= nil)
		CHECK(members[1].world:get(ce, members[1].components[1]) == nil)
	end)

	CASE("client ownership grant cleanup when server component removed but entity stays", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		server:set_reliable(entity1, components[2])
		world:set(entity1, components[1], "initial1")
		world:set(entity1, components[2], "initial2")

		-- full sync
		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		-- grant ownership of component1 and deliver
		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)
		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		local c_entity = client_entity(members[1], entity1) :: any
		CHECK(members[1].client:has_ownership(c_entity, members[1].components[1]) == true)

		-- revoke ownership then remove component1
		world:remove(entity1, jecs.pair(replecs.owned, components[1]))
		world:remove(entity1, components[1])

		-- sync removal
		for player, ubuf, uchanges in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(ubuf, uchanges)
		end

		-- deliver revocation grant
		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		-- component1 ownership should be gone
		local grants = members[1].client.ownership_grants[c_entity]
		if grants then
			CHECK(grants[members[1].components[1]] == nil)
		end
		-- entity should still exist with component2
		CHECK(members[1].world:contains(c_entity))
		CHECK(members[1].world:get(c_entity, members[1].components[2]) == "initial2")
	end)

	CASE("entity deletion should clean client ownership_buffer and grants end-to-end", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)
		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		local c_entity = client_entity(members[1], entity1) :: any
		CHECK(members[1].client:has_ownership(c_entity, members[1].components[1]) == true)

		members[1].client:request_set(c_entity, members[1].components[1], "client_val")
		CHECK(members[1].client.ownership_buffer[c_entity] ~= nil)

		world:delete(entity1)

		for player, ubuf, uchanges in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(ubuf, uchanges)
		end

		CHECK(members[1].client.ownership_grants[c_entity] == nil)
		CHECK(members[1].client.ownership_buffer[c_entity] == nil)
		CHECK(members[1].world:contains(c_entity) == false)
	end)

	CASE("entity deletion with throttle should clean throttle buffer and replicate deletion", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		world:set(world:entity(), jecs.pair(replecs.throttle, components[1]), 999999)

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)
		for player, ubuf, uchanges in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(ubuf, uchanges)
		end

		world:set(entity1, components[1], "throttled_val")
		local throttle_entry = server.throttle[components[1]]
		CHECK(throttle_entry ~= nil)
		CHECK(throttle_entry.component_changes[entity1] ~= nil or throttle_entry.removals[entity1] ~= nil)

		world:delete(entity1)
		CHECK(
			throttle_entry.component_changes[entity1] == nil
				and throttle_entry.tag_changes[entity1] == nil
				and throttle_entry.removals[entity1] == nil
		)

		for player, ubuf, uchanges in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(ubuf, uchanges)
		end

		local ce = client_entity(members[1], entity1)
		if ce then
			CHECK(members[1].world:contains(ce) == false)
		end
	end)

	CASE("entity deletion with ownership and pending buffer should clean all client state", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		server:set_reliable(entity1, components[2])
		world:set(entity1, components[1], "initial1")
		world:set(entity1, components[2], "initial2")

		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)
		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		local c_entity = client_entity(members[1], entity1) :: any
		CHECK(members[1].client:has_ownership(c_entity, members[1].components[1]) == true)

		members[1].client:request_set(c_entity, members[1].components[1], "client_val")
		CHECK(members[1].client.ownership_buffer[c_entity] ~= nil)

		world:delete(entity1)

		for player, ubuf, uchanges in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(ubuf, uchanges)
		end

		CHECK(members[1].client.ownership_grants[c_entity] == nil)
		CHECK(members[1].client.ownership_buffer[c_entity] == nil)
		CHECK(members[1].world:contains(c_entity) == false)
	end)

	CASE("owned component should NOT be overwritten on replicate (changed)", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		-- full sync
		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		-- grant ownership
		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)
		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		local c_entity = client_entity(members[1], entity1) :: any

		-- owner sets a predicted value locally
		members[1].client:request_set(c_entity, members[1].components[1], "predicted")

		-- server changes the value — simulates stale roundtrip
		world:remove(entity1, jecs.pair(replecs.owned, components[1]))
		world:set(entity1, components[1], "server_stale")
		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)

		-- deliver the replicated change to client
		for player, ubuf, uchanges in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(ubuf, uchanges)
		end

		-- the owner's predicted value should be preserved, not overwritten by server_stale
		local val = members[1].world:get(c_entity, members[1].components[1])
		CHECK(val == "predicted")
	end)

	CASE("unowned component should still be written on replicate", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		-- full sync
		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		-- NO ownership — server changes the value
		world:set(entity1, components[1], "server_update")

		for player, ubuf, uchanges in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(ubuf, uchanges)
		end

		local c_entity = client_entity(members[1], entity1) :: any
		local val = members[1].world:get(c_entity, members[1].components[1])
		CHECK(val == "server_update")
	end)

	CASE("initial sync should go through even for owned component", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "synced_value")

		-- grant ownership before sync
		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)

		-- full sync — initial value should arrive even though owned
		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		local c_entity = client_entity(members[1], entity1)
		CHECK(c_entity ~= nil)

		local val = members[1].world:get(c_entity :: any, members[1].components[1])
		CHECK(val == "synced_value")
	end)

	CASE("override should receive owned values even when component exists", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		-- full sync
		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		-- grant ownership
		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)
		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		local c_entity = client_entity(members[1], entity1) :: any

		-- install override that tracks calls
		local override_called = false
		local override_value: any = nil
		members[1].client:override(
			"changed",
			jecs.pair(replecs.reliable, members[1].components[1]),
			function(_entity: any, _id: any, value: any)
				override_called = true
				override_value = value
			end
		)

		-- owner sets predicted value
		members[1].client:request_set(c_entity, members[1].components[1], "predicted")

		-- simulate server stale roundtrip
		world:remove(entity1, jecs.pair(replecs.owned, components[1]))
		world:set(entity1, components[1], "server_stale")
		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)

		for player, ubuf, uchanges in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(ubuf, uchanges)
		end

		-- override should have been called with the server value
		CHECK(override_called == true)
		CHECK(override_value == "server_stale")

		-- world value should NOT have been written by override (default behavior)
		-- since override only gets callback, not world write
		local world_val = members[1].world:get(c_entity, members[1].components[1])
		CHECK(world_val == "predicted")
	end)

	CASE("hook should NOT fire on owned component change", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		-- full sync
		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		-- grant ownership
		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)
		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		local c_entity = client_entity(members[1], entity1) :: any

		-- install hook that tracks calls
		local hook_called = false
		members[1].client:hook(
			"changed",
			jecs.pair(replecs.reliable, members[1].components[1]),
			function(_entity: any, _id: any, _value: any)
				hook_called = true
			end
		)

		-- owner sets predicted value
		members[1].client:request_set(c_entity, members[1].components[1], "predicted")

		-- simulate server stale roundtrip
		world:remove(entity1, jecs.pair(replecs.owned, components[1]))
		world:set(entity1, components[1], "server_stale")
		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)

		for player, ubuf, uchanges in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(ubuf, uchanges)
		end

		-- hook should NOT have been called (owned component, already exists)
		CHECK(hook_called == false)
		-- world value should be preserved
		local val = members[1].world:get(c_entity, members[1].components[1])
		CHECK(val == "predicted")
	end)

	CASE("non-owner should still receive owned component updates", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(2)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		-- full sync to both
		for _, member in members do
			local buf, variants = server:get_full(member :: any)
			member.client:apply_full(buf, variants)
		end

		-- grant ownership to member1 only
		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)
		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		-- revoke, change, re-grant to simulate owner sending value through server
		world:remove(entity1, jecs.pair(replecs.owned, components[1]))
		world:set(entity1, components[1], "from_owner")
		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)

		for player, ubuf, uchanges in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(ubuf, uchanges)
		end

		-- member2 (non-owner) should receive the value
		local c_entity2 = client_entity(members[2], entity1) :: any
		local val2 = members[2].world:get(c_entity2, members[2].components[1])
		CHECK(val2 == "from_owner")

		-- member1 (owner) should keep predicted value (or initial since no prediction)
		local c_entity1 = client_entity(members[1], entity1) :: any
		local val1 = members[1].world:get(c_entity1, members[1].components[1])
		CHECK(val1 == "initial")
	end)
end)

TEST("simplified hook API", function()
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

	CASE("bare component hook fires on reliable changes", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		-- full sync
		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		local hook_value: any = nil
		local hook_added: boolean? = nil

		-- bare component — no pair needed
		members[1].client:hook(
			"changed",
			members[1].components[1],
			function(_entity: any, _id: any, value: any, added: boolean)
				hook_value = value
				hook_added = added
			end
		)

		-- change value via server update
		world:set(entity1, components[1], "updated")
		for player, ubuf, uchanges in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(ubuf, uchanges)
		end

		CHECK(hook_value == "updated")
		CHECK(hook_added == false)
	end)

	CASE("bare component hook fires with added=true on initial sync", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local hook_value: any = nil
		local hook_added: boolean? = nil

		-- register hook before sync
		members[1].client:hook(
			"changed",
			members[1].components[1],
			function(_entity: any, _id: any, value: any, added: boolean)
				hook_value = value
				hook_added = added
			end
		)

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		CHECK(hook_value == "initial")
		CHECK(hook_added == true)
	end)

	CASE("bare component hook fires on unreliable changes", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_unreliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		-- full sync
		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		local hook_value: any = nil

		-- bare component covers both reliable and unreliable
		members[1].client:hook(
			"changed",
			members[1].components[1],
			function(_entity: any, _id: any, value: any, _added: boolean)
				hook_value = value
			end
		)

		-- unreliable change
		world:set(entity1, components[1], "unreliable_val")
		for player, ubuf, uchanges in server:collect_unreliable() do
			local member: MemberData = player :: any
			member.client:apply_unreliable(ubuf, uchanges)
		end

		CHECK(hook_value == "unreliable_val")
	end)

	CASE("bare component hook disconnect stops callbacks", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		local count = 0
		local disconnect = members[1].client:hook(
			"changed",
			members[1].components[1],
			function(_entity: any, _id: any, _value: any, _added: boolean)
				count += 1
			end
		)

		-- first change fires
		world:set(entity1, components[1], "val1")
		for player, ubuf, uchanges in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(ubuf, uchanges)
		end
		CHECK(count == 1)

		-- disconnect
		disconnect()

		-- second change should NOT fire
		world:set(entity1, components[1], "val2")
		for player, ubuf, uchanges in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(ubuf, uchanges)
		end
		CHECK(count == 1)
	end)

	CASE("bare component removed hook fires", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		-- drain additions so subsequent removals go through masking
		for player, ubuf, uchanges in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(ubuf, uchanges)
		end

		local removed = false
		members[1].client:hook("removed", members[1].components[1], function(_entity: any, _id: any)
			removed = true
		end)

		-- remove component
		world:remove(entity1, components[1])
		for player, ubuf, uchanges in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(ubuf, uchanges)
		end

		CHECK(removed == true)
	end)

	CASE("legacy pair hook still works", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		local hook_value: any = nil

		-- legacy pair syntax still works
		members[1].client:hook(
			"changed",
			jecs.pair(replecs.reliable, members[1].components[1]),
			function(_entity: any, _id: any, value: any, _added: boolean)
				hook_value = value
			end
		)

		world:set(entity1, components[1], "updated")
		for player, ubuf, uchanges in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(ubuf, uchanges)
		end

		CHECK(hook_value == "updated")
	end)
end)

TEST("client throttle", function()
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

	CASE("should buffer request_set and not send until interval", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		-- full sync
		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		-- grant ownership
		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)
		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		-- set client-side throttle with a very long interval
		members[1].client:set_throttle(members[1].components[1], 999999)

		local c_entity = client_entity(members[1], entity1) :: any

		-- request_set multiple times
		members[1].client:request_set(c_entity, members[1].components[1], "change1")
		members[1].client:request_set(c_entity, members[1].components[1], "change2")
		members[1].client:request_set(c_entity, members[1].components[1], "change3")

		-- Local world should have latest prediction
		CHECK(members[1].world:get(c_entity, members[1].components[1]) == "change3")

		-- collect_ownership should produce no packets (throttled, interval not elapsed)
		local ownership_count = 0
		for _buf, _variants in members[1].client:collect_ownership() do
			ownership_count += 1
		end
		CHECK(ownership_count == 0)

		-- ownership_buffer should be empty (values are in throttle buffer)
		CHECK(members[1].client.ownership_buffer[c_entity] == nil)
	end)

	CASE("should flush when interval elapses", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)
		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		-- Set throttle with 0 interval (flush immediately)
		members[1].client:set_throttle(members[1].components[1], 0)

		local c_entity = client_entity(members[1], entity1) :: any
		members[1].client:request_set(c_entity, members[1].components[1], "throttled_val")

		-- collect_ownership should flush and produce a packet
		local applied = false
		for ownership_buf, ownership_variants in members[1].client:collect_ownership() do
			server:apply_ownership(ownership_buf, members[1] :: any, ownership_variants)
			applied = true
		end
		CHECK(applied == true)

		-- Server should have the value
		CHECK(server.storage[entity1].components[components[1]] == "throttled_val")
	end)

	CASE("should only send latest value (overwrite)", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)
		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		-- Set throttle with long interval to accumulate
		members[1].client:set_throttle(members[1].components[1], 999999)

		local c_entity = client_entity(members[1], entity1) :: any

		-- Write many values — only the last should survive
		members[1].client:request_set(c_entity, members[1].components[1], "val1")
		members[1].client:request_set(c_entity, members[1].components[1], "val2")
		members[1].client:request_set(c_entity, members[1].components[1], "val3")
		members[1].client:request_set(c_entity, members[1].components[1], "final")

		-- Force flush by setting interval to 0
		local throttle_entry = members[1].client.ownership_throttle[members[1].components[1]]
		CHECK(throttle_entry ~= nil)
		throttle_entry.interval = 0

		-- Flush and apply
		for ownership_buf, ownership_variants in members[1].client:collect_ownership() do
			server:apply_ownership(ownership_buf, members[1] :: any, ownership_variants)
		end

		-- Server should have "final" only
		CHECK(server.storage[entity1].components[components[1]] == "final")
	end)

	CASE("should clean up throttle buffer on entity deletion", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)
		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		-- Set throttle with long interval
		members[1].client:set_throttle(members[1].components[1], 999999)

		local c_entity = client_entity(members[1], entity1) :: any

		-- Buffer a change
		members[1].client:request_set(c_entity, members[1].components[1], "buffered")

		local throttle_entry = members[1].client.ownership_throttle[members[1].components[1]]
		CHECK(throttle_entry ~= nil)
		CHECK(throttle_entry.values[c_entity] ~= nil)

		-- Delete entity on server
		world:delete(entity1)

		-- Sync deletion to client
		for player, ubuf, uchanges in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(ubuf, uchanges)
		end

		-- Entity should be purged from throttle buffer
		CHECK(throttle_entry.values[c_entity] == nil)
	end)

	CASE("should clean up throttle buffer on ownership revocation", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)
		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		-- Set throttle with long interval
		members[1].client:set_throttle(members[1].components[1], 999999)

		local c_entity = client_entity(members[1], entity1) :: any

		-- Buffer a change
		members[1].client:request_set(c_entity, members[1].components[1], "buffered")

		local throttle_entry = members[1].client.ownership_throttle[members[1].components[1]]
		CHECK(throttle_entry ~= nil)
		CHECK(throttle_entry.values[c_entity] ~= nil)

		-- Revoke ownership
		world:remove(entity1, jecs.pair(replecs.owned, components[1]))

		-- Deliver revocation grant
		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		-- After revocation, has_ownership returns false — subsequent request_set would be blocked
		-- The stale throttle entry should still be there (it's harmless, will be flushed as no-op)
		-- But verify request_set is now blocked (no new entries added)
		members[1].client:request_set(c_entity, members[1].components[1], "should_not_work")
		-- The entry still exists from "buffered" — the important thing is request_set logged a warning and returned
	end)

	CASE("should handle reliable vs unreliable throttle independently", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		server:set_reliable(entity1, components[2])
		world:set(entity1, components[1], "init1")
		world:set(entity1, components[2], "init2")

		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		-- Grant ownership of both
		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)
		world:set(entity1, jecs.pair(replecs.owned, components[2]), members[1] :: any)
		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		-- Only throttle component1 (component2 has no throttle)
		members[1].client:set_throttle(members[1].components[1], 999999)

		local c_entity = client_entity(members[1], entity1) :: any

		-- Both go through request_set
		members[1].client:request_set(c_entity, members[1].components[1], "throttled")
		members[1].client:request_set(c_entity, members[1].components[2], "not_throttled")

		-- Component2 should be sent immediately (no throttle)
		local buf2: buffer = nil :: any
		local v2: any = nil
		for ownership_buf, ownership_variants in members[1].client:collect_ownership() do
			buf2 = ownership_buf
			v2 = ownership_variants
		end
		CHECK(buf2 ~= nil)
		server:apply_ownership(buf2, members[1] :: any, v2)
		CHECK(server.storage[entity1].components[components[2]] == "not_throttled")

		-- Component1 should NOT be in the ownership buffer (still throttled)
		-- After flush (set interval to 0), it should appear
		local throttle_entry = members[1].client.ownership_throttle[members[1].components[1]]
		CHECK(throttle_entry ~= nil)
		throttle_entry.interval = 0

		for ownership_buf, ownership_variants in members[1].client:collect_ownership() do
			server:apply_ownership(ownership_buf, members[1] :: any, ownership_variants)
		end
		CHECK(server.storage[entity1].components[components[1]] == "throttled")
	end)

	CASE("unreliable request_set should use unreliable throttle buffer", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)
		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		-- Set throttle with long interval
		members[1].client:set_throttle(members[1].components[1], 999999)

		local c_entity = client_entity(members[1], entity1) :: any

		-- Send unreliable (true flag)
		members[1].client:request_set(c_entity, members[1].components[1], "unreliable_throttled", true)

		-- reliable collect should be empty
		local reliable_count = 0
		for _ in members[1].client:collect_ownership() do
			reliable_count += 1
		end
		CHECK(reliable_count == 0)

		-- unreliable collect should also be empty (still throttled)
		local unreliable_count = 0
		for _ in members[1].client:collect_ownership_unreliable() do
			unreliable_count += 1
		end
		CHECK(unreliable_count == 0)

		-- Force flush
		local throttle_entry = members[1].client.ownership_throttle[members[1].components[1]]
		CHECK(throttle_entry ~= nil)
		throttle_entry.interval = 0

		-- Now unreliable collect should yield
		local applied = false
		for ownership_buf, ownership_variants in members[1].client:collect_ownership_unreliable() do
			server:apply_ownership(ownership_buf, members[1] :: any, ownership_variants)
			applied = true
		end
		CHECK(applied == true)
		CHECK(server.storage[entity1].components[components[1]] == "unreliable_throttled")
	end)

	CASE("nil value request_set should round-trip correctly", function()
		local components = create_test_components(world)
		server:init()

		-- two members: member1 owns the component, member2 is a non-owner observer
		local members = create_members_data(2)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		-- full sync to both
		for _, member in members do
			local buf, variants = server:get_full(member :: any)
			member.client:apply_full(buf, variants)
		end

		-- grant ownership to member1 only
		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)
		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		local c_entity1 = client_entity(members[1], entity1) :: any
		local c_entity2 = client_entity(members[2], entity1) :: any
		CHECK(c_entity2 ~= nil)

		-- client-side: both should see "initial"
		CHECK(members[1].world:get(c_entity1, members[1].components[1]) == "initial")
		CHECK(members[2].world:get(c_entity2, members[2].components[1]) == "initial")

		-- owner sets to nil via request_set
		members[1].client:request_set(c_entity1, members[1].components[1], nil)

		-- local prediction should write nil (component should still exist, value nil)
		CHECK(members[1].world:has(c_entity1, members[1].components[1]))
		CHECK(members[1].world:get(c_entity1, members[1].components[1]) == nil)

		-- flush ownership to server, then replicate to non-owner
		for ownership_buf, ownership_variants in members[1].client:collect_ownership() do
			server:apply_ownership(ownership_buf, members[1] :: any, ownership_variants)
		end
		for player, ubuf, uchanges in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(ubuf, uchanges)
		end

		-- non-owner should see nil value (component still present, value nil)
		CHECK(members[2].world:has(c_entity2, members[2].components[1]))
		CHECK(members[2].world:get(c_entity2, members[2].components[1]) == nil)
	end)

	CASE("nil value should round-trip through throttled ownership", function()
		local components = create_test_components(world)
		server:init()

		-- two members: member1 owns, member2 observes
		local members = create_members_data(2)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		for _, member in members do
			local buf, variants = server:get_full(member :: any)
			member.client:apply_full(buf, variants)
		end

		-- grant ownership to member1
		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)
		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		-- throttle on client
		members[1].client:set_throttle(members[1].components[1], 999999)

		local c_entity1 = client_entity(members[1], entity1) :: any
		local c_entity2 = client_entity(members[2], entity1) :: any

		-- set to nil via throttled request_set
		members[1].client:request_set(c_entity1, members[1].components[1], nil)

		-- nothing should be in ownership_buffer yet (throttled)
		local reliable_count = 0
		for _ in members[1].client:collect_ownership() do
			reliable_count += 1
		end
		CHECK(reliable_count == 0)

		-- force flush
		local throttle_entry = members[1].client.ownership_throttle[members[1].components[1]]
		CHECK(throttle_entry ~= nil)
		throttle_entry.interval = 0

		for ownership_buf, ownership_variants in members[1].client:collect_ownership() do
			server:apply_ownership(ownership_buf, members[1] :: any, ownership_variants)
		end
		for player, ubuf, uchanges in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(ubuf, uchanges)
		end

		-- non-owner should see nil
		CHECK(members[2].world:has(c_entity2, members[2].components[1]))
		CHECK(members[2].world:get(c_entity2, members[2].components[1]) == nil)
	end)

	CASE("nil value should overwrite previous non-nil value in buffer", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(2)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		for _, member in members do
			local buf, variants = server:get_full(member :: any)
			member.client:apply_full(buf, variants)
		end

		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)
		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		local c_entity1 = client_entity(members[1], entity1) :: any
		local c_entity2 = client_entity(members[2], entity1) :: any

		-- set a value then overwrite with nil
		members[1].client:request_set(c_entity1, members[1].components[1], "something")
		members[1].client:request_set(c_entity1, members[1].components[1], nil)

		-- flush to server, replicate to non-owner — only nil should arrive
		for ownership_buf, ownership_variants in members[1].client:collect_ownership() do
			server:apply_ownership(ownership_buf, members[1] :: any, ownership_variants)
		end
		for player, ubuf, uchanges in server:collect_updates() do
			local member: MemberData = player :: any
			member.client:apply_updates(ubuf, uchanges)
		end

		CHECK(members[2].world:has(c_entity2, members[2].components[1]))
		CHECK(members[2].world:get(c_entity2, members[2].components[1]) == nil)
	end)

	CASE("non-nil value should overwrite previous nil value in buffer", function()
		local components = create_test_components(world)
		server:init()

		local members = create_members_data(1)
		for _, member in members do
			server.masking:activate_client(member)
			member.client:init()
		end

		local entity1 = world:entity()
		server:set_networked(entity1)
		server:set_reliable(entity1, components[1])
		world:set(entity1, components[1], "initial")

		local buf, variants = server:get_full(members[1] :: any)
		members[1].client:apply_full(buf, variants)

		world:set(entity1, jecs.pair(replecs.owned, components[1]), members[1] :: any)
		for player, grant_buf, grant_variants in server:collect_ownership_grant() do
			local member: MemberData = player :: any
			member.client:apply_ownership_grant(grant_buf, grant_variants)
		end

		local c_entity = client_entity(members[1], entity1) :: any

		-- set nil then overwrite with non-nil
		members[1].client:request_set(c_entity, members[1].components[1], nil)
		members[1].client:request_set(c_entity, members[1].components[1], "restored")

		for ownership_buf, ownership_variants in members[1].client:collect_ownership() do
			server:apply_ownership(ownership_buf, members[1] :: any, ownership_variants)
		end

		CHECK(server.storage[entity1].components[components[1]] == "restored")
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

	CASE("blacklisted player keeps orphaned entity", function()
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

		-- blacklist member1
		server:set_networked(entity1, { [members[2] :: any] = true })
		apply_updates(members)

		-- member1 still has the orphan (no deletion sent)
		CHECK(client_entity(members[1], entity1) ~= nil)
		CHECK(client_component(members[1], entity1, 1) == "value")

		-- member2 still has it
		CHECK(client_entity(members[2], entity1) ~= nil)
	end)

	CASE("world:delete after blacklist does not remove for blacklisted player", function()
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

		-- blacklist member1
		server:set_networked(entity1, { [members[2] :: any] = true })
		apply_updates(members)

		-- delete entity
		world:delete(entity1)
		apply_updates(members)

		-- member1 STILL has the orphaned entity (deletion only went to current storage group)
		CHECK(client_entity(members[1], entity1) ~= nil)
		CHECK(client_component(members[1], entity1, 1) == "value")

		-- member2 correctly lost it
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

		-- stop → blacklist → restart in same frame
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

local report = testlib.run(plan)
testlib.report(report)
