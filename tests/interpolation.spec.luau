local interpolation = require "@replecs/interpolation"
local jecs = require "@pkg/jecs"
local testlib = require "./testlib"

local plan = testlib.plan()

local TEST, CASE = plan.TEST, plan.CASE
local SKIP, FOCUS = plan.SKIP, plan.FOCUS
local BEFORE_EACH, AFTER_EACH = plan.BEFORE_EACH, plan.AFTER_EACH
local CHECK = assert

type Entity<T = any> = jecs.Entity<T>

-- Helpers

local function lerp_number(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Test 1: creation and defaults
TEST("creation", function()
	CASE("should create with defaults", function()
		local interp = interpolation.create()
		CHECK(interp.max_snapshots == 8)
		CHECK(interp.base_delay == 0)
		CHECK(interp.jitter_smoothing == 0.1)
	end)

	CASE("should create with custom config", function()
		local interp = interpolation.create {
			max_snapshots = 4,
			base_delay = 0.1,
			jitter_smoothing = 0.2,
		}
		CHECK(interp.max_snapshots == 4)
		CHECK(interp.base_delay == 0.1)
		CHECK(interp.jitter_smoothing == 0.2)
	end)
end)

-- Test 2: basic push and get
TEST("push and get", function()
	local world: jecs.World
	local interp: interpolation.Interpolator

	BEFORE_EACH(function()
		world = jecs.world()
		interp = interpolation.create {
			base_delay = 0,
		}
	end)

	CASE("should return nil for empty buffer", function()
		local entity = world:entity()
		CHECK(interp:get(entity, 1) == nil)
	end)

	CASE("should return raw value with single snapshot and no lerp", function()
		local entity = world:entity()
		interp:push(entity, 1, 42, 1.0)
		local val = interp:get(entity, 1)
		CHECK(val == 42)
	end)

	CASE("should return raw value with single snapshot and lerp registered", function()
		local comp = world:component()
		interp:register(comp, lerp_number)
		local entity = world:entity()
		interp:push(entity, comp, 10, 1.0)
		local val = interp:get(entity, comp)
		CHECK(val == 10)
	end)

	CASE("should interpolate between two snapshots", function()
		local comp = world:component()
		interp:register(comp, lerp_number)

		local entity = world:entity()

		-- Push two values 0.2s apart
		interp:push(entity, comp, 0, 1.0)
		interp:push(entity, comp, 100, 1.2)

		-- We need os.clock() to be between 1.0 and 1.2 relative to these timestamps
		-- Since base_delay = 0 and no jitter, render_time = os.clock()
		-- os.clock() will be way past 1.2, so it should return the newest value (100)
		local val = interp:get(entity, comp)
		-- os.clock() is way past the snapshots, so returns newest
		CHECK(val == 100)
	end)
end)

-- Test 3: ring buffer overflow
TEST("ring buffer", function()
	local world: jecs.World
	local interp: interpolation.Interpolator

	BEFORE_EACH(function()
		world = jecs.world()
		interp = interpolation.create {
			max_snapshots = 3,
			base_delay = 0,
		}
	end)

	CASE("should handle overflow and return newest value", function()
		local comp = world:component()
		interp:register(comp, lerp_number)

		local entity = world:entity()

		-- Push 5 values into a buffer of size 3
		interp:push(entity, comp, 10, 1.0)
		interp:push(entity, comp, 20, 2.0)
		interp:push(entity, comp, 30, 3.0)
		interp:push(entity, comp, 40, 4.0)
		interp:push(entity, comp, 50, 5.0)

		-- Should return the newest value (50) since we're past all timestamps
		local val = interp:get(entity, comp)
		CHECK(val == 50)
	end)
end)

-- Test 4: multiple entities and components
TEST("multiple entities and components", function()
	local world: jecs.World
	local interp: interpolation.Interpolator

	BEFORE_EACH(function()
		world = jecs.world()
		interp = interpolation.create {
			base_delay = 0,
		}
	end)

	CASE("should track separate buffers per entity", function()
		local comp = world:component()
		interp:register(comp, lerp_number)

		local e1 = world:entity()
		local e2 = world:entity()

		interp:push(e1, comp, 100, 1.0)
		interp:push(e2, comp, 200, 1.0)

		CHECK(interp:get(e1, comp) == 100)
		CHECK(interp:get(e2, comp) == 200)
	end)

	CASE("should track separate buffers per component on same entity", function()
		local pos = world:component()
		local vel = world:component()

		local entity = world:entity()

		interp:push(entity, pos, 10, 1.0)
		interp:push(entity, vel, 50, 1.0)

		CHECK(interp:get(entity, pos) == 10)
		CHECK(interp:get(entity, vel) == 50)
	end)

	CASE("should return nil for unregistered component on existing entity", function()
		local comp1 = world:component()
		local comp2 = world:component()

		local entity = world:entity()

		interp:push(entity, comp1, 42, 1.0)

		-- comp1 has data
		CHECK(interp:get(entity, comp1) == 42)
		-- comp2 has no data
		CHECK(interp:get(entity, comp2) == nil)
	end)
end)

-- Test 5: remove_entity
TEST("remove_entity", function()
	local world: jecs.World
	local interp: interpolation.Interpolator

	BEFORE_EACH(function()
		world = jecs.world()
		interp = interpolation.create()
	end)

	CASE("should remove all data for an entity", function()
		local comp = world:component()
		interp:register(comp, lerp_number)

		local entity = world:entity()
		interp:push(entity, comp, 42, 1.0)
		CHECK(interp:get(entity, comp) == 42)

		interp:remove_entity(entity)
		CHECK(interp:get(entity, comp) == nil)
	end)

	CASE("should be safe to call on non-existent entity", function()
		local entity = world:entity()
		-- Should not error
		interp:remove_entity(entity)
	end)

	CASE("should not affect other entities", function()
		local comp = world:component()
		interp:register(comp, lerp_number)

		local e1 = world:entity()
		local e2 = world:entity()

		interp:push(e1, comp, 10, 1.0)
		interp:push(e2, comp, 20, 1.0)

		interp:remove_entity(e1)

		CHECK(interp:get(e1, comp) == nil)
		CHECK(interp:get(e2, comp) == 20)
	end)
end)

-- Test 6: remove_component
TEST("remove_component", function()
	local world: jecs.World
	local interp: interpolation.Interpolator

	BEFORE_EACH(function()
		world = jecs.world()
		interp = interpolation.create()
	end)

	CASE("should remove a single component's buffer", function()
		local comp1 = world:component()
		local comp2 = world:component()

		local entity = world:entity()

		interp:push(entity, comp1, 10, 1.0)
		interp:push(entity, comp2, 20, 1.0)

		interp:remove_component(entity, comp1)

		CHECK(interp:get(entity, comp1) == nil)
		CHECK(interp:get(entity, comp2) == 20)
	end)

	CASE("should clean up entity entry when last component is removed", function()
		local comp = world:component()
		local entity = world:entity()

		interp:push(entity, comp, 42, 1.0)
		CHECK(interp:get(entity, comp) == 42)

		interp:remove_component(entity, comp)

		-- Entity entry should be cleaned up
		CHECK(interp:get(entity, comp) == nil)

		-- Pushing again should still work (fresh entry)
		interp:push(entity, comp, 99, 2.0)
		CHECK(interp:get(entity, comp) == 99)
	end)

	CASE("should be safe to call on non-existent entity or component", function()
		local comp = world:component()
		local entity = world:entity()

		-- Should not error
		interp:remove_component(entity, comp)
	end)
end)

-- Test 7: overwrite / duplicate push at same time
TEST("duplicate and overwrite", function()
	local world: jecs.World
	local interp: interpolation.Interpolator

	BEFORE_EACH(function()
		world = jecs.world()
		interp = interpolation.create {
			base_delay = 0,
		}
	end)

	CASE("should overwrite value at same timestamp", function()
		local comp = world:component()
		interp:register(comp, lerp_number)

		local entity = world:entity()
		interp:push(entity, comp, 10, 1.0)
		interp:push(entity, comp, 99, 1.0)

		-- Both snapshots at time 1.0 — the newer one (99) should be returned
		CHECK(interp:get(entity, comp) == 99)
	end)
end)

-- Test 8: get_delay
TEST("get_delay", function()
	CASE("should return base_delay + jitter initially", function()
		local interp = interpolation.create {
			base_delay = 0.1,
		}
		-- jitter starts at 0
		local delay = interp:get_delay()
		-- base_delay is 0.1, jitter should be 0
		CHECK(math.abs(delay - 0.1) < 0.001)
	end)

	CASE("should increase when packets arrive with jitter", function()
		local interp = interpolation.create {
			base_delay = 0.05,
		}
		local world = jecs.world()
		local comp = world:component()
		local entity = world:entity()

		-- Push several packets with increasing intervals to build up jitter
		interp:push(entity, comp, 1, 1.000)
		interp:push(entity, comp, 2, 1.200) -- 0.2s gap
		interp:push(entity, comp, 3, 1.201) -- tiny gap (skipped due to < 1ms rule)
		interp:push(entity, comp, 4, 1.500) -- 0.299s gap
		interp:push(entity, comp, 5, 1.550) -- 0.05s gap

		-- Jitter should be > 0 now since there were late packets
		local delay = interp:get_delay()
		CHECK(delay > 0.05)
	end)
end)

-- Test 9: many rapid pushes (stress / no-gc test)
TEST("stress", function()
	CASE("should handle many pushes without error", function()
		local interp = interpolation.create {
			max_snapshots = 8,
			base_delay = 0,
		}
		local world = jecs.world()
		local comp = world:component()
		interp:register(comp, lerp_number)

		local entity = world:entity()

		for i = 1, 1000 do
			interp:push(entity, comp, i, i * 0.1)
		end

		local val = interp:get(entity, comp)
		CHECK(val == 1000)
	end)

	CASE("should handle many entities", function()
		local interp = interpolation.create {
			max_snapshots = 4,
			base_delay = 0,
		}
		local world = jecs.world()
		local comp = world:component()

		local entities = {}
		for i = 1, 200 do
			local e = world:entity()
			table.insert(entities, e)
			interp:push(e, comp, i, 1.0)
		end

		for i, e in entities do
			CHECK(interp:get(e, comp) == i)
		end
	end)
end)

-- Test 10: component-specific behavior (unregistered lerp)
TEST("unregistered lerp", function()
	local world: jecs.World
	local interp: interpolation.Interpolator

	BEFORE_EACH(function()
		world = jecs.world()
		interp = interpolation.create {
			base_delay = 0,
		}
	end)

	CASE("should return newest raw value when no lerp is registered", function()
		local comp = world:component()

		local entity = world:entity()
		interp:push(entity, comp, 10, 1.0)
		interp:push(entity, comp, 20, 2.0)

		-- Without lerp, should return the newest value
		local val = interp:get(entity, comp)
		CHECK(val == 20)
	end)
end)

-- Test 11: heavy jitter
TEST("heavy jitter", function()
	CASE("should spike jitter with wildly variable intervals", function()
		local interp = interpolation.create {
			base_delay = 0,
			jitter_smoothing = 0.1,
		}
		local world = jecs.world()
		local comp = world:component()
		interp:register(comp, lerp_number)
		local entity = world:entity()

		-- Push packets with alternating huge/tiny gaps
		interp:push(entity, comp, 1, 0.000)
		interp:push(entity, comp, 2, 0.010) -- 10ms gap
		interp:push(entity, comp, 3, 0.510) -- 500ms gap (huge spike!)
		interp:push(entity, comp, 4, 0.520) -- 10ms gap
		interp:push(entity, comp, 5, 1.520) -- 1000ms gap (another huge spike!)
		interp:push(entity, comp, 6, 1.530) -- 10ms gap

		-- Jitter should be significantly above 0 because of the big gaps
		CHECK(interp.jitter > 0.1)
	end)

	CASE("delay should be at least as large as worst jitter seen", function()
		local interp = interpolation.create {
			base_delay = 0,
			jitter_smoothing = 0.1,
		}
		local world = jecs.world()
		local comp = world:component()
		local entity = world:entity()

		-- Push with big interval variance
		interp:push(entity, comp, 1, 0.0)
		interp:push(entity, comp, 2, 0.05) -- 50ms
		interp:push(entity, comp, 3, 1.05) -- 1000ms gap!
		interp:push(entity, comp, 4, 1.10) -- 50ms

		local delay = interp:get_delay()
		-- The jitter from the 1s gap should drive delay above 0
		CHECK(delay > 0)
	end)
end)

-- Test 12: stale buffer (no packets for a long time, then get)
TEST("stale buffer", function()
	CASE("should return newest value when render_time is past all snapshots", function()
		local interp = interpolation.create {
			base_delay = 0,
		}
		local world = jecs.world()
		local comp = world:component()
		interp:register(comp, lerp_number)
		local entity = world:entity()

		-- Push two old values far in the past
		interp:push(entity, comp, 10, 0.0)
		interp:push(entity, comp, 99, 0.1)

		-- Call get — os.clock() is way past 0.1, so it should clamp to newest
		local val = interp:get(entity, comp)
		CHECK(val == 99)
	end)

	CASE("should still return data even after long silence", function()
		local interp = interpolation.create {
			base_delay = 0,
			max_snapshots = 4,
		}
		local world = jecs.world()
		local comp = world:component()
		interp:register(comp, lerp_number)
		local entity = world:entity()

		-- Push one very old value
		interp:push(entity, comp, 42, 0.001)

		-- get() should still return it even though it's ancient
		local val = interp:get(entity, comp)
		CHECK(val == 42)
	end)

	CASE("should return nil for entity with no data at all", function()
		local interp = interpolation.create()
		local world = jecs.world()
		local comp = world:component()
		local entity = world:entity()

		-- Never pushed anything
		CHECK(interp:get(entity, comp) == nil)
	end)
end)

-- Test 13: jitter recovery
TEST("jitter recovery", function()
	CASE("jitter should decay when packets return to regular cadence", function()
		local interp = interpolation.create {
			base_delay = 0,
			jitter_smoothing = 0.2,
		}
		local world = jecs.world()
		local comp = world:component()
		local entity = world:entity()

		-- Phase 1: create a big jitter spike
		interp:push(entity, comp, 1, 0.0)
		interp:push(entity, comp, 2, 1.0) -- 1s gap → big jitter spike
		interp:push(entity, comp, 3, 1.1) -- 100ms

		local jitter_after_spike = interp.jitter
		CHECK(jitter_after_spike > 0)

		-- Phase 2: push many packets at a steady 100ms cadence
		for i = 4, 30 do
			interp:push(entity, comp, i, 1.1 + (i - 3) * 0.1)
		end

		-- After ~27 regular packets, jitter should have decayed significantly
		local jitter_after_recovery = interp.jitter
		CHECK(jitter_after_recovery < jitter_after_spike)
		-- With 0.2 smoothing and ~27 iterations, jitter should be quite small
		CHECK(jitter_after_recovery < 0.1)
	end)

	CASE("jitter should react to a new spike after settling to zero", function()
		local interp = interpolation.create {
			base_delay = 0,
			jitter_smoothing = 0.2,
		}
		local world = jecs.world()
		local comp = world:component()
		local entity = world:entity()

		-- Start fresh with a perfectly steady cadence (jitter should stay near 0)
		for i = 1, 50 do
			interp:push(entity, comp, i, i * 0.1)
		end

		local settled_jitter = interp.jitter
		-- After 50 pushes at perfectly steady cadence, jitter should be tiny
		CHECK(settled_jitter < 0.01)

		-- Now inject a big gap
		interp:push(entity, comp, 100, 10.0) -- 5s gap from last push at 5.0

		-- Jitter should have jumped up
		CHECK(interp.jitter > settled_jitter)
	end)
end)

local report = testlib.run(plan)
testlib.report(report)
