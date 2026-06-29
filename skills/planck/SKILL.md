---
name: planck
description: >
  Expert guidance for Planck — an agnostic ECS Scheduler for Roblox, inspired by Bevy Schedules and Flecs Pipelines.
  Covers the Scheduler, Systems, Phases, Pipelines, Run Conditions, Plugins, ordering via Kahn's algorithm,
  RunService integration, Matter Hooks, Jabby debugger support, hot-reload, and system lifecycle hooks.
  USE WHEN: writing or debugging code that uses Planck; setting up ECS system scheduling and execution order;
  implementing Run Conditions (timePassed, runOnce, onEvent, isNot); creating Phases and Pipelines for ordered execution;
  building or using Plugins with the Scheduler Hooks API; integrating Planck with Jecs, Matter, or ECR;
  understanding off-by-a-frame issues and system ordering.
  DO NOT USE FOR: general ECS composition questions unrelated to scheduling; direct jecs world queries/components (use jecs docs);
  networking/replication (use Replecs instead).
---

# Planck Skill

## Overview

Planck is a standalone, library-agnostic ECS scheduler for Roblox inspired by **Bevy Schedules** and **Flecs Pipelines & Phases**. It provides:

- **Scheduler** — the core orchestrator that runs Systems in a defined order
- **Systems** — functions (or tables) that execute game logic on events or in a loop
- **Phases** — sync points / tags that group systems for ordered execution
- **Pipelines** — ordered groups of Phases running on the same event
- **Run Conditions** — predicates that gate system/phase/pipeline execution
- **Plugins** — extensible hooks into the Scheduler lifecycle
- **Library-agnostic** — works with Jecs, Matter, ECR, or no ECS at all

## Architecture

```
┌──────────────────────────────────────────────────────┐
│                     Scheduler                         │
│  (world, state, plugins, hooks, dependency graph)     │
└──────────────────────┬───────────────────────────────┘
                       │ Kahn's algorithm ordering
          ┌────────────┴────────────┐
          ▼                         ▼
   ┌─────────────┐          ┌─────────────┐
   │  Pipelines  │          │   Phases    │
   │ (ordered    │────contains──→│ (sync      │
   │  phases)    │          │  points)    │
   └─────────────┘          └──────┬──────┘
                                   │ assigned to
                            ┌──────┴──────┐
                            ▼             ▼
                     ┌──────────┐  ┌──────────┐
                     │ Systems  │  │ Systems  │
                     │ (fn or   │  │ (fn or   │
                     │  table)  │  │  table)  │
                     └──────────┘  └──────────┘
                            ▲
                            │ gated by
                     ┌──────┴──────┐
                     │   Run       │
                     │ Conditions  │
                     └─────────────┘
```

## Quick Start

### 1. Create the Scheduler

```lua
local Planck = require("@packages/Planck")
local Scheduler = Planck.Scheduler

local Jecs = require("@packages/Jecs")
local World = Jecs.World

local world = World.new()
local state = {}

local scheduler = Scheduler.new(world, state)
```

```ts
import { Scheduler } from "@rbxts/planck";
import { World } from "@rbxts/jecs";

const world = new World();
const state = {};

const scheduler = new Scheduler(world, state);
```

### 2. Add the RunService Plugin (recommended)

```lua
local PlanckRunService = require("@packages/PlanckRunService")
local runServicePlugin = PlanckRunService.new()

scheduler:addPlugin(runServicePlugin)
```

```ts
import { Plugin as RunServicePlugin } from "@rbxts/planck-runservice";
const runServicePlugin = new RunServicePlugin();

scheduler.addPlugin(runServicePlugin);
```

### 3. Write Systems

Systems are functions (or tables with metadata) that receive the world and state.

```lua
-- Simple function system
local function movementSystem(world, state)
    for entity, position, velocity in world:query(Position, Velocity) do
        world:set(entity, Position, position + velocity)
    end
end
```

