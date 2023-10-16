const std = @import("std");

export const end_of_stack = "end_of_stack";
export const parent_context = "parent_context";

const VariableTag = enum(c_int) {
    none,
    number,
    closure,
    str,
    context_parent,
    context_end_of_stack,
};

const ManagedVariable = extern struct {
    tag: VariableTag,
    v: extern union {
        none: u8,
        number: i64,
        str: [*:0]const u8,
    },
};

const ManagedContext = extern struct {
    name: [*:0]const u8,
    u: extern union {
        variable: ManagedVariable,
        parent: [*]ManagedContext,
        none: u64,
    },
};

export fn set_variable(begin: [*]ManagedContext, name: [*:0]const u8, value: *const ManagedVariable) void {
    for (0..1024) |i| {
        var context = &begin[i];
        if (context.name == name) {
            context.u.variable = value.*;
            return;
        } else if (context.name == end_of_stack) {
            @panic("could not find variable");
        } else if (context.name == parent_context) {
            return set_variable(context.u.parent, name, value);
        }
    }
    @panic("context is longer than 1024");
}

export fn get_variable(begin: [*]ManagedContext, name: [*:0]const u8) *const ManagedVariable {
    for (0..1024) |i| {
        var context = &begin[i];
        if (context.name == name) {
            return &context.u.variable;
        } else if (context.name == end_of_stack) {
            @panic("could not find variable");
        } else if (context.name == parent_context) {
            return get_variable(context.u.parent, name);
        }
    }
    @panic("context is longer than 1024");
}

const GC = struct {
    fba: std.heap.FixedBufferAllocator,
    old_memory: []u8,
};

fn gc_scan_stack(gc: *GC, ctx: [*]ManagedContext) void {
    for (0..1024) |i| {
        var context = &ctx[i];
        if (context.name == end_of_stack) {
            return;
        } else if (context.name == parent_context) {
            return gc_scan_stack(gc, context.u.parent);
        } else {

        }
    }
    @panic("context is longer than 1024");
}

fn gc_alloc(gc: *GC, ctx: [*]ManagedContext, comptime T: type) T {
    const allocator = std.heap.page_allocator;
    const many = gc.fba.allocator().alloc(T, 1) catch blk: {
        // TODO: panic if error is caught during gc scan.

        const min_target_size = gc.fba.buffer.len + @sizeOf(T) * 2;
        var target_size: usize = 1;
        while (target_size < min_target_size) {
            target_size <<= 1; // Could be optimized using @clz.
        }
        const new_memory = allocator.alloc(u8, target_size) catch {
            @panic("out of memory!");
        };

        gc.old_memory = gc.fba.buffer;

        gc.fba = std.heap.FixedBufferAllocator.init(new_memory);
        gc_scan_stack(gc, ctx);

        allocator.free(gc.old_memory);

        break :blk gc.fba.allocator().alloc(T, 1) catch {
            @panic("gc is failing weirdly");
        };
    };
    return many[0];
}

test "context_size" {
    try std.testing.expectEqual(16, @sizeOf(ManagedVariable));
    try std.testing.expectEqual(24, @sizeOf(ManagedContext));
}

test "set_variable" {
    const str_a = "a";
    var ctx = [_]ManagedContext {
        ManagedContext {
            .name = str_a,
            .u = .{.none = 0},
        },
        ManagedContext {
            .name = end_of_stack,
            .u = .{.none = 0},
        },
    };
    var new_var = ManagedVariable {
        .tag = .none,
        .v = .{ .number = 333 },
    };
    set_variable(&ctx, str_a, &new_var);
    try std.testing.expectEqual(ctx[0].u.variable.v.number, 333);
}

test "get_variable" {
    const str_a = "a";
    var ctx = [_]ManagedContext {
        ManagedContext {
            .name = str_a,
            .u = .{.none = 0},
        },
        ManagedContext {
            .name = end_of_stack,
            .u = .{.none = 0},
        },
    };
    var new_var = ManagedVariable {
        .tag = .none,
        .v = .{ .number = 333 },
    };
    set_variable(&ctx, str_a, &new_var);
    try std.testing.expectEqual(get_variable(&ctx, str_a).v.number, 333);
}

test "gc_alloc" {
    const allocator = std.heap.page_allocator;
    const mem = try allocator.alloc(u8, 1);
    var gc = GC {
        .fba = std.heap.FixedBufferAllocator.init(mem),
        .old_memory = undefined
    };
    var ctx = [_]ManagedContext {
        ManagedContext {
            .name = end_of_stack,
            .u = .{.none = 0},
        },
    };
    var thing = gc_alloc(&gc, &ctx, [31]u8);
    thing[0] = 'h';
    thing[1] = 'i';
    thing[2] = 0;
}
