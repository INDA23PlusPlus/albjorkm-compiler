//! This file contains unit tests for the support header file.

const std = @import("std");

const support = @cImport({
    @cDefine("SUPPORT_IGNORE_FATAL_ERRORS", "1");
    @cInclude("support.h");
});

test "gcAlloc" {
    var mem = support.gcAlloc(32);
    _ = mem;
}

test "push bind then get" {
    support.supPushNumber(32);
    support.supBind();
    support.supPushNumber(42);
    support.supPushNumber(52);
    support.supBind();
    support.supGet(1);
    try std.testing.expectEqual(support.top.v.number, 32);
    support.supGet(0);
    try std.testing.expectEqual(support.top.v.number, 52);
}

test "crash supCall" {
    support.supPushNumber(32);
    support.supCall();
    try std.testing.expectEqual(support.call_number_error, support.crash_message);
}


test "custom call" {
    support.supPushNumber(32);
    support.supPushNumber(32);
    // TODO: Implement later.
}

test "captured get and bind" {
    support.supPushNumber(1);
    support.supPushNumber(2);
    support.supPushNumber(3);
    support.supBindCaptured();
    support.supBindCaptured();
    support.supBindCaptured();
    support.supGetCaptured(1);
    try std.testing.expectEqual(support.top.v.number, 2);
    support.supGetCaptured(0);
    try std.testing.expectEqual(support.top.v.number, 1);
    support.supGetCaptured(2);
    try std.testing.expectEqual(support.top.v.number, 3);

}

