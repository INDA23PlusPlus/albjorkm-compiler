const std = @import("std");

const TokenTag = enum {
    none,
    l_par,
    r_par,
    symbol,
    string,
};

const Token = struct {
    index: u32,
    tag: TokenTag,
};
const Tokens = std.MultiArrayList(Token);

const TokenizerState = enum {
    normal,
    symbol,
    string,
    comment,
    escape_string,
};

const TokenizerError = error{unexpected_char};

fn isSymbolToken(c: u8) bool {
    return switch(c) {
        'a'...'z', 'A'...'Z', '0'...'9' => true,
        else => false,
    };
}

const Tokenizer = struct {
    index: u32,
    state: TokenizerState,
    allocator: std.mem.Allocator,
    tokens: Tokens,
    source: std.ArrayList(u8),
    fn addToken(self: *Tokenizer, comptime t: TokenTag) !void {
        try self.tokens.append(self.allocator, Token{
            .index = self.index,
            .tag = t,
        });
    }
    fn feedChar(self: *Tokenizer, c: u8) !void {
        top: while (true) {
            switch (self.state) {
                .normal => switch (c) {
                    '\"' => {
                        self.state = .string;
                        try self.addToken(.string);
                    },
                    '(' => try self.addToken(.l_par),
                    ')' => try self.addToken(.r_par),
                    'a'...'z', 'A'...'Z', '0'...'9' => {
                        self.state = .symbol;
                        try self.addToken(.symbol);
                    },
                    ' ', '\n', '\t', '\r' => {},
                    ';' => self.state = .comment,
                    else => return TokenizerError.unexpected_char,
                },
                .symbol => if (!isSymbolToken(c)) {
                    self.state = .normal;
                    continue :top;
                },
                .string => switch (c) {
                    '\\' => self.state = .escape_string,
                    '\"' => self.state = .normal,
                    else => {},
                },
                .escape_string => self.state = .string,
                .comment => switch (c) {
                    '\r', '\n' => self.state = .normal,
                    else => {},
                },
            }
            break;
        }
        self.index += 1;
        return;
    }
    fn feed(self: *Tokenizer, buf: []u8) !void {
        try self.source.appendSlice(buf);
        for (buf) |c| {
            try self.feedChar(c);
        }
    }
};

fn tokenToSymbol(source: []u8, start: usize) []u8 {
    var end: usize = start;
    while (isSymbolToken(source[end])) {
        end += 1;
    }
    return source[start..end];
}

const ASTTag = enum {
    list,
    symbol,
    string,
};

const ASTList = struct {
    elem: u32,
    next: u32,
};

const ASTString = struct {
    source_start: u32,
};

const ASTSymbol = struct {
    source_start: u32,
};

const ASTNode = union(ASTTag) {
    list: ASTList,
    symbol: ASTSymbol,
    string: ASTString,
};

const AST_EMPTY_LIST = std.math.maxInt(u32);

const Parser = struct {
    nodes: std.ArrayList(ASTNode),
    index: u32,
    fn parseList(self: *Parser, tokens: *Tokens.Slice) std.mem.Allocator.Error!u32 {
        var cursor: u32 = AST_EMPTY_LIST;
        var id: u32 = AST_EMPTY_LIST;
        while (true) {
            var token = tokens.get(self.index);
            if (token.tag == .r_par) {
                self.index += 1;
                break;
            }
            var new_cursor: u32 = @truncate(self.nodes.items.len);
            try self.nodes.append(ASTNode{ .list = ASTList{ .next = AST_EMPTY_LIST, .elem = AST_EMPTY_LIST } });
            if (id == AST_EMPTY_LIST) {
                id = new_cursor;
            } else {
                self.nodes.items[cursor].list.next = new_cursor;
            }
            cursor = new_cursor;
            //std.debug.print("{d} {d}\n", .{ new_cursor, self.nodes.items.len });
            var result = try self.parseExpr(tokens);
            self.nodes.items[new_cursor].list.elem = result;
        }
        return id;
    }
    fn parseExpr(self: *Parser, tokens: *Tokens.Slice) std.mem.Allocator.Error!u32 {
        var token = tokens.get(self.index);
        var id: u32 = @truncate(self.nodes.items.len);
        switch (token.tag) {
            .l_par => {
                self.index += 1;
                return try self.parseList(tokens);
            },
            .none, .r_par => {
                @panic("unexpected end of list");
            },
            .string => {
                try self.nodes.append(ASTNode{ .string = ASTString{ .source_start = token.index } });
                self.index += 1;
                return id;
            },
            .symbol => {
                try self.nodes.append(ASTNode{ .symbol = ASTSymbol{ .source_start = token.index } });
                self.index += 1;
                return id;
            },
        }
    }

    fn prettyPrint(self: *Parser, at: u32, in_list: bool) void {
        if (at == AST_EMPTY_LIST) {
            return;
        }
        switch (self.nodes.items[at]) {
            .list => |v| {
                if (!in_list) {
                    std.debug.print("[", .{});
                }
                self.prettyPrint(v.elem, false);
                self.prettyPrint(v.next, true);
                if (!in_list) {
                    std.debug.print("]", .{});
                }
            },
            .symbol => |v| {
                std.debug.print(" {d} ", .{v.source_start});
            },
            .string => |v| {
                std.debug.print(" {d} ", .{v.source_start});
            },
        }
    }
};


