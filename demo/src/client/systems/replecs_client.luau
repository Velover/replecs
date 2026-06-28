local ReplicatedStorage = game:GetService "ReplicatedStorage"

local collect = require(ReplicatedStorage.code.utils.collect)
local replicator = require(script.Parent.Parent.replicator)
local scheduler = require(ReplicatedStorage.code.utils.ecs.scheduler)
local zap = require(ReplicatedStorage.code.zap)

local reliable_updates = collect(zap.OnReliableUpdates.SetCallback)
local unreliable_updates = collect(zap.OnUnreliableUpdates.SetCallback)
local ownership_grants = collect(zap.OnOwnershipGrant.SetCallback)

local ownership_interval = 1 / 30
local last_ownership_tick = os.clock()

function REPLECS_CLIENT()
	for _, buf, variants in reliable_updates do
		replicator:apply_updates(buf, variants)
	end
	for _, buf, variants in unreliable_updates do
		replicator:apply_unreliable(buf, variants)
	end
	for _, buf, variants in ownership_grants do
		replicator:apply_ownership_grant(buf, variants)
	end

	-- Send ownership updates at a fixed rate
	local now = os.clock()
	if now - last_ownership_tick >= ownership_interval then
		last_ownership_tick = now
		for buf, variants in replicator:collect_ownership() do
			zap.OnOwnershipReliable.Fire(buf, variants)
		end
		for buf, variants in replicator:collect_ownership_unreliable() do
			zap.OnOwnershipUnreliable.Fire(buf, variants)
		end
	end
end

scheduler.System(REPLECS_CLIENT)
return REPLECS_CLIENT
