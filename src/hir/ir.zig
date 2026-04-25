const std = @import("std");
const base = @import("../base.zig");
const parser = @import("../parser.zig");

const Allocator = std.mem.Allocator;
const DumpError = Allocator.Error || std.Io.Writer.Error;

pub const ExprId = u32;
pub const StmtId = u32;
pub const BlockId = u32;

pub const PathSegment = struct {
    name: base.SymbolId,
    span: base.Span,
};

pub const ImportDecl = struct {
    visibility: parser.Visibility,
    path: base.Range,
    alias: ?base.SymbolId,
    span: base.Span,
};

pub const NamedDecl = struct {
    visibility: parser.Visibility,
    name: base.SymbolId,
    span: base.Span,
};

pub const FunctionDecl = struct {
    visibility: parser.Visibility,
    name: base.SymbolId,
    params_len: u32,
    body: BlockId,
    span: base.Span,
};

pub const ImplDecl = struct {
    visibility: parser.Visibility,
    methods_len: u32,
    span: base.Span,
};

pub const TestDecl = struct {
    name_span: base.Span,
    body: BlockId,
    span: base.Span,
};

pub const BinaryOp = parser.BinaryOp;

pub const Expr = union(enum) {
    name: struct { symbol: base.SymbolId, span: base.Span },
    int_literal: base.Span,
    float_literal: base.Span,
    string_literal: base.Span,
    char_literal: base.Span,
    bool_literal: struct { value: bool, span: base.Span },
    unit_literal: base.Span,
    binary: struct { op: BinaryOp, left: ExprId, right: ExprId, span: base.Span },
    field: struct { base: ExprId, name: base.SymbolId, span: base.Span },
    call: struct { callee: ExprId, args: base.Range, span: base.Span },
    unsupported: base.Span,
};

pub const Stmt = union(enum) {
    let_stmt: struct { name: ?base.SymbolId, value: ExprId, span: base.Span },
    return_stmt: struct { value: ?ExprId, span: base.Span },
    expr_stmt: ExprId,
    unsupported: base.Span,
};

pub const Block = struct {
    stmts: base.Range,
    final_expr: ?ExprId,
    span: base.Span,
};

pub const Decl = union(enum) {
    import: ImportDecl,
    type_alias: NamedDecl,
    function: FunctionDecl,
    struct_decl: NamedDecl,
    enum_decl: NamedDecl,
    impl_decl: ImplDecl,
    interface_decl: NamedDecl,
    test_decl: TestDecl,
};

pub const Hir = struct {
    allocator: Allocator,
    source: base.SourceId,
    decls: std.ArrayListUnmanaged(Decl) = .empty,
    path_segments: std.ArrayListUnmanaged(PathSegment) = .empty,
    blocks: std.ArrayListUnmanaged(Block) = .empty,
    stmts: std.ArrayListUnmanaged(Stmt) = .empty,
    block_stmt_ids: std.ArrayListUnmanaged(StmtId) = .empty,
    exprs: std.ArrayListUnmanaged(Expr) = .empty,
    expr_args: std.ArrayListUnmanaged(ExprId) = .empty,

    pub fn init(allocator: Allocator, source: base.SourceId) Hir {
        return .{ .allocator = allocator, .source = source };
    }

    pub fn deinit(self: *Hir) void {
        self.decls.deinit(self.allocator);
        self.path_segments.deinit(self.allocator);
        self.blocks.deinit(self.allocator);
        self.stmts.deinit(self.allocator);
        self.block_stmt_ids.deinit(self.allocator);
        self.exprs.deinit(self.allocator);
        self.expr_args.deinit(self.allocator);
        self.* = undefined;
    }
};

