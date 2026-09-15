# Runtime and target integration

This document is for compiler, runtime, and target-adapter contributors. Most
application developers only need the main [embedded.mod guide](../README.md)
and the README belonging to their target.

## Ownership boundary

`embedded.mod` owns the target-neutral compact runtime ABI and the public
`Embedded.*` contracts. A target repository owns SDK startup, task/core policy,
panic handling, managed-arena placement, and the native implementation behind
the shared hardware and system interfaces.

The public native interfaces are under
`runtime.mod/native/include/blitzmax`. A target adapter should implement only
the contracts it advertises and should report unsupported optional operations
explicitly.

## Managed arena and precise roots

The compact runtime manages objects, arrays, strings, enums, and reusable heap
blocks within a target-provided arena. Compiler-generated root frames describe
live managed values precisely; native code which retains a managed Object past
the call boundary must use `ObjectRootRetain()` and `ObjectRootRelease()`.

The collector tracks live and unreachable allocations, queues finalizers, and
returns reusable blocks to the arena. `HeapIntegrityValid()` audits the
physical block chain, free list, flags, bounds, alignment, and live-allocation
metrics without changing heap state.

Managed Object, Array, and String allocation performs automatic collection and
one retry. If that retry fails, the runtime throws a static String identifying
the allocation kind, so reporting failure does not itself require heap memory.
Raw `MemAlloc()` is outside that guarantee and returns `Null` on exhaustion.

## Objects and dispatch

Compact type descriptors preserve the language-level behaviour expected by
BlitzMax code:

- virtual and interface dispatch, including methods which return callable
  values;
- direct `Super` calls through base descriptors;
- generated hooks for `ToString`, `Compare`, `HashCode`, `Equals`, and
  `SendMessage`; and
- concrete type-name fallback when formatting an uncaught Object fails.

An adapter should not introduce target-owned alternatives to those layouts or
hooks. Compiler, runtime, and target changes which alter a descriptor must land
as a coordinated ABI change.

## Exceptions, finalizers, and panic handling

Allocation failures and ordinary language exceptions use the compact exception
frames generated for embedded code. An uncaught String is reported as bounded
UTF-8 without allocating. An uncaught Object uses its generated `ToString`
hook, with the concrete type name as the final fallback.

The target panic handler receives the resulting message and owns the final
policy: printing, halting, restarting, or handing control to a debugger. The
shared runtime does not maintain a separate debug stack.

If an exception escapes a finalizer, collection discards its pending-finalizer
queue and returns to an idle state. A finalizer which was already entered is
still at-most-once; untouched finalizers become eligible again during a later
collection.

## Native callback boundary

Interrupt handlers, radio callbacks, timers, and SDK worker tasks must not call
arbitrary BlitzMax code or allocate managed values. Their adapter should copy
bounded native data into a queue and signal the shared deferred-event system.
`PollSystem()` and `WaitSystem()` drain that queue later in the managed owner
context.

Adapters should define queue capacity, report dropped records, validate source
generation tokens, and make shutdown invalidate outstanding native callbacks.
The application-visible ordering and persistence semantics belong in the
portable module contract, not in SDK-specific application code.

## Adding or changing a portable adapter

For a new target or a new shared module:

1. Define only the behaviour that can be made meaningfully equivalent across
   targets. Keep richer native capabilities in the target namespace.
2. Implement the corresponding `bmx_embedded_*` interface in each participating
   target repository.
3. Expose capability queries or explicit unavailable results for optional
   hardware; do not silently approximate an unsupported operation.
4. Keep interrupt and SDK callback work on the native side of the deferred
   event boundary.
5. Add or extend a program in `tests` which checks the shared semantics.
6. Build and run the conformance program on every affected architecture and on
   representative hardware for each target family.
7. Compare release size and runtime behaviour when refactoring an existing
   adapter, particularly around roots, finalizers, and allocation failure.

Target-specific tests remain useful for capabilities which intentionally sit
outside `Embedded.*`; they do not replace the shared conformance programs.
