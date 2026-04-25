const std = @import("std");
const ast_mod = @import("../parser/ast.zig");
const base = @import("../base.zig");

const Allocator = std.mem.Allocator;
const FormatError = Allocator.Error || std.Io.Writer.Error;

pub fn formatAst(allocator: Allocator, ast: *const ast_mod.Ast, interner: *const base.Interner) FormatError![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();

    for (ast.decls.items) |decl| {
        switch (decl) {
            .import => |import_decl| try formatImport(&output.writer, ast, interner, import_decl),
            else => {},
        }
    }

    return output.toOwnedSlice();
}

fn formatImport(
    writer: *std.Io.Writer,
    ast: *const ast_mod.Ast,
    interner: *const base.Interner,
    import_decl: ast_mod.ImportDecl,
) std.Io.Writer.Error!void {
    switch (import_decl.visibility) {
        .public => try writer.writeAll("pub "),
        .private => try writer.writeAll("private "),
        .package => {},
    }
    try writer.writeAll("import ");
    try writePath(writer, ast, interner, import_decl.path);
    if (import_decl.items.len != 0) {
        try writer.writeAll(".{");
        const start: usize = @intCast(import_decl.items.start);
        const end: usize = @intCast(import_decl.items.end());
        for (ast.import_items.items[start..end], 0..) |item, index| {
            if (index != 0) try writer.writeAll(", ");
            try writer.writeAll(interner.get(item.name) orelse "<missing>");
            if (item.alias) |alias| {
                try writer.writeAll(" as ");
                try writer.writeAll(interner.get(alias) orelse "<missing>");
            }
        }
        try writer.writeByte('}');
    }
    if (import_decl.alias) |alias| {
        try writer.writeAll(" as ");
        try writer.writeAll(interner.get(alias) orelse "<missing>");
    }
    try writer.writeByte('\n');
}

fn writePath(
    writer: *std.Io.Writer,
    ast: *const ast_mod.Ast,
    interner: *const base.Interner,
    path: base.Range,
) std.Io.Writer.Error!void {
    const start: usize = @intCast(path.start);
    const end: usize = @intCast(path.end());
    for (ast.path_segments.items[start..end], 0..) |segment, index| {
        if (index != 0) try writer.writeByte('.');
        try writer.writeAll(interner.get(segment.name) orelse "<missing>");
    }
}

test "formatter formats imports" {
    const veyl = @import("../root.zig");
    const source =
        \\pub import http.router.{Route, Router as HttpRouter}
        \\import std.json as json
        \\
    ;

    var diagnostics = veyl.diag.DiagnosticBag.init(std.testing.allocator);
    defer diagnostics.deinit();
    var tokens = try veyl.lexer.lex(std.testing.allocator, 0, source, &diagnostics);
    defer tokens.deinit();
    var interner = veyl.base.Interner.init(std.testing.allocator);
    defer interner.deinit();
    var tree = try veyl.parser.parse(std.testing.allocator, 0, source, tokens.tokens.items, &interner, &diagnostics);
    defer tree.deinit();

    const formatted = try formatAst(std.testing.allocator, &tree, &interner);
    defer std.testing.allocator.free(formatted);
    try std.testing.expectEqualStrings(source, formatted);
}
