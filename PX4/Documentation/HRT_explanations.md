# HRT on the ZynqMP RPU

What `platforms/nuttx/src/px4/amd/zynqmp_rpu/hrt/hrt.c` does, function by function.

## What the file is for

PX4 needs two things from a timer:

- **A clock:** µs since boot that never wraps (`hrt_abstime`, 64 bits).
- **Scheduled callbacks:** run a function at a given time, once or periodically.

The file builds both on TTC2 counter 1. That counter is NuttX's free-running timebase: it counts at 100 MHz and wraps every 42.9 s. Its Match 1 interrupt (IRQ 75) is the wake-up.

## File-level setup (before the functions)

- **Includes:** they bring in the counter read, the TTC register offsets, the TTC clock rate and the register access macros.
- **`#error`:** it stops the build if Kconfig moves the timebase, because the IRQ number and register addresses below are fixed for TTC2 counter 1.
- **Register macros:** the HRT touches only three registers of counter 1: Match 1, the interrupt status (ISR) and the interrupt enable (IER). NuttX owns the rest.
- **`HRT_INTERVAL_MIN`/`MAX`:** every deadline is 50 µs to 50 ms from now.
- **State:**
  - `callout_queue`: the pending callbacks, sorted by deadline.
  - Two latency samples: the match value last programmed, and the counter value when the interrupt ran.
  - The latency histogram arrays, which PX4's shared code expects.

## Clock

### `hrt_counts()` (internal)

**Purpose:** turn the 32-bit counter into a 64-bit count that never wraps.

- **How:** if the counter reads lower than last time, it has wrapped, so 2³² is added to a 64-bit base.
- **Requirements:** it must run at least once per wrap (42.9 s), and the interrupt guarantees one run every 50 ms. Callers hold the critical section, so the base and the last value change together.

### `hrt_absolute_time()`

**Purpose:** PX4's main clock: µs since boot.

- **How:** it reads the 64-bit count with interrupts off, then divides by counts per µs (100, or 133 in QEMU) after interrupts are back on, to keep the critical section short.

### `hrt_store_absolute_time()`

**Purpose:** write the current time to a shared variable without being interrupted.

- **Why:** a 64-bit store takes two instructions on the R5, and an interrupt between them would leave half a value.

## Setup

### `hrt_init()`

**Purpose:** start the wake-up interrupt. PX4 calls it once at boot.

- **First match:** it programs one 50 ms ahead, since the queue is empty.
- **Stale flags:** it reads ISR first to clear match flags that latched since boot. Match 1 starts at 0 and the counter passes 0 at every wrap.
- **Enabling:** only then does it enable Match 1 in IER, attach the handler and enable IRQ 75. All of this happens with interrupts off, so nothing fires half-configured.

### `hrt_tim_isr()` (interrupt handler)

**Purpose:** wake up at each programmed deadline and do the scheduled work.

- **Status:** it reads the counter (for latency), then reads ISR, which also clears it.
- **On a Match 1 interrupt:** it records the latency, runs the callbacks that are due (`hrt_call_invoke`), and programs the next wake-up (`hrt_call_reschedule`).
- **Floating point:** callbacks can use it here, because the armv7-r interrupt entry saves the FPU registers.

## Scheduling API (used by drivers and modules)

### `hrt_call_after()`, `hrt_call_at()`, `hrt_call_every()`

**Purpose:** schedule a callback: after a delay, at an absolute time, or periodically.

- **How:** each one computes an absolute deadline and passes it to `hrt_call_internal`.

### `hrt_call_internal()` (internal)

**Purpose:** the shared body of those three: (re)schedule one entry safely.

- **How:** with interrupts off, it removes the entry if it's already queued (its deadline isn't 0), fills it in and inserts it in order.

### `hrt_cancel()`

**Purpose:** unschedule a callback.

- **How:** it removes the entry and sets the deadline to 0. It also clears the period, so a periodic call that cancels itself from its own callback isn't re-queued.

### `hrt_called()`

**Purpose:** tell the caller whether a one-shot callback has already run.

- **How:** a deadline of 0 means it ran and isn't queued.

### `hrt_call_init()`

**Purpose:** prepare a new entry before its first use.

- **How:** it zeroes the entry, so "deadline 0" correctly means "not queued".

### `hrt_call_delay()`

**Purpose:** let a periodic callback push back its own next run, from inside the callback.

- **How:** it only moves the deadline; `hrt_call_invoke` re-queues the entry at that time.

## Internals

### `hrt_call_enter()`

**Purpose:** insert an entry in the queue, sorted by deadline.

- **New earliest deadline:** the entry goes first and the match is reprogrammed for it.
- **Otherwise:** it goes after every entry with the same or an earlier deadline, so equal deadlines run in the order they were added.

### `hrt_call_invoke()` (interrupt context)

**Purpose:** run every callback whose deadline has passed.

- **How:** while the first entry is due, it removes it, marks it called (deadline 0) and runs its callback.
- **Periodic calls:** they are re-queued one period after their previous deadline, so they don't drift, unless the callback moved the deadline with `hrt_call_delay()`.

### `hrt_call_reschedule()`

**Purpose:** program Match 1 so the interrupt fires at the next deadline.

- **Choosing the deadline:** it's the first entry's deadline, limited to between 50 µs and 50 ms from now.
- **Why 50 ms at most:** with nothing queued, the interrupt still fires, which keeps the wrap detection in `hrt_counts()` current.
- **Match value:** the deadline in µs times counts per µs, keeping the low 32 bits. That's the counter value at that moment.
- **Why it re-reads the counter:** the match fires only when the counter equals the value exactly, so a value already passed would fire only after the next wrap, 42.9 s later. It reads the counter after writing and tries again if the value is no longer ahead. With interrupts off and a 50 µs margin, that happens only if the core stalls, for example under a debugger.

### `hrt_latency_update()`

**Purpose:** measure how late the interrupt runs compared with the programmed deadline.

- **How:** it converts the gap between the match value and the counter at interrupt entry to µs, and counts it in the histogram. Anything over 1000 µs goes in the last counter.
