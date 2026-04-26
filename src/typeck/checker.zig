const std = @import("std");
const base = @import("../base.zig");
const hir = @import("../hir.zig");
const diag = @import("../diag.zig");

const CheckError = std.mem.Allocator.Error;
const TypeEnv = std.AutoHashMapUnmanaged(base.SymbolId, LocalInfo);
const FunctionEnv = std.AutoHashMapUnmanaged(base.SymbolId, hir.ir.FunctionDecl);
const StructEnv = std.AutoHashMapUnmanaged(base.SymbolId, hir.ir.StructDecl);

const LocalInfo = struct {
    type: Type,
    is_mut: bool,
};

pub const Type = enum {
    unknown,
    unit,
    bool,
    int,
    float,
    string,
    char,
    array,
};

pub fn checkModule(allocator: std.mem.Allocator, module: *const hir.Hir, interner: *const base.Interner, diagnostics: *diag.DiagnosticBag) CheckError!void {
    var functions = FunctionEnv{};
    defer functions.deinit(allocator);
    var structs = StructEnv{};
    defer structs.deinit(allocator);

    for (module.decls.items) |decl| {
        switch (decl) {
            .function => |function| try functions.put(allocator, function.name, function),
            .struct_decl => |struct_decl| try structs.put(allocator, struct_decl.name, struct_decl),
            .impl_decl => |impl_decl| {
                const start: usize = @intCast(impl_decl.methods.start);
                const end: usize = @intCast(impl_decl.methods.end());
                for (module.impl_methods.items[start..end]) |method| {
                    try functions.put(allocator, method.name, method);
                }
            },
            else => {},
        }
    }

    for (module.decls.items) |decl| {
        switch (decl) {
            .function => |function| try checkFunction(allocator, module, interner, &functions, &structs, function, diagnostics),
            .test_decl => |test_decl| {
                var env = TypeEnv{};
                defer env.deinit(allocator);
                _ = try checkBlock(allocator, module, interner, &functions, &structs, &env, test_decl.body, .unit, diagnostics);
            },
            .impl_decl => |impl_decl| {
                const start: usize = @intCast(impl_decl.methods.start);
                const end: usize = @intCast(impl_decl.methods.end());
                for (module.impl_methods.items[start..end]) |method| {
                    try checkFunction(allocator, module, interner, &functions, &structs, method, diagnostics);
                }
            },
            else => {},
        }
    }
}

fn checkFunction(allocator: std.mem.Allocator, module: *const hir.Hir, interner: *const base.Interner, functions: *const FunctionEnv, structs: *const StructEnv, function: hir.ir.FunctionDecl, diagnostics: *diag.DiagnosticBag) CheckError!void {
    var env = TypeEnv{};
    defer env.deinit(allocator);

    const start: usize = @intCast(function.params.start);
    const end: usize = @intCast(function.params.end());
    for (module.fn_params.items[start..end]) |param| {
        try env.put(allocator, param.name, .{ .type = typeFromAnnotation(module, interner, param.type_expr), .is_mut = param.is_mut });
    }

    const expected = if (function.return_type) |return_type| typeFromAnnotation(module, interner, return_type) else Type.unit;
    const actual = try checkBlock(allocator, module, interner, functions, structs, &env, function.body, expected, diagnostics);
    if (expected != .unknown and actual != .unknown and expected != actual) {
        try diagnostics.add(.{
            .severity = .err,
            .span = module.blocks.items[function.body].span,
            .message = "function body type does not match return type",
        });
    }
}

fn checkBlock(allocator: std.mem.Allocator, module: *const hir.Hir, interner: *const base.Interner, functions: *const FunctionEnv, structs: *const StructEnv, env: *TypeEnv, block_id: hir.ir.BlockId, expected_return: Type, diagnostics: *diag.DiagnosticBag) CheckError!Type {
    const block = module.blocks.items[block_id];
    const start: usize = @intCast(block.stmts.start);
    const end: usize = @intCast(block.stmts.end());
    for (module.block_stmt_ids.items[start..end]) |stmt_id| {
        try checkStmt(allocator, module, interner, functions, structs, env, module.stmts.items[stmt_id], expected_return, diagnostics);
    }
    if (block.final_expr) |final_expr| return try inferExpr(allocator, module, interner, functions, structs, env, final_expr, expected_return, diagnostics);
    if (block.stmts.len != 0) {
        const last_stmt_id = module.block_stmt_ids.items[end - 1];
        if (module.stmts.items[last_stmt_id] == .return_stmt) return expected_return;
    }
    return .unit;
}

