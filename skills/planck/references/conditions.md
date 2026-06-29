# Run Conditions Reference

## Overview

Run Conditions are predicate functions that gate execution of Systems, Phases, or Pipelines. If **any** condition returns a falsy value (`nil`, `false`, `void`), execution is skipped.

```lua
scheduler:addRunCondition(target, conditionFn)
```

Multiple conditions can be added to the same target. **All** must pass for execution.

---

## Built-in Conditions

### `timePassed(time)`

Throttle — only allows execution after `time` seconds have elapsed since last successful run.

```lua
local timePassed = Planck.timePassed

scheduler:addRunCondition(mySystem, timePassed(10)) -- every 10 seconds
```

```ts
import { timePassed } from "@rbxts/planck";

scheduler.addRunCondition(mySystem, timePassed(10));
```

**Behavior:**

- Tracks elapsed time internally.
- Returns `true` when the interval has passed, resets timer.
- Returns `false` otherwise (system is skipped, timer continues counting).
- The system still runs on the same event (e.g., `Heartbeat`); only the condition check happens each frame.

---

### `runOnce()`

Only allows execution on the first call. Skips all subsequent runs.

```lua
local runOnce = Planck.runOnce

scheduler:addRunCondition(mySystem, runOnce())
```

```ts
import { runOnce } from "@rbxts/planck";

scheduler.addRunCondition(mySystem, runOnce());
```

**Behavior:**

- First call: returns `true`, sets internal flag.
- All subsequent calls: returns `false`.

Useful for recreating startup-like behavior without using built-in Startup phases.

---

### `onEvent(signal, event?)`

Checks for new events since last frame. Returns a tuple of `[hasNewEvent, collectEvents, getDisconnectFn]`.

```lua
local onEvent = Planck.onEvent

local hasNewPlayer, collectPlayers = onEvent(Players.PlayerAdded)

local function playerJoinSystem()
    for i, player in collectPlayers() do
        print("New player:", player.Name)
    end
end

scheduler
    :addSystem(playerJoinSystem)
    :addRunCondition(playerJoinSystem, hasNewPlayer)
```

```ts
import { onEvent } from "@rbxts/planck";

const [hasNewPlayer, collectPlayers] = onEvent(Players.PlayerAdded);

function playerJoinSystem() {
  for (const [i, player] of collectPlayers()) {
    print("New player:", player.Name);
  }
}

scheduler
  .addSystem(playerJoinSystem)
  .addRunCondition(playerJoinSystem, hasNewPlayer);
```

**Return values:**

| Name            | Type                     | Description                                         |
| --------------- | ------------------------ | --------------------------------------------------- |
| `hasNewEvent`   | `() -> boolean`          | Run Condition — `true` if new events                |
| `collectEvents` | `() -> IterableFunction` | Iterator over queued events                         |
| `getDisconnect` | `() -> () -> ()`         | Returns a function to disconnect the event listener |

**Supported event sources:**

| Form                              | Example                                          |
| --------------------------------- | ------------------------------------------------ |
| `RBXScriptSignal`                 | `onEvent(Players.PlayerAdded)`                   |
| `Instance` + `RBXScriptSignal`    | `onEvent(RunService, RunService.Heartbeat)`      |
| `Instance` + `string`             | `onEvent(RunService, "Heartbeat")`               |
| Signal-like `{ connect(fn) }`     | `onEvent(myCustomSignal)`                        |
| Table + `string` (connect method) | `onEvent(emitter, "onUpdate")`                   |
| Connectable function              | `onEvent(function(cb) return myConnect(cb) end)` |

**Important:** `hasNewEvent` clears the queue on frames with no events. Always call `collectEvents()` inside the system to process events. If you don't call it, events are lost.

---

### `isNot(condition)`

Inverts a condition. Returns `true` when the wrapped condition returns falsy, and vice versa.

```lua
local isNot = Planck.isNot

scheduler:addRunCondition(mySystem, isNot(timePassed(5)))
-- This system runs ONLY when less than 5 seconds have passed
```

```ts
import { isNot } from "@rbxts/planck";

scheduler.addRunCondition(mySystem, isNot(timePassed(5)));
```

---

## Custom Conditions

Any function that returns a truthy/falsy value can be used as a condition.

```lua
local function onlyOnWeekdays(world)
    local day = os.date("*t").wday
    return day >= 2 and day <= 6 -- Mon-Fri
end

scheduler:addRunCondition(mySystem, onlyOnWeekdays)
```

```ts
function onlyOnWeekdays(world: World): boolean {
  const day = new Date().getDay();
  return day >= 1 && day <= 5; // Mon-Fri
}

scheduler.addRunCondition(mySystem, onlyOnWeekdays);
```

### Stateful Conditions

Use closures to maintain state:

```lua
local function maxRuns(limit)
    local count = 0
    return function()
        count += 1
        return count <= limit
    end
end

scheduler:addRunCondition(mySystem, maxRuns(100))
```

---

## Condition Cleanup

The `onEvent` condition manages a connection internally. To disconnect it:

```lua
local hasNewEvent, collectEvents, getDisconnect = onEvent(mySignal)
local disconnect = getDisconnect()
disconnect() -- cleans up the connection
```

Planck also tracks condition cleanup via `cleanupCondition()` internally for plugin use.

---

## Combining Conditions

```lua
-- Run every 5 seconds, but only when a new player has joined
scheduler
    :addRunCondition(system, timePassed(5))
    :addRunCondition(system, hasNewPlayer)
```

Multiple conditions are AND'd — all must return truthy.

For OR logic, compose them into a single condition:

```lua
local function either(condA, condB)
    return function(...)
        return condA(...) or condB(...)
    end
end

scheduler:addRunCondition(system, either(timePassed(5), hasNewPlayer))
```
