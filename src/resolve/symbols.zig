const std = @import("std");
const base = @import("../base.zig");
const diag = @import("../diag.zig");
const hir = @import("../hir.zig");

const Allocator = std.mem.Allocator;
const DumpError = Allocator.Error || std.Io.Writer.Error;

pub const SymbolKind = enum {
    import,
    function,
    type_alias,
    struct_type,
    enum_type,
    interface_type,
};

pub const Symbol = struct {
    name: base.SymbolId,
    kind: SymbolKind,
    span: base.Span,
};

pub const ResolvedModule = struct {
    allocator: Allocator,
    symbols: std.ArrayListUnmanaged(Symbol) = .empty,

    pub fn init(allocator: Allocator) ResolvedModule {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *ResolvedModule) void {
        self.symbols.deinit(self.allocator);
        self.* = undefined;
    }
};

pub fn resolveModule(
    allocator: Allocator,
    module: *const hir.Hir,
    interner: *const base.Interner,
    diagnostics: *diag.DiagnosticBag,
) Allocator.Error!ResolvedModule {
    var resolved = ResolvedModule.init(allocator);
    errdefer resolved.deinit();

    var seen = std.AutoHashMapUnmanaged(base.SymbolId, base.Span){};
    defer seen.deinit(allocator);

    for (module.decls.items) |decl| {
        switch (decl) {
            .import => |import_decl| try addImportSymbols(allocator, module, import_decl, &seen, &resolved, diagnostics),
            else => if (topLevelSymbol(decl)) |symbol| {
                try addSymbol(allocator, symbol, &seen, &resolved, diagnostics);
            },
        }
    }

    try resolveBodies(allocator, module, interner, &seen, diagnostics);

    return resolved;
}

fn addImportSymbols(
    allocator: Allocator,
    module: *const hir.Hir,
    import_decl: hir.ir.ImportDecl,
    seen: *std.AutoHashMapUnmanaged(base.SymbolId, base.Span),
    resolved: *ResolvedModule,
    diagnostics: *diag.DiagnosticBag,
) Allocator.Error!void {
    if (import_decl.items.len == 0) {
        const binding = import_decl.alias orelse finalPathSegment(module, import_decl.path).?.name;
        const span = if (import_decl.alias != null) import_decl.span else finalPathSegment(module, import_decl.path).?.span;
        try addSymbol(allocator, .{ .name = binding, .kind = .import, .span = span }, seen, resolved, diagnostics);
        return;
    }

    const start: usize = @intCast(import_decl.items.start);
    const end: usize = @intCast(import_decl.items.end());
    for (module.import_items.items[start..end]) |item| {
        try addSymbol(allocator, .{
            .name = item.alias orelse item.name,
            .kind = .import,
            .span = item.span,
        }, seen, resolved, diagnostics);
    }
}

fn finalPathSegment(module: *const hir.Hir, path: base.Range) ?hir.ir.PathSegment {
    if (path.len == 0) return null;
    const index: usize = @intCast(path.start + path.len - 1);
    return module.path_segments.items[index];
}

fn addSymbol(
    allocator: Allocator,
    symbol: Symbol,
    seen: *std.AutoHashMapUnmanaged(base.SymbolId, base.Span),
    resolved: *ResolvedModule,
    diagnostics: *diag.DiagnosticBag,
) Allocator.Error!void {
    if (seen.get(symbol.name)) |first_span| {
        try diagnostics.add(.{
            .severity = .err,
            .span = symbol.span,
            .message = "duplicate top-level declaration",
            .labels = &.{.{ .span = first_span, .message = "first declaration is here" }},
        });
        return;
    }

    try seen.put(allocator, symbol.name, symbol.span);
    try resolved.symbols.append(allocator, symbol);
}

fn topLevelSymbol(decl: hir.Decl) ?Symbol {
    return switch (decl) {
        .function => |function| .{ .name = function.name, .kind = .function, .span = function.span },
        .type_alias => |type_alias| .{ .name = type_alias.name, .kind = .type_alias, .span = type_alias.span },
        .struct_decl => |struct_decl| .{ .name = struct_decl.name, .kind = .struct_type, .span = struct_decl.span },
        .enum_decl => |enum_decl| .{ .name = enum_decl.name, .kind = .enum_type, .span = enum_decl.span },
        .interface_decl => |interface_decl| .{ .name = interface_decl.name, .kind = .interface_type, .span = interface_decl.span },
        else => null,
    };
}

