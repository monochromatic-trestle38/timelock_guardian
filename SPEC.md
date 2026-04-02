# timelock_guardian — Technical Specification

## Overview

`timelock_guardian` is a Gno realm that enforces mandatory delays on scheduled operations. Actions are created with a minimum waiting period, become publicly visible immediately, and can only execute after the delay has elapsed. This provides a trust-minimization layer for any system that performs sensitive on-chain operations.

## Data Model

### Action

```
type Action struct {
    ID           string
    Creator      std.Address
    Target       string      // realm or contract this applies to
    Data         string      // encoded call data or human-readable description
    ScheduledAt  time.Time   // when the action was created
    ExecuteAfter time.Time   // earliest execution time
    Executed     bool        // one-shot: true after execution
    Cancelled    bool        // true if creator cancelled
}
```

### Storage

```
actions map[string]*Action   // action ID → action
nextID  int                  // monotonic counter for ID generation
```

IDs are formatted as `action_1`, `action_2`, etc. Sequential, predictable, and human-readable.

## Time Model

The realm uses `time.Now()` for all time comparisons. In Gno, `time.Now()` returns the block time — it is deterministic across all nodes processing the same block and cannot be manipulated by the caller.

- `ScheduledAt` = `time.Now()` at creation
- `ExecuteAfter` = `ScheduledAt + delay` (delay in seconds, converted to `time.Duration`)
- Execution check: `time.Now().Before(ExecuteAfter)` must be false

## Authentication

| Operation | Caller requirement |
|-----------|--------------------|
| Schedule | Anyone (caller becomes creator) |
| Execute | **Anyone** — the timelock is the protection |
| Cancel | Must be action creator |

### Why anyone can execute

The delay period is the security mechanism. Restricting execution to the creator would create a single point of failure — if the creator goes offline, ready actions can never execute. By allowing anyone to trigger execution after the delay, the system is permissionless and liveness-preserving.

### Why only creator can cancel

If anyone could cancel, an attacker could grief the system by cancelling all pending actions. Cancel is restricted to the creator to prevent this.

## Invariants

1. **Positive delay**: `Schedule` requires `delay > 0`. Zero-delay timelocks defeat the purpose.
2. **No early execution**: `Execute` panics if `time.Now()` is before `ExecuteAfter`, reporting the remaining seconds.
3. **No double execution**: `Execute` panics if `Executed == true`.
4. **No executing cancelled actions**: `Execute` panics if `Cancelled == true`.
5. **No cancelling executed actions**: `Cancel` panics if `Executed == true`.
6. **No double cancel**: `Cancel` panics if `Cancelled == true`.
7. **Creator-only cancel**: `Cancel` verifies `caller() == a.Creator`.
8. **Monotonic IDs**: `nextID` only increments. IDs are never reused.

## State Transitions

```
                Schedule
                   │
                   ▼
              ┌─────────┐
              │ PENDING  │
              └────┬─────┘
                   │
          ┌────────┴────────┐
          │                 │
      Cancel            (delay elapses)
          │                 │
          ▼                 ▼
    ┌───────────┐     ┌──────────┐
    │ CANCELLED │     │  READY   │
    └───────────┘     └────┬─────┘
                           │
                       Execute
                           │
                           ▼
                     ┌──────────┐
                     │ EXECUTED │
                     └──────────┘
```

All transitions are one-way. There is no path from EXECUTED or CANCELLED back to PENDING.

## Operations

### Schedule

```
validate target (non-empty)
validate data (non-empty)
validate delay (> 0)
id = "action_" + nextID++
actions[id] = &Action{
    Creator:      caller(),
    ScheduledAt:  time.Now(),
    ExecuteAfter: time.Now() + delay seconds,
}
return id
```

### Execute

```
a = mustGet(actionID)
assert !a.Cancelled
assert !a.Executed
assert time.Now() >= a.ExecuteAfter
a.Executed = true
```

Note: the realm does not perform the actual operation described in `Data`. It marks the action as executed. The calling realm is responsible for checking this status and performing the operation. This keeps the timelock generic and composable.

### Cancel

```
a = mustGet(actionID)
assert caller() == a.Creator
assert !a.Executed
assert !a.Cancelled
a.Cancelled = true
```

### GetPending

Linear scan over all actions. Returns IDs where `!Executed && !Cancelled`. At expected scale (tens to hundreds of actions), this is adequate.

### IsReady

```
a = actions[actionID]
return exists && !a.Executed && !a.Cancelled && time.Now() >= a.ExecuteAfter
```

Returns `false` (never panics) for missing or terminal actions.

## Render

Groups actions into three sections: Pending, Executed, Cancelled. Each action is rendered as a bullet with ID, target, truncated data (40 chars), and status. Pending actions that have passed their delay show as **ready** in bold.

Uses `strings.Builder` and `strconv` only. Nil-safe at every level. Never panics.

## Integration Pattern

The timelock realm is a generic scheduling layer. It does not execute application logic directly. Instead, consuming realms follow this pattern:

```
1. Consuming realm calls Schedule() with a description of the intent
2. The action ID is stored or emitted
3. After the delay, anyone calls Execute() to mark it as done
4. The consuming realm checks the action status and performs the actual operation
```

This separation means the timelock realm never needs to understand the semantics of the actions it guards.

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| Execute before delay | Panics with remaining seconds |
| Execute twice | Panics: "already executed" |
| Cancel after execute | Panics: "cannot cancel executed" |
| Cancel by non-creator | Panics: "only the creator can cancel" |
| Schedule with delay=0 | Panics: "delay must be positive" |
| GetPending with no actions | Returns "none" |
| IsReady on cancelled action | Returns false |
| Very long delay (years) | Accepted — no upper bound enforced |
| Render with mixed states | Groups correctly into sections |

## Limitations

- No on-chain execution of the described action. The realm is a scheduling and status layer only.
- No minimum delay enforcement per target. Any positive delay is accepted. Consuming realms should enforce their own minimum delay policies.
- No event emission. Consumers must poll `GetPending()` or `IsReady()`.
- Action data is unstructured. The realm does not parse or validate it.
- No batch operations. Actions are scheduled and executed individually.
