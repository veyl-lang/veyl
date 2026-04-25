const std = @import("std");
const base = @import("../base.zig");

const Allocator = std.mem.Allocator;
const DumpError = Allocator.Error || std.Io.Writer.Error;

pub const DeclId = base.DeclId;
pub const BlockId = u32;

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

pub const TypeAliasDecl = struct {
    visibility: Visibility,
    name: base.SymbolId,
    name_span: base.Span,
    aliased_type: base.Range,
    span: base.Span,
};

pub const FnParam = struct {
    is_mut: bool,
    name: base.SymbolId,
    name_span: base.Span,
    type_path: base.Range,
    span: base.Span,
};

pub const FnDecl = struct {
    visibility: Visibility,
    name: base.SymbolId,
    name_span: base.Span,
    params: base.Range,
    return_type: ?base.Range = null,
    body: BlockId,
    span: base.Span,
};

pub const RawExpr = struct {
    span: base.Span,
};

pub const LetStmt = struct {
    is_mut: bool,
    name: base.SymbolId,
    name_span: base.Span,
    value: RawExpr,
    span: base.Span,
};

pub const ReturnStmt = struct {
    value: ?RawExpr,
    span: base.Span,
};

pub const Stmt = union(enum) {
    let_stmt: LetStmt,
    return_stmt: ReturnStmt,
    expr_stmt: RawExpr,
};