fn resolveBodies(
    allocator: Allocator,
    module: *const hir.Hir,
    interner: *const base.Interner,
    top_level: *const std.AutoHashMapUnmanaged(base.SymbolId, base.Span),
    diagnostics: *diag.DiagnosticBag,
) Allocator.Error!void {
    for (module.decls.items) |decl| {
        switch (decl) {
            .function => |function| try resolveFunction(allocator, module, interner, top_level, function, diagnostics),
            .test_decl => |test_decl| {
                var locals = std.AutoHashMapUnmanaged(base.SymbolId, void){};
                defer locals.deinit(allocator);
                try resolveBlock(allocator, module, interner, top_level, &locals, test_decl.body, diagnostics);
            },
            .impl_decl => |impl_decl| {
                const start: usize = @intCast(impl_decl.methods.start);
                const end: usize = @intCast(impl_decl.methods.end());
                for (module.impl_methods.items[start..end]) |method| {
                    try resolveFunction(allocator, module, interner, top_level, method, diagnostics);
                }
            },
            else => {},
        }
    }
}

fn resolveFunction(
    allocator: Allocator,
    module: *const hir.Hir,
    interner: *const base.Interner,
    top_level: *const std.AutoHashMapUnmanaged(base.SymbolId, base.Span),
    function: hir.ir.FunctionDecl,
    diagnostics: *diag.DiagnosticBag,
) Allocator.Error!void {
    var locals = std.AutoHashMapUnmanaged(base.SymbolId, void){};
    defer locals.deinit(allocator);

    const start: usize = @intCast(function.params.start);
    const end: usize = @intCast(function.params.end());
    for (module.fn_params.items[start..end]) |param| {
        try locals.put(allocator, param.name, {});
    }

    try resolveBlock(allocator, module, interner, top_level, &locals, function.body, diagnostics);
}

fn resolveBlock(
    allocator: Allocator,
    module: *const hir.Hir,
    interner: *const base.Interner,
    top_level: *const std.AutoHashMapUnmanaged(base.SymbolId, base.Span),
    locals: *std.AutoHashMapUnmanaged(base.SymbolId, void),
    block_id: hir.ir.BlockId,
    diagnostics: *diag.DiagnosticBag,
) Allocator.Error!void {
    const block = module.blocks.items[block_id];
    const start: usize = @intCast(block.stmts.start);
    const end: usize = @intCast(block.stmts.end());
    for (module.block_stmt_ids.items[start..end]) |stmt_id| {
        try resolveStmt(allocator, module, interner, top_level, locals, module.stmts.items[stmt_id], diagnostics);
    }
    if (block.final_expr) |final_expr| {
        try resolveExpr(allocator, module, interner, top_level, locals, final_expr, diagnostics);
    }
}

fn resolveStmt(
    allocator: Allocator,
    module: *const hir.Hir,
    interner: *const base.Interner,
    top_level: *const std.AutoHashMapUnmanaged(base.SymbolId, base.Span),
    locals: *std.AutoHashMapUnmanaged(base.SymbolId, void),
    stmt: hir.ir.Stmt,
    diagnostics: *diag.DiagnosticBag,
) Allocator.Error!void {
    switch (stmt) {
        .let_stmt => |let_stmt| {
            try resolveExpr(allocator, module, interner, top_level, locals, let_stmt.value, diagnostics);
            if (let_stmt.else_block) |else_block| try resolveBlock(allocator, module, interner, top_level, locals, else_block, diagnostics);
            if (let_stmt.name) |name| try locals.put(allocator, name, {});
        },
        .return_stmt => |return_stmt| if (return_stmt.value) |value| try resolveExpr(allocator, module, interner, top_level, locals, value, diagnostics),
        .while_stmt => |while_stmt| {
            try resolveControlCondition(allocator, module, interner, top_level, locals, while_stmt.condition, diagnostics);
            try resolveBlock(allocator, module, interner, top_level, locals, while_stmt.body, diagnostics);
        },
        .for_stmt => |for_stmt| {
            try resolveExpr(allocator, module, interner, top_level, locals, for_stmt.iterable, diagnostics);
            if (for_stmt.name) |name| try locals.put(allocator, name, {});
            try resolveBlock(allocator, module, interner, top_level, locals, for_stmt.body, diagnostics);
        },
        .defer_stmt => |defer_stmt| try resolveBlock(allocator, module, interner, top_level, locals, defer_stmt.body, diagnostics),
        .expr_stmt => |expr| try resolveExpr(allocator, module, interner, top_level, locals, expr, diagnostics),
        .break_stmt, .continue_stmt, .unsupported => {},
    }
}