fn checkStmt(allocator: std.mem.Allocator, module: *const hir.Hir, interner: *const base.Interner, functions: *const FunctionEnv, structs: *const StructEnv, env: *TypeEnv, stmt: hir.ir.Stmt, expected_return: Type, diagnostics: *diag.DiagnosticBag) CheckError!void {
    switch (stmt) {
        .let_stmt => |let_stmt| {
            const value_type = try inferExpr(allocator, module, interner, functions, structs, env, let_stmt.value, expected_return, diagnostics);
            if (let_stmt.else_block) |else_block| _ = try checkBlock(allocator, module, interner, functions, structs, env, else_block, expected_return, diagnostics);
            if (let_stmt.name) |name| try env.put(allocator, name, .{ .type = value_type, .is_mut = bindingIsMut(module, let_stmt.pattern) });
        },
        .return_stmt => |return_stmt| {
            const actual = if (return_stmt.value) |value| try inferExpr(allocator, module, interner, functions, structs, env, value, expected_return, diagnostics) else Type.unit;
            if (expected_return != .unknown and actual != .unknown and expected_return != actual) {
                try diagnostics.add(.{
                    .severity = .err,
                    .span = return_stmt.span,
                    .message = "return value type does not match function return type",
                });
            }
        },
        .while_stmt => |while_stmt| {
            try checkCondition(allocator, module, interner, functions, structs, env, while_stmt.condition, expected_return, diagnostics);
            _ = try checkBlock(allocator, module, interner, functions, structs, env, while_stmt.body, expected_return, diagnostics);
        },
        .for_stmt => |for_stmt| {
            _ = try inferExpr(allocator, module, interner, functions, structs, env, for_stmt.iterable, expected_return, diagnostics);
            if (for_stmt.name) |name| try env.put(allocator, name, .{ .type = .unknown, .is_mut = bindingIsMut(module, for_stmt.pattern) });
            _ = try checkBlock(allocator, module, interner, functions, structs, env, for_stmt.body, expected_return, diagnostics);
        },
        .defer_stmt => |defer_stmt| _ = try checkBlock(allocator, module, interner, functions, structs, env, defer_stmt.body, expected_return, diagnostics),
        .expr_stmt => |expr| {
            _ = try inferExpr(allocator, module, interner, functions, structs, env, expr, expected_return, diagnostics);
        },
        .break_stmt, .continue_stmt, .unsupported => {},
    }
}

fn checkCondition(allocator: std.mem.Allocator, module: *const hir.Hir, interner: *const base.Interner, functions: *const FunctionEnv, structs: *const StructEnv, env: *TypeEnv, condition: hir.ir.ControlCondition, expected_return: Type, diagnostics: *diag.DiagnosticBag) CheckError!void {
    switch (condition) {
        .expr => |expr| {
            const condition_type = try inferExpr(allocator, module, interner, functions, structs, env, expr, expected_return, diagnostics);
            if (condition_type != .unknown and condition_type != .bool) {
                try diagnostics.add(.{
                    .severity = .err,
                    .span = exprSpan(module, expr),
                    .message = "condition must be Bool",
                });
            }
        },
        .let_pattern => |let_pattern| {
            _ = try inferExpr(allocator, module, interner, functions, structs, env, let_pattern.value, expected_return, diagnostics);
        },
    }
}

fn inferExpr(allocator: std.mem.Allocator, module: *const hir.Hir, interner: *const base.Interner, functions: *const FunctionEnv, structs: *const StructEnv, env: *TypeEnv, expr_id: hir.ir.ExprId, expected_return: Type, diagnostics: *diag.DiagnosticBag) CheckError!Type {
    return switch (module.exprs.items[expr_id]) {
        .name => |name| if (env.get(name.symbol)) |local| local.type else .unknown,
        .int_literal => .int,
        .float_literal => .float,
        .string_literal => .string,
        .char_literal => .char,
        .bool_literal => .bool,
        .unit_literal => .unit,
        .binary => |binary| try inferBinaryExpr(allocator, module, interner, functions, structs, env, binary, expected_return, diagnostics),
        .if_expr => |if_expr| try inferIfExpr(allocator, module, interner, functions, structs, env, if_expr, expected_return, diagnostics),
        .block_expr => |block_expr| {
            return try checkBlock(allocator, module, interner, functions, structs, env, block_expr.block, expected_return, diagnostics);
        },
        .match_expr => |match_expr| {
            _ = try inferExpr(allocator, module, interner, functions, structs, env, match_expr.value, expected_return, diagnostics);
            return .unknown;
        },
        .try_expr => |try_expr| try inferExpr(allocator, module, interner, functions, structs, env, try_expr.value, expected_return, diagnostics),
        .catch_expr => |catch_expr| try inferExpr(allocator, module, interner, functions, structs, env, catch_expr.value, expected_return, diagnostics),
        .call => |call| try inferCallExpr(allocator, module, interner, functions, structs, env, call, expected_return, diagnostics),
        .array_literal => |array_literal| try inferArrayLiteral(allocator, module, interner, functions, structs, env, array_literal, expected_return, diagnostics),
        .index => |index| try inferIndexExpr(allocator, module, interner, functions, structs, env, index, expected_return, diagnostics),
        .struct_literal => |literal| try inferStructLiteral(allocator, module, interner, functions, structs, env, literal, expected_return, diagnostics),
        .field, .unsupported => .unknown,
    };
}