```ts
function movementSystem(world: World, state: unknown) {
  for (const [entity, position, velocity] of world.query(Position, Velocity)) {
    world.set(entity, Position, position.add(velocity));
  }
}
```

#### System Tables

```lua
return {
    name = "movementSystem",
    system = movementSystem,
    phase = Planck.Phase.Update,
    runConditions = { condition }
}
```

```ts
export = {
  name: "movementSystem",
  system: movementSystem,
  phase: Phase.Update,
  runConditions: [condition],
};
```

#### Initializer Systems (one-time setup)

```lua
local function renderSystem(world)
    local renderables = world:query(Transform, Model):cached()

    return function(world)
        for entity, transform, model in renderables do
            render(transform, model)
        end
    end
end
```

```ts
function renderSystem(world: World): SystemFn<[World]> {
  const renderables = world.query(Transform, Model).cached();
  return (world: World) => {
    for (const [, transform, model] of renderables) {
      render(transform, model);
    }
  };
}
```

#### Initializer with Cleanup

```lua
local function networkSystem(world)
    local conn = connect()

    return {
        system = function(world) sync(conn) end,
        cleanup = function() conn:disconnect() end,
    }
end
```

```ts
function networkSystem(world: World) {
  const conn = connect();
  return {
    system: (world: World) => sync(conn),
    cleanup: () => conn.disconnect(),
  };
}
```

### 4. Add Systems to the Scheduler

```lua
scheduler:addSystem(movementSystem)
-- or with explicit phase:
scheduler:addSystem(renderSystem, Phases.Update)
-- or batch:
scheduler:addSystems({ systemA, systemB })
```

```ts
scheduler.addSystem(movementSystem);
// or with explicit phase:
scheduler.addSystem(renderSystem, Phases.Update);
// or batch:
scheduler.addSystems([systemA, systemB]);
```

### 5. The Scheduler automatically runs systems via connected events

There is no explicit `start()` call — once systems are added and phases are connected to events (via the RunService plugin or manual `insert`), the scheduler runs them when those events fire.

```lua
-- Manual event connection (if not using RunService plugin)
scheduler:insert(myPhase, RunService, "Heartbeat")
```

## Key Concepts

### Phases

Phases are sync points that group systems. They represent _when_ in a frame code runs.

**Built-in Startup Phases** (run once, before everything else):

| Phase         | Description                            |
| ------------- | -------------------------------------- |
| `PreStartup`  | Runs before `Startup`                  |
| `Startup`     | Runs once on first scheduler execution |
| `PostStartup` | Runs after `Startup`                   |

**RunService Plugin Phases** (via `planck-runservice`):

| Pipeline         | Phases                                                   |
| ---------------- | -------------------------------------------------------- |
| `PreRender`      | `PreRender`                                              |
| `PreAnimation`   | `PreAnimation`                                           |
| `PreSimulation`  | `PreSimulation`                                          |
| `PostSimulation` | `PostSimulation`                                         |
| `Heartbeat`      | `First` → `PreUpdate` → `Update` → `PostUpdate` → `Last` |

```lua
local Phase = Planck.Phase
local myPhase = Phase.new("myPhase")

scheduler:insert(myPhase)
scheduler:insert(myPhase, RunService, "Heartbeat")
```

```ts
import { Phase } from "@rbxts/planck";
const myPhase = new Phase("myPhase");

scheduler.insert(myPhase);
scheduler.insert(myPhase, RunService, "Heartbeat");
```

### Pipelines

Pipelines are ordered groups of Phases that run on the same event.

```lua
local Pipeline = Planck.Pipeline

local PreUpdate = Phase.new()
local Update = Phase.new()
local PostUpdate = Phase.new()

local MyPipeline = Pipeline.new()
    :insert(PreUpdate)
    :insert(Update)
    :insert(PostUpdate)

scheduler:insert(MyPipeline, RunService, "Heartbeat")
```