// const VariableTag = enum(c_int) {
//     none,
//     context_parent,
//     context_end,
//     var_number,
//     var_closure,
//     var_str,
//     closure_function_ptr,
// };
// 
// const ManagedVariable = extern struct {
//     v: extern union {
//         none: u64,
//         number: i64,
//         str: [*:0]const u8,
//         closure: [*]ManagedVariable,
//         parent: [*]ManagedVariable,
//         /// Exists for context_end
//         relocation: [*]ManagedVariable,
//     },
//     tag: VariableTag,
// };
// 
// var no_context = [_]ManagedVariable {
//     ManagedVariable {
//         .v = .{ .none = 0 },
//         .tag = .context_end,
//     }
// };
// 
// const GC = struct {
//     fba: std.heap.FixedBufferAllocator,
//     old_memory: []u8,
// };
// 
// fn copyHeapContextToHeap(gc: *GC, ctx: [*]ManagedVariable) [*]ManagedVariable {
//     var size: usize = 0;
//     for (0..1024) |i| {
//         var context = &ctx[i];
//         if (context.tag == .context_end) {
//             size = i;
//             break;
//         }
//     }
// 
//     var new_context = gcAlloc(gc, ctx, ManagedVariable, size + 1);
//     for (0..1024) |i| {
//         new_context[i] = ctx[i];
//         if (new_context[i].tag == .context_end) {
//             return new_context.ptr;
//         }
//     }
// 
//     @panic("context is longer than 1024");
// }
// 
// fn gcScanClosure(gc: *GC, ctx: [*]ManagedVariable) [*]ManagedVariable {
//     var size: usize = 0;
//     for (0..1024) |i| {
//         var context = &ctx[i];
//         if (context.tag == .context_end) {
//             if (gc.fba.ownsPtr(@ptrCast(context.v.relocation))) {
//                 return context.v.relocation;
//             }
//             size = i;
//             break;
//         }
//     }
// 
//     var new_context = gcAlloc(gc, &no_context, ManagedVariable, size + 1);
//     for (0..1024) |i| {
//         gcScanManagedVariable(gc, &new_context[i], &ctx[i]);
//         if (new_context[i].tag == .context_end) {
//             ctx[i].v.relocation = new_context.ptr;
//             return new_context.ptr;
//         }
//     }
// 
//     @panic("context is longer than 1024");
// 
// }
// 
// fn gcScanManagedVariable(gc: *GC, v: *ManagedVariable, into: *ManagedVariable) void {
//     switch (v.tag) {
//         .var_closure => {
//             into.tag = .var_closure;
//             into.v.closure = gcScanClosure(gc, v.v.closure);
//         },
//         else => {
//             v.* = into.*;
//         }
//     }
// }
// 
// fn gcScanStack(gc: *GC, ctx: [*]ManagedVariable) void {
//     for (0..1024) |i| {
//         var context = &ctx[i];
//         if (context.tag == .context_end) {
//             return;
//         } else if (context.tag == .var_closure) {
//              gcScanManagedVariable(gc, &context.v.closure[0], context);
//         } else if (context.tag == .context_parent) {
//             return gcScanStack(gc, context.v.parent);
//         }
//     }
//     @panic("context is longer than 1024");
// }
// 
// fn gcAlloc(gc: *GC, ctx: [*]ManagedVariable, comptime T: type, n: usize) []T {
//     return gc.fba.allocator().alloc(T, n) catch blk: {
//         const allocator = std.heap.page_allocator;
//         // TODO: panic if error is caught during gc scan.
// 
//         // We add 16 because we are paranoid about alignment or something...
//         // No clue if this is really required.
//         const min_target_size = gc.fba.buffer.len + @sizeOf(T) * n + 16;
//         var target_size: usize = 1;
//         while (target_size < min_target_size) {
//             target_size <<= 1; // Could be optimized using @clz.
//         }
//         const new_memory = allocator.alloc(u8, target_size) catch {
//             @panic("out of memory!");
//         };
// 
//         gc.old_memory = gc.fba.buffer;
// 
//         gc.fba = std.heap.FixedBufferAllocator.init(new_memory);
//         gcScanStack(gc, ctx);
// 
//         allocator.free(gc.old_memory);
// 
//         break :blk gc.fba.allocator().alloc(T, n) catch {
//             @panic("gc is failing weirdly");
//         };
//     };
// }
// 
// fn moveCurrentContextToHeap(gc: *GC, ctx: [*]ManagedVariable) [*]ManagedVariable {
//     if (gc.fba.ownsPtr(ctx)) {
//         // Already on the heap! No moves is required.
//         return ctx;
//     }
// 
//     var size: usize = 0;
//     for (0..1024) |i| {
//         var context = &ctx[i];
//         if (context.tag == .context_end) {
//             size = i;
//             break;
//         }
//     }
// 
//     var new_context = gcAlloc(gc, ctx, ManagedVariable, size + 1);
//     for (0..1024) |i| {
//         new_context[i] = ctx[i];
//         if (new_context[i].tag == .context_end) {
//             return new_context.ptr;
//         }
//     }
// 
//     @panic("context is longer than 1024");
// }
// 
// test "managed_variable_size" {
//     try std.testing.expectEqual(16, @sizeOf(ManagedVariable));
// }
// 
// 
// test "gc_alloc" {
//     const allocator = std.heap.page_allocator;
//     const mem = try allocator.alloc(u8, 1);
//     var gc = GC {
//         .fba = std.heap.FixedBufferAllocator.init(mem),
//         .old_memory = undefined
//     };
//     var ctx = [_]ManagedVariable {
//         ManagedVariable {
//             .tag = .context_end,
//             .v = .{.none = 0},
//         },
//     };
//     var thing = gcAlloc(&gc, &ctx, u8, 31);
//     thing[0] = 'h';
//     thing[1] = 'i';
//     thing[2] = 0;
// }
// 
// test "gc_alloc_context" {
//     const allocator = std.heap.page_allocator;
//     const mem = try allocator.alloc(u8, 1);
//     var gc = GC {
//         .fba = std.heap.FixedBufferAllocator.init(mem),
//         .old_memory = undefined
//     };
//     var ctx = [_]ManagedVariable {
//         ManagedVariable {
//             .tag = .var_number,
//             .v = .{.number = 333},
//         },
//         ManagedVariable {
//             .tag = .context_end,
//             .v = .{.none = 0},
//         },
//     };
//     var new_ctx = moveCurrentContextToHeap(&gc, &ctx);
//     try std.testing.expectEqual(new_ctx[0].v.number, 333);
// }
// 