pub fn lowerAst(allocator: Allocator, ast: *const parser.Ast) Allocator.Error!Hir {
    var hir = Hir.init(allocator, ast.source);
    errdefer hir.deinit();

    try hir.path_segments.ensureTotalCapacity(allocator, ast.path_segments.items.len);
    for (ast.path_segments.items) |segment| {
        hir.path_segments.appendAssumeCapacity(.{ .name = segment.name, .span = segment.span });
    }

    for (ast.decls.items) |decl| {
        try hir.decls.append(allocator, switch (decl) {
            .import => |import_decl| .{ .import = .{
                .visibility = import_decl.visibility,
                .path = import_decl.path,
                .alias = import_decl.alias,
                .span = import_decl.span,
            } },
            .type_alias => |type_alias| .{ .type_alias = .{
                .visibility = type_alias.visibility,
                .name = type_alias.name,
                .span = type_alias.span,
            } },
            .fn_decl => |fn_decl| .{ .function = .{
                .visibility = fn_decl.visibility,
                .name = fn_decl.name,
                .params_len = fn_decl.params.len,
                .body = try lowerBlock(&hir, ast, fn_decl.body),
                .span = fn_decl.span,
            } },
            .struct_decl => |struct_decl| .{ .struct_decl = .{
                .visibility = struct_decl.visibility,
                .name = struct_decl.name,
                .span = struct_decl.span,
            } },
            .enum_decl => |enum_decl| .{ .enum_decl = .{
                .visibility = enum_decl.visibility,
                .name = enum_decl.name,
                .span = enum_decl.span,
            } },
            .impl_decl => |impl_decl| .{ .impl_decl = .{
                .visibility = impl_decl.visibility,
                .methods_len = impl_decl.methods.len,
                .span = impl_decl.span,
            } },
            .interface_decl => |interface_decl| .{ .interface_decl = .{
                .visibility = interface_decl.visibility,
                .name = interface_decl.name,
                .span = interface_decl.span,
            } },
            .test_decl => |test_decl| .{ .test_decl = .{
                .name_span = test_decl.name_span,
                .body = try lowerBlock(&hir, ast, test_decl.body),
                .span = test_decl.span,
            } },
        });
    }

    return hir;
}

fn lowerBlock(hir: *Hir, ast: *const parser.Ast, block_id: parser.ast.BlockId) Allocator.Error!BlockId {
    const ast_block = ast.blocks.items[block_id];
    const stmts_start: u32 = @intCast(hir.block_stmt_ids.items.len);
    const start: usize = @intCast(ast_block.stmts.start);
    const end: usize = @intCast(ast_block.stmts.end());
    for (ast.block_stmt_ids.items[start..end]) |ast_stmt_id| {
        const stmt_id: StmtId = @intCast(hir.stmts.items.len);
        try hir.stmts.append(hir.allocator, try lowerStmt(hir, ast, ast.stmts.items[ast_stmt_id]));
        try hir.block_stmt_ids.append(hir.allocator, stmt_id);
    }

    const final_expr = if (ast_block.final_expr) |expr| try lowerExpr(hir, ast, expr) else null;
    const hir_block: BlockId = @intCast(hir.blocks.items.len);
    try hir.blocks.append(hir.allocator, .{
        .stmts = .{ .start = stmts_start, .len = @intCast(hir.block_stmt_ids.items.len - stmts_start) },
        .final_expr = final_expr,
        .span = ast_block.span,
    });
    return hir_block;
}

fn lowerStmt(hir: *Hir, ast: *const parser.Ast, stmt: parser.Stmt) Allocator.Error!Stmt {
    return switch (stmt) {
        .let_stmt => |let_stmt| .{ .let_stmt = .{
            .name = bindingName(ast, let_stmt.pattern),
            .value = try lowerExpr(hir, ast, let_stmt.value),
            .span = let_stmt.span,
        } },
        .return_stmt => |return_stmt| .{ .return_stmt = .{
            .value = if (return_stmt.value) |value| try lowerExpr(hir, ast, value) else null,
            .span = return_stmt.span,
        } },
        .expr_stmt => |expr| .{ .expr_stmt = try lowerExpr(hir, ast, expr) },
        .while_stmt => |while_stmt| .{ .unsupported = while_stmt.span },
        .for_stmt => |for_stmt| .{ .unsupported = for_stmt.span },
        .defer_stmt => |defer_stmt| .{ .unsupported = defer_stmt.span },
        .break_stmt => |span| .{ .unsupported = span },
        .continue_stmt => |span| .{ .unsupported = span },
    };
}

fn bindingName(ast: *const parser.Ast, pattern_id: parser.PatternId) ?base.SymbolId {
    return switch (ast.patterns.items[pattern_id]) {
        .binding => |binding| binding.name,
        else => null,
    };
}