```ts
import { Phase, Pipeline } from "@rbxts/planck";

const PreUpdate = new Phase();
const Update = new Phase();
const PostUpdate = new Pipeline();

const MyPipeline = new Pipeline()
  .insert(PreUpdate)
  .insert(Update)
  .insert(PostUpdate);

scheduler.insert(MyPipeline, RunService, "Heartbeat");
```

### Ordering

- **Systems**: Ordered by insertion order within a Phase.
- **Phases/Pipelines**: Ordered by Kahn's algorithm using dependency graphs.
- **Implicit ordering**: `insert(A)` then `insert(B)` → A runs before B.
- **Explicit ordering**: `insertAfter(B, A)` or `insertBefore(B, A)`.
- **Groups**: Each event forms a group. Phases in different groups are ordered independently.

### Run Conditions

Gate system/phase/pipeline execution with predicate functions.

```lua
local timePassed = Planck.timePassed
local runOnce = Planck.runOnce
local onEvent = Planck.onEvent
local isNot = Planck.isNot

scheduler
    :addRunCondition(systemA, timePassed(10))       -- every 10 seconds
    :addRunCondition(systemB, runOnce())            -- only once
    :addRunCondition(systemC, onEvent(Players.PlayerAdded)) -- on event
    :addRunCondition(systemD, isNot(timePassed(5))) -- invert a condition
```

```ts
import { timePassed, runOnce, onEvent, isNot } from "@rbxts/planck";

scheduler
  .addRunCondition(systemA, timePassed(10))
  .addRunCondition(systemB, runOnce())
  .addRunCondition(systemC, onEvent(Players.PlayerAdded))
  .addRunCondition(systemD, isNot(timePassed(5)));
```

#### `onEvent` — Event-driven conditions

`onEvent` returns `[hasNewEvent, collectEvents]`. Use `hasNewEvent` as a run condition and `collectEvents` inside the system to iterate events.

```lua
local hasNewPlayer, collectPlayers = onEvent(Players.PlayerAdded)

local function playerJoinSystem()
    for i, player in collectPlayers() do
        -- handle new player
    end
end

scheduler
    :addSystem(playerJoinSystem)
    :addRunCondition(playerJoinSystem, hasNewPlayer)
```

```ts
const [hasNewPlayer, collectPlayers] = onEvent(Players.PlayerAdded);

function playerJoinSystem() {
  for (const [i, player] of collectPlayers()) {
    // handle new player
  }
}

scheduler
  .addSystem(playerJoinSystem)
  .addRunCondition(playerJoinSystem, hasNewPlayer);
```

### Plugins

Plugins extend the Scheduler via the Hooks API.

```lua
local MyPlugin = {}
MyPlugin.__index = MyPlugin

function MyPlugin.build(self, scheduler)
    scheduler:addHook(scheduler.Hooks.SystemAdd, function(context)
        local systemInfo = context.system
        -- react to system being added
    end)
end

function MyPlugin.cleanup(self)
    -- disconnect/cleanup
end

function MyPlugin.new()
    return setmetatable({}, MyPlugin)
end

scheduler:addPlugin(MyPlugin.new())
```

```ts
import { Plugin, Scheduler } from "@rbxts/planck";

const MyPlugin: Plugin<[World]> = {
  build(scheduler) {
    scheduler.addHook(scheduler.Hooks.SystemAdd, (context) => {
      const systemInfo = context.system;
      // react to system being added
    });
  },
  cleanup() {
    // disconnect/cleanup
  },
};

scheduler.addPlugin(MyPlugin);
```

#### Available Hooks

