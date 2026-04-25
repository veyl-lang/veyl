const std = @import("std");
const base = @import("../base.zig");

const Allocator = std.mem.Allocator;
const DumpError = Allocator.Error || std.Io.Writer.Error;

pub const DeclId = base.DeclId;

pub const Visibility = enum {
    package,
    public,
    private,
};

pub const PathSegment = struct {
    name: base.SymbolId,
    span: base.Span,
};

pub const ImportDecl = struct {
    visibility: Visibility,
    path: base.Range,
    alias: ?base.SymbolId = null,
    alias_span: ?base.Span = null,
    span: base.Span,
};

pub const StructField = struct {
    visibility: Visibility,
    name: base.SymbolId,
    name_span: base.Span,
    type_path: base.Range,
    span: base.Span,
};

pub const StructDecl = struct {
    visibility: Visibility,
    name: base.SymbolId,
    name_span: base.Span,
    fields: base.Range,
    span: base.Span,
};

pub const Decl = union(enum) {
    import: ImportDecl,
    struct_decl: StructDecl,

    pub fn span(self: Decl) base.Span {
        return switch (self) {
            .import => |decl| decl.span,
            .struct_decl => |decl| decl.span,
        };
    }
};

pub const Ast = struct {
    allocator: Allocator,
    source: base.SourceId,
    decls: std.ArrayListUnmanaged(Decl) = .empty,
    path_segments: std.ArrayListUnmanaged(PathSegment) = .empty,
    struct_fields: std.ArrayListUnmanaged(StructField) = .empty,

    pub fn init(allocator: Allocator, source: base.SourceId) Ast {
        return .{
            .allocator = allocator,
            .source = source,
        };
    }

    pub fn deinit(self: *Ast) void {
        self.decls.deinit(self.allocator);
        self.path_segments.deinit(self.allocator);
        self.struct_fields.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn addDecl(self: *Ast, decl: Decl) Allocator.Error!DeclId {
        const id: DeclId = @intCast(self.decls.items.len);
        try self.decls.append(self.allocator, decl);
        return id;
    }

    pub fn addPathSegment(self: *Ast, segment: PathSegment) Allocator.Error!void {
        try self.path_segments.append(self.allocator, segment);
    }

    pub fn reservePath(self: *const Ast) u32 {
        return @intCast(self.path_segments.items.len);
    }

    pub fn reserveStructFields(self: *const Ast) u32 {
        return @intCast(self.struct_fields.items.len);
    }

    pub fn addStructField(self: *Ast, field: StructField) Allocator.Error!void {
        try self.struct_fields.append(self.allocator, field);
    }
};

pub fn dumpAst(allocator: Allocator, ast: *const Ast, interner: *const base.Interner) DumpError![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();

    try output.writer.writeAll("Root\n");
    for (ast.decls.items) |decl| {
        switch (decl) {
            .import => |import_decl| try dumpImport(&output.writer, ast, interner, import_decl),
            .struct_decl => |struct_decl| try dumpStruct(&output.writer, ast, interner, struct_decl),
        }
    }

    return output.toOwnedSlice();
}

fn dumpStruct(
    writer: *std.Io.Writer,
    ast: *const Ast,
    interner: *const base.Interner,
    struct_decl: StructDecl,
) std.Io.Writer.Error!void {
    try writer.print("  StructDecl {s} {s}\n", .{
        @tagName(struct_decl.visibility),
        interner.get(struct_decl.name) orelse "<missing>",
    });

    const start: usize = @intCast(struct_decl.fields.start);
    const end: usize = @intCast(struct_decl.fields.end());
    for (ast.struct_fields.items[start..end]) |field| {
        try writer.print("    Field {s} {s}: ", .{
            @tagName(field.visibility),
            interner.get(field.name) orelse "<missing>",
        });
        try dumpPath(writer, ast, interner, field.type_path);
        try writer.writeByte('\n');
    }
}

fn dumpImport(
    writer: *std.Io.Writer,
    ast: *const Ast,
    interner: *const base.Interner,
    import_decl: ImportDecl,
) std.Io.Writer.Error!void {
    try writer.print("  ImportDecl {s}\n", .{@tagName(import_decl.visibility)});
    try writer.writeAll("    path ");
    try dumpPath(writer, ast, interner, import_decl.path);
    try writer.writeByte('\n');
    if (import_decl.alias) |alias| {
        try writer.print("    alias {s}\n", .{interner.get(alias) orelse "<missing>"});
    }
}

fn dumpPath(
    writer: *std.Io.Writer,
    ast: *const Ast,
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

test "AST dump renders import declarations" {
    var interner = base.Interner.init(std.testing.allocator);
    defer interner.deinit();

    var tree = Ast.init(std.testing.allocator, 0);
    defer tree.deinit();

    const start = tree.reservePath();
    try tree.addPathSegment(.{ .name = try interner.intern("std"), .span = .{ .source = 0, .start = 7, .len = 3 } });
    try tree.addPathSegment(.{ .name = try interner.intern("fs"), .span = .{ .source = 0, .start = 11, .len = 2 } });
    _ = try tree.addDecl(.{ .import = .{
        .visibility = .public,
        .path = .{ .start = start, .len = 2 },
        .span = .{ .source = 0, .start = 0, .len = 13 },
    } });

    const dumped = try dumpAst(std.testing.allocator, &tree, &interner);
    defer std.testing.allocator.free(dumped);

    try std.testing.expectEqualStrings(
        "Root\n" ++
            "  ImportDecl public\n" ++
            "    path std.fs\n",
        dumped,
    );
}

test "AST dump renders struct declarations" {
    var interner = base.Interner.init(std.testing.allocator);
    defer interner.deinit();

    var tree = Ast.init(std.testing.allocator, 0);
    defer tree.deinit();

    const name_type_start = tree.reservePath();
    try tree.addPathSegment(.{ .name = try interner.intern("Str"), .span = .{ .source = 0, .start = 23, .len = 3 } });
    const fields_start = tree.reserveStructFields();
    try tree.addStructField(.{
        .visibility = .public,
        .name = try interner.intern("name"),
        .name_span = .{ .source = 0, .start = 17, .len = 4 },
        .type_path = .{ .start = name_type_start, .len = 1 },
        .span = .{ .source = 0, .start = 17, .len = 9 },
    });
    _ = try tree.addDecl(.{ .struct_decl = .{
        .visibility = .public,
        .name = try interner.intern("User"),
        .name_span = .{ .source = 0, .start = 11, .len = 4 },
        .fields = .{ .start = fields_start, .len = 1 },
        .span = .{ .source = 0, .start = 0, .len = 29 },
    } });

    const dumped = try dumpAst(std.testing.allocator, &tree, &interner);
    defer std.testing.allocator.free(dumped);

    try std.testing.expectEqualStrings(
        "Root\n" ++
            "  StructDecl public User\n" ++
            "    Field public name: Str\n",
        dumped,
    );
}
