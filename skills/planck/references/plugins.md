# Plugins Reference

## Overview

Plugins extend the Scheduler via the **Hooks API**. They can add systems, phases, run conditions, and react to lifecycle events.

## Plugin Interface

```lua
type Plugin = setmetatable<{}, {
    build: (self: Plugin, scheduler: Scheduler<...unknown>) -> (),
    cleanup: ((self: Plugin) -> ())?,
    new: (...any) -> Plugin,
}>
```

```ts
interface Plugin<T extends unknown[]> {
  build(scheduler: Scheduler<T>): void;
  cleanup?(): void;
}
```

| Method    | Required | Description                                  |
| --------- | -------- | -------------------------------------------- |
| `build`   | **Yes**  | Called when plugin is added to scheduler     |
| `cleanup` | No       | Called when `scheduler:cleanup()` is invoked |
| `new`     | No\*     | Static constructor (Luau pattern)            |

\*In Luau, plugins use metatables with a `new()` constructor. In TypeScript, plugins are plain objects.

---

## Plugin Template (Luau)

```lua
local Planck = require("@packages/planck")
type Scheduler<U...> = Planck.Scheduler<U...>

local Plugin = {}
Plugin.__index = Plugin

function Plugin.build(self: Plugin, scheduler: Scheduler<...unknown>)
    -- Add hooks, systems, phases, etc.
end

function Plugin.cleanup(self: Plugin)
    -- Disconnect connections, free resources
end

function Plugin.new(): Plugin
    local plugin = {}
    return setmetatable(plugin, Plugin)
end

type Plugin = setmetatable<{
    -- properties
}, typeof(Plugin)>

return Plugin
```

## Plugin Template (TypeScript)

```ts
import { Plugin, Scheduler } from "@rbxts/planck";
import { World } from "@rbxts/jecs";

const MyPlugin: Plugin<[World]> = {
  build(scheduler) {
    scheduler.addHook(scheduler.Hooks.SystemAdd, (context) => {
      // ...
    });
  },
  cleanup() {
    // ...
  },
};

export = MyPlugin;
```

---

## Adding Plugins

```lua
scheduler:addPlugin(MyPlugin.new())
```

```ts
scheduler.addPlugin(myPlugin);
```

---

## Hooks API

The Scheduler exposes lifecycle hooks via `scheduler.Hooks`. Register callbacks with `scheduler:addHook(hook, fn)`.

### Hook: `SystemAdd`

Fires when a system is added to the scheduler.

**Context:**

```lua
{
    scheduler: Scheduler,
    system: SystemInfo,
}
```

**Use case:** Debugger integration, logging, tracking systems.

---

### Hook: `SystemRemove`

Fires when a system is removed.

**Context:** Same as `SystemAdd`.

**Use case:** Cleaning up debugger registrations, hot-reload support.

---

### Hook: `SystemReplace`

Fires when a system is replaced via `replaceSystem`.

**Context:**

```lua
{
    scheduler: Scheduler,
    new: SystemInfo,
    old: SystemInfo,
}
```

---

### Hook: `SystemEdited`

Fires when a system's phase is changed via `editSystem`.

**Context:**

```lua
{
    scheduler: Scheduler,
    system: SystemInfo,
    old: Phase,
    new: Phase,
}
```

---

### Hook: `SystemCleanup`

Fires when a system's cleanup function encounters an error during removal.

**Context:**

```lua
{
    scheduler: Scheduler,
    system: SystemInfo,
    error: SystemLog?,
}
```

---

### Hook: `SystemError`

Fires when a system throws a runtime error.

**Context:**

```lua
{
    scheduler: Scheduler,
    system: SystemInfo,
    error: SystemLog,
}
```

---

### Hook: `SystemTriedRun`

Fires when a system attempted to run but was blocked by a Run Condition.

**Context:** Same as `SystemAdd`.

---

### Hook: `OuterSystemCall` / `InnerSystemCall` / `SystemCall`

Wrapping hooks for system execution. Return a function that calls `context.nextFn()` to proceed.

**Context:**

