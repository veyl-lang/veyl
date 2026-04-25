const std = @import("std");
const base = @import("../base.zig");
const hir = @import("../hir.zig");
const diag = @import("../diag.zig");

const CheckError = std.mem.Allocator.Error;
const TypeEnv = std.AutoHashMapUnmanaged(base.SymbolId, Type);

pub const Type = enum {
    unknown,
    unit,
    bool,
    int,
    float,
    string,
    char,
};

pub fn checkModule(allocator: std.mem.Allocator, module: *const hir.Hir, interner: *const base.Interner, diagnostics: *diag.DiagnosticBag) CheckError!void {
    for (module.decls.items) |decl| {
        switch (decl) {
            .function => |function| try checkFunction(allocator, module, interner, function, diagnostics),
            .test_decl => |test_decl| {
                var env = TypeEnv{};
                defer env.deinit(allocator);
                _ = try checkBlock(allocator, module, &env, test_decl.body, diagnostics);
            },
            .impl_decl => |impl_decl| {
                const start: usize = @intCast(impl_decl.methods.start);
                const end: usize = @intCast(impl_decl.methods.end());
                for (module.impl_methods.items[start..end]) |method| {
                    try checkFunction(allocator, module, interner, method, diagnostics);
                }
            },
            else => {},
        }
    }
}

fn checkFunction(allocator: std.mem.Allocator, module: *const hir.Hir, interner: *const base.Interner, function: hir.ir.FunctionDecl, diagnostics: *diag.DiagnosticBag) CheckError!void {
    var env = TypeEnv{};
    defer env.deinit(allocator);

    const start: usize = @intCast(function.params.start);
    const end: usize = @intCast(function.params.end());
    for (module.fn_params.items[start..end]) |param| {
        try env.put(allocator, param.name, .unknown);
    }

    const actual = try checkBlock(allocator, module, &env, function.body, diagnostics);
    const expected = if (function.return_type) |return_type| typeFromAnnotation(module, interner, return_type) else Type.unit;
    if (expected != .unknown and actual != .unknown and expected != actual) {
        try diagnostics.add(.{
            .severity = .err,
            .span = module.blocks.items[function.body].span,
            .message = "function body type does not match return type",
        });
    }
}

fn checkBlock(allocator: std.mem.Allocator, module: *const hir.Hir, env: *TypeEnv, block_id: hir.ir.BlockId, diagnostics: *diag.DiagnosticBag) CheckError!Type {
    const block = module.blocks.items[block_id];
    const start: usize = @intCast(block.stmts.start);
    const end: usize = @intCast(block.stmts.end());
    for (module.block_stmt_ids.items[start..end]) |stmt_id| {
        try checkStmt(allocator, module, env, module.stmts.items[stmt_id], diagnostics);
    }
    if (block.final_expr) |final_expr| return try inferExpr(allocator, module, env, final_expr, diagnostics);
    return .unit;
}

fn checkStmt(allocator: std.mem.Allocator, module: *const hir.Hir, env: *TypeEnv, stmt: hir.ir.Stmt, diagnostics: *diag.DiagnosticBag) CheckError!void {
    switch (stmt) {
        .let_stmt => |let_stmt| {
            const value_type = try inferExpr(allocator, module, env, let_stmt.value, diagnostics);
            if (let_stmt.else_block) |else_block| _ = try checkBlock(allocator, module, env, else_block, diagnostics);
            if (let_stmt.name) |name| try env.put(allocator, name, value_type);
        },
        .return_stmt => |return_stmt| {
            if (return_stmt.value) |value| _ = try inferExpr(allocator, module, env, value, diagnostics);
        },
        .while_stmt => |while_stmt| {
            try checkCondition(allocator, module, env, while_stmt.condition, diagnostics);
            _ = try checkBlock(allocator, module, env, while_stmt.body, diagnostics);
        },
        .for_stmt => |for_stmt| {
            _ = try inferExpr(allocator, module, env, for_stmt.iterable, diagnostics);
            if (for_stmt.name) |name| try env.put(allocator, name, .unknown);
            _ = try checkBlock(allocator, module, env, for_stmt.body, diagnostics);
        },
        .defer_stmt => |defer_stmt| _ = try checkBlock(allocator, module, env, defer_stmt.body, diagnostics),
        .expr_stmt => |expr| {
            _ = try inferExpr(allocator, module, env, expr, diagnostics);
        },
        .break_stmt, .continue_stmt, .unsupported => {},
    }
}

fn checkCondition(allocator: std.mem.Allocator, module: *const hir.Hir, env: *TypeEnv, condition: hir.ir.ControlCondition, diagnostics: *diag.DiagnosticBag) CheckError!void {
    switch (condition) {
        .expr => |expr| {
            const condition_type = try inferExpr(allocator, module, env, expr, diagnostics);
            if (condition_type != .unknown and condition_type != .bool) {
                try diagnostics.add(.{
                    .severity = .err,
                    .span = exprSpan(module, expr),
                    .message = "condition must be Bool",
                });
            }
        },
        .let_pattern => |let_pattern| {
            _ = try inferExpr(allocator, module, env, let_pattern.value, diagnostics);
        },
    }
}

