const std = @import("std");
const token_mod = @import("token.zig");

const Allocator = std.mem.Allocator;
const DumpError = Allocator.Error || std.Io.Writer.Error;

pub fn dumpTokens(
    allocator: Allocator,
    source: []const u8,
    tokens: []const token_mod.Token,
) DumpError![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();

    for (tokens) |token| {
        try output.writer.print("{s} {d}..{d} \"", .{
            @tagName(token.kind),
            token.span.start,
            token.span.end(),
        });

        const start: usize = token.span.start;
        const end: usize = token.span.end();
        if (start <= source.len and end <= source.len and start <= end) {
            try writeEscaped(&output.writer, source[start..end]);
        }

        try output.writer.writeAll("\"\n");
    }

    return output.toOwnedSlice();
}

fn writeEscaped(writer: *std.Io.Writer, text: []const u8) std.Io.Writer.Error!void {
    for (text) |byte| {
        switch (byte) {
            '\\' => try writer.writeAll("\\\\"),
            '"' => try writer.writeAll("\\\""),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => try writer.writeByte(byte),
        }
    }
}

test "dump tokens includes spans and escaped lexemes" {
    const tokens = [_]token_mod.Token{
        .{ .kind = .keyword_let, .span = .{ .source = 0, .start = 0, .len = 3 } },
        .{ .kind = .string_literal, .span = .{ .source = 0, .start = 8, .len = 3 } },
        .{ .kind = .eof, .span = .{ .source = 0, .start = 11, .len = 0 } },
    };

    const dumped = try dumpTokens(std.testing.allocator, "let x = \"a\"", &tokens);
    defer std.testing.allocator.free(dumped);

    try std.testing.expectEqualStrings(
        "keyword_let 0..3 \"let\"\n" ++
            "string_literal 8..11 \"\\\"a\\\"\"\n" ++
            "eof 11..11 \"\"\n",
        dumped,
    );
}
