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
            .type_alias => |type_alias| try formatTypeAlias(&output.writer, ast, interner, type_alias),
            .struct_decl => |struct_decl| try formatStruct(&output.writer, ast, interner, struct_decl),
            .enum_decl => |enum_decl| try formatEnum(&output.writer, ast, interner, enum_decl),
            else => {},
        }
    }

    return output.toOwnedSlice();
}

fn formatStruct(
    writer: *std.Io.Writer,
    ast: *const ast_mod.Ast,
    interner: *const base.Interner,
    struct_decl: ast_mod.StructDecl,
) std.Io.Writer.Error!void {
    try writeVisibility(writer, struct_decl.visibility);
    try writer.writeAll("struct ");
    try writer.writeAll(interner.get(struct_decl.name) orelse "<missing>");
    try writeGenericParams(writer, ast, interner, struct_decl.generic_params);
    try writer.writeAll(" {\n");

    const start: usize = @intCast(struct_decl.fields.start);
    const end: usize = @intCast(struct_decl.fields.end());
    for (ast.struct_fields.items[start..end]) |field| {
        try writer.writeAll("    ");
        if (field.visibility == .private) try writer.writeAll("private ");
        try writer.writeAll(interner.get(field.name) orelse "<missing>");
        try writer.writeAll(": ");
        try writeTypeExpr(writer, ast, interner, field.type_expr);
        try writer.writeAll(",\n");
    }

    try writer.writeAll("}\n");
}

fn formatEnum(
    writer: *std.Io.Writer,
    ast: *const ast_mod.Ast,
    interner: *const base.Interner,
    enum_decl: ast_mod.EnumDecl,
) std.Io.Writer.Error!void {
    try writeVisibility(writer, enum_decl.visibility);
    try writer.writeAll("enum ");
    try writer.writeAll(interner.get(enum_decl.name) orelse "<missing>");
    try writeGenericParams(writer, ast, interner, enum_decl.generic_params);
    try writer.writeAll(" {\n");

    const start: usize = @intCast(enum_decl.variants.start);
    const end: usize = @intCast(enum_decl.variants.end());
    for (ast.enum_variants.items[start..end]) |variant| {
        try writer.writeAll("    ");
        try writer.writeAll(interner.get(variant.name) orelse "<missing>");
        switch (variant.kind) {
            .unit => {},
            .tuple => {
                try writer.writeByte('(');
                try writeEnumFields(writer, ast, interner, variant.fields, false);
                try writer.writeByte(')');
            },
            .record => {
                try writer.writeAll(" { ");
                try writeEnumFields(writer, ast, interner, variant.fields, true);
                try writer.writeAll(" }");
            },
        }
        try writer.writeAll(",\n");
    }

    try writer.writeAll("}\n");
}

fn writeEnumFields(
    writer: *std.Io.Writer,
    ast: *const ast_mod.Ast,
    interner: *const base.Interner,
    fields: base.Range,
    include_names: bool,
) std.Io.Writer.Error!void {
    const start: usize = @intCast(fields.start);
    const end: usize = @intCast(fields.end());
    for (ast.enum_fields.items[start..end], 0..) |field, index| {
        if (index != 0) try writer.writeAll(", ");
        if (include_names) {
            if (field.name) |name| {
                try writer.writeAll(interner.get(name) orelse "<missing>");
                try writer.writeAll(": ");
            }
        }
        try writeTypeExpr(writer, ast, interner, field.type_expr);
    }
}

fn formatTypeAlias(
    writer: *std.Io.Writer,
    ast: *const ast_mod.Ast,
    interner: *const base.Interner,
    type_alias: ast_mod.TypeAliasDecl,
) std.Io.Writer.Error!void {
    try writeVisibility(writer, type_alias.visibility);
    try writer.writeAll("type ");
    try writer.writeAll(interner.get(type_alias.name) orelse "<missing>");
    try writeGenericParams(writer, ast, interner, type_alias.generic_params);
    try writer.writeAll(" = ");
    try writeTypeExpr(writer, ast, interner, type_alias.aliased_type);
    try writer.writeAll(";\n");
}

fn formatImport(
    writer: *std.Io.Writer,
    ast: *const ast_mod.Ast,
    interner: *const base.Interner,
    import_decl: ast_mod.ImportDecl,
) std.Io.Writer.Error!void {
    try writeVisibility(writer, import_decl.visibility);
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

fn writeVisibility(writer: *std.Io.Writer, visibility: ast_mod.Visibility) std.Io.Writer.Error!void {
    switch (visibility) {
        .public => try writer.writeAll("pub "),
        .private => try writer.writeAll("private "),
        .package => {},
    }
}

fn writeGenericParams(
    writer: *std.Io.Writer,
    ast: *const ast_mod.Ast,
    interner: *const base.Interner,
    params: base.Range,
) std.Io.Writer.Error!void {
    if (params.len == 0) return;
    try writer.writeByte('<');
    const start: usize = @intCast(params.start);
    const end: usize = @intCast(params.end());
    for (ast.generic_params.items[start..end], 0..) |param, index| {
        if (index != 0) try writer.writeAll(", ");
        try writer.writeAll(interner.get(param.name) orelse "<missing>");
        if (param.constraint) |constraint| {
            try writer.writeAll(": ");
            try writeTypeExpr(writer, ast, interner, constraint);
        }
    }
    try writer.writeByte('>');
}

fn writeTypeExpr(
    writer: *std.Io.Writer,
    ast: *const ast_mod.Ast,
    interner: *const base.Interner,
    type_id: ast_mod.TypeId,
) std.Io.Writer.Error!void {
    switch (ast.types.items[type_id]) {
        .unit => try writer.writeAll("()"),
        .path => |path_type| {
            try writePath(writer, ast, interner, path_type.segments);
            if (path_type.args.len != 0) {
                try writer.writeByte('<');
                const start: usize = @intCast(path_type.args.start);
                const end: usize = @intCast(path_type.args.end());
                for (ast.type_args.items[start..end], 0..) |arg, index| {
                    if (index != 0) try writer.writeAll(", ");
                    try writeTypeExpr(writer, ast, interner, arg);
                }
                try writer.writeByte('>');
            }
        },
    }
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