fn lowerExpr(hir: *Hir, ast: *const parser.Ast, expr_id: parser.ExprId) Allocator.Error!ExprId {
    const expr = ast.exprs.items[expr_id];
    const lowered: Expr = switch (expr) {
        .name => |name| .{ .name = .{ .symbol = name.symbol, .span = name.span } },
        .int_literal => |span| .{ .int_literal = span },
        .float_literal => |span| .{ .float_literal = span },
        .string_literal => |span| .{ .string_literal = span },
        .char_literal => |span| .{ .char_literal = span },
        .bool_literal => |bool_lit| .{ .bool_literal = .{ .value = bool_lit.value, .span = bool_lit.span } },
        .unit_literal => |span| .{ .unit_literal = span },
        .binary => |binary| .{ .binary = .{
            .op = binary.op,
            .left = try lowerExpr(hir, ast, binary.left),
            .right = try lowerExpr(hir, ast, binary.right),
            .span = binary.span,
        } },
        .field => |field| .{ .field = .{
            .base = try lowerExpr(hir, ast, field.base),
            .name = field.name,
            .span = field.span,
        } },
        .call => |call| .{ .call = .{
            .callee = try lowerExpr(hir, ast, call.callee),
            .args = try lowerCallArgs(hir, ast, call.args),
            .span = call.span,
        } },
        else => .{ .unsupported = expr.span() },
    };

    const lowered_id: ExprId = @intCast(hir.exprs.items.len);
    try hir.exprs.append(hir.allocator, lowered);
    return lowered_id;
}

fn lowerCallArgs(hir: *Hir, ast: *const parser.Ast, args: base.Range) Allocator.Error!base.Range {
    const args_start: u32 = @intCast(hir.expr_args.items.len);
    const start: usize = @intCast(args.start);
    const end: usize = @intCast(args.end());
    for (ast.call_args.items[start..end]) |arg| {
        try hir.expr_args.append(hir.allocator, try lowerExpr(hir, ast, arg.value));
    }
    return .{ .start = args_start, .len = @intCast(hir.expr_args.items.len - args_start) };
}

pub fn dumpHir(allocator: Allocator, hir: *const Hir, interner: *const base.Interner) DumpError![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();

    try output.writer.writeAll("HirRoot\n");
    for (hir.decls.items) |decl| {
        switch (decl) {
            .import => |import_decl| {
                try output.writer.print("  Import {s} ", .{@tagName(import_decl.visibility)});
                try dumpPath(&output.writer, hir, interner, import_decl.path);
                if (import_decl.alias) |alias| {
                    try output.writer.print(" as {s}", .{interner.get(alias) orelse "<missing>"});
                }
                try output.writer.writeByte('\n');
            },
            .type_alias => |decl_info| try dumpNamed(&output.writer, interner, "TypeAlias", decl_info),
            .function => |function| {
                try output.writer.print("  Function {s} {s} params={d}\n", .{
                    @tagName(function.visibility),
                    interner.get(function.name) orelse "<missing>",
                    function.params_len,
                });
                try dumpBlock(&output.writer, hir, interner, function.body, 2);
            },
            .struct_decl => |decl_info| try dumpNamed(&output.writer, interner, "Struct", decl_info),
            .enum_decl => |decl_info| try dumpNamed(&output.writer, interner, "Enum", decl_info),
            .impl_decl => |impl_decl| try output.writer.print("  Impl {s} methods={d}\n", .{ @tagName(impl_decl.visibility), impl_decl.methods_len }),
            .interface_decl => |decl_info| try dumpNamed(&output.writer, interner, "Interface", decl_info),
            .test_decl => |test_decl| {
                try output.writer.writeAll("  Test\n");
                try dumpBlock(&output.writer, hir, interner, test_decl.body, 2);
            },
        }
    }

    return output.toOwnedSlice();
}

fn dumpBlock(
    writer: *std.Io.Writer,
    hir: *const Hir,
    interner: *const base.Interner,
    block_id: BlockId,
    indent: usize,
) std.Io.Writer.Error!void {
    try writeIndent(writer, indent);
    try writer.writeAll("Block\n");
    const block = hir.blocks.items[block_id];
    const start: usize = @intCast(block.stmts.start);
    const end: usize = @intCast(block.stmts.end());
    for (hir.block_stmt_ids.items[start..end]) |stmt_id| {
        try dumpStmt(writer, hir, interner, hir.stmts.items[stmt_id], indent + 1);
    }
    if (block.final_expr) |final_expr| {
        try writeIndent(writer, indent + 1);
        try writer.writeAll("FinalExpr\n");
        try dumpExpr(writer, hir, interner, final_expr, indent + 2);
    }
}

