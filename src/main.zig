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
        'a'...'z', 'A'...'Z', '0'...'9', '+', '-', '=', '<' => true,
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
                    'a'...'z', 'A'...'Z', '0'...'9', '+', '-', '=', '<' => {
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
    lambda_context_load,
    lambda_ret,
    scope_begin,
    scope_end,
    condition_start,
    condition_else,
    condition_end,
    bind,
    bind_captured,
    set,
    set_captured,
    set_by_hops,
    set_captured_by_hops,
    get,
    get_captured,
    get_by_hops,
    get_captured_by_hops,
    push_number,
    call,
    str,
};

const RPN = union(RPNTag) {
    placeholder: usize,
    lambda: usize,
    lambda_context_load: usize,
    lambda_ret: usize,
    scope_begin: usize,
    scope_end: usize,
    condition_start: usize,
    condition_else: usize,
    condition_end: usize,
    bind: []u8,
    bind_captured: []u8,
    set: []u8,
    set_captured: []u8,
    set_by_hops: usize,
    set_captured_by_hops: usize,
    get: []u8,
    get_captured: []u8,
    get_by_hops: usize,
    get_captured_by_hops: usize,
    push_number: i64,
    call: usize,
    str: usize,

    pub fn format(value: ?RPN, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;
        switch (value.?) {
            .set, .get, .get_captured, .bind, .bind_captured => |sym| try writer.print("{s}({s})", .{@tagName(value.?), sym}),
            .scope_begin, .scope_end, .call, .get_by_hops, .get_captured_by_hops => |num| try writer.print("{s}({d})", .{@tagName(value.?), num}),
            .push_number => |num| try writer.print("{s}({d})", .{@tagName(value.?), num}),
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
        try self.rpn.append(RPN{.scope_begin = lambda_index + 1});
        try self.rpn.append(RPN{.lambda_context_load = undefined});

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

        try self.exprToRPN(expr);

        try self.rpn.append(RPN{.scope_end = lambda_index + 1});
        try self.rpn.append(RPN{.lambda_ret = undefined});
    }

    fn scopedExprToRPN(self: *RPNConverter, n: u32) std.mem.Allocator.Error!void {
        var scope_id = self.rpn.items.len;
        try self.rpn.append(RPN{.scope_begin = scope_id});
        try self.exprToRPN(n);
        try self.rpn.append(RPN{.scope_end = scope_id});
    }

    fn ifToRPN(self: *RPNConverter, n: u32) std.mem.Allocator.Error!void {
        var list = self.assertList(n);

        try self.scopedExprToRPN(list.elem);

        var positive_branch = self.assertList(list.next);
        var condition_start_index = self.rpn.items.len;
        try self.rpn.append(RPN{.condition_start = undefined});
        try self.scopedExprToRPN(positive_branch.elem);

        var negative_branch = self.assertList(positive_branch.next);
        var condition_else_index = self.rpn.items.len;
        try self.rpn.append(RPN{.condition_else = undefined});
        try self.scopedExprToRPN(negative_branch.elem);

        var condition_end_index = self.rpn.items.len;
        try self.rpn.append(RPN{.condition_end = undefined});

        // Link the conditions.
        self.rpn.items[condition_start_index] = RPN{.condition_start = condition_else_index};
        self.rpn.items[condition_else_index] = RPN{.condition_else = condition_end_index};
    }

    fn listToRPN(self: *RPNConverter, at: u32) std.mem.Allocator.Error!void {
        var list = self.assertList(at);
        while (true) {
            try self.exprToRPN(list.elem);
            if (list.next == AST_EMPTY_LIST) {
                break;
            }
            list = self.assertList(list.next);
        }
    }

    fn letToRPN(self: *RPNConverter, at: u32) std.mem.Allocator.Error!void {
        var list = self.assertList(at);
        var statements = self.assertList(list.elem);

        var scope_id = self.rpn.items.len;
        try self.rpn.append(RPN{.scope_begin = scope_id});
        while (true) {
            var symbol = self.assertSymbol(statements.elem);
            statements = self.assertList(statements.next);
            var expr = statements.elem;

            try self.rpn.append(RPN{.push_number = 0});
            try self.rpn.append(RPN{.bind = tokenToSymbol(self.source, symbol.source_start)});

            try self.exprToRPN(expr);

            try self.rpn.append(RPN{.set = tokenToSymbol(self.source, symbol.source_start)});

            if (statements.next == AST_EMPTY_LIST) {
                break;
            }
            list = self.assertList(list.next);
        }

        var expression = self.assertList(list.next);
        try self.exprToRPN(expression.elem);

        try self.rpn.append(RPN{.scope_end = scope_id});
    }

    fn exprToRPN(self: *RPNConverter, at: u32) std.mem.Allocator.Error!void {
        if (at == AST_EMPTY_LIST) {
            return;
        }
        switch (self.parser.nodes.items[at]) {
            .list => |v| {
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
                        if (std.mem.eql(u8, symbol, "if")) {
                            try self.ifToRPN(v.next);
                            return;
                        }
                        if (std.mem.eql(u8, symbol, "let")) {
                            try self.letToRPN(v.next);
                            return;
                        }
                    },
                    else => {},
                }
                try self.listToRPN(v.next);
                try self.exprToRPN(v.elem);
                var call_arity = self.listLength(v.next);
                try self.rpn.append(RPN{.call = call_arity});
            },
            .symbol => |v| {
                const symbol = tokenToSymbol(self.source, v.source_start);
                if (std.fmt.parseInt(i64, symbol, 10)) |num| {
                    try self.rpn.append(RPN{.push_number = num});
                } else |_| {
                    try self.rpn.append(RPN{.get = tokenToSymbol(self.source, v.source_start)});
                }
            },
            .string => |v| {
                try self.rpn.append(RPN{.str = v.source_start});
            },
        }
    }
};