fn inferArrayLiteral(
    allocator: std.mem.Allocator,
    module: *const hir.Hir,
    interner: *const base.Interner,
    functions: *const FunctionEnv,
    structs: *const StructEnv,
    env: *TypeEnv,
    array_literal: anytype,
    expected_return: Type,
    diagnostics: *diag.DiagnosticBag,
) CheckError!Type {
    var element_type = Type.unknown;
    const start: usize = @intCast(array_literal.items.start);
    const end: usize = @intCast(array_literal.items.end());
    for (module.expr_args.items[start..end]) |item| {
        const item_type = try inferExpr(allocator, module, interner, functions, structs, env, item, expected_return, diagnostics);
        if (item_type == .unknown) continue;
        if (element_type == .unknown) {
            element_type = item_type;
        } else if (element_type != item_type) {
            try diagnostics.add(.{
                .severity = .err,
                .span = exprSpan(module, item),
                .message = "array elements must have matching types",
            });
        }
    }
    return .array;
}

fn inferIndexExpr(
    allocator: std.mem.Allocator,
    module: *const hir.Hir,
    interner: *const base.Interner,
    functions: *const FunctionEnv,
    structs: *const StructEnv,
    env: *TypeEnv,
    index: anytype,
    expected_return: Type,
    diagnostics: *diag.DiagnosticBag,
) CheckError!Type {
    const base_type = try inferExpr(allocator, module, interner, functions, structs, env, index.base, expected_return, diagnostics);
    const index_type = try inferExpr(allocator, module, interner, functions, structs, env, index.index, expected_return, diagnostics);
    if (base_type != .unknown and base_type != .array) {
        try diagnostics.add(.{
            .severity = .err,
            .span = exprSpan(module, index.base),
            .message = "index base must be an array",
        });
    }
    if (index_type != .unknown and index_type != .int) {
        try diagnostics.add(.{
            .severity = .err,
            .span = exprSpan(module, index.index),
            .message = "array index must be Int",
        });
    }
    return .unknown;
}

fn inferStructLiteral(
    allocator: std.mem.Allocator,
    module: *const hir.Hir,
    interner: *const base.Interner,
    functions: *const FunctionEnv,
    structs: *const StructEnv,
    env: *TypeEnv,
    literal: anytype,
    expected_return: Type,
    diagnostics: *diag.DiagnosticBag,
) CheckError!Type {
    const decl = switch (module.exprs.items[literal.type_expr]) {
        .name => |name| structs.get(name.symbol) orelse return .unknown,
        else => return .unknown,
    };

    const start: usize = @intCast(literal.fields.start);
    const end: usize = @intCast(literal.fields.end());
    for (module.struct_literal_fields.items[start..end]) |field| {
        const struct_field = findStructField(module, decl, field.name) orelse {
            try diagnostics.add(.{
                .severity = .err,
                .span = field.span,
                .message = "unknown struct field",
            });
            continue;
        };

        if (field.value) |value| {
            const actual = try inferExpr(allocator, module, interner, functions, structs, env, value, expected_return, diagnostics);
            const expected = typeFromAnnotation(module, interner, struct_field.type_expr);
            if (expected != .unknown and actual != .unknown and expected != actual) {
                try diagnostics.add(.{
                    .severity = .err,
                    .span = exprSpan(module, value),
                    .message = "struct field value type mismatch",
                });
            }
        }
    }

    return .unknown;
}