const RPNTag = enum {
    placeholder,
    lambda,
    bind,
    bind_captured,
    get,
    get_captured,
    get_by_hops,
    get_captured_by_hops,
    unbind,
    const_num,
    call,
    add,
    str,
    lambda_ret,
};

const RPN = union(RPNTag) {
    placeholder: usize,
    lambda: usize,
    bind: []u8,
    bind_captured: []u8,
    get: []u8,
    get_captured: []u8,
    get_by_hops: usize,
    get_captured_by_hops: usize,
    unbind: usize,
    const_num: usize,
    call: usize,
    add: usize,
    str: usize,
    lambda_ret: usize,

    pub fn format(value: ?RPN, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;
        switch (value.?) {
            .get, .get_captured, .bind, .bind_captured => |sym| try writer.print("{s}({s})", .{@tagName(value.?), sym}),
            .call, .get_by_hops, .get_captured_by_hops => |num| try writer.print("{s}({d})", .{@tagName(value.?), num}),
            else => try writer.print("{s}", .{@tagName(value.?)}),
        }
    }
};



const RPNConverter = struct {
    source: []u8,
    parser: *Parser,
    rpn: std.ArrayList(RPN),

    fn assertSymbol(self: *RPNConverter, at: u32) ASTSymbol {
        switch (self.parser.nodes.items[at]) {
            .symbol => |s| return s,
            else => @panic("expected symbol but got something else"),
        }
    }

    fn assertList(self: *RPNConverter, at: u32) ASTList {
        switch (self.parser.nodes.items[at]) {
            .list => |l| return l,
            else => @panic("expected list but got something else"),
        }
    }

    fn listLength(self: *RPNConverter, at: u32) usize {
        var list = self.assertList(at);
        var length: usize = 0;
        while (true) {
            length += 1;
            if (list.next == AST_EMPTY_LIST) {
                break;
            }
            list = self.assertList(list.next);
        }
        return length;
    }

    fn lambdaToRPN(self: *RPNConverter, n: u32) std.mem.Allocator.Error!void {
        var list = self.assertList(n);
        var arg_list = self.assertList(list.elem);
        var expr_list = self.assertList(list.next);
        var expr = expr_list.elem;

        var lambda_index = self.rpn.items.len;
        try self.rpn.append(RPN{.lambda = undefined});

        var arg_count: u32 = 0;
        while (true) {
            arg_count += 1;
            var symbol = self.assertSymbol(arg_list.elem);
            try self.rpn.append(RPN{.bind = tokenToSymbol(self.source, symbol.source_start)});
            if (arg_list.next == AST_EMPTY_LIST) {
                break;
            }
            arg_list = self.assertList(arg_list.next);
        }
        self.rpn.items[lambda_index] = RPN{.lambda = arg_count};

        try self.exprToRPN(expr, false);

        try self.rpn.append(RPN{.lambda_ret = undefined});
    }

    fn exprToRPN(self: *RPNConverter, at: u32, in_list: bool) std.mem.Allocator.Error!void {
        if (at == AST_EMPTY_LIST) {
            return;
        }
        switch (self.parser.nodes.items[at]) {
            .list => |v| {
                if (!in_list) {
                    if (v.next == AST_EMPTY_LIST) {
                        @panic("empty call detected");
                    }
                    switch (self.parser.nodes.items[v.elem]) {
                        .symbol => |s| {
                            const symbol = tokenToSymbol(self.source, s.source_start);
                            if (std.mem.eql(u8, symbol, "lambda")) {
                                try self.lambdaToRPN(v.next);
                                return;
                            }
                        },
                        else => {},
                    }
                }
                try self.exprToRPN(v.elem, false);
                try self.exprToRPN(v.next, true);

                if (!in_list) {
                    var call_arity = self.listLength(v.next);
                    try self.rpn.append(RPN{.call = call_arity});
                }
            },
            .symbol => |v| {
                try self.rpn.append(RPN{.get = tokenToSymbol(self.source, v.source_start)});
            },
            .string => |v| {
                try self.rpn.append(RPN{.str = v.source_start});
            },
        }
    }
};

