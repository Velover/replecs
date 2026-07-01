--!optimize 2
--!native

local common = require "./common"

type Entity = common.Entity
type Component<T = any> = common.Component<T>

type Array<T> = { T }
type Map<K, V> = { [K]: V }

type LerpFn<T> = (a: T, b: T, t: number) -> T

export type InterpolatorConfig = {
	max_snapshots: number?,
	base_delay: number?,
	jitter_smoothing: number?,
}

type SnapshotRing = {
	values: Array<any>,
	times: Array<number>,
	write: number,
	count: number,
}

type Interpolator = {
	max_snapshots: number,
	base_delay: number,
	jitter_smoothing: number,

	lerps: Map<Component, LerpFn<any>>,
	buffers: Map<Entity, Map<Component, SnapshotRing>>,

	last_push_time: number?,
	avg_interval: number?,
	jitter: number,
}

local interpolator = {}
interpolator.__index = interpolator

local function create_ring(max: number): SnapshotRing
	return {
		values = table.create(max),
		times = table.create(max),
		write = 1,
		count = 0,
	}
end

-- Get 1-indexed array position for the i-th most recent entry (0 = newest)
local function ring_idx(write: number, i: number, max: number): number
	return (write - 2 - i + max * 2) % max + 1
end

--[[
	Register a lerp function for a component type.
	If not registered, get() returns the newest raw value without interpolation.
]]
function interpolator.register<T>(self: Interpolator, component: Component<T>, lerp: LerpFn<T>)
	self.lerps[component] = lerp
end

--[[
	Push a new snapshot for an entity/component.
	Typically called from a client hook or override callback.
	`time` should be os.clock() or equivalent monotonic timestamp.
]]
function interpolator.push(self: Interpolator, entity: Entity, component: Component, value: any, time: number)
	local entity_buf = self.buffers[entity]
	if not entity_buf then
		entity_buf = {}
		self.buffers[entity] = entity_buf
	end

	local ring = entity_buf[component]
	if not ring then
		ring = create_ring(self.max_snapshots)
		entity_buf[component] = ring
	end

	local max = self.max_snapshots
	ring.values[ring.write] = value
	ring.times[ring.write] = time
	ring.write = ring.write % max + 1
	if ring.count < max then
		ring.count += 1
	end

	-- Jitter tracking: skip if this push is within 1ms of the last
	-- (same packet, multiple components)
	if self.last_push_time then
		local delta = time - self.last_push_time
		if delta > 0.001 then
			if self.avg_interval then
				self.avg_interval += 0.1 * (delta - self.avg_interval)
			else
				self.avg_interval = delta
			end

			local deviation = math.abs(delta - self.avg_interval)
			if deviation > self.jitter then
				-- Fast attack: packets arrived late, increase buffer quickly
				self.jitter += 0.5 * (deviation - self.jitter)
			else
				-- Slow decay: packets arrived on time, shrink buffer gradually
				self.jitter += self.jitter_smoothing * (deviation - self.jitter)
			end
		end
	end
	self.last_push_time = time
end

--[[
	Get the interpolated value for an entity/component.
	Returns nil if no snapshots exist.

	`now` (optional): the current time in the same domain as push timestamps.
		If omitted, defaults to os.clock().
	Render time = now - (base_delay + jitter)
	Finds two bracketing snapshots and lerps between them.
	If render_time is past the newest snapshot, returns the newest value.
]]
function interpolator.get(self: Interpolator, entity: Entity, component: Component, now: number?): any
	local entity_buf = self.buffers[entity]
	if not entity_buf then
		return nil
	end

	local ring = entity_buf[component]
	if not ring or ring.count == 0 then
		return nil
	end

	local max = self.max_snapshots
	local lerp = self.lerps[component]
	local render_time = (now or os.clock()) - (self.base_delay + self.jitter)

	-- Only one snapshot: return it directly
	if ring.count == 1 then
		return ring.values[ring_idx(ring.write, 0, max)]
	end

	-- Walk backward from newest to find two snapshots bracketing render_time
	for i = 0, ring.count - 2 do
		local newer = ring_idx(ring.write, i, max)
		local older = ring_idx(ring.write, i + 1, max)

		if ring.times[older] <= render_time and ring.times[newer] > render_time then
			if lerp then
				local duration = ring.times[newer] - ring.times[older]
				local t = (render_time - ring.times[older]) / duration
				return lerp(ring.values[older], ring.values[newer], t)
			else
				return ring.values[newer]
			end
		end
	end

	-- render_time is outside the snapshot range — return newest
	return ring.values[ring_idx(ring.write, 0, max)]
end

--[[
	Remove all buffered state for an entity.
	Call when an entity is deleted or leaves the client's scope.
]]
function interpolator.remove_entity(self: Interpolator, entity: Entity)
	self.buffers[entity] = nil
end

--[[
	Remove buffered state for a specific component on an entity.
	Call when a component is removed or stops being replicated.
	Also cleans up the entity entry if no components remain.
]]
function interpolator.remove_component(self: Interpolator, entity: Entity, component: Component)
	local entity_buf = self.buffers[entity]
	if not entity_buf then
		return
	end
	entity_buf[component] = nil
	if next(entity_buf) == nil then
		self.buffers[entity] = nil
	end
end

--[[
	Returns the current effective render delay: base_delay + jitter.
	Useful for debugging or displaying network conditions.
]]
function interpolator.get_delay(self: Interpolator): number
	return self.base_delay + self.jitter
end

--[[
	Create a new interpolator.

	Config:
	  - max_snapshots (default 8): ring buffer size per entity/component
	  - base_delay (default 0): minimum render delay in seconds.
	        Set to roughly the replication interval (e.g. 0.1 for 10Hz).
	  - jitter_smoothing (default 0.1): how fast the jitter buffer
	        shrinks when packets arrive on time. Higher = faster recovery.
	        Attack (growth) is always ~5x faster than this.
]]
local function create(config: InterpolatorConfig?): Interpolator
	local cfg = config or {} :: InterpolatorConfig
	local self = {} :: Interpolator

	self.max_snapshots = cfg.max_snapshots or 8
	self.base_delay = cfg.base_delay or 0
	self.jitter_smoothing = cfg.jitter_smoothing or 0.1

	self.lerps = {}
	self.buffers = {}

	self.last_push_time = nil
	self.avg_interval = nil
	self.jitter = 0

	return setmetatable(self, interpolator) :: any
end

return {
	create = create,
}
