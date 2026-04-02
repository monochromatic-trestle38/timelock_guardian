package timelock_guardian

import (
	"std"
	"strconv"
	"strings"
	"time"
)

// Action represents a scheduled operation that can only execute after
// a mandatory delay period has elapsed.
type Action struct {
	ID           string
	Creator      std.Address
	Target       string // the realm or contract this action applies to
	Data         string // encoded call data or description of the action
	ScheduledAt  time.Time
	ExecuteAfter time.Time
	Executed     bool
	Cancelled    bool
}

var (
	actions map[string]*Action
	nextID  int
)

func init() {
	actions = make(map[string]*Action)
	nextID = 1
}

func caller() std.Address {
	return std.PreviousRealm().Address()
}

func now() time.Time {
	return time.Now()
}

// ---------- write operations ----------

// Schedule creates a new timelocked action. The caller becomes its
// creator. The action cannot be executed until `delay` seconds have
// passed. Returns the action ID.
func Schedule(cross realm, target, data string, delay int64) string {
	if target == "" {
		panic("target must not be empty")
	}
	if data == "" {
		panic("data must not be empty")
	}
	if delay <= 0 {
		panic("delay must be positive")
	}

	id := "action_" + strconv.Itoa(nextID)
	nextID++

	t := now()
	actions[id] = &Action{
		ID:           id,
		Creator:      caller(),
		Target:       target,
		Data:         data,
		ScheduledAt:  t,
		ExecuteAfter: t.Add(time.Duration(delay) * time.Second),
		Executed:     false,
		Cancelled:    false,
	}
	return id
}

// Execute marks an action as executed. Anyone can call this — the
// timelock is the protection, not the executor's identity. The action
// must exist, not be cancelled, not already executed, and the delay
// must have elapsed.
func Execute(cross realm, actionID string) string {
	a := mustGet(actionID)
	if a.Cancelled {
		panic("action is cancelled")
	}
	if a.Executed {
		panic("action already executed")
	}
	if now().Before(a.ExecuteAfter) {
		remaining := a.ExecuteAfter.Sub(now())
		panic("too early: " + strconv.FormatInt(int64(remaining.Seconds()), 10) + "s remaining")
	}

	a.Executed = true
	return "executed: " + actionID
}

// Cancel removes a pending action. Only the original creator can cancel.
// Cannot cancel already-executed actions.
func Cancel(cross realm, actionID string) string {
	a := mustGet(actionID)
	if caller() != a.Creator {
		panic("only the creator can cancel")
	}
	if a.Executed {
		panic("cannot cancel an already-executed action")
	}
	if a.Cancelled {
		panic("action is already cancelled")
	}

	a.Cancelled = true
	return "cancelled: " + actionID
}

// ---------- read-only queries ----------

// GetAction returns a formatted summary of a single action.
func GetAction(actionID string) string {
	a := mustGet(actionID)
	return formatAction(a)
}

// GetPending returns a summary of all pending (non-executed, non-cancelled)
// actions.
func GetPending() string {
	var results []string
	for _, a := range actions {
		if a == nil || a.Executed || a.Cancelled {
			continue
		}
		results = append(results, a.ID)
	}
	if len(results) == 0 {
		return "none"
	}
	return strings.Join(results, ", ")
}

// IsReady returns true if the action exists, is pending, and its delay
// has elapsed.
func IsReady(actionID string) bool {
	a, ok := actions[actionID]
	if !ok || a.Executed || a.Cancelled {
		return false
	}
	return !now().Before(a.ExecuteAfter)
}

// ---------- render ----------

// Render returns a markdown overview. Never panics.
func Render(path string) string {
	if actions == nil || len(actions) == 0 {
		return "# Timelock Guardian\n\nNo actions scheduled.\n"
	}

	var pending []*Action
	var executed []*Action
	var cancelled []*Action

	for _, a := range actions {
		if a == nil {
			continue
		}
		if a.Cancelled {
			cancelled = append(cancelled, a)
		} else if a.Executed {
			executed = append(executed, a)
		} else {
			pending = append(pending, a)
		}
	}

	var b strings.Builder
	b.WriteString("# Timelock Guardian\n\n")

	if len(pending) > 0 {
		b.WriteString("## Pending (" + strconv.Itoa(len(pending)) + ")\n\n")
		for _, a := range pending {
			b.WriteString(renderActionRow(a))
		}
		b.WriteString("\n")
	}

	if len(executed) > 0 {
		b.WriteString("## Executed (" + strconv.Itoa(len(executed)) + ")\n\n")
		for _, a := range executed {
			b.WriteString(renderActionRow(a))
		}
		b.WriteString("\n")
	}

	if len(cancelled) > 0 {
		b.WriteString("## Cancelled (" + strconv.Itoa(len(cancelled)) + ")\n\n")
		for _, a := range cancelled {
			b.WriteString(renderActionRow(a))
		}
		b.WriteString("\n")
	}

	return b.String()
}

// ---------- helpers ----------

func mustGet(id string) *Action {
	a, ok := actions[id]
	if !ok {
		panic("action not found: " + id)
	}
	return a
}

func formatAction(a *Action) string {
	var b strings.Builder
	b.WriteString("ID: " + a.ID + "\n")
	b.WriteString("Creator: " + string(a.Creator) + "\n")
	b.WriteString("Target: " + a.Target + "\n")
	b.WriteString("Data: " + a.Data + "\n")
	b.WriteString("Scheduled: " + a.ScheduledAt.Format(time.RFC3339) + "\n")
	b.WriteString("Execute after: " + a.ExecuteAfter.Format(time.RFC3339) + "\n")

	if a.Cancelled {
		b.WriteString("Status: cancelled\n")
	} else if a.Executed {
		b.WriteString("Status: executed\n")
	} else if now().Before(a.ExecuteAfter) {
		remaining := a.ExecuteAfter.Sub(now())
		b.WriteString("Status: locked (" + strconv.FormatInt(int64(remaining.Seconds()), 10) + "s remaining)\n")
	} else {
		b.WriteString("Status: ready\n")
	}
	return b.String()
}

func renderActionRow(a *Action) string {
	data := a.Data
	if len(data) > 40 {
		data = data[:37] + "..."
	}

	status := "pending"
	if a.Cancelled {
		status = "cancelled"
	} else if a.Executed {
		status = "executed"
	} else if !now().Before(a.ExecuteAfter) {
		status = "**ready**"
	}

	return "- **" + a.ID + "** | target: `" + a.Target + "` | " + data + " | " + status + "\n"
}
