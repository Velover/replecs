# Systems Reference

## What is a System?

A system is a function that executes game logic. It receives the arguments passed to the Scheduler (typically `world` and `state`).

## System Forms

### 1. Plain Function

The simplest form. Runs every time the scheduler executes it.

```lua
local function movementSystem(world, state)
    for entity, pos, vel in world:query(Position, Velocity) do
        world:set(entity, Position, pos + vel)
    end
end
```

```ts
function movementSystem(world: World, state: unknown) {
  for (const [entity, pos, vel] of world.query(Position, Velocity)) {
    world.set(entity, Position, pos.add(vel));
  }
}
```

### 2. System Table

A table with metadata for debugging, phase assignment, and run conditions.

```lua
return {
    name = "movementSystem",
    system = movementSystem,
    phase = Planck.Phase.Update,
    runConditions = { timePassed(0.1) }
}
```

```ts
export = {
  name: "movementSystem",
  system: movementSystem,
  phase: Phase.Update,
  runConditions: [timePassed(0.1)],
};
```

**Fields:**

| Field           | Type          | Required | Description                        |
| --------------- | ------------- | -------- | ---------------------------------- |
| `name`          | `string`      | No       | Debug name (auto-inferred from fn) |
| `system`        | `function`    | **Yes**  | The system function or initializer |
| `phase`         | `Phase`       | No       | Phase to assign to                 |
| `runConditions` | `Condition[]` | No       | Conditions gating execution        |

### 3. Initializer System

A function that performs one-time setup and returns the runtime system. Runs once, then the returned function runs on all subsequent executions.

```lua
local function renderSystem(world)
    -- One-time setup
    local renderables = world:query(Transform, Model):cached()

    -- Return the runtime system
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

### 4. Initializer with Cleanup

Returns a table with optional `system` and `cleanup` functions. At least one must be present.

```lua
local function networkSystem(world)
    local conn = connectToServer()

    return {
        system = function(world)
            sync(conn)
        end,
        cleanup = function()
            conn:disconnect()
        end,
    }
end
```

```ts
function networkSystem(world: World) {
  const conn = connectToServer();
  return {
    system: (world: World) => sync(conn),
    cleanup: () => conn.disconnect(),
  };
}
```

**InitializerResult fields:**

| Field     | Type       | Required     | Description             |
| --------- | ---------- | ------------ | ----------------------- |
| `system`  | `function` | At least one | Runtime system function |
| `cleanup` | `function` | At least one | Cleanup on removal      |

### 5. Tuple Return (Luau)

Alternative to table return — `(systemFn, cleanupFn)` tuple.

```lua
local function audioSystem(world)
    local audio = setupAudio()

    local function run(world)
        updateAudio(audio)
    end

    local function cleanup()
        audio:Destroy()
    end

    return run, cleanup
end
```

---

## Best Practices

### Single Responsibility

Each system should do one thing:

- `spawnEnemies` — spawns entities
- `moveEnemies` — updates positions
- `despawnEnemies` — removes dead entities

### Self-Contained

Systems should not depend on other systems. If you remove a system, only its behavior should disappear.

### Generic & Reusable

Design systems to be reusable across projects when possible.

### Avoid Yielding

Systems **must not yield** (`wait()`, `task.wait()`, async calls). The scheduler runs systems in a coroutine wrapper that detects yields and reports them as errors.

### Access Delta Time

```lua
local function movementSystem(world)
    local dt = scheduler:getDeltaTime()
    -- use dt for frame-rate independent movement
end
```

---

## System Sets

Batch-add multiple systems at once:

```lua
local systems = { spawnEnemies, moveEnemies, despawnEnemies }
scheduler:addSystems(systems, Phase.Update)
```

```ts
const systems = [spawnEnemies, moveEnemies, despawnEnemies];
scheduler.addSystems(systems, Phase.Update);
```