```lua
{
    scheduler: Scheduler,
    system: SystemInfo,
    nextFn: () -> (),
}
```

**Returns:** `() -> ()` — a function that wraps the next call.

**Use case:** Profiling, measuring execution time, error boundaries.

```lua
scheduler:addHook(scheduler.Hooks.SystemCall, function(context)
    return function()
        local start = os.clock()
        context.nextFn()
        local elapsed = os.clock() - start
        print(context.system.name .. " took " .. elapsed .. "s")
    end
end)
```

---

### Hook: `PhaseAdd`

Fires when a Phase is added to the scheduler.

**Context:**

```lua
{
    scheduler: Scheduler,
    phase: Phase,
}
```

---

### Hook: `PhaseBegan`

Fires when a Phase begins execution.

**Context:** Same as `PhaseAdd`.

---

## SystemInfo Type

Available in all hook contexts via `context.system`:

| Field         | Type       | Description                             |
| ------------- | ---------- | --------------------------------------- |
| `system`      | `function` | Original system function                |
| `run`         | `function` | Current callable (changes after init)   |
| `cleanup?`    | `function` | Cleanup function (if provided)          |
| `initialized` | `boolean`  | Whether the initializer has run         |
| `name`        | `string`   | System name                             |
| `deltaTime?`  | `number`   | Time since last execution               |
| `lastTime?`   | `number`   | Timestamp of last execution             |
| `logs`        | `array`    | Accumulated errors/warnings             |
| `recentLogs`  | `table`    | Recently reported errors (dedup window) |
| `phase`       | `Phase`    | Assigned Phase                          |

---

## Official Plugins

### `planck-runservice`

Adds Phases and Pipelines for all RunService events.

**Wally:** `yetanotherclown/planck-runservice@0.2.0`
**npm:** `@rbxts/planck-runservice`

```lua
local PlanckRunService = require("@packages/PlanckRunService")
scheduler:addPlugin(PlanckRunService.new())
```

**Exports:**

- `Pipelines.PreRender`, `PreAnimation`, `PreSimulation`, `PostSimulation`, `Heartbeat`
- `Phases.PreRender`, `PreAnimation`, `PreSimulation`, `PostSimulation`, `First`, `PreUpdate`, `Update`, `PostUpdate`, `Last`

---

### `planck-jabby`

Integrates the [Jabby](https://github.com/alicesaidhi/jabby) debugger for Jecs.

**Wally:** `yetanotherclown/planck-jabby@0.2.0`
**npm:** `@rbxts/planck-jabby`

```lua
local PlanckJabby = require("@packages/PlanckJabby")
scheduler:addPlugin(PlanckJabby.new())
```

Uses `SystemAdd`, `SystemRemove`, `PhaseAdd`, and `PhaseBegan` hooks to register/unregister systems and phases with Jabby.

---

### `planck-matter-hooks`

Provides the Matter topoRuntime for using Matter-style hooks (like `useThrottle`, `useEvent`, `useDeltaTime`) with **any** ECS library.

**Wally:** `yetanotherclown/planck-matter-hooks@0.2.1`
**npm:** `@rbxts/planck-matter-hooks`

```lua
local MatterHooks = require("@packages/MatterHooks")
scheduler:addPlugin(MatterHooks.new())
```

**Exports (usable in systems):**

- `useDeltaTime()` — returns delta time
- `useEvent(signal)` — collects events per frame
- `useThrottle(seconds)` — throttle within a system
- `useHookState()` — per-system hook state
- `log(...)` — logging with dedup

---

### `planck-matter-debugger`

Integrates the Matter Debugger with Planck.

**Wally:** `yetanotherclown/planck-matter-debugger@0.2.0`
**npm:** `@rbxts/planck-matter-debugger`

---

## Important Notes

- **Avoid private members** (`_` prefix) in plugins — they may change without notice in any version.
- **SystemInfo** members are accessible and relatively stable, but breaking changes may occur with notice.
- **Jabby/Matter Debugger** plugins cannot be properly cleaned up — use caution with throwaway schedulers.
- Use `scheduler:cleanup()` only when discarding the scheduler entirely.