fn inferIfExpr(
    allocator: std.mem.Allocator,
    module: *const hir.Hir,
    interner: *const base.Interner,
    functions: *const FunctionEnv,
    structs: *const StructEnv,
    env: *TypeEnv,
    if_expr: anytype,
    expected_return: Type,
    diagnostics: *diag.DiagnosticBag,
) CheckError!Type {
    try checkCondition(allocator, module, interner, functions, structs, env, if_expr.condition, expected_return, diagnostics);
    const then_type = try checkBlock(allocator, module, interner, functions, structs, env, if_expr.then_block, expected_return, diagnostics);
    const else_type = if (if_expr.else_block) |else_block|
        try checkBlock(allocator, module, interner, functions, structs, env, else_block, expected_return, diagnostics)
    else
        Type.unit;

    if (then_type == .unknown or else_type == .unknown) return .unknown;
    if (then_type != else_type) {
        try diagnostics.add(.{
            .severity = .err,
            .span = if_expr.span,
            .message = "if branch types must match",
        });
        return .unknown;
    }
    return then_type;
}

fn inferBinaryExpr(allocator: std.mem.Allocator, module: *const hir.Hir, interner: *const base.Interner, functions: *const FunctionEnv, structs: *const StructEnv, env: *TypeEnv, binary: anytype, expected_return: Type, diagnostics: *diag.DiagnosticBag) CheckError!Type {
    const left_type = try inferExpr(allocator, module, interner, functions, structs, env, binary.left, expected_return, diagnostics);
    const right_type = try inferExpr(allocator, module, interner, functions, structs, env, binary.right, expected_return, diagnostics);

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
        .assign => {
            switch (module.exprs.items[binary.left]) {
                .name => |name| {
                    if (env.get(name.symbol)) |local| {
                        if (!local.is_mut) {
                            try diagnostics.add(.{
                                .severity = .err,
                                .span = exprSpan(module, binary.left),
                                .message = "cannot assign to immutable binding",
                            });
                        }
                    }
                },
                else => {},
            }
            if (left_type != .unknown and right_type != .unknown and left_type != right_type) {
                try diagnostics.add(.{
                    .severity = .err,
                    .span = exprSpan(module, binary.right),
                    .message = "assignment value type mismatch",
                });
                return .unknown;
            }
            return left_type;
        },
    }
}

fn inferCallExpr(
    allocator: std.mem.Allocator,
    module: *const hir.Hir,
    interner: *const base.Interner,
    functions: *const FunctionEnv,
    structs: *const StructEnv,
    env: *TypeEnv,
    call: anytype,
    expected_return: Type,
    diagnostics: *diag.DiagnosticBag,
) CheckError!Type {
    switch (module.exprs.items[call.callee]) {
        .name => |callee| {
            const function = functions.get(callee.symbol) orelse return .unknown;
            if (function.params.len != call.args.len) {
                try diagnostics.add(.{
                    .severity = .err,
                    .span = call.span,
                    .message = "function argument count mismatch",
                });
                return .unknown;
            }

            const arg_start: usize = @intCast(call.args.start);
            const arg_end: usize = @intCast(call.args.end());
            const param_start: usize = @intCast(function.params.start);
            for (module.expr_args.items[arg_start..arg_end], module.fn_params.items[param_start .. param_start + call.args.len]) |arg, param| {
                const actual = try inferExpr(allocator, module, interner, functions, structs, env, arg, expected_return, diagnostics);
                const expected = typeFromAnnotation(module, interner, param.type_expr);
                if (expected != .unknown and actual != .unknown and expected != actual) {
                    try diagnostics.add(.{
                        .severity = .err,
                        .span = exprSpan(module, arg),
                        .message = "function argument type mismatch",
                    });
                }
            }

            return if (function.return_type) |return_type| typeFromAnnotation(module, interner, return_type) else .unit;
        },
        else => return .unknown,
    }
}

fn findStructField(module: *const hir.Hir, decl: hir.ir.StructDecl, name: base.SymbolId) ?hir.ir.StructField {
    const start: usize = @intCast(decl.fields.start);
    const end: usize = @intCast(decl.fields.end());
    for (module.struct_fields.items[start..end]) |field| {
        if (field.name == name) return field;
    }
    return null;
}

fn bindingIsMut(module: *const hir.Hir, pattern_id: hir.ir.PatternId) bool {
    return switch (module.patterns.items[pattern_id]) {
        .binding => |binding| binding.is_mut,
        else => false,
    };
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
