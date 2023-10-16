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
                .symbol => switch (c) {
                    'a'...'z', 'A'...'Z', '0'...'9' => {},
                    else => {
                        self.state = .normal;
                        continue :top;
                    },
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
    fn parse_list(self: *Parser, tokens: *Tokens.Slice) std.mem.Allocator.Error!u32 {
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
            var result = try self.parse_expr(tokens);
            self.nodes.items[new_cursor].list.elem = result;
        }
        return id;
    }
    fn parse_expr(self: *Parser, tokens: *Tokens.Slice) std.mem.Allocator.Error!u32 {
        var token = tokens.get(self.index);
        var id: u32 = @truncate(self.nodes.items.len);
        switch (token.tag) {
            .l_par => {
                self.index += 1;
                return try self.parse_list(tokens);
            },
            .none, .r_par => {
                std.debug.print("HEY HEY PEOPLE\n", .{});
                return 42;
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

    fn pretty_print(self: *Parser, at: u32, in_list: bool) void {
        if (at == AST_EMPTY_LIST) {
            return;
        }
        switch (self.nodes.items[at]) {
            .list => |v| {
                if (!in_list) {
                    std.debug.print("[", .{});
                }
                self.pretty_print(v.elem, false);
                self.pretty_print(v.next, true);
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
        std.debug.print("{any} at {d}\n", .{ tag, index });
    }

    var parser = Parser{
        .index = 0,
        .nodes = std.ArrayList(ASTNode).init(allocator),
    };

    var start = try parser.parse_expr(&slice);
    //std.debug.print("start: {d}\nnodes:{any}\n", .{ start, parser.nodes.items });
    parser.pretty_print(start, false);

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