fn dumpStmt(
    writer: *std.Io.Writer,
    hir: *const Hir,
    interner: *const base.Interner,
    stmt: Stmt,
    indent: usize,
) std.Io.Writer.Error!void {
    switch (stmt) {
        .let_stmt => |let_stmt| {
            try writeIndent(writer, indent);
            if (let_stmt.name) |name| {
                try writer.print("Let {s}\n", .{interner.get(name) orelse "<missing>"});
            } else {
                try writer.writeAll("LetPattern\n");
            }
            try dumpExpr(writer, hir, interner, let_stmt.value, indent + 1);
        },
        .return_stmt => |return_stmt| {
            try writeIndent(writer, indent);
            try writer.writeAll("Return\n");
            if (return_stmt.value) |value| try dumpExpr(writer, hir, interner, value, indent + 1);
        },
        .expr_stmt => |expr| {
            try writeIndent(writer, indent);
            try writer.writeAll("ExprStmt\n");
            try dumpExpr(writer, hir, interner, expr, indent + 1);
        },
        .unsupported => {
            try writeIndent(writer, indent);
            try writer.writeAll("UnsupportedStmt\n");
        },
    }
}

fn dumpExpr(
    writer: *std.Io.Writer,
    hir: *const Hir,
    interner: *const base.Interner,
    expr_id: ExprId,
    indent: usize,
) std.Io.Writer.Error!void {
    try writeIndent(writer, indent);
    switch (hir.exprs.items[expr_id]) {
        .name => |name| try writer.print("Name {s}\n", .{interner.get(name.symbol) orelse "<missing>"}),
        .int_literal => try writer.writeAll("IntLiteral\n"),
        .float_literal => try writer.writeAll("FloatLiteral\n"),
        .string_literal => try writer.writeAll("StringLiteral\n"),
        .char_literal => try writer.writeAll("CharLiteral\n"),
        .bool_literal => |bool_lit| try writer.print("BoolLiteral {}\n", .{bool_lit.value}),
        .unit_literal => try writer.writeAll("UnitLiteral\n"),
        .binary => |binary| {
            try writer.print("Binary {s}\n", .{@tagName(binary.op)});
            try dumpExpr(writer, hir, interner, binary.left, indent + 1);
            try dumpExpr(writer, hir, interner, binary.right, indent + 1);
        },
        .field => |field| {
            try writer.print("Field {s}\n", .{interner.get(field.name) orelse "<missing>"});
            try dumpExpr(writer, hir, interner, field.base, indent + 1);
        },
        .call => |call| {
            try writer.writeAll("Call\n");
            try dumpExpr(writer, hir, interner, call.callee, indent + 1);
            const start: usize = @intCast(call.args.start);
            const end: usize = @intCast(call.args.end());
            for (hir.expr_args.items[start..end]) |arg| {
                try dumpExpr(writer, hir, interner, arg, indent + 1);
            }
        },
        .unsupported => try writer.writeAll("UnsupportedExpr\n"),
    }
}

fn writeIndent(writer: *std.Io.Writer, indent: usize) std.Io.Writer.Error!void {
    var i: usize = 0;
    while (i < indent) : (i += 1) {
        try writer.writeAll("  ");
    }
}

fn dumpNamed(writer: *std.Io.Writer, interner: *const base.Interner, label: []const u8, decl: NamedDecl) std.Io.Writer.Error!void {
    try writer.print("  {s} {s} {s}\n", .{ label, @tagName(decl.visibility), interner.get(decl.name) orelse "<missing>" });
}

fn dumpPath(writer: *std.Io.Writer, hir: *const Hir, interner: *const base.Interner, path: base.Range) std.Io.Writer.Error!void {
    const start: usize = @intCast(path.start);
    const end: usize = @intCast(path.end());
    for (hir.path_segments.items[start..end], 0..) |segment, index| {
        if (index != 0) try writer.writeByte('.');
        try writer.writeAll(interner.get(segment.name) orelse "<missing>");
    }
}
