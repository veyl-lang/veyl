const std = @import("std");
const hir = @import("../hir.zig");
const diag = @import("../diag.zig");

const CheckError = std.mem.Allocator.Error;

pub const Type = enum {
    unknown,
    unit,
    bool,
    int,
    float,
    string,
    char,
};

pub fn checkModule(module: *const hir.Hir, diagnostics: *diag.DiagnosticBag) CheckError!void {
    for (module.decls.items) |decl| {
        switch (decl) {
            .function => |function| try checkBlock(module, function.body, diagnostics),
            .test_decl => |test_decl| try checkBlock(module, test_decl.body, diagnostics),
            .impl_decl => |impl_decl| {
                const start: usize = @intCast(impl_decl.methods.start);
                const end: usize = @intCast(impl_decl.methods.end());
                for (module.impl_methods.items[start..end]) |method| {
                    try checkBlock(module, method.body, diagnostics);
                }
            },
            else => {},
        }
    }
}

fn checkBlock(module: *const hir.Hir, block_id: hir.ir.BlockId, diagnostics: *diag.DiagnosticBag) CheckError!void {
    const block = module.blocks.items[block_id];
    const start: usize = @intCast(block.stmts.start);
    const end: usize = @intCast(block.stmts.end());
    for (module.block_stmt_ids.items[start..end]) |stmt_id| {
        try checkStmt(module, module.stmts.items[stmt_id], diagnostics);
    }
    if (block.final_expr) |final_expr| _ = try inferExpr(module, final_expr, diagnostics);
}

fn checkStmt(module: *const hir.Hir, stmt: hir.ir.Stmt, diagnostics: *diag.DiagnosticBag) CheckError!void {
    switch (stmt) {
        .let_stmt => |let_stmt| {
            _ = try inferExpr(module, let_stmt.value, diagnostics);
            if (let_stmt.else_block) |else_block| try checkBlock(module, else_block, diagnostics);
        },
        .return_stmt => |return_stmt| {
            if (return_stmt.value) |value| _ = try inferExpr(module, value, diagnostics);
        },
        .while_stmt => |while_stmt| {
            try checkCondition(module, while_stmt.condition, diagnostics);
            try checkBlock(module, while_stmt.body, diagnostics);
        },
        .for_stmt => |for_stmt| {
            _ = try inferExpr(module, for_stmt.iterable, diagnostics);
            try checkBlock(module, for_stmt.body, diagnostics);
        },
        .defer_stmt => |defer_stmt| try checkBlock(module, defer_stmt.body, diagnostics),
        .expr_stmt => |expr| {
            _ = try inferExpr(module, expr, diagnostics);
        },
        .break_stmt, .continue_stmt, .unsupported => {},
    }
}

fn checkCondition(module: *const hir.Hir, condition: hir.ir.ControlCondition, diagnostics: *diag.DiagnosticBag) CheckError!void {
    switch (condition) {
        .expr => |expr| {
            const condition_type = try inferExpr(module, expr, diagnostics);
            if (condition_type != .unknown and condition_type != .bool) {
                try diagnostics.add(.{
                    .severity = .err,
                    .span = exprSpan(module, expr),
                    .message = "condition must be Bool",
                });
            }
        },
        .let_pattern => |let_pattern| {
            _ = try inferExpr(module, let_pattern.value, diagnostics);
        },
    }
}

fn inferExpr(module: *const hir.Hir, expr_id: hir.ir.ExprId, diagnostics: *diag.DiagnosticBag) CheckError!Type {
    return switch (module.exprs.items[expr_id]) {
        .int_literal => .int,
        .float_literal => .float,
        .string_literal => .string,
        .char_literal => .char,
        .bool_literal => .bool,
        .unit_literal => .unit,
        .binary => |binary| try inferBinaryExpr(module, binary, diagnostics),
        .if_expr => |if_expr| {
            try checkCondition(module, if_expr.condition, diagnostics);
            try checkBlock(module, if_expr.then_block, diagnostics);
            if (if_expr.else_block) |else_block| try checkBlock(module, else_block, diagnostics);
            return .unknown;
        },
        .block_expr => |block_expr| {
            try checkBlock(module, block_expr.block, diagnostics);
            return .unknown;
        },
        .match_expr => |match_expr| {
            _ = try inferExpr(module, match_expr.value, diagnostics);
            return .unknown;
        },
        .try_expr => |try_expr| try inferExpr(module, try_expr.value, diagnostics),
        .catch_expr => |catch_expr| try inferExpr(module, catch_expr.value, diagnostics),
        .array_literal, .struct_literal, .index, .field, .call, .name, .unsupported => .unknown,
    };
}

fn inferBinaryExpr(module: *const hir.Hir, binary: anytype, diagnostics: *diag.DiagnosticBag) CheckError!Type {
    const left_type = try inferExpr(module, binary.left, diagnostics);
    const right_type = try inferExpr(module, binary.right, diagnostics);

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