fn rpnDetectCaptured(rpn: []RPN) void {
    for(0..rpn.len) |i| {
        switch (rpn[i]) {
            .get => |search| {
                var depth: i32 = 0;
                var j = i;
                while(true) {
                    switch (rpn[j]) {
                        .bind => |found| {
                            if (depth < 0
                                and std.mem.eql(u8, search, found)) {
                                rpn[j] = RPN{.bind_captured = found};
                                break;
                            }
                        },
                        .lambda_ret => depth += 1,
                        .lambda => depth -= 1,
                        else => {}
                    }
                    if (j == 0) {
                        break;
                    }
                    j -= 1;
                }
            },
            else => {},
        }
    }
}

fn rpnFixGetCaptures(rpn: []RPN) void {
    for(0..rpn.len) |i| {
        switch (rpn[i]) {
            .get => |search| {
                var depth: i32 = 0;
                var j = i;
                while(true) {
                    switch (rpn[j]) {
                        .bind_captured => |found| {
                            if (depth <= 0
                                and std.mem.eql(u8, found, search)) {
                                rpn[i] = RPN{.get_captured = search};
                                break;
                            }
                        },
                        .bind => |found| {
                            if (depth <= 0
                                and std.mem.eql(u8, found, search)) {
                                break;
                            }
                        },
                        .lambda_ret => depth += 1,
                        .lambda => depth -= 1,
                        else => {}
                    }
                    if (j == 0) {
                        break;
                    }
                    j -= 1;
                }
            },
            else => {},
        }
    }
}

fn rpnConvertGetToGetBySteps(rpn: []RPN) void {
    for(0..rpn.len) |i| {
        switch (rpn[i]) {
            .get => |search| {
                var depth: i32 = 0;
                var steps: usize = 0;
                var j = i;
                while(true) {
                    switch (rpn[j]) {
                        .bind => |found| {
                            if (depth <= 0) {
                                if (std.mem.eql(u8, search, found)) {
                                    rpn[i] = RPN{.get_by_hops = steps};
                                    break;
                                }
                                steps += 1;
                            }
                        },
                        .lambda_ret => depth += 1,
                        .lambda => depth -= 1,
                        else => {}
                    }
                    if (j == 0) {
                        break;
                    }
                    j -= 1;
                }
            },
            .get_captured => |search| {
                var depth: i32 = 0;
                var steps: usize = 0;
                var j = i;
                while(true) {
                    switch (rpn[j]) {
                        .bind_captured => |found| {
                            if (depth <= 0) {
                                if (std.mem.eql(u8, search, found)) {
                                    rpn[i] = RPN{.get_captured_by_hops = steps};
                                    break;
                                }
                                steps += 1;
                            }
                        },
                        .lambda_ret => depth += 1,
                        .lambda => depth -= 1,
                        else => {}
                    }
                    if (j == 0) {
                        break;
                    }
                    j -= 1;
                }
            },
            else => {},
        }
    }
}

fn rpnFindLambdas(rpn: []RPN, list: *std.ArrayList(usize)) !void {
    for(0..rpn.len) |i| {
        switch (rpn[i]) {
            .lambda => try list.append(i),
            else => {}
        }
    }
}

