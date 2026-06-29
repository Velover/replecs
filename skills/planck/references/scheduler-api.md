# Scheduler API Reference

## `Scheduler`

The core object that orchestrates system execution. Manages phases, pipelines, systems, plugins, hooks, and the dependency graph.

### Constructor

```lua
-- Luau
local scheduler = Scheduler.new(world, state)
```

```ts
// TypeScript
const scheduler = new Scheduler(world, state);
```

**Parameters:**

- `...args` — Variadic arguments passed to every system each time it runs. Typically `(world, state)`.

---

### Methods

#### `addPlugin(plugin)`

Registers a Plugin with the scheduler. Calls `plugin:build(scheduler)` internally.

```lua
scheduler:addPlugin(MyPlugin.new())
```

**Returns:** `self` (chainable)

---

#### `addHook(hook, fn)`

Registers a callback for a lifecycle hook. Use `scheduler.Hooks.*` constants.

```lua
scheduler:addHook(scheduler.Hooks.SystemAdd, function(context)
    -- context.scheduler, context.system
end)
```

---

#### `addSystem(system, phase?)`

Adds a system to the scheduler. The system can be:

- A plain function: `function(world, state) ... end`
- An initializer function: returns a function or `{system?, cleanup?}`
- A SystemTable: `{ name?, system, phase?, runConditions? }`

```lua
scheduler:addSystem(mySystem)
scheduler:addSystem(mySystem, myPhase)
```

**Returns:** `self` (chainable)

---

#### `addSystems(systems, phase?)`

Adds an array of systems at once.

```lua
scheduler:addSystems({ systemA, systemB }, myPhase)
```

**Returns:** `self` (chainable)

---

#### `editSystem(system, newPhase)`

Changes the Phase a system is scheduled on.

**Returns:** `self` (chainable)

---

#### `removeSystem(system)`

Removes a system. If the system provided a `cleanup` function, it runs before removal.

**Returns:** `self` (chainable)

---

#### `replaceSystem(system, newSystem)`

Replaces a system with a new one. Old system's cleanup runs, new system is initialized.

**Returns:** `self` (chainable)

---

#### `getDeltaTime()`

Returns time (seconds) since the system last ran. **Must be called from within a registered system.**

```lua
local dt = scheduler:getDeltaTime()
```

**Returns:** `number`

---

#### `insert(phase_or_pipeline, instance?, event?)`

Registers a Phase or Pipeline with the scheduler.

- Without event: adds to the default group, ordered by insertion.
- With event: adds to the event's group, runs when that event fires.

```lua
scheduler:insert(myPhase)
scheduler:insert(myPhase, RunService, "Heartbeat")
scheduler:insert(myPipeline, RunService, "Heartbeat")
```

**Returns:** `self` (chainable)

---

#### `insertAfter(phase_or_pipeline, after)`

Orders a Phase/Pipeline to run after another. The dependent inherits the event group of the dependency.

```lua
scheduler:insertAfter(phaseB, phaseA)
```

**Returns:** `self` (chainable)

---

#### `insertBefore(phase_or_pipeline, before)`

Orders a Phase/Pipeline to run before another.

```lua
scheduler:insertBefore(phaseB, phaseA)
```

**Returns:** `self` (chainable)

---

#### `addRunCondition(target, condition)`

Adds a Run Condition to a System, Phase, or Pipeline. If any condition returns falsy, execution is skipped.

```lua
scheduler:addRunCondition(mySystem, timePassed(10))
scheduler:addRunCondition(myPhase, someCondition)
scheduler:addRunCondition(myPipeline, anotherCondition)
```

**Returns:** `self` (chainable)

---

#### `run(target)`

Runs a specific Phase, Pipeline, or System.

```lua
scheduler:run(myPhase)
scheduler:run(myPipeline)
scheduler:run(mySystem)
```

**Returns:** `self` (chainable)

---

#### `runAll()`

Runs all systems in order. Default group first, then each event group in creation order.

**Returns:** `self` (chainable)

---

#### `cleanup()`

Disconnects all events, closes threads, performs full cleanup. **Only use when discarding the scheduler entirely.**

---

### Properties

#### `Hooks`

Table of hook identifiers for use with `addHook`.

| Key               | Context Type           |
| ----------------- | ---------------------- |
| `SystemAdd`       | `SystemHookContext`    |
| `SystemRemove`    | `SystemHookContext`    |
| `SystemReplace`   | `SystemReplaceContext` |
| `SystemEdited`    | `SystemEditedContext`  |
| `SystemCleanup`   | `SystemErrorContext`   |
| `SystemError`     | `SystemErrorContext`   |
| `SystemTriedRun`  | `SystemHookContext`    |
| `OuterSystemCall` | `SystemCallContext`    |
| `InnerSystemCall` | `SystemCallContext`    |
| `SystemCall`      | `SystemCallContext`    |
| `PhaseAdd`        | `PhaseContext`         |
| `PhaseBegan`      | `PhaseContext`         |

---

## Types

### `SystemFn<T>`

```ts
type SystemFn<T extends unknown[]> = (...args: T) => void | undefined;
```

### `InitializerSystemFn<T>`

```ts
type InitializerSystemFn<T extends unknown[]> = (
  ...args: T
) => InitializerResult<T> | LuaTuple<[SystemFn<T>, CleanupFn<T>]> | SystemFn<T>;
```

### `SystemTable<T>`

```ts
interface SystemTable<T extends unknown[]> {
  name?: string;
  system: InitializerSystemFn<T> | SystemFn<T>;
  phase?: Phase;
  runConditions?: Condition<T>[];
}
```

### `System<T>`

```ts
type System<T extends unknown[]> =
  | InitializerSystemFn<T>
  | SystemFn<T>
  | SystemTable<T>;
```

### `SystemInfo<T>`

Internal metadata about a registered system:

| Field         | Type       | Description                           |
| ------------- | ---------- | ------------------------------------- |
| `system`      | `System`   | Original system                       |
| `run`         | `Function` | Current callable (may change on init) |
| `cleanup?`    | `Function` | Cleanup function                      |
| `initialized` | `boolean`  | Whether init has run                  |
| `name`        | `string`   | System name (from table or inferred)  |
| `deltaTime?`  | `number`   | Time since last run                   |
| `lastTime?`   | `number`   | Timestamp of last run                 |
| `logs`        | `array`    | Accumulated errors/warnings           |
| `phase`       | `Phase`    | Assigned phase                        |
