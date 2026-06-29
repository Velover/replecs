# Phases & Pipelines Reference

## Phases

A Phase is a tag that tells the Scheduler _when_ to run a group of systems. Think of Roblox's RunService events (`Heartbeat`, `PreSimulation`, etc.) as built-in phases — they are sync points within a frame.

### Creating Phases

```lua
local Phase = Planck.Phase
local myPhase = Phase.new("myPhase")
```

```ts
import { Phase } from "@rbxts/planck";
const myPhase = new Phase("myPhase");
```

If no name is provided, the script and line number are used automatically.

### Built-in Phases

#### Startup Phases

Run **once** before any other phases, on the first scheduler execution.

| Phase         | Order |
| ------------- | ----- |
| `PreStartup`  | 1     |
| `Startup`     | 2     |
| `PostStartup` | 3     |

```lua
local PreStartup = Phase.PreStartup
local Startup = Phase.Startup
local PostStartup = Phase.PostStartup
```

```ts
const { PreStartup, Startup, PostStartup } = Phase;
```

Startup systems are useful for one-time initialization (creating components, spawning initial entities, etc.).

#### RunService Phases (via `planck-runservice`)

| Event            | Pipeline         | Phases                                                   |
| ---------------- | ---------------- | -------------------------------------------------------- |
| `PreRender`      | `PreRender`      | `PreRender`                                              |
| `PreAnimation`   | `PreAnimation`   | `PreAnimation`                                           |
| `PreSimulation`  | `PreSimulation`  | `PreSimulation`                                          |
| `PostSimulation` | `PostSimulation` | `PostSimulation`                                         |
| `Heartbeat`      | `Heartbeat`      | `First` → `PreUpdate` → `Update` → `PostUpdate` → `Last` |

```ts
import { Pipelines, Phases } from "@rbxts/planck-runservice";

const { PreRender, Heartbeat } = Pipelines;
const { First, PreUpdate, Update, PostUpdate, Last } = Phases;
```

### Assigning Systems to Phases

**Via `addSystem`:**

```lua
scheduler:addSystem(mySystem, myPhase)
```

**Via SystemTable:**

```lua
return {
    system = mySystem,
    phase = myPhase,
}
```

**Via `insert` (registers phase with scheduler):**

```lua
scheduler:insert(myPhase, RunService, "Heartbeat")
```

---

## Pipelines

A Pipeline is an ordered group of Phases. Systems are assigned to Phases _within_ Pipelines, not to Pipelines directly.

### Creating Pipelines

```lua
local Pipeline = Planck.Pipeline

local PreUpdate = Phase.new()
local Update = Phase.new()
local PostUpdate = Phase.new()

local MyPipeline = Pipeline.new("MyPipeline")
    :insert(PreUpdate)
    :insert(Update)
    :insert(PostUpdate)
```

```ts
import { Phase, Pipeline } from "@rbxts/planck";

const PreUpdate = new Phase();
const Update = new Phase();
const PostUpdate = new Phase();

const MyPipeline = new Pipeline("MyPipeline")
  .insert(PreUpdate)
  .insert(Update)
  .insert(PostUpdate);
```

### Built-in Pipelines

| Pipeline  | Description                                     |
| --------- | ----------------------------------------------- |
| `Startup` | Contains `PreStartup`, `Startup`, `PostStartup` |

```lua
local StartupPipeline = Pipeline.Startup
```

```ts
import { Pipeline } from "@rbxts/planck";
const StartupPipeline = Pipeline.Startup;
```

### Pipeline Methods

#### `insert(phase)`

Adds a Phase to the end of the Pipeline (implicit ordering).

#### `insertAfter(phase, afterPhase)`

Adds a Phase after another Phase (explicit ordering).

#### `insertBefore(phase, beforePhase)`

Adds a Phase before another Phase (explicit ordering).

---

## Ordering

### Kahn's Algorithm

Planck uses **Kahn's algorithm** for topological sorting of Phases and Pipelines.

**How it works:**

1. Start with the first inserted Phase/Pipeline.
2. If it has dependencies, skip it.
3. Add it to the order.
4. If it has dependents, process them in insertion order.
5. Move to the next Phase/Pipeline.

### Dependency Terminology

- **Dependency**: A Phase/Pipeline that must run _before_ another.
- **Dependent**: A Phase/Pipeline that runs _after_ its dependency.

`insertAfter(dependent, dependency)` — dependent runs after dependency.
`insertBefore(dependent, dependency)` — dependent runs before dependency.

### Implicit vs Explicit Ordering

**Implicit** (by insertion):

```lua
scheduler:insert(phaseA)
scheduler:insert(phaseB)
-- phaseA runs before phaseB
```

**Explicit** (by dependency):

```lua
scheduler:insertAfter(phaseB, phaseA)
-- phaseB runs after phaseA
```

### System Ordering

Systems within a Phase are ordered by insertion order only.

```lua
scheduler:addSystem(systemA, myPhase)
scheduler:addSystem(systemB, myPhase)
-- systemA runs before systemB
```

### Groups

Each event forms an independent **group**. Phases in different groups are ordered independently.

```lua
-- Two groups: Heartbeat and PostSimulation
scheduler:insert(pipelineA, RunService, "Heartbeat")
scheduler:insert(pipelineB, RunService, "PostSimulation")
```

When using `runAll()`, the Default group runs first, then each event group in creation order.

### Off-by-a-Frame

When `systemA` modifies data that `systemB` reads, place `systemA` in an earlier Phase than `systemB`. Otherwise, `systemB` sees stale data for one full frame — visible as input lag or visual latency.