| Hook              | Context Fields                | Description                         |
| ----------------- | ----------------------------- | ----------------------------------- |
| `SystemAdd`       | `scheduler, system`           | System added to scheduler           |
| `SystemRemove`    | `scheduler, system`           | System removed                      |
| `SystemReplace`   | `scheduler, new, old`         | System replaced                     |
| `SystemEdited`    | `scheduler, system, old, new` | System phase changed                |
| `SystemCleanup`   | `scheduler, system, error?`   | Cleanup error during removal        |
| `SystemError`     | `scheduler, system, error`    | Runtime error in system             |
| `SystemTriedRun`  | `scheduler, system`           | System tried to run but was blocked |
| `OuterSystemCall` | `scheduler, system, nextFn`   | Wraps entire system call            |
| `InnerSystemCall` | `scheduler, system, nextFn`   | Wraps inner system execution        |
| `SystemCall`      | `scheduler, system, nextFn`   | Direct system call wrapper          |
| `PhaseAdd`        | `scheduler, phase`            | Phase added to scheduler            |
| `PhaseBegan`      | `scheduler, phase`            | Phase execution started             |

### Official Plugins

| Plugin          | Package (Wally)                          | Package (npm)                   | Description                                     |
| --------------- | ---------------------------------------- | ------------------------------- | ----------------------------------------------- |
| RunService      | `yetanotherclown/planck-runservice`      | `@rbxts/planck-runservice`      | Built-in Phases/Pipelines for RunService events |
| Jabby           | `yetanotherclown/planck-jabby`           | `@rbxts/planck-jabby`           | Jabby debugger integration                      |
| Matter Hooks    | `yetanotherclown/planck-matter-hooks`    | `@rbxts/planck-matter-hooks`    | Matter topoRuntime & hooks (library-agnostic)   |
| Matter Debugger | `yetanotherclown/planck-matter-debugger` | `@rbxts/planck-matter-debugger` | Matter Debugger integration                     |

### `scheduler:getDeltaTime()`

Returns the delta time for the currently executing system. Must be called from within a registered system.

```lua
local function movementSystem(world, state)
    local dt = scheduler:getDeltaTime()
    for entity, position, velocity in world:query(Position, Velocity) do
        world:set(entity, Position, position + velocity * dt)
    end
end
```

```ts
function movementSystem(world: World, state: unknown) {
  const dt = scheduler.getDeltaTime();
  for (const [entity, position, velocity] of world.query(Position, Velocity)) {
    world.set(entity, Position, position.add(velocity.mul(dt)));
  }
}
```

### Cleanup & Hot-Reload

```lua
-- Remove a system (triggers cleanup function if provided)
scheduler:removeSystem(mySystem)

-- Replace a system
scheduler:replaceSystem(oldSystem, newSystem)

-- Change a system's phase
scheduler:editSystem(mySystem, newPhase)

-- Full cleanup (disconnects everything — only if discarding the scheduler)
scheduler:cleanup()
```

```ts
scheduler.removeSystem(mySystem);
scheduler.replaceSystem(oldSystem, newSystem);
scheduler.editSystem(mySystem, newPhase);
scheduler.cleanup();
```

## Design Principles

### Single Responsibility

Each system should do one thing. Split large systems into smaller ones.

### Self-Contained

Systems should not depend on other systems. Removing a system should only remove its behavior.

### Avoid Off-by-a-Frame

When `systemA` modifies data that `systemB` depends on, ensure `systemA` runs in an earlier Phase than `systemB`. Otherwise `systemB` sees stale data for one frame.

### Minimize Phase Count

Too many phases increases complexity. Use Pipelines to group related phases.

### Conditions Are For Optimization

Conditions don't change game logic — they optimize by skipping unnecessary work (e.g., throttling, event-driven execution).

## Reference Files

- **[Scheduler API](references/scheduler-api.md)** — Complete Scheduler class API reference
- **[Systems](references/systems.md)** — Systems deep-dive: functions, tables, initializers, cleanup
- **[Phases & Pipelines](references/phases-pipelines.md)** — Phase/Pipeline types, ordering, groups
- **[Conditions](references/conditions.md)** — All built-in Run Conditions
- **[Plugins](references/plugins.md)** — Plugin system, Hooks API, official plugins
