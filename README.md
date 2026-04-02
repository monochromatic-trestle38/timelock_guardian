# timelock_guardian

On-chain timelock for critical contract operations on Gno.land.

## Problem

When a contract admin executes a critical action — changing parameters, upgrading logic, moving treasury funds — it takes effect immediately. There is no window for anyone to review the change, raise objections, or exit the system before the damage is done.

This is how rug pulls work. This is how governance bypasses happen. This is how honest mistakes become irreversible.

The core issue: immediate execution of sensitive operations in systems that require trust.

## Solution

`timelock_guardian` introduces a mandatory delay between scheduling an action and executing it. Every critical operation goes through three steps:

1. **Schedule** — declare what you intend to do, with a minimum delay
2. **Wait** — the action is publicly visible but locked for the delay period
3. **Execute** — after the delay, anyone can trigger the action

During the waiting period, the community can review the scheduled action. If it's malicious or wrong, the creator can cancel it — or governance can respond.

```
Schedule(cross, "treasury", "transfer 1000000ugnot to g1abc...", 86400)
// locked for 24 hours, publicly visible
// after 24h: Execute(cross, "action_1")
```

## Why this matters

- **DAOs** can enforce cooling periods on treasury operations
- **Protocol teams** can prove they won't rug — scheduled upgrades are visible before they happen
- **Users** get exit time when they see a pending action they disagree with
- **Multisigs** can add timelocks on top of approval workflows
- **Auditors** can verify that all sensitive operations go through a delay

Timelocks are the simplest trust-minimization primitive. They don't prevent bad actions — they prevent *surprise* bad actions.

## How it works

Actions are stored with a `ScheduleAt` timestamp and an `ExecuteAfter` deadline. The realm uses `time.Now()` to enforce the delay at execution time.

**Anyone can execute** a ready action. The timelock is the protection mechanism, not the executor's identity. This prevents a single point of failure where only the creator can trigger execution.

**Only the creator can cancel.** This prevents griefing where someone cancels another user's scheduled action.

**Execution is one-shot.** Once executed, an action is permanently marked and cannot be replayed.

## Usage

### Schedule an action (24-hour delay)

```
Schedule(cross, "treasury", "transfer 500000ugnot to g1grant_recipient...", 86400)
// returns: "action_1"
```

### Check pending actions

```
GetPending()
// returns: "action_1, action_3"
```

### Check if ready

```
IsReady("action_1")
// returns: true (after delay has passed)
```

### Execute

```
Execute(cross, "action_1")
// returns: "executed: action_1"
// panics if delay hasn't elapsed
```

### Cancel (creator only)

```
Cancel(cross, "action_1")
// returns: "cancelled: action_1"
```

### Inspect a specific action

```
GetAction("action_1")
// ID: action_1
// Creator: g1admin...
// Target: treasury
// Data: transfer 500000ugnot to g1grant_recipient...
// Scheduled: 2025-01-15T10:00:00Z
// Execute after: 2025-01-16T10:00:00Z
// Status: ready
```

## Integrating from another realm

```go
import "gno.land/r/timelock_guardian"

func ProposeUpgrade(cross realm, newCodeHash string) string {
    // Schedule the upgrade with a 48-hour delay
    return timelock_guardian.Schedule(
        cross,
        "gno.land/r/my_protocol",
        "upgrade to " + newCodeHash,
        172800, // 48 hours
    )
}

func ExecuteUpgrade(cross realm, actionID string) {
    timelock_guardian.Execute(cross, actionID)
    // proceed with actual upgrade logic
}
```

## API

| Function | Access | Description |
|----------|--------|-------------|
| `Schedule(cross, target, data, delay)` | Anyone | Create a timelocked action. Caller is creator. |
| `Execute(cross, actionID)` | Anyone | Execute after delay. Panics if too early. |
| `Cancel(cross, actionID)` | Creator | Cancel a pending action. |
| `GetAction(actionID)` | Anyone | Full details of an action. |
| `GetPending()` | Anyone | List all pending action IDs. |
| `IsReady(actionID)` | Anyone | Check if delay has elapsed. |
| `Render(path)` | Anyone | Markdown overview of all actions by status. |

## Query on Gno.land

```
gnokey query vm/qeval --data 'gno.land/r/timelock_guardian.GetPending()' --remote <rpc>
gnokey query vm/qeval --data 'gno.land/r/timelock_guardian.IsReady("action_1")' --remote <rpc>
gnokey query vm/qeval --data 'gno.land/r/timelock_guardian.GetAction("action_1")' --remote <rpc>
```

Visit `/r/timelock_guardian` on any Gno.land node to see all pending, executed, and cancelled actions.

---