fn rpnDetectCaptured(rpn: []RPN) void {
    // TODO: Detect if in same lambda but different scope.
    for(0..rpn.len) |i| {
        switch (rpn[i]) {
            .set, .get => |search| {
                var depth: i32 = 0;
                var j = i;
                var lambda_passed = false;
                while(true) {
                    switch (rpn[j]) {
                        .bind => |found| {
                            if (depth < 0
                                and std.mem.eql(u8, search, found)
                                and lambda_passed) {
                                rpn[j] = RPN{.bind_captured = found};
                                break;
                            }
                        },
                        .lambda_context_load => {
                            if (depth <= 0) {
                                lambda_passed = true;
                            }
                        },
                        .scope_begin => depth -= 1,
                        .scope_end => depth += 1,
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
                        .scope_begin => depth -= 1,
                        .scope_end => depth += 1,
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

fn rpnFixSetCaptures(rpn: []RPN) void {
    for(0..rpn.len) |i| {
        switch (rpn[i]) {
            .set => |search| {
                var depth: i32 = 0;
                var j = i;
                while(true) {
                    switch (rpn[j]) {
                        .bind_captured => |found| {
                            if (depth <= 0
                                and std.mem.eql(u8, found, search)) {
                                rpn[i] = RPN{.set_captured = search};
                                break;
                            }
                        },
                        .bind => |found| {
                            if (depth <= 0
                                and std.mem.eql(u8, found, search)) {
                                break;
                            }
                        },
                        .scope_begin => depth -= 1,
                        .scope_end => depth += 1,
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
                        .scope_begin => depth -= 1,
                        .scope_end => depth += 1,
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
                        .scope_end => depth += 1,
                        .scope_begin => depth -= 1,
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

fn rpnConvertSetToSetBySteps(rpn: []RPN) void {
    for(0..rpn.len) |i| {
        switch (rpn[i]) {
            .set => |search| {
                var depth: i32 = 0;
                var steps: usize = 0;
                var j = i;
                while(true) {
                    switch (rpn[j]) {
                        .bind => |found| {
                            if (depth <= 0) {
                                if (std.mem.eql(u8, search, found)) {
                                    rpn[i] = RPN{.set_by_hops = steps};
                                    break;
                                }
                                steps += 1;
                            }
                        },
                        .scope_begin => depth -= 1,
                        .scope_end => depth += 1,
                        else => {}
                    }
                    if (j == 0) {
                        break;
                    }
                    j -= 1;
                }
            },
            .set_captured => |search| {
                var depth: i32 = 0;
                var steps: usize = 0;
                var j = i;
                while(true) {
                    switch (rpn[j]) {
                        .bind_captured => |found| {
                            if (depth <= 0) {
                                if (std.mem.eql(u8, search, found)) {
                                    rpn[i] = RPN{.set_captured_by_hops = steps};
                                    break;
                                }
                                steps += 1;
                            }
                        },
                        .scope_end => depth += 1,
                        .scope_begin => depth -= 1,
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

fn builtinName(sym: []u8) []const u8 {
    if (std.mem.eql(u8, sym, "+")) {
        return "sup_builtin_add";
    }
    if (std.mem.eql(u8, sym, "-")) {
        return "sup_builtin_subtract";
    }
    if (std.mem.eql(u8, sym, "=")) {
        return "sup_builtin_equals";
    }
    if (std.mem.eql(u8, sym, "or")) {
        return "sup_builtin_bitwise_or";
    }
    if (std.mem.eql(u8, sym, "and")) {
        return "sup_builtin_bitwise_and";
    }
    if (std.mem.eql(u8, sym, "<")) {
        return "sup_builtin_less_than";
    }
    if (std.mem.eql(u8, sym, "prog-arg")) {
        return "sup_builtin_program_argument";
    }
    if (std.mem.eql(u8, sym, "str-to-num")) {
        return "sup_builtin_string_to_number";
    }
    if (std.mem.eql(u8, sym, "num-to-str")) {
        return "sup_builtin_number_to_string";
    }
    if (std.mem.eql(u8, sym, "put-str")) {
        return "sup_builtin_put_string";
    }


    std.debug.panic("unknown primitive: {s}", .{sym});
}

fn codegenInstructionC(rpn: []RPN, i: usize, writer: *std.ArrayList(u8).Writer) !void {
    switch (rpn[i]) {
        .lambda_context_load => try writer.print(
            \\    context_stack = top.v.context;
            \\    supStackDrop();
            \\
            , .{}),
        .condition_start => try writer.print("    if (top.v.number) {{\n    supStackDrop();\n", .{}),
        .condition_else => try writer.print("    }} else {{\n    supStackDrop();\n", .{}),
        .condition_end => try writer.print("    }}\n", .{}),
        .bind => try writer.print("    supBind();\n", .{}),
        .bind_captured => try writer.print("    supBindCaptured();\n", .{}),
        .set_by_hops => |hops| try writer.print("    supSet({d});\n", .{hops}),
        .set_captured_by_hops => |hops| try writer.print("    supSetCaptured({d});\n", .{hops}),
        .get_by_hops => |hops| try writer.print("    supGet({d});\n", .{hops}),
        .get_captured_by_hops => |hops| try writer.print("    supGetCaptured({d});\n", .{hops}),
        .get => |sym| {
            var name = builtinName(sym);
            try writer.print("    supPushLambda(&{s});\n", .{name});
        },
        .call => try writer.print("    supCall();\n", .{}),
        .push_number => |n| try writer.print("    supPushNumber({d});\n", .{n}),
        .scope_begin => |id| {
            try writer.print(
                \\    struct HeapVariable *scope_{d}_context = context_stack;
                \\    BindsIndex scope_{d}_binds_index = binds_index;
                \\
            , .{id, id});
        },
        .scope_end => |id| {
            try writer.print(
                \\    context_stack = scope_{d}_context;
                \\    binds_index = scope_{d}_binds_index;
                \\
            , .{id, id});
        },
        else => std.debug.panic("attempting to generate unsupported instruction: {any} ", .{rpn[i]}),
    }
}


fn codegenC(rpn: []RPN, start: usize, writer: *std.ArrayList(u8).Writer) !void {
    // TODO: Don't count depth, instead search for the end using ID as that is more robust.
    var depth: usize = 0;
    for(start..rpn.len) |i| {
        switch (rpn[i]) {
            .lambda => {
                if (depth != 0) {
                    try writer.print("    supPushLambda(&lambda_type_{d});\n", .{i});
                } else {
                    try writer.print("void genLambda{d}() {{\n", .{start});
                }
                depth += 1;
            },
            .lambda_ret => {
                if (depth == 1) {
                    try writer.print(
                        \\}}
                        \\struct ManagedType lambda_type_{d} = {{
                        \\    "lambda",
                        \\    &genLambda{d}
                        \\}};
                        \\
                    , .{start, start});
                    return;
                }
                depth -= 1;
            },
            else => {
                if (depth == 1) {
                    try codegenInstructionC(rpn, i, writer);
                }
            }
        }
    }
}

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
    std.debug.print("// ", .{});
    parser.prettyPrint(start, false);

    var lambdas = std.ArrayList(usize).init(allocator);
    var rpnConverter = RPNConverter {
        .source = tokenizer.source.items,
        .rpn = std.ArrayList(RPN).init(allocator),
        .parser = &parser,
    };
    try rpnConverter.exprToRPN(start);
    rpnDetectCaptured(rpnConverter.rpn.items);
    rpnFixGetCaptures(rpnConverter.rpn.items);
    rpnFixSetCaptures(rpnConverter.rpn.items);
    rpnConvertGetToGetBySteps(rpnConverter.rpn.items);
    rpnConvertSetToSetBySteps(rpnConverter.rpn.items);
    try rpnFindLambdas(rpnConverter.rpn.items, &lambdas);


    std.debug.print("\n// RPN: {any}\n", .{rpnConverter.rpn.items});


    var output = std.ArrayList(u8).init(allocator);
    var writer = output.writer();
    try writer.print("#include \"support.h\"\n", .{});
    var i = lambdas.items.len;
    while(i > 0) {
        i -= 1;
        var lambda_start = lambdas.items[i];
        try codegenC(rpnConverter.rpn.items, lambda_start, &writer);
    }
    try writer.print(
        \\int main(int argc, const char **args) {{
        \\    program_args = args;
        \\    program_args_count = argc;
        \\    supPushNumber(argc);
        \\    supPushLambda(&lambda_type_0);
        \\    supCall();
        \\    return top.v.number;
        \\}}
    , .{});
    std.debug.print("// output:\n", .{});

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    try stdout.print("{s}\n", .{output.items});
    try bw.flush();
}

// demonstrates higher-order functions:
// echo "(lambda (x z) (lambda (y z) (+ x y)))" | zig run src\main.zig

// this works:
// echo "(lambda (x) (+ x 1))" | zig run src\main.zig | wsl gcc -g3 -I src -xc -

// this also works now:
// echo "(lambda (x) ((lambda (a b) (+ a b)) x 1))" | zig run src\main.zig

// higher order function working example:
// echo "(lambda (x) ((lambda (y) (+ x y)) 332))" | zig build run