fn codegenC(rpn: []RPN, start: usize, writer: *std.ArrayList(u8).Writer) !void {
    var depth: usize = 0;
    for(start..rpn.len) |i| {
        switch (rpn[i]) {
            .lambda_ret => {
                if (depth == 1) {
                    try writer.print("}}\n", .{});
                    return;
                }
                depth -= 1;
            },
            .lambda => {
                if (depth != 0) {
                    try writer.print("    supPushLambda(&LAMBDA_{d});\n", .{i});
                } else {
                    try writer.print("void LAMBDA_{d}() {{\n", .{i});
                }
                depth += 1;
            },
            else => {
                if (depth != 1) {
                    continue;
                }
                switch (rpn[i]) {
                    .bind => try writer.print("    supBind();\n", .{}),
                    .get_by_hops => |hops| try writer.print("    supGet({d});\n", .{hops}),
                    .call => try writer.print("    supCall();\n", .{}),
                    else => {}
                }
            }
        }
    }
}


// const context_begin = "(context_begin)";
// const context_primitive = "(primitve)";
// 

// const CompileBinding = struct {
//     name: []const char,
//     next: ?*CompileBinding,
// };
// 
// const CompileContext = struct {
//     previous: ?*const CompileContext,
//     stack: usize,
//     bindings: ?*CompileBinding,
//     source: []u8,
//     writer: *std.ArrayList(u8).Writer
// };
// // 
// // 
// // const context_top = CompileContext {
// //     .previous = undefined,
// //     .index = 0,
// //     .name = "(context_end)",
// // };
// // 
// fn compileSymbolLookup(ctx: ?*CompileContext, into: *CompileContext, symbol: []u8, ) !void {
//     var current = ctx;
//     var ctx_index: usize = 0;
//     var ctx_levels_up: usize = 0;
//     while (ctx != null) {
//         ctx_levels_up += 1;
// 
//     }
//     while (true) {
//         if (std.mem.eql(u8, current.name, symbol)) {
//             ctx_index = current.index;
//             break;
//         }
//         current = current.previous;
//         if (current == &context_top) {
//             std.debug.panic("unknown symbol: {s}\n", .{symbol}); // TODO: handle better
//             return;
//         }
//     }
// 
//     try writer.print("   context_ptr[{d}] = context_lookup({d}, {d});\n", .{into.index, ctx_levels_up, ctx_index});
// }
// 
// fn compileNormalCall(ctx: *const CompileContext, allocator: std.mem.Allocator, parser: *Parser, source: []u8, at: u32, writer: *std.ArrayList(u8).Writer) !*const CompileContext {
//     var current_ctx = ctx;
//     var argument_count = 0;
//     while (true) {
//         if (at == AST_EMPTY_LIST) {
//             break;
//         }
//         switch (parser.nodes.items[at]) {
//             .list => |v| {
//                 argument_count += 1;
// 
//                 compileExpr();
// 
//                 at = v.next;
//             },
//             else => @panic("strange list detected during compilation"),
//         }
//     }
// }
// fn compileCall(ctx: *const CompileContext, allocator: std.mem.Allocator, parser: *Parser, source: []u8, at: u32, writer: *std.ArrayList(u8).Writer) !*const CompileContext {
//     if (at == AST_EMPTY_LIST) {
//         @panic("empty call!");
//     }
//     switch (parser.nodes.items[at]) {
//         .symbol => |v| {
//             const sym = tokenToSymbol(v.source_start);
//             if (std.mem.eql(u8, sym, "lambda")) {
//                 var into = &(try allocator.alloc(CompileContext, 1))[0];
//                 into.previous = ctx;
//                 into.name = context_primitive;
//                 into.index = ctx.index + 1;
//                 return into;
//             }
//         },
//         else => return try compileExpr(ctx, allocator, parser, source, at, writer),
//     }
// }
// 
// 
// fn compileExpr(ctx: *const CompileContext, allocator: std.mem.Allocator, parser: *Parser, source: []u8, at: u32, writer: *std.ArrayList(u8).Writer) !*const CompileContext {
//     if (at == AST_EMPTY_LIST) {
//         return &context_top;
//     }
// 
//     var into = &(try allocator.alloc(CompileContext, 1))[0];
//     into.previous = ctx;
//     into.name = "";
//     into.index = ctx.index + 1;
//     switch (parser.nodes.items[at]) {
//         .list => |v| {
//             try writer.print("// begin apply\n", .{});
//             const call_ctx = try compileCall(ctx, allocator, parser, source, v.elem, writer);
//             if (call_ctx.name == context_primitive) {
//                 try writer.print("    // do primitive\n", .{});
//             } else {
//                 _ = try compileNormalCall(ctx2, allocator, parser, source, v.next, writer);
//             }
//             try writer.print("// end apply\n", .{});
//         },
//         .symbol => |v| {
//             const symbol = tokenToSymbol(source, v.source_start);
//             try compileSymbolLookup(ctx, into, symbol, writer);
//         },
//         .string => |v| {
//             try writer.print("    context_ptr[{d}] = make_string(\"{d}\");", .{into.index, v.source_start});
//         },
//     }
//     return into;
// }

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var tokenizer = Tokenizer{
        .index = 0,
        .state = .normal,
        .tokens = Tokens{},
        .allocator = allocator,
        .source = std.ArrayList(u8).init(allocator),
    };

    var reader = std.io.getStdIn().reader();
    var buf: [1024]u8 = undefined;
    while (reader.read(&buf)) |count| {
        if (count == 0) {
            break;
        }
        tokenizer.feed(buf[0..count]) catch |err| {
            if (err == TokenizerError.unexpected_char) {
                var index = tokenizer.index;
                var items = tokenizer.source.items;
                var loc = std.zig.findLineColumn(items, index);
                std.debug.print(
                    \\char: "{c}" at location {d}:{d}
                    \\line: {s}\n
                , .{
                    items[index],
                    loc.line + 1,
                    loc.column + 1,
                    loc.source_line,
                });
            } else {
                std.debug.print("{any}\n", .{err});
            }
        };
    } else |err| {
        return err;
    }

    var slice = tokenizer.tokens.slice();
    for (slice.items(.tag), slice.items(.index)) |tag, index| {
        std.debug.print("// {any} at {d}\n", .{ tag, index });
    }

    var parser = Parser{
        .index = 0,
        .nodes = std.ArrayList(ASTNode).init(allocator),
    };

    var start = try parser.parseExpr(&slice);
    //std.debug.print("start: {d}\nnodes:{any}\n", .{ start, parser.nodes.items });
    std.debug.print("// ", .{});
    parser.prettyPrint(start, false);

    //var output = std.ArrayList(u8).init(allocator);
    //var writer = output.writer();
    //var ctx = CompileContext {
    //    .name = "test",
    //
    //.previous = &context_top,
    //    .index = 0,
    //};
    //var c = try compileExpr(&ctx, allocator, &parser, tokenizer.source.items, start, &writer, false);
    //std.debug.print("\n// c: {any}\n// output:\n{s}\n", .{c, output.items});
    var lambdas = std.ArrayList(usize).init(allocator);
    var rpnConverter = RPNConverter {
        .source = tokenizer.source.items,
        .rpn = std.ArrayList(RPN).init(allocator),
        .parser = &parser,
    };
    try rpnConverter.exprToRPN(start, false);
    rpnDetectCaptured(rpnConverter.rpn.items);
    rpnFixGetCaptures(rpnConverter.rpn.items);
    rpnConvertGetToGetBySteps(rpnConverter.rpn.items);
    try rpnFindLambdas(rpnConverter.rpn.items, &lambdas);


    std.debug.print("RPN:\n{any}\n", .{rpnConverter.rpn.items});


    var output = std.ArrayList(u8).init(allocator);
    var writer = output.writer();

    var i = lambdas.items.len;
    while(i > 0) {
        i -= 1;
        var lambda_start = lambdas.items[i];
        try codegenC(rpnConverter.rpn.items, lambda_start, &writer);
    }
    std.debug.print("output:\n{s}\n", .{output.items});


    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    //const stdout_file = std.io.getStdOut().writer();
    //var bw = std.io.bufferedWriter(stdout_file);
    //const stdout = bw.writer();
    //try stdout.print("Run `zig build test` to run the tests.\n", .{});
    //try bw.flush(); // don't forget to flush!
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