fn resolveControlCondition(
    allocator: Allocator,
    module: *const hir.Hir,
    interner: *const base.Interner,
    top_level: *const std.AutoHashMapUnmanaged(base.SymbolId, base.Span),
    locals: *std.AutoHashMapUnmanaged(base.SymbolId, void),
    condition: hir.ir.ControlCondition,
    diagnostics: *diag.DiagnosticBag,
) Allocator.Error!void {
    switch (condition) {
        .expr => |expr| try resolveExpr(allocator, module, interner, top_level, locals, expr, diagnostics),
        .let_pattern => |let_pattern| try resolveExpr(allocator, module, interner, top_level, locals, let_pattern.value, diagnostics),
    }
}

fn resolveExpr(
    allocator: Allocator,
    module: *const hir.Hir,
    interner: *const base.Interner,
    top_level: *const std.AutoHashMapUnmanaged(base.SymbolId, base.Span),
    locals: *std.AutoHashMapUnmanaged(base.SymbolId, void),
    expr_id: hir.ir.ExprId,
    diagnostics: *diag.DiagnosticBag,
) Allocator.Error!void {
    switch (module.exprs.items[expr_id]) {
        .name => |name| {
            if (!locals.contains(name.symbol) and !top_level.contains(name.symbol) and !isPreludeName(interner, name.symbol)) {
                try diagnostics.add(.{ .severity = .err, .span = name.span, .message = "unresolved name" });
            }
        },
        .binary => |binary| {
            try resolveExpr(allocator, module, interner, top_level, locals, binary.left, diagnostics);
            try resolveExpr(allocator, module, interner, top_level, locals, binary.right, diagnostics);
        },
        .field => |field| try resolveExpr(allocator, module, interner, top_level, locals, field.base, diagnostics),
        .call => |call| {
            try resolveExpr(allocator, module, interner, top_level, locals, call.callee, diagnostics);
            const start: usize = @intCast(call.args.start);
            const end: usize = @intCast(call.args.end());
            for (module.expr_args.items[start..end]) |arg| {
                try resolveExpr(allocator, module, interner, top_level, locals, arg, diagnostics);
            }
        },
        .index => |index| {
            try resolveExpr(allocator, module, interner, top_level, locals, index.base, diagnostics);
            try resolveExpr(allocator, module, interner, top_level, locals, index.index, diagnostics);
        },
        .array_literal => |array_literal| {
            const start: usize = @intCast(array_literal.items.start);
            const end: usize = @intCast(array_literal.items.end());
            for (module.expr_args.items[start..end]) |item| try resolveExpr(allocator, module, interner, top_level, locals, item, diagnostics);
        },
        .struct_literal => |literal| {
            try resolveExpr(allocator, module, interner, top_level, locals, literal.type_expr, diagnostics);
            const start: usize = @intCast(literal.fields.start);
            const end: usize = @intCast(literal.fields.end());
            for (module.struct_literal_fields.items[start..end]) |field| if (field.value) |value| try resolveExpr(allocator, module, interner, top_level, locals, value, diagnostics);
        },
        .block_expr => |block_expr| try resolveBlock(allocator, module, interner, top_level, locals, block_expr.block, diagnostics),
        .if_expr => |if_expr| {
            try resolveControlCondition(allocator, module, interner, top_level, locals, if_expr.condition, diagnostics);
            try resolveBlock(allocator, module, interner, top_level, locals, if_expr.then_block, diagnostics);
            if (if_expr.else_block) |else_block| try resolveBlock(allocator, module, interner, top_level, locals, else_block, diagnostics);
        },
        .match_expr => |match_expr| try resolveExpr(allocator, module, interner, top_level, locals, match_expr.value, diagnostics),
        .try_expr => |try_expr| try resolveExpr(allocator, module, interner, top_level, locals, try_expr.value, diagnostics),
        .catch_expr => |catch_expr| try resolveExpr(allocator, module, interner, top_level, locals, catch_expr.value, diagnostics),
        .int_literal, .float_literal, .string_literal, .char_literal, .bool_literal, .unit_literal, .unsupported => {},
    }
}

fn isPreludeName(interner: *const base.Interner, symbol: base.SymbolId) bool {
    const name = interner.get(symbol) orelse return false;
    const prelude = [_][]const u8{ "print", "assert", "panic", "Ok", "Err", "Some", "None" };
    for (prelude) |item| if (std.mem.eql(u8, name, item)) return true;
    return false;
}

pub fn dumpResolvedModule(
    allocator: Allocator,
    resolved: *const ResolvedModule,
    interner: *const base.Interner,
) DumpError![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();

    try output.writer.writeAll("ResolvedModule\n");
    for (resolved.symbols.items) |symbol| {
        try output.writer.print("  Symbol {s} {s}\n", .{
            @tagName(symbol.kind),
            interner.get(symbol.name) orelse "<missing>",
        });
    }

    return output.toOwnedSlice();
}
