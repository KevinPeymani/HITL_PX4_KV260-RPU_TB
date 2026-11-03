# Tutoring Plan — OS, RTOS and the NuttX-on-KV260 Port

Sep 24, 2026 · @Kevin

## How this works

Eleven modules, about 51 lessons of 45–60 minutes, taught just ahead of the porting phase that needs them. Every concept named in the [NuttX on Kria KV260 RPU — Porting Plan](https://claude.ai/code/artifact/8572f9d2-ae28-481e-a5ab-16c56c2998bd) appears in a module and in the concept index at the end.

**Built around your background.** You come from software and know computer architecture: ISAs, pipelines, caches, the memory hierarchy, virtual memory. Lessons explain OS ideas through software you already use (threads, coroutines, event loops, interfaces, tail latency) and lean on your architecture knowledge for the CPU side. The hardware side — peripheral registers, clocks, resets, interrupt lines, reading a technical reference manual — is taught from zero, starting in M0.L4.

**Tutoring rules.** I explain, you predict, the hardware or the source code decides. I will not write your port for you; exercises are yours, and I review them. Every claim I make about a register or a NuttX function, you check against UG1085 (behavior), UG1087 (register bit tables), the Arm ARM or the NuttX source at least once per lesson.

**Sourcing rule.** Every explanation names where it comes from: the document and chapter or section, or for code, the file path in the NuttX, PX4 or Linux tree. Quotes are short (a phrase or one sentence) and marked as quotes; everything else is paraphrase with a pointer, so you can read the original. Primary sources come first: standards, Arm and AMD manuals, specifications and source code. Textbooks and papers are used for concepts and history. When I am working from memory, or a section number is not confirmed against the linked edition, I say "verify", and the claim goes on your source-check list. Sources for each module are listed under the module and collected in the reference library below.

**Session format**

1. Recall (5 min): three questions on the previous lesson.
2. Concept (20 min): explanation, one diagram, the hardware analogy and where it breaks.
3. Predict-then-verify (20 min): you predict what code, a register or a debugger will show; then run it.
4. Check (5 min): the lesson's self-check questions; you tick it in the tracker only if you can answer them without notes.

**How to start a lesson.** Open a new chat, paste this doc's link, and say e.g. "Teach M2.L3". Ask for a quiz or flashcards at any time. Say "go deeper" or "too basic" freely; the plan adapts.

**Schedule against the port**

| Before porting phase | Modules | Lessons | Approx. weeks (part-time) |
| --- | --- | --- | --- |
| Setup (§2) and Phase 1 (§3) | M0, M1, M2 | 14 | 3 |
| Phase 1 trace + Phase 2 (§3–§4) | M3, M4, M6 (L1–L3) | 13 | 3 |
| Phase 3 scaffold (§5) | M5, M6 (L4–L6) | 8 | 2 |
| Phase 4 QEMU (§6) | M9 | 4 | 1, then ongoing |
| Phase 5 hardware (§7) | M7 | 4 | 1 |
| Phase 6 RPMsg + PX4 (§8) | M8, M10 | 8 | 2 |

## Reference library

Keys used in each module's **Sources** line. Section and chapter numbers refer to the linked editions; confirm them when you open a document, since vendor manuals are revised.

| Key | Source | Used for |
| --- | --- | --- |
| C11 | ISO/IEC 9899:2011 (C11), final public draft [N1570](https://www.open-std.org/jtc1/sc22/wg14/www/docs/n1570.pdf) | `volatile`, linkage, storage duration, `inline`, bit fields, shifts |
| GCC | [GCC manual](https://gcc.gnu.org/onlinedocs/gcc/): "Optimize Options", "Volatiles", "ARM Options", "Inline" | What the compiler may do, R5 flags |
| BINUTILS | [GNU ld manual](https://sourceware.org/binutils/docs/ld/) and [binutils manual](https://sourceware.org/binutils/docs/binutils/) (`nm`, `objdump`, `readelf`) | Linker scripts, inspecting objects |
| AAPCS | Arm [AAPCS32 and AAELF32](https://github.com/ARM-software/abi-aa) (Arm ABI for the Arm Architecture) | Calling convention, bit-field layout, float ABI, ELF for Arm |
| ARMARM | Arm Architecture Reference Manual ARMv7-A and ARMv7-R edition, [DDI 0406C](https://developer.arm.com/documentation/ddi0406/latest) | ISA, modes, exceptions, PMSA (MPU), memory ordering |
| R5TRM | Cortex-R5 Technical Reference Manual, [DDI 0460](https://developer.arm.com/documentation/ddi0460/latest) | R5 caches, TCM, MPU regions, FPU, reset state |
| BARRIERS | Arm, *Barrier Litmus Tests and Cookbook* (GENC007826) | `dmb`/`dsb`/`isb` patterns |
| GIC | Arm GIC Architecture Specification v1.0 and v2.0, [IHI 0048B](https://developer.arm.com/documentation/ihi0048/latest); PrimeCell GIC PL390 TRM (DDI 0416) | RPU interrupt controller (PL390, GICv1) |
| UG1085 | AMD, *Zynq UltraScale+ Device Technical Reference Manual*, [UG1085](https://docs.amd.com/r/en-US/ug1085-zynq-ultrascale-trm) | How each block behaves: RPU, interrupts, UART, TTC, boot, clocks, resets |
| UG1087 | AMD, *Zynq UltraScale+ Devices Register Reference*, UG1087 | Per-register bit tables, access types, reset values |
| UG1137 | AMD, *Zynq UltraScale+ MPSoC Software Developer Guide*, UG1137 | Boot chain, RPU software flow |
| UG1186 | AMD, *Libmetal and OpenAMP User Guide*, UG1186 | OpenAMP on ZynqMP, `echo_test` |
| UG1169 | AMD, *Xilinx Quick Emulator (QEMU) User Guide*, UG1169 | Xilinx QEMU machines |
| UG1400 | AMD, *Vitis Unified Software Platform: Embedded Software Development*, UG1400 (XSDB chapter) | JTAG, `xsdb` |
| XSW | AMD [embeddedsw](https://github.com/Xilinx/embeddedsw) repo (`xuartps_hw.h`, `xttcps_hw.h`, `xil_mpu.c`) | Cross-checking register definitions |
| NXDOC | [Apache NuttX documentation](https://nuttx.apache.org/docs/latest/) | Configuration, NSH, `ostest`, contributing, coding standard |
| NXSRC | [Apache NuttX source](https://github.com/apache/nuttx) and [nuttx-apps](https://github.com/apache/nuttx-apps) | Every NuttX function or struct named in a lesson |
| OSTEP | Arpaci-Dusseau and Arpaci-Dusseau, [*Operating Systems: Three Easy Pieces*](https://pages.cs.wisc.edu/~remzi/OSTEP/) (free online) | Processes, context switch, scheduling, concurrency |
| POSIX | The Open Group, [Base Specifications (POSIX.1)](https://pubs.opengroup.org/onlinepubs/9799919799/) | `pthread_*`, `sched_*`, semaphores |
| LL73 | Liu and Layland, "Scheduling Algorithms for Multiprogramming in a Hard-Real-Time Environment", *Journal of the ACM* 20(1), 1973 | Rate-monotonic scheduling |
| SRL90 | Sha, Rajkumar and Lehoczky, "Priority Inheritance Protocols: An Approach to Real-Time Synchronization", *IEEE Transactions on Computers* 39(9), 1990 | Priority inversion and inheritance |
| BUTTAZZO | Buttazzo, *Hard Real-Time Computing Systems*, Springer | Real-time theory, WCET, schedulability |
| PATHFINDER | Mike Jones, "What really happened on Mars?" (1997), including Glenn Reeves' (JPL) account | The Pathfinder priority-inversion case |
| LEVINE | Levine, *Linkers and Loaders*, Morgan Kaufmann, 2000 | Sections, relocation, loading |
| DTSPEC | [Devicetree Specification](https://www.devicetree.org/specifications/) | Device tree syntax and semantics |
| KERNEL | Linux kernel docs: [remoteproc](https://docs.kernel.org/staging/remoteproc.html), [rpmsg](https://docs.kernel.org/staging/rpmsg.html); bindings `Documentation/devicetree/bindings/remoteproc/xlnx,zynqmp-r5fss.yaml` and `reserved-memory/` | Linux side of the RPU |
| VIRTIO | OASIS, [Virtual I/O Device (VIRTIO) Version 1.2](https://docs.oasis-open.org/virtio/virtio/v1.2/virtio-v1.2.html), "Split Virtqueues" | vring layout and ownership |
| OPENAMP | [OpenAMP documentation](https://openamp.readthedocs.io/) and [open-amp](https://github.com/OpenAMP/open-amp) source | RPMsg, virtqueues, remoteproc from the remote side |
| QEMU | [QEMU documentation](https://www.qemu.org/docs/master/) | GDB stub, machine models |
| GDB | [GDB manual](https://sourceware.org/gdb/current/onlinedocs/gdb/) | Remote debugging, watchpoints |
| PX4 | [PX4 User Guide](https://docs.px4.io/main/en/) (architecture, uORB, "Flight Controller Porting Guide") and [PX4-Autopilot](https://github.com/PX4/PX4-Autopilot) source | PX4 structure and porting |

## M0 — Baseline and hardware for software engineers (4 lessons)

Three diagnostic lessons to find what to skip, then one lesson that gives you the hardware vocabulary the rest of the plan assumes. After M0 I adjust the depth of later modules.

| Lesson | Topic | You do | Pass when you can |
| --- | --- | --- | --- |
| M0.L1 | C for systems code: `volatile`, pointer casts to fixed addresses, bit fields vs masks, `static`, function pointers, structs of function pointers (the driver-ops pattern) | Write a `REG32(addr)` macro and a read-modify-write helper; explain what the compiler may do without `volatile` | Say why `uart_dev_s` in NuttX is a struct of function pointers |
| M0.L2 | Memory as a bare-metal program sees it: one physical address space, stack vs heap vs static data, alignment, endianness, no loader and no OS to set anything up for you | Compile a small C file for `arm-none-eabi`, run `arm-none-eabi-nm` and `-objdump -h`, find each variable's section | Name which of `.text`, `.data`, `.bss`, `.rodata`, stack, heap each variable lands in, and why `.data` needs copying at boot |
| M0.L3 | Reading ARM assembly: registers r0–r15, `ldr`/`str`, `mov`, `bl`, `bx lr`, `push`/`pop`, AAPCS calling convention (fast if your architecture courses used another RISC ISA) | Disassemble your L2 file, annotate one function line by line | Follow a function call and return in assembly and say which registers a callee must preserve |
| M0.L4 | What a peripheral looks like to software: memory-mapped registers, register maps in a TRM, reset values, read-only / write-only fields, side effects (clear-on-read status, write-1-to-clear bits), clocks (no clock, no peripheral), resets (held in reset, registers unreachable), interrupt lines as the device raising a flag to the CPU | Read three UART registers in UG1087 (bit tables), with UG1085's UART chapter for behavior; for each, say what a read does, what a write does, and what the reset value means | Explain why reading a status register twice can return different values with no code running in between |

**Sources.** L1: C11 §5.1.2.3 (program execution, observable behavior), §6.7.3 (`volatile`), §6.7.2.1 (bit fields), §6.5.7 (shifts), §6.2.2 and §6.2.4 (linkage, storage duration), §6.7.4 (`inline`); GCC "Volatiles"; AAPCS32 (bit-field layout); NXSRC `include/nuttx/serial/serial.h`. L2: BINUTILS (`nm`, `objdump`); LEVINE ch. 3 (verify). L3: ARMARM Part A (instruction set); AAPCS32 (core registers, subroutine calls). L4: UG1085 UART chapter; UG1087 UART registers; XSW `xuartps_hw.h`.

**From computer architecture, carry over:** the fetch-execute model, registers, caches and memory ordering, physical vs virtual addresses. **New for you:** the device side of the bus, where a store can start a transmission and a load can clear a flag. M5 builds directly on M0.L4.

## M1 — Operating system fundamentals (5 lessons)

The one idea underneath everything: an OS is code that saves one computation's CPU registers, restores another's, and decides when to do it. Master that and the rest of the port is detail.

| Lesson | Topic | Key concepts | Exercise |
| --- | --- | --- | --- |
| M1.L1 | What an OS is for | Kernel, application, abstraction over hardware, why bare-metal super-loops stop scaling, monolithic vs microkernel vs NuttX's flat model | List what your bare-metal code would need to add to run two independent control loops at different rates |
| M1.L2 | Tasks and threads | Task, thread, task control block (TCB), stack per task, task states (ready, running, blocked, suspended), POSIX `pthread_create` vs NuttX `task_create` | In the `sim` build, run `ps` in NSH; map each column to a TCB field in `include/nuttx/sched.h` |
| M1.L3 | The context switch | CPU context = registers + status word + stack pointer; saving to the TCB; `up_switch_context`; why each task needs its own stack; FPU context as optional extra state | Step through a context switch in the `sim` build with GDB; watch the stack pointer change task |
| M1.L4 | Scheduling | Scheduler, ready list, preemptive vs cooperative, time slicing, round-robin, idle task, `nx_start` creating the first tasks | Predict the output order of two tasks at equal and at different priorities; run it in `sim` |
| M1.L5 | Memory and system calls | Heap allocator (`mm_malloc`), stack overflow, flat address space vs MMU-protected processes, why NuttX has no user/kernel split in the default "flat" build, syscall concept and `CONFIG_BUILD_PROTECTED` | Trigger a stack overflow in `sim` with `CONFIG_STACK_COLORATION`; read the `ps` stack column |

**Sources.** OSTEP "The Abstraction: The Process", "Limited Direct Execution" (context switch), "Scheduling: Introduction", "Free-Space Management", "Concurrency: An Introduction"; POSIX `pthread_create`; NXDOC OS components; NXSRC `include/nuttx/sched.h`, `sched/init/nx_start.c`, `arch/arm/src/armv7-r/` (context switch), `mm/`.

**Software analogy.** A context switch is `swapcontext()` or a coroutine yield: save the registers and stack pointer, load another set, continue. The difference is that the kernel can force it from an interrupt at any instruction, without the running task's cooperation. That preemption is what makes locking necessary (M2.L4).

**Self-check after M1:** explain, with a whiteboard sketch, what is in a TCB, where a blocked task's registers physically are, and what code runs when no task is ready.

## M2 — Real-time systems (5 lessons)

An RTOS is not a fast OS; it is an OS whose worst-case response time is bounded and known. Every lesson here comes back to that bound.

| Lesson | Topic | Key concepts | Exercise |
| --- | --- | --- | --- |
| M2.L1 | What "real-time" means | Hard vs soft real-time, deadline, jitter, worst-case execution time (WCET), determinism, why a flight controller on an R5 and not the A53s | For a 400 Hz attitude loop, compute the period and budget; list what could make one iteration late |
| M2.L2 | The system tick and time | Tick timer, `CONFIG_USEC_PER_TICK`, `nxsched_process_timer`, timeouts, `usleep`, tickless mode (`CONFIG_SCHED_TICKLESS`) and why you start with a tick | Change the tick rate in `sim`; predict and measure the effect on `usleep(1500)` accuracy |
| M2.L3 | Priority-based preemptive scheduling | Fixed priorities, preemption point, rate-monotonic assignment, `SCHED_FIFO` vs `SCHED_RR`, starvation | Assign priorities to four PX4-like tasks by rate; justify with rate-monotonic reasoning |
| M2.L4 | Synchronization | Critical section, disabling interrupts vs locking, semaphore, mutex, condition variable, message queue, `enter_critical_section` in NuttX, why ISRs may not block | Build a producer/consumer in `sim` with a semaphore, then break it by removing the semaphore and explain the failure |
| M2.L5 | Priority inversion and latency | Priority inversion (Mars Pathfinder), priority inheritance (`CONFIG_PRIORITY_INHERITANCE`), interrupt latency, scheduling latency, critical-section length as the real enemy, `CONFIG_SCHED_CRITMONITOR` | Reproduce priority inversion with three tasks in `sim`; fix it with inheritance; measure with critmonitor |

**Sources.** BUTTAZZO (hard vs soft real-time, WCET, fixed-priority scheduling); LL73 (rate-monotonic); SRL90 (priority inheritance); PATHFINDER; OSTEP "Locks", "Condition Variables", "Semaphores"; POSIX `sched_setscheduler`, `sem_*`; NXDOC on tickless mode and critical-section monitor; NXSRC `sched/sched/`, `sched/semaphore/`.

**Software analogy.** Real-time is a service's p100 latency, not its p50: one garbage-collection pause or one long lock hold sets the worst case. The difference is that a missed deadline here is a failure, not a slow request, so you design to bound the maximum and then measure it (M10).

**Self-check after M2:** explain why disabling interrupts for 200 µs in a UART driver can make a 400 Hz control loop miss deadlines even though interrupts are off less than 10% of the time.

## M3 — Cortex-R5 architecture (6 lessons)

The CPU contract the NuttX armv7-r layer is written against. You know ISAs, pipelines and caches from computer architecture, so this module covers the ARMv7-R specifics, not the theory. **Sources.** ARMARM (DDI 0406C) Part B: system-level programmers' model (modes, banked registers, exceptions), PMSA (MPU), memory ordering and caches (verify chapter numbers); R5TRM chapters on the MPU, TCM, caches and FPU; BARRIERS; UG1085 RPU chapter (split vs lockstep, TCM); AAPCS32 (hard-float ABI); XSW `xil_mpu.c`; NXSRC `arch/arm/src/armv7-r/`.

| Lesson | Topic | Key concepts | Exercise |
| --- | --- | --- | --- |
| M3.L1 | Profiles and the R5's place | A/R/M profiles, why R has an MPU and no MMU, ARMv7-R vs ARMv7-A differences that matter to NuttX (no virtual memory, same exception model), Cortex-R5 vs R5F | Explain why NuttX puts TMS570 (R4F) and the RPU in `armv7-r` but the A53 in `arm64` |
| M3.L2 | Processor modes and banked registers | User, System, IRQ, FIQ, Supervisor (SVC), Abort, Undefined; CPSR/SPSR; banked SP and LR; why `__start` sets a stack per mode | Read `arm_vectors.S` in `armv7-r`; list which mode each vector enters and which stack it uses |
| M3.L3 | Exceptions and the vector table | Reset, undefined, SVC, prefetch abort, data abort, IRQ, FIQ; vector base (`SCTLR.V`, high vs low vectors); exception entry/return (`srsdb`, `rfeia`, `subs pc, lr, #4`) | Trace an IRQ from vector to `arm_doirq` to return, naming every register saved |
| M3.L4 | The MPU | Regions, base, size, attributes (normal/device/strongly-ordered, cacheable, shareable, XN, access permissions), background region, region priority, why device space must be strongly-ordered or device | Write the MPU region table for the TCM-only layout in the porting plan §5; compare with Xilinx `xil_mpu.c` |
| M3.L5 | Caches, TCM and memory ordering | I-cache, D-cache, write-back vs write-through, clean vs invalidate, ATCM/BTCM and why they are uncached and deterministic, `dsb`/`dmb`/`isb`, cache maintenance before sharing a buffer | Predict what Linux reads from a shared DDR buffer the R5 wrote with D-cache on and no clean; explain the fix |
| M3.L6 | FPU, CP15 and lockstep | VFPv3-D16, `CPACR`, `FPEXC.EN`, hard-float ABI and why it forces FPU context saving; CP15 system registers (`SCTLR`, `ACTLR`, MPU regs); split vs lockstep, what the comparator checks, why lockstep doubles TCM | Write the three-instruction sequence that enables the FPU; say what happens to hard-float code if you forget it |

**From computer architecture.** The MPU is page-table permissions without translation: a handful of physical address regions, each with access rights and a memory type, where the highest-numbered matching region wins. Lockstep is dual modular redundancy: both cores execute the same instruction stream and a comparator faults on any mismatch.

**Self-check after M3:** given a PC stuck at 0x10 (data abort vector), list the four registers you read first and what each tells you.

## M4 — From source to running image (4 lessons)

The path from `.c` files to an R5 executing `__start`, and the contract between linker script and startup code that decides whether milestone 1 ever prints.

| Lesson | Topic | Key concepts | Exercise |
| --- | --- | --- | --- |
| M4.L1 | Cross toolchain and flags | Bare-metal `arm-none-eabi` vs Linux-targeting `arm-linux-gnueabihf`, multilibs, `-mcpu=cortex-r5 -mfloat-abi=hard -mfpu=vfpv3-d16`, `-ffunction-sections`, `--gc-sections`, newlib vs NuttX's own libc | Build the same file with soft and hard float; diff the disassembly |
| M4.L2 | ELF files | Sections vs segments, VMA vs LMA (virtual/load address), program headers, symbols, `readelf -l`/`-S`, why remoteproc cares about segments and physical addresses | Run `readelf -l` on a NuttX `sim` or QEMU image; explain every LOAD line |
| M4.L3 | Linker scripts | `MEMORY`, `SECTIONS`, `ENTRY`, `>region AT>region`, `KEEP`, alignment, symbol definitions (`_sbss`, `_ebss`, `_sdata`, `_edata`, `_eronly`), placing a section at a fixed address (`.resource_table`) | Write a minimal TCM-only `.ld` from scratch for a bare-metal R5 blinky; compare with the TMS570 script |
| M4.L4 | Startup code | Reset state of the R5, mode stacks, `.data` copy from LMA to VMA, `.bss` zeroing, MPU and cache enable order, FPU enable, jumping to C, why C cannot run before a stack exists | Write `__start` for your bare-metal blinky in C + inline asm; get it running in Xilinx QEMU and print one character |

**Sources.** GCC "ARM Options"; BINUTILS ld manual (`MEMORY`, `SECTIONS`, output section LMA) and `readelf`; AAELF32 in AAPCS; LEVINE; R5TRM (reset state); UG1169 (Xilinx QEMU); NXSRC `arch/arm/src/armv7-r/` startup and a TMS570 linker script.

**Why a bare-metal detour.** M4.L3–L4 build a standalone R5 program with no OS. It isolates toolchain, linker and QEMU problems from NuttX problems, so porting plan milestone 1 becomes a copy of something you already made work.

**Self-check after M4:** explain why a variable initialized to 5 reads as garbage if `.data` is placed correctly but the copy loop uses `_sdata`/`_edata` from the wrong region.

## M5 — Interrupts, timers and drivers (5 lessons)

The three peripherals the port needs — GIC, TTC, UART — and the driver model NuttX wraps them in. The RPU's interrupt controller is an Arm PL390, which implements GICv1; the APU uses a GIC-400 (GICv2). M5.L1 teaches the GICv1 programming model and notes where GICv2 differs, since NuttX's shared driver is named `arm_gicv2.c`.

**Sources.** GIC (IHI 0048B covers v1 and v2 and marks the differences; DDI 0416 for the PL390); UG1085 interrupts, TTC and UART chapters; UG1087 register tables for the RPU GIC, TTC and UART; XSW `xttcps_hw.h`, `xuartps_hw.h`; NXDOC character and serial drivers; NXSRC `include/nuttx/serial/serial.h`, `drivers/serial/serial.c`, `arch/arm/src/armv7-r/arm_gicv2.c`.

| Lesson | Topic | Key concepts | Exercise |
| --- | --- | --- | --- |
| M5.L1 | Interrupt controllers and the RPU GIC (PL390, GICv1) | Distributor vs CPU interface, SGI/PPI/SPI and the +32 offset, enable/pending/active, priority and priority mask (`GICC_PMR`), IAR read = acknowledge, EOIR write = end, level vs edge, target CPU | Draw the state machine of one SPI (inactive → pending → active → inactive); mark where software reads and writes |
| M5.L2 | Interrupt handling in an OS | ISR vs thread context, `irq_attach`, `irq_dispatch`, why ISRs are short, deferring work (work queues, `nxsem_post` from ISR), nested interrupts, what "interrupts disabled" means for latency (ties to M2.L5) | Read `arm_gicv2.c`'s `arm_decodeirq`; annotate each GIC register access with the M5.L1 state it moves |
| M5.L3 | Timers and the tick | Triple Timer Counter: prescaler, interval mode, match registers, interrupt enable/status (clear-on-read), deriving the reload value from the input clock and `CONFIG_USEC_PER_TICK` | Compute TTC prescaler and interval for a 1 kHz tick from a 100 MHz clock; verify the arithmetic against the register widths |
| M5.L4 | UART hardware and polled output | Cadence PS UART: FIFOs, baud generator and divisor, channel status, TX empty/full, why polled `arm_lowputc` comes first and interrupt-driven serial later | Compute the baud divisors for 115200 from the UART reference clock; write a polled putc for your M4 bare-metal program |
| M5.L5 | The NuttX driver model | Character drivers, `file_operations`, `register_driver`, `/dev` pseudo-filesystem, `uart_dev_s` + `uart_ops_s` (the upper-half/lower-half split), `arm_earlyserialinit` vs `arm_serialinit`, `/dev/console` | Map every function in `zynq_mpsoc/zynq_serial.c` to its slot in `uart_ops_s` |

**Software analogy.** The upper/lower-half split is an interface and its implementations: `uart_ops_s` is a vtable, `drivers/serial/serial.c` is generic code written against it (buffering, termios, blocking reads), and your chip file is one concrete implementation that knows the registers. In this port you write only implementations.

**Self-check after M5:** explain what happens to the whole system if your ISR never writes EOIR, and why the symptom looks like "one interrupt, then silence".

## M6 — NuttX internals (6 lessons)

How NuttX is organized and where your chip and board code plug in. L1–L3 run alongside porting plan Phase 1; L4–L6 alongside the scaffold in Phase 3.

| Lesson | Topic | Key concepts | Exercise |
| --- | --- | --- | --- |
| M6.L1 | Build and configuration | Kconfig, `defconfig`, `.config`, `make menuconfig`, `tools/configure.sh board:config`, `Make.defs`, `Toolchain.defs`, the `nuttx`/`nuttx-apps` split, how `CONFIG_*` becomes `#define` in `include/nuttx/config.h` (like Yocto's `local.conf` → recipe variables, which you know) | Add a Kconfig option to an existing board, use it in C, find it in the generated header |
| M6.L2 | Source tree layout | `sched/`, `mm/`, `fs/`, `drivers/`, `libs/`, `arch/<arch>/src/<core-family>/`, `arch/<arch>/src/<chip>/`, `boards/<arch>/<chip>/<board>/`; what is generic, what is per-core, what is per-chip, what is per-board | Place each file of porting plan §5's tables in the right layer and say why it is not one layer up or down |
| M6.L3 | Boot sequence | `__start` → `nx_start` → `up_initialize` → board hooks → init task (`nsh_main`); idle task; `CONFIG_INIT_ENTRYPOINT`; `board_early_initialize` vs `board_late_initialize` vs `board_app_initialize` | Produce the boot trace from porting plan §3 yourself on TMS570, then compare |
| M6.L4 | The arch interface | Every `up_*` / `arm_*` function in porting plan §3's table: who calls it, when, what state it may assume, what it must leave true; `CURRENT_REGS`; `g_idle_topstack`; `up_allocate_heap` | For each function, write the one-line precondition and postcondition before reading its TMS570 implementation |
| M6.L5 | NSH, syslog and debug facilities | NSH as an ordinary app, `syslog`, `_err`/`_warn`/`_info`, `CONFIG_DEBUG_*` levels and their timing cost, `CONFIG_ARCH_STACKDUMP`, `procfs` (`/proc/<pid>/status`, `/proc/meminfo`), assertions | Force an assertion in `sim`; read the dump; identify the failing task and line |
| M6.L6 | `ostest` and upstream contribution | What `ostest` exercises (semaphores, signals, timers, FPU, priority inheritance) and which failure points to which arch function; NuttX coding standard, `tools/checkpatch.sh`, docs `index.rst`, PR etiquette | Run `ostest` in `sim`; for three tests, name the arch-layer code they depend on |

**Sources.** NXDOC (quickstart, configuring, NSH, `ostest`, debugging, contributing and the coding standard); NXSRC `tools/configure.sh`, `tools/checkpatch.sh`, `sched/init/`, `boards/arm/tms570/`, `apps/testing/ostest/`.

**Self-check after M6:** someone hands you a new ARMv7-R chip; list the directories you create, the files in each, and the first five functions you implement, in order.

## M7 — The ZynqMP SoC and the Linux side (4 lessons)

How the RPU sits inside the MPSoC and how Linux on the APU loads and controls it. Device-tree syntax and PetaLinux kernel configuration may be familiar from earlier Zynq-7000 work; everything about running a second, independent processor is new, and L1–L2 start from the hardware basics of M0.L4.

| Lesson | Topic | Key concepts | Exercise |
| --- | --- | --- | --- |
| M7.L1 | MPSoC architecture | APU (4× A53), RPU (2× R5F), PMU, CSU, full-power vs low-power domain (FPD/LPD), which peripherals live in the LPD and why the RPU owns them well, the two views of TCM (R5-local 0x0 vs APU alias 0xFFE0\_0000), OCM, DDR address map | Draw the address map as the R5 sees it and as the A53 sees it; mark every address from porting plan §4 on both |
| M7.L2 | Boot, clocks and resets | BootROM → PMU firmware → FSBL → ATF → U-Boot → Linux; where the RPU could start in that chain and why the plan starts it later from Linux; `CRL_APB` resets, `RPU_GLBL_CNTL`, clock sources for UART and TTC (`LPD_LSBUS_CLK`), why bricking is a BOOT.bin risk and not a remoteproc risk | On your KV260, read the UART and TTC reference clocks from Linux (`/sys/kernel/debug/clk/clk_summary`) |
| M7.L3 | Device tree for co-processors | `reserved-memory` and `no-map`, `memory-region`, `sram` references to TCM, the `xlnx,zynqmp-r5fss` binding, `xlnx,cluster-mode`, overlays (`.dtso`, `xmutil loadapp`), `status = "disabled"` to keep Linux off a peripheral | Write the porting plan §7 overlay from the binding YAML alone; I review it |
| M7.L4 | remoteproc | Linux remoteproc framework, `xlnx_r5_remoteproc`, `/sys/class/remoteproc/`, how the driver parses ELF segments and the resource table, start/stop lifecycle, crash recovery, what `dmesg` tells you | Load a known-good R5 firmware (AMD's `echo_test` or your M4 bare-metal program) via remoteproc before NuttX exists |

**Sources.** UG1085 system overview, power domains, boot, clocking and reset chapters, RPU chapter (TCM address views); UG1087 (`CRL_APB`, `RPU_GLBL_CNTL`); UG1137 (boot chain, RPU flow); DTSPEC; KERNEL remoteproc doc, `xlnx,zynqmp-r5fss.yaml`, reserved-memory bindings, `drivers/remoteproc/xlnx_r5_remoteproc.c`.

**Why M7.L4's exercise matters.** Getting the load path working with a trivial bare-metal image first means porting plan Phase 5 only has one unknown — NuttX — instead of three.

**Self-check after M7:** explain why the ELF your linker places at 0x0 lands in TCM when the APU loads it, and what goes wrong if a segment's physical address is outside every carve-out.

## M8 — Inter-processor communication (4 lessons)

Linux and NuttX are two independent operating systems on different processors sharing some memory. This module is how they talk safely, from the raw mechanism up to NuttX's `rptun`. Taught before porting plan §8.

| Lesson | Topic | Key concepts | Exercise |
| --- | --- | --- | --- |
| M8.L1 | Shared memory and doorbells | No shared kernel, no shared locks; shared DDR/OCM regions; the R5 is not cache-coherent with the A53s; clean/invalidate discipline (M3.L5); inter-processor interrupts (IPI) as a doorbell; polling vs interrupts | Design a single-producer/single-consumer ring buffer in shared memory; mark every barrier and cache operation on both sides |
| M8.L2 | virtio and vrings | Why a standard transport, virtqueue, descriptor table, available ring, used ring, ownership hand-off, the notify/kick | Read the vring layout in OpenAMP's `virtqueue.h`; draw one message going R5 → Linux step by step |
| M8.L3 | RPMsg and OpenAMP | RPMsg channels, endpoints, addresses, name service announcements; OpenAMP layers (libmetal, remoteproc, virtio, rpmsg); the resource table's vdev entry; Linux side `rpmsg_char`, `/dev/rpmsgN`, `ttyRPMSG` | Run AMD's OpenAMP `echo_test` firmware on the R5 via remoteproc and exchange messages from Linux, before NuttX is involved |
| M8.L4 | NuttX `rptun` and your data contract | `rptun` driver, `rptun_ops_s` (another vtable), what `zynqmp_rptun.c` must provide, `RPMSG_UART`, RPMsg sockets; designing an APU↔R5 contract: framing, versioning, rates, backpressure, what happens when one side restarts | List every `rptun_ops_s` slot and the ZynqMP resource it touches; draft the message schema for sensor-in / actuator-out |

**Sources.** VIRTIO "Split Virtqueues"; OPENAMP docs and `lib/virtio/`, `lib/rpmsg/`; UG1186; KERNEL rpmsg doc; UG1085 IPI chapter; R5TRM and BARRIERS for cache maintenance; NXSRC `drivers/rptun/`, `include/nuttx/rptun/rptun.h`.

**Software analogy.** This is two processes talking through a shared-memory queue with an `eventfd` doorbell, minus the shared kernel: nothing keeps caches coherent or arbitrates access for you, so the protocol has to.

**Self-check after M8:** explain why a message can arrive intact on Linux in QEMU and corrupted on the KV260, and name the two fixes.

## M9 — Debugging embedded and RTOS code (4 lessons)

The debugging you know — a debugger attached to a process, logs, stack traces — mostly works here, but the target has no OS underneath to help, and early on no console at all. Taught before porting plan §6, then used every week after.

| Lesson | Topic | Key concepts | Exercise |
| --- | --- | --- | --- |
| M9.L1 | QEMU as a development target | Machine models, what is emulated faithfully (instructions, GIC, UART registers) and what is not (clocks, timing, caches), Xilinx QEMU `arm-generic-fdt`, GDB stub (`-s -S`), when a QEMU pass means nothing | Run your M4 bare-metal program under Xilinx QEMU with GDB; break at `__start` and step to the first character |
| M9.L2 | GDB on bare metal and on NuttX | Loading symbols, breakpoints vs hardware watchpoints, `info registers` including CPSR, reading peripheral registers with `x/`, NuttX thread awareness (`tools/gdb` Python scripts, `info threads`) | In the NuttX QEMU build, list tasks from GDB and print one task's saved registers from its TCB |
| M9.L3 | JTAG and `xsdb` | What JTAG gives you (halt any core, read/write memory without the CPU's help), `hw_server`, `xsdb` targets, `stop`, `rrd`, `mrd`/`mwr`, `dow`, `con`; attaching GDB through `hw_server` | Halt the R5 running a remoteproc-loaded image; read its PC and one TTC register; resume it |
| M9.L4 | Fault analysis and method | Abort types; decoding DFSR/DFAR and IFSR/IFAR; reading a NuttX assert and stack dump; stack overflow signatures; bisecting with the porting plan's milestones; one hypothesis per experiment | I give you three crash dumps from an R5; you diagnose each and name the one-line fix |

**Sources.** QEMU (GDB stub); UG1169; GDB manual (remote debugging, watchpoints); UG1400 XSDB chapter; ARMARM fault status and address registers (DFSR/DFAR, IFSR/IFAR) for PMSA; NXDOC debugging guides; NXSRC `tools/gdb/`.

**Self-check after M9:** for each hang class in porting plan §9 (no output, output then silence, no tick, garbled console), name the first tool you reach for and the first thing you look at.

## M10 — PX4 on NuttX (4 lessons)

The end goal: PX4 running on your NuttX port on the R5. L1 uses PX4 SITL (software-in-the-loop on your Linux host), so you learn PX4's structure as pure software before any board is involved.

| Lesson | Topic | Key concepts | Exercise |
| --- | --- | --- | --- |
| M10.L1 | PX4 architecture | Modules, uORB publish/subscribe, work queues and `ScheduledWorkItem`, module threads vs work-queue items, how these map onto NuttX tasks and priorities, typical loop rates | Run PX4 SITL; use `uorb top`, `work_queue status` and `top`; trace one sensor topic from driver to attitude controller |
| M10.L2 | PX4 build and board support | PX4's CMake build, `.px4board` configs, PX4's vendored NuttX fork, `boards/<vendor>/<board>/nuttx-config/`, `init/rc.board_*`, how a PX4 board wraps a NuttX board | Build an existing NuttX-based PX4 board (e.g. `px4_fmu-v5_default`); map each of its files to your NuttX board's files |
| M10.L3 | Porting PX4 onto your board | Memory budget and the DDR linker layout (porting plan §5, layout 2); PX4 platform drivers every board must provide — high-resolution timer (`hrt`), board reset, version, and I/O timers if driving outputs; feeding sensors over RPMsg instead of I2C/SPI | List each platform driver PX4 needs, which R5 resource backs it (a second TTC for `hrt`, RPMsg for sensors), and in what order you bring them up |
| M10.L4 | Real-time validation | Latency vs jitter, measuring worst case not average, `CONFIG_SCHED_CRITMONITOR`, PX4 `perf` counters, trace capture over RPMsg, stress tests (load on Linux side, RPMsg floods), writing up results with pass criteria | Write the validation plan for the 400 Hz loop: what you measure, how, for how long, and the numbers that count as pass |

**Sources.** PX4 User Guide (architecture overview, uORB messaging, "Flight Controller Porting Guide", SITL); PX4-Autopilot `platforms/nuttx/`, `boards/px4/fmu-v5/`, `src/drivers/drv_hrt.h`; NXDOC `CONFIG_SCHED_CRITMONITOR`; BUTTAZZO for validation methods.

**Software analogy.** uORB is an in-process pub/sub bus (ROS topics without the network); work queues are a small thread pool per priority level, like executor pools in an async runtime, but with fixed, real-time priorities.

**Self-check after M10:** explain why PX4's `hrt` cannot use the NuttX system tick, and what breaks in the flight stack if `hrt` jitters.

## Concept index

Every concept the porting plan relies on, where it is taught, and where the plan uses it.

| Concept | Taught in | Used in porting plan |
| --- | --- | --- |
| Memory-mapped registers, reset values, clear-on-read | M0.L4 | §4, §5 |
| `volatile`, driver-ops structs | M0.L1 | §5 |
| Sections `.text`/`.data`/`.bss`, stack, heap | M0.L2, M4.L2 | §3, §5 |
| Task, thread, TCB, task states | M1.L2 | §3, §6 |
| Context switch, FPU context | M1.L3, M3.L6 | §6 (M7) |
| Scheduler, idle task, `nx_start` | M1.L4, M6.L3 | §3 |
| Heap, stack overflow, stack coloration | M1.L5, M6.L5 | §5, §6 |
| Determinism, WCET, jitter | M2.L1 | §8 |
| System tick, `USEC_PER_TICK`, tickless | M2.L2, M5.L3 | §3, §6 (M4) |
| Priority preemption, `SCHED_FIFO` | M2.L3 | §8 |
| Critical sections, semaphores, mutexes | M2.L4 | §3, §6 |
| Priority inversion and inheritance, critmonitor | M2.L5 | §8 |
| ARM profiles, ARMv7-R | M3.L1 | §1 |
| Processor modes, banked registers, CPSR | M3.L2 | §5 (`__start`) |
| Exceptions, vector table, abort vectors | M3.L3 | §3, §9 |
| MPU regions and memory types | M3.L4 | §5, §9 |
| Caches, TCM, barriers, cache maintenance | M3.L5 | §5, §7, §9 |
| FPU enable, CP15, lockstep vs split | M3.L6 | §5, §8, §9 |
| Cross toolchain, float ABI | M4.L1 | §2 |
| ELF segments, VMA/LMA | M4.L2 | §7, §9 |
| Linker script, `.resource_table` | M4.L3 | §5, §7 |
| Startup code, `.data` copy, `.bss` zero | M4.L4 | §5, §6 (M1–M2) |
| RPU GIC (PL390, GICv1), SPI numbering, IAR/EOIR, PMR | M5.L1–L2 | §4, §5, §6 (M4), §9 |
| Triple Timer Counter | M5.L3 | §4, §5, §7 |
| Cadence UART, baud divisors, polled putc | M5.L4 | §5, §6 (M1, M5) |
| NuttX driver model, `uart_ops_s`, `/dev/console` | M5.L5 | §5 |
| Kconfig, defconfig, `configure.sh` | M6.L1 | §2, §5 |
| arch/chip/board layers | M6.L2 | §1, §5 |
| NuttX boot sequence and board hooks | M6.L3 | §3 |
| Arch interface (`up_*`, `arm_*`) | M6.L4 | §3, §5 |
| NSH, syslog, assertions, procfs | M6.L5 | §6 |
| `ostest`, upstreaming, checkpatch | M6.L6 | §6 (M7), §7 |
| APU/RPU, power domains, TCM aliases, OCM | M7.L1 | §4, §7 |
| Boot chain, clocks, resets, brick risk | M7.L2 | §7 |
| Reserved memory, r5fss binding, overlays | M7.L3 | §7 |
| Linux remoteproc | M7.L4 | §7 |
| Shared memory, IPI, coherency | M8.L1 | §8, §9 |
| virtio, vrings | M8.L2 | §8 |
| RPMsg, OpenAMP, resource table vdev | M8.L3 | §7, §8 |
| NuttX `rptun`, APU↔R5 data contract | M8.L4 | §8 |
| QEMU, GDB stub | M9.L1–L2 | §6 |
| JTAG, `xsdb` | M9.L3 | §7, §9 |
| Fault decoding, crash dumps | M9.L4 | §9 |
| PX4 modules, uORB, work queues | M10.L1 | §8 |
| PX4 board support, vendored NuttX | M10.L2–L3 | §8 |
| Real-time validation | M10.L4 | §8 |

## Lesson tracker

Tick a lesson only when you can answer its self-check without notes.

Items with a note in parentheses are hands-on checkpoints that de-risk a porting phase before NuttX is involved.

- [ ] M0.L1 C for systems code
- [ ] M0.L2 Memory for bare metal
- [ ] M0.L3 Reading ARM assembly
- [ ] M0.L4 Peripherals for software engineers
- [ ] M1.L1 What an OS is for
- [ ] M1.L2 Tasks and threads
- [ ] M1.L3 The context switch
- [ ] M1.L4 Scheduling
- [ ] M1.L5 Memory and system calls
- [ ] M2.L1 What real-time means
- [ ] M2.L2 The system tick
- [ ] M2.L3 Priority-based preemption
- [ ] M2.L4 Synchronization
- [ ] M2.L5 Priority inversion and latency
- [ ] M3.L1 Profiles and the R5
- [ ] M3.L2 Modes and banked registers
- [ ] M3.L3 Exceptions and vectors
- [ ] M3.L4 The MPU
- [ ] M3.L5 Caches, TCM, ordering
- [ ] M3.L6 FPU, CP15, lockstep
- [ ] M4.L1 Cross toolchain
- [ ] M4.L2 ELF files
- [ ] M4.L3 Linker scripts
- [ ] M4.L4 Startup code (bare-metal R5 prints in QEMU)
- [ ] M5.L1 RPU GIC (GICv1)
- [ ] M5.L2 Interrupts in an OS
- [ ] M5.L3 Timers and the tick
- [ ] M5.L4 UART and polled output
- [ ] M5.L5 NuttX driver model
- [ ] M6.L1 Build and configuration
- [ ] M6.L2 Source tree layout
- [ ] M6.L3 Boot sequence
- [ ] M6.L4 The arch interface
- [ ] M6.L5 NSH and debug facilities
- [ ] M6.L6 ostest and upstreaming
- [ ] M7.L1 MPSoC architecture
- [ ] M7.L2 Boot, clocks, resets
- [ ] M7.L3 Device tree for co-processors
- [ ] M7.L4 remoteproc (bare-metal image loads)
- [ ] M8.L1 Shared memory and doorbells
- [ ] M8.L2 virtio and vrings
- [ ] M8.L3 RPMsg and OpenAMP (echo\_test runs)
- [ ] M8.L4 rptun and the data contract
- [ ] M9.L1 QEMU as a target
- [ ] M9.L2 GDB on bare metal and NuttX
- [ ] M9.L3 JTAG and xsdb
- [ ] M9.L4 Fault analysis
- [ ] M10.L1 PX4 architecture (SITL)
- [ ] M10.L2 PX4 build and board support
- [ ] M10.L3 Porting PX4 onto your board
- [ ] M10.L4 Real-time validation
