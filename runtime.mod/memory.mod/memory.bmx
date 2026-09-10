' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Compact heap, precise Object collection, and allocation metrics for embedded targets.
End Rem
Module Embedded.Runtime.Memory
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Extern "C"
	Function ArenaAllocate:Byte Ptr(bytes:UInt) = "bmx_embedded_arena_allocate"
	Function ArenaCapacity:UInt() = "bmx_embedded_arena_capacity"
	Function ArenaUsed:UInt() = "bmx_embedded_arena_used"
	Function ArenaRemaining:UInt() = "bmx_embedded_arena_remaining"
	Function ArenaHighWater:UInt() = "bmx_embedded_arena_high_water"
	Function ArenaAllocationCount:UInt() = "bmx_embedded_arena_allocation_count"
	Function ArenaFailureCount:UInt() = "bmx_embedded_arena_failure_count"
	Function ArrayFailureCount:UInt() = "bmx_embedded_array_failure_count"
	Function ArrayAllocationCount:UInt() = "bmx_embedded_array_allocation_count"
	Function ArrayAllocatedBytes:UInt() = "bmx_embedded_array_allocated_bytes"
	Function ArrayLiveCount:UInt() = "bmx_embedded_array_live_count"
	Function ArrayLiveBytes:UInt() = "bmx_embedded_array_live_bytes"
	Function ReachableArrayCount:UInt() = "bmx_embedded_reachable_array_count"
	Function UnreachableArrayCount:UInt() = "bmx_embedded_unreachable_array_count"
	Function StringFailureCount:UInt() = "bmx_embedded_string_failure_count"
	Function StringAllocationCount:UInt() = "bmx_embedded_string_allocation_count"
	Function StringAllocatedBytes:UInt() = "bmx_embedded_string_allocated_bytes"
	Function StringLiveCount:UInt() = "bmx_embedded_string_live_count"
	Function StringLiveBytes:UInt() = "bmx_embedded_string_live_bytes"
	Function ReachableStringCount:UInt() = "bmx_embedded_reachable_string_count"
	Function UnreachableStringCount:UInt() = "bmx_embedded_unreachable_string_count"
	Function EnumFailureCount:UInt() = "bmx_embedded_enum_failure_count"
	Function ObjectFailureCount:UInt() = "bmx_embedded_object_failure_count"
	Function ObjectAllocationCount:UInt() = "bmx_embedded_object_allocation_count"
	Function ObjectAllocatedBytes:UInt() = "bmx_embedded_object_allocated_bytes"
	Function ObjectLiveCount:UInt() = "bmx_embedded_object_live_count"
	Function ObjectLiveBytes:UInt() = "bmx_embedded_object_live_bytes"
	Function ObjectRootRetain:UInt(value:Object) = "bmx_embedded_object_root_retain"
	Function ObjectRootRelease(token:UInt) = "bmx_embedded_object_root_release"
	Function ObjectRootCount:UInt() = "bmx_embedded_object_root_count"
	Function ReachabilityAudit:UInt() = "bmx_embedded_reachability_audit"
	Function ReachableObjectCount:UInt() = "bmx_embedded_reachable_object_count"
	Function UnreachableObjectCount:UInt() = "bmx_embedded_unreachable_object_count"
	Function InvalidReferenceCount:UInt() = "bmx_embedded_invalid_reference_count"
	Function CollectObjects:UInt() = "bmx_embedded_collect_objects"
	Function CollectionCount:UInt() = "bmx_embedded_collection_count"
	Function AutomaticCollectionCount:UInt() = "bmx_embedded_automatic_collection_count"
	Function LastReclaimedObjectCount:UInt() = "bmx_embedded_last_reclaimed_object_count"
	Function LastReclaimedBytes:UInt() = "bmx_embedded_last_reclaimed_bytes"
	Function LastReclaimedArrayCount:UInt() = "bmx_embedded_last_reclaimed_array_count"
	Function LastReclaimedArrayBytes:UInt() = "bmx_embedded_last_reclaimed_array_bytes"
	Function LastReclaimedStringCount:UInt() = "bmx_embedded_last_reclaimed_string_count"
	Function LastReclaimedStringBytes:UInt() = "bmx_embedded_last_reclaimed_string_bytes"
	Function FinalizerPendingCount:UInt() = "bmx_embedded_finalizer_pending_count"
	Function FinalizerInvocationCount:UInt() = "bmx_embedded_finalizer_invocation_count"
	Function LastFinalizedObjectCount:UInt() = "bmx_embedded_last_finalized_object_count"
	Function HeapReusableBytes:UInt() = "bmx_embedded_heap_reusable_bytes"
	Function HeapLargestFreeBlock:UInt() = "bmx_embedded_heap_largest_free_block"
	Function RootFrameCount:UInt() = "bmx_embedded_root_frame_count"
	Function RootSlotCount:UInt() = "bmx_embedded_root_slot_count"
	Function ExceptionDepth:UInt() = "bmx_embedded_exception_depth"
	Function ExceptionThrowCount:UInt() = "bmx_embedded_exception_throw_count"
	Function ExceptionCatchCount:UInt() = "bmx_embedded_exception_catch_count"
	Function ExceptionMaxDepth:UInt() = "bmx_embedded_exception_max_depth"
	Function ExceptionUnhandledCount:UInt() = "bmx_embedded_exception_unhandled_count"
End Extern
?