pub const Block = struct {
    stmts: base.Range,
    final_expr: ?RawExpr = null,
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

pub const EnumField = struct {
    name: ?base.SymbolId = null,
    name_span: ?base.Span = null,
    type_path: base.Range,
    span: base.Span,
};

pub const EnumVariantKind = enum {
    unit,
    tuple,
    record,
};

pub const EnumVariant = struct {
    name: base.SymbolId,
    name_span: base.Span,
    kind: EnumVariantKind,
    fields: base.Range = .{ .start = 0, .len = 0 },
    span: base.Span,
};

pub const EnumDecl = struct {
    visibility: Visibility,
    name: base.SymbolId,
    name_span: base.Span,
    variants: base.Range,
    span: base.Span,
};

pub const Decl = union(enum) {
    import: ImportDecl,
    type_alias: TypeAliasDecl,
    fn_decl: FnDecl,
    struct_decl: StructDecl,
    enum_decl: EnumDecl,

    pub fn span(self: Decl) base.Span {
        return switch (self) {
            .import => |decl| decl.span,
            .type_alias => |decl| decl.span,
            .fn_decl => |decl| decl.span,
            .struct_decl => |decl| decl.span,
            .enum_decl => |decl| decl.span,
        };
    }
};

pub const Ast = struct {
    allocator: Allocator,
    source: base.SourceId,
    decls: std.ArrayListUnmanaged(Decl) = .empty,
    path_segments: std.ArrayListUnmanaged(PathSegment) = .empty,
    fn_params: std.ArrayListUnmanaged(FnParam) = .empty,
    blocks: std.ArrayListUnmanaged(Block) = .empty,
    stmts: std.ArrayListUnmanaged(Stmt) = .empty,
    struct_fields: std.ArrayListUnmanaged(StructField) = .empty,
    enum_variants: std.ArrayListUnmanaged(EnumVariant) = .empty,
    enum_fields: std.ArrayListUnmanaged(EnumField) = .empty,

    pub fn init(allocator: Allocator, source: base.SourceId) Ast {
        return .{
            .allocator = allocator,
            .source = source,
        };
    }

    pub fn deinit(self: *Ast) void {
        self.decls.deinit(self.allocator);
        self.path_segments.deinit(self.allocator);
        self.fn_params.deinit(self.allocator);
        self.blocks.deinit(self.allocator);
        self.stmts.deinit(self.allocator);
        self.struct_fields.deinit(self.allocator);
        self.enum_variants.deinit(self.allocator);
        self.enum_fields.deinit(self.allocator);
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

    pub fn reserveFnParams(self: *const Ast) u32 {
        return @intCast(self.fn_params.items.len);
    }

    pub fn addFnParam(self: *Ast, param: FnParam) Allocator.Error!void {
        try self.fn_params.append(self.allocator, param);
    }

    pub fn reserveStmts(self: *const Ast) u32 {
        return @intCast(self.stmts.items.len);
    }

    pub fn addStmt(self: *Ast, stmt: Stmt) Allocator.Error!void {
        try self.stmts.append(self.allocator, stmt);
    }

    pub fn addBlock(self: *Ast, block: Block) Allocator.Error!BlockId {
        const id: BlockId = @intCast(self.blocks.items.len);
        try self.blocks.append(self.allocator, block);
        return id;
    }

    pub fn addStructField(self: *Ast, field: StructField) Allocator.Error!void {
        try self.struct_fields.append(self.allocator, field);
    }

    pub fn reserveEnumVariants(self: *const Ast) u32 {
        return @intCast(self.enum_variants.items.len);
    }

    pub fn addEnumVariant(self: *Ast, variant: EnumVariant) Allocator.Error!void {
        try self.enum_variants.append(self.allocator, variant);
    }

    pub fn reserveEnumFields(self: *const Ast) u32 {
        return @intCast(self.enum_fields.items.len);
    }

    pub fn addEnumField(self: *Ast, field: EnumField) Allocator.Error!void {
        try self.enum_fields.append(self.allocator, field);
    }
};

pub fn dumpAst(allocator: Allocator, ast: *const Ast, interner: *const base.Interner) DumpError![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();

    try output.writer.writeAll("Root\n");
    for (ast.decls.items) |decl| {
        switch (decl) {
            .import => |import_decl| try dumpImport(&output.writer, ast, interner, import_decl),
            .type_alias => |type_alias| try dumpTypeAlias(&output.writer, ast, interner, type_alias),
            .fn_decl => |fn_decl| try dumpFn(&output.writer, ast, interner, fn_decl),
            .struct_decl => |struct_decl| try dumpStruct(&output.writer, ast, interner, struct_decl),
            .enum_decl => |enum_decl| try dumpEnum(&output.writer, ast, interner, enum_decl),
        }
    }

    return output.toOwnedSlice();
}

fn dumpFn(
    writer: *std.Io.Writer,
    ast: *const Ast,
    interner: *const base.Interner,
    fn_decl: FnDecl,
) std.Io.Writer.Error!void {
    try writer.print("  FnDecl {s} {s}\n", .{
        @tagName(fn_decl.visibility),
        interner.get(fn_decl.name) orelse "<missing>",
    });

    const start: usize = @intCast(fn_decl.params.start);
    const end: usize = @intCast(fn_decl.params.end());
    for (ast.fn_params.items[start..end]) |param| {
        try writer.print("    Param {s}{s}: ", .{
            if (param.is_mut) "mut " else "",
            interner.get(param.name) orelse "<missing>",
        });
        try dumpPath(writer, ast, interner, param.type_path);
        try writer.writeByte('\n');
    }

    try writer.writeAll("    Return ");
    if (fn_decl.return_type) |return_type| {
        try dumpPath(writer, ast, interner, return_type);
    } else {
        try writer.writeAll("()");
    }
    try writer.writeByte('\n');

    try dumpBlock(writer, ast, interner, ast.blocks.items[fn_decl.body], 2);
}

fn dumpBlock(
    writer: *std.Io.Writer,
    ast: *const Ast,
    interner: *const base.Interner,
    block: Block,
    indent: usize,
) std.Io.Writer.Error!void {
    try writeIndent(writer, indent);
    try writer.writeAll("Block\n");

    const start: usize = @intCast(block.stmts.start);
    const end: usize = @intCast(block.stmts.end());
    for (ast.stmts.items[start..end]) |stmt| {
        try dumpStmt(writer, ast, interner, stmt, indent + 1);
    }

    if (block.final_expr != null) {
        try writeIndent(writer, indent + 1);
        try writer.writeAll("FinalExpr\n");
    }
}

fn dumpStmt(
    writer: *std.Io.Writer,
    ast: *const Ast,
    interner: *const base.Interner,
    stmt: Stmt,
    indent: usize,
) std.Io.Writer.Error!void {
    switch (stmt) {
        .let_stmt => |let_stmt| {
            try writeIndent(writer, indent);
            try writer.print("LetStmt {s}{s}\n", .{
                if (let_stmt.is_mut) "mut " else "",
                interner.get(let_stmt.name) orelse "<missing>",
            });
        },
        .return_stmt => {
            try writeIndent(writer, indent);
            try writer.writeAll("ReturnStmt\n");
        },
        .expr_stmt => {
            try writeIndent(writer, indent);
            try writer.writeAll("ExprStmt\n");
        },
    }
    _ = ast;
}

fn writeIndent(writer: *std.Io.Writer, indent: usize) std.Io.Writer.Error!void {
    var i: usize = 0;
    while (i < indent) : (i += 1) {
        try writer.writeAll("  ");
    }
}

fn dumpTypeAlias(
    writer: *std.Io.Writer,
    ast: *const Ast,
    interner: *const base.Interner,
    type_alias: TypeAliasDecl,
) std.Io.Writer.Error!void {
    try writer.print("  TypeAliasDecl {s} {s} = ", .{
        @tagName(type_alias.visibility),
        interner.get(type_alias.name) orelse "<missing>",
    });
    try dumpPath(writer, ast, interner, type_alias.aliased_type);
    try writer.writeByte('\n');
}

fn dumpEnum(
    writer: *std.Io.Writer,
    ast: *const Ast,
    interner: *const base.Interner,
    enum_decl: EnumDecl,
) std.Io.Writer.Error!void {
    try writer.print("  EnumDecl {s} {s}\n", .{
        @tagName(enum_decl.visibility),
        interner.get(enum_decl.name) orelse "<missing>",
    });

    const start: usize = @intCast(enum_decl.variants.start);
    const end: usize = @intCast(enum_decl.variants.end());
    for (ast.enum_variants.items[start..end]) |variant| {
        try writer.print("    Variant {s} {s}\n", .{
            @tagName(variant.kind),
            interner.get(variant.name) orelse "<missing>",
        });

        const field_start: usize = @intCast(variant.fields.start);
        const field_end: usize = @intCast(variant.fields.end());
        for (ast.enum_fields.items[field_start..field_end]) |field| {
            try writer.writeAll("      Field ");
            if (field.name) |name| {
                try writer.print("{s}: ", .{interner.get(name) orelse "<missing>"});
            } else {
                try writer.writeAll("_: ");
            }
            try dumpPath(writer, ast, interner, field.type_path);
            try writer.writeByte('\n');
        }
    }
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

test "AST dump renders type alias declarations" {
    var interner = base.Interner.init(std.testing.allocator);
    defer interner.deinit();

    var tree = Ast.init(std.testing.allocator, 0);
    defer tree.deinit();

    const int_type_start = tree.reservePath();
    try tree.addPathSegment(.{ .name = try interner.intern("Int"), .span = .{ .source = 0, .start = 14, .len = 3 } });
    _ = try tree.addDecl(.{ .type_alias = .{
        .visibility = .package,
        .name = try interner.intern("UserId"),
        .name_span = .{ .source = 0, .start = 5, .len = 6 },
        .aliased_type = .{ .start = int_type_start, .len = 1 },
        .span = .{ .source = 0, .start = 0, .len = 17 },
    } });

    const dumped = try dumpAst(std.testing.allocator, &tree, &interner);
    defer std.testing.allocator.free(dumped);

    try std.testing.expectEqualStrings(
        "Root\n" ++
            "  TypeAliasDecl package UserId = Int\n",
        dumped,
    );
}

test "AST dump renders function declarations" {
    var interner = base.Interner.init(std.testing.allocator);
    defer interner.deinit();

    var tree = Ast.init(std.testing.allocator, 0);
    defer tree.deinit();

    const user_type_start = tree.reservePath();
    try tree.addPathSegment(.{ .name = try interner.intern("User"), .span = .{ .source = 0, .start = 22, .len = 4 } });

    const params_start = tree.reserveFnParams();
    try tree.addFnParam(.{
        .is_mut = true,
        .name = try interner.intern("user"),
        .name_span = .{ .source = 0, .start = 16, .len = 4 },
        .type_path = .{ .start = user_type_start, .len = 1 },
        .span = .{ .source = 0, .start = 12, .len = 14 },
    });

    const stmts_start = tree.reserveStmts();
    const body = try tree.addBlock(.{
        .stmts = .{ .start = stmts_start, .len = 0 },
        .span = .{ .source = 0, .start = 35, .len = 2 },
    });

    _ = try tree.addDecl(.{ .fn_decl = .{
        .visibility = .public,
        .name = try interner.intern("birthday"),
        .name_span = .{ .source = 0, .start = 7, .len = 8 },
        .params = .{ .start = params_start, .len = 1 },
        .return_type = .{ .start = user_type_start, .len = 1 },
        .body = body,
        .span = .{ .source = 0, .start = 0, .len = 37 },
    } });

    const dumped = try dumpAst(std.testing.allocator, &tree, &interner);
    defer std.testing.allocator.free(dumped);

    try std.testing.expectEqualStrings(
        "Root\n" ++
            "  FnDecl public birthday\n" ++
            "    Param mut user: User\n" ++
            "    Return User\n" ++
            "    Block\n",
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

test "AST dump renders enum declarations" {
    var interner = base.Interner.init(std.testing.allocator);
    defer interner.deinit();

    var tree = Ast.init(std.testing.allocator, 0);
    defer tree.deinit();

    const variants_start = tree.reserveEnumVariants();
    const fields_start = tree.reserveEnumFields();
    const int_type_start = tree.reservePath();
    try tree.addPathSegment(.{ .name = try interner.intern("Int"), .span = .{ .source = 0, .start = 22, .len = 3 } });
    try tree.addEnumField(.{
        .type_path = .{ .start = int_type_start, .len = 1 },
        .span = .{ .source = 0, .start = 22, .len = 3 },
    });
    try tree.addEnumVariant(.{
        .name = try interner.intern("Some"),
        .name_span = .{ .source = 0, .start = 17, .len = 4 },
        .kind = .tuple,
        .fields = .{ .start = fields_start, .len = 1 },
        .span = .{ .source = 0, .start = 17, .len = 9 },
    });
    try tree.addEnumVariant(.{
        .name = try interner.intern("None"),
        .name_span = .{ .source = 0, .start = 29, .len = 4 },
        .kind = .unit,
        .span = .{ .source = 0, .start = 29, .len = 4 },
    });
    _ = try tree.addDecl(.{ .enum_decl = .{
        .visibility = .package,
        .name = try interner.intern("MaybeInt"),
        .name_span = .{ .source = 0, .start = 5, .len = 8 },
        .variants = .{ .start = variants_start, .len = 2 },
        .span = .{ .source = 0, .start = 0, .len = 36 },
    } });

    const dumped = try dumpAst(std.testing.allocator, &tree, &interner);
    defer std.testing.allocator.free(dumped);

    try std.testing.expectEqualStrings(
        "Root\n" ++
            "  EnumDecl package MaybeInt\n" ++
            "    Variant tuple Some\n" ++
            "      Field _: Int\n" ++
            "    Variant unit None\n",
        dumped,
    );
}