fn inferExpr(allocator: std.mem.Allocator, module: *const hir.Hir, env: *TypeEnv, expr_id: hir.ir.ExprId, diagnostics: *diag.DiagnosticBag) CheckError!Type {
    return switch (module.exprs.items[expr_id]) {
        .name => |name| env.get(name.symbol) orelse .unknown,
        .int_literal => .int,
        .float_literal => .float,
        .string_literal => .string,
        .char_literal => .char,
        .bool_literal => .bool,
        .unit_literal => .unit,
        .binary => |binary| try inferBinaryExpr(allocator, module, env, binary, diagnostics),
        .if_expr => |if_expr| {
            try checkCondition(allocator, module, env, if_expr.condition, diagnostics);
            _ = try checkBlock(allocator, module, env, if_expr.then_block, diagnostics);
            if (if_expr.else_block) |else_block| _ = try checkBlock(allocator, module, env, else_block, diagnostics);
            return .unknown;
        },
        .block_expr => |block_expr| {
            return try checkBlock(allocator, module, env, block_expr.block, diagnostics);
        },
        .match_expr => |match_expr| {
            _ = try inferExpr(allocator, module, env, match_expr.value, diagnostics);
            return .unknown;
        },
        .try_expr => |try_expr| try inferExpr(allocator, module, env, try_expr.value, diagnostics),
        .catch_expr => |catch_expr| try inferExpr(allocator, module, env, catch_expr.value, diagnostics),
        .array_literal, .struct_literal, .index, .field, .call, .unsupported => .unknown,
    };
}

fn inferBinaryExpr(allocator: std.mem.Allocator, module: *const hir.Hir, env: *TypeEnv, binary: anytype, diagnostics: *diag.DiagnosticBag) CheckError!Type {
    const left_type = try inferExpr(allocator, module, env, binary.left, diagnostics);
    const right_type = try inferExpr(allocator, module, env, binary.right, diagnostics);

    switch (binary.op) {
        .add, .sub, .mul, .div, .rem, .add_assign, .sub_assign, .mul_assign, .div_assign, .rem_assign => {
            if (left_type == .unknown or right_type == .unknown) return .unknown;
            if (!isNumeric(left_type) or !isNumeric(right_type)) {
                try diagnostics.add(.{
                    .severity = .err,
                    .span = binary.span,
                    .message = "arithmetic operands must be numeric",
                });
                return .unknown;
            }
            if (left_type != right_type) {
                try diagnostics.add(.{
                    .severity = .err,
                    .span = binary.span,
                    .message = "arithmetic operands must have matching types",
                });
                return .unknown;
            }
            return left_type;
        },
        .logical_or, .logical_and => {
            if (left_type == .unknown or right_type == .unknown) return .unknown;
            if (left_type != .bool or right_type != .bool) {
                try diagnostics.add(.{
                    .severity = .err,
                    .span = binary.span,
                    .message = "logical operands must be Bool",
                });
                return .unknown;
            }
            return .bool;
        },
        .less, .less_equal, .greater, .greater_equal => {
            if (left_type == .unknown or right_type == .unknown) return .bool;
            if (!isNumeric(left_type) or !isNumeric(right_type) or left_type != right_type) {
                try diagnostics.add(.{
                    .severity = .err,
                    .span = binary.span,
                    .message = "comparison operands must be matching numeric types",
                });
            }
            return .bool;
        },
        .equal, .not_equal => {
            if (left_type != .unknown and right_type != .unknown and left_type != right_type) {
                try diagnostics.add(.{
                    .severity = .err,
                    .span = binary.span,
                    .message = "equality operands must have matching types",
                });
            }
            return .bool;
        },
        .assign => return left_type,
    }
}

fn isNumeric(value_type: Type) bool {
    return value_type == .int or value_type == .float;
}

fn typeFromAnnotation(module: *const hir.Hir, interner: *const base.Interner, type_id: hir.ir.TypeId) Type {
    return switch (module.types.items[type_id]) {
        .unit => .unit,
        .path => |path| {
            if (path.args.len != 0 or path.segments.len != 1) return .unknown;
            const segment = module.path_segments.items[path.segments.start];
            const name = interner.get(segment.name) orelse return .unknown;
            if (std.mem.eql(u8, name, "Bool")) return .bool;
            if (std.mem.eql(u8, name, "Int")) return .int;
            if (std.mem.eql(u8, name, "Float")) return .float;
            if (std.mem.eql(u8, name, "Str")) return .string;
            if (std.mem.eql(u8, name, "Char")) return .char;
            return .unknown;
        },
    };
}

fn exprSpan(module: *const hir.Hir, expr_id: hir.ir.ExprId) @import("../base.zig").Span {
    return switch (module.exprs.items[expr_id]) {
        .name => |expr| expr.span,
        .int_literal => |span| span,
        .float_literal => |span| span,
        .string_literal => |span| span,
        .char_literal => |span| span,
        .bool_literal => |expr| expr.span,
        .unit_literal => |span| span,
        .binary => |expr| expr.span,
        .field => |expr| expr.span,
        .call => |expr| expr.span,
        .index => |expr| expr.span,
        .array_literal => |expr| expr.span,
        .struct_literal => |expr| expr.span,
        .block_expr => |expr| expr.span,
        .if_expr => |expr| expr.span,
        .match_expr => |expr| expr.span,
        .try_expr => |expr| expr.span,
        .catch_expr => |expr| expr.span,
        .unsupported => |span| span,
    };
}
