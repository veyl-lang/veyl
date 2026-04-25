const std = @import("std");
const base = @import("../base.zig");
const hir = @import("../hir.zig");

const Allocator = std.mem.Allocator;
const DumpError = Allocator.Error || std.Io.Writer.Error;

pub const Op = enum {
    constant_int,
    constant_float,
    constant_string,
    constant_char,
    constant_bool,
    unit,
    load_local,
    store_local,
    get_name,
    get_field,
    call,
    call_function,
    add,
    sub,
    mul,
    div,
    rem,
    equal,
    not_equal,
    less,
    less_equal,
    greater,
    greater_equal,
    logical_and,
    logical_or,
    assign,
    jump,
    jump_if_false,
    pop,
    ret,
    unsupported,
};

pub const Instruction = struct {
    op: Op,
    operand: u32 = 0,
};

pub const Function = struct {
    name: base.SymbolId,
    params: base.Range,
    code: base.Range,
    local_count: u32,
};

pub const StringConstant = struct {
    bytes: []const u8,
};

const CompileContext = struct {
    bytecode: *BytecodeModule,
    module: *const hir.Hir,
    source: []const u8,
    locals: std.AutoHashMapUnmanaged(base.SymbolId, u32) = .empty,
    break_patches: std.ArrayListUnmanaged(u32) = .empty,
    continue_target: ?u32 = null,
    local_count: u32 = 0,

    fn deinit(self: *CompileContext) void {
        self.locals.deinit(self.bytecode.allocator);
        self.break_patches.deinit(self.bytecode.allocator);
    }

    fn localSlot(self: *CompileContext, name: base.SymbolId) CompileError!u32 {
        if (self.locals.get(name)) |slot| return slot;
        const slot = self.local_count;
        self.local_count += 1;
        try self.locals.put(self.bytecode.allocator, name, slot);
        return slot;
    }
};

pub const BytecodeModule = struct {
    allocator: Allocator,
    functions: std.ArrayListUnmanaged(Function) = .empty,
    function_names: std.AutoHashMapUnmanaged(base.SymbolId, u32) = .empty,
    entry_function: u32 = 0,
    instructions: std.ArrayListUnmanaged(Instruction) = .empty,
    int_constants: std.ArrayListUnmanaged(i64) = .empty,
    string_constants: std.ArrayListUnmanaged(StringConstant) = .empty,

    pub fn init(allocator: Allocator) BytecodeModule {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *BytecodeModule) void {
        self.functions.deinit(self.allocator);
        self.function_names.deinit(self.allocator);
        self.instructions.deinit(self.allocator);
        self.int_constants.deinit(self.allocator);
        self.string_constants.deinit(self.allocator);
        self.* = undefined;
    }
};

pub const CompileError = Allocator.Error || error{InvalidIntegerLiteral};

pub fn compileHir(allocator: Allocator, module: *const hir.Hir, source: []const u8, interner: *const base.Interner) CompileError!BytecodeModule {
    var bytecode = BytecodeModule.init(allocator);
    errdefer bytecode.deinit();

    try predeclareFunctions(&bytecode, module, interner);

    for (module.decls.items) |decl| {
        switch (decl) {
            .function => |function| try compileFunction(&bytecode, module, source, function),
            .impl_decl => |impl_decl| {
                const start: usize = @intCast(impl_decl.methods.start);
                const end: usize = @intCast(impl_decl.methods.end());
                for (module.impl_methods.items[start..end]) |method| {
                    try compileFunction(&bytecode, module, source, method);
                }
            },
            else => {},
        }
    }

    return bytecode;
}

fn predeclareFunctions(bytecode: *BytecodeModule, module: *const hir.Hir, interner: *const base.Interner) Allocator.Error!void {
    for (module.decls.items) |decl| {
        switch (decl) {
            .function => |function| {
                const index: u32 = @intCast(bytecode.function_names.count());
                try bytecode.function_names.put(bytecode.allocator, function.name, index);
                if (std.mem.eql(u8, interner.get(function.name) orelse "", "main")) bytecode.entry_function = index;
            },
            .impl_decl => |impl_decl| {
                const start: usize = @intCast(impl_decl.methods.start);
                const end: usize = @intCast(impl_decl.methods.end());
                for (module.impl_methods.items[start..end]) |method| {
                    try bytecode.function_names.put(bytecode.allocator, method.name, @intCast(bytecode.function_names.count()));
                }
            },
            else => {},
        }
    }
}

fn compileFunction(bytecode: *BytecodeModule, module: *const hir.Hir, source: []const u8, function: hir.ir.FunctionDecl) CompileError!void {
    var context = CompileContext{ .bytecode = bytecode, .module = module, .source = source };
    defer context.deinit();

    const params_start: usize = @intCast(function.params.start);
    const params_end: usize = @intCast(function.params.end());
    for (module.fn_params.items[params_start..params_end]) |param| {
        _ = try context.localSlot(param.name);
    }

    const code_start: u32 = @intCast(bytecode.instructions.items.len);
    try compileBlock(&context, function.body, true);
    try bytecode.functions.append(bytecode.allocator, .{
        .name = function.name,
        .params = function.params,
        .code = .{ .start = code_start, .len = @intCast(bytecode.instructions.items.len - code_start) },
        .local_count = context.local_count,
    });
}

fn compileBlock(context: *CompileContext, block_id: hir.ir.BlockId, returns: bool) CompileError!void {
    const bytecode = context.bytecode;
    const module = context.module;
    const block = module.blocks.items[block_id];
    const start: usize = @intCast(block.stmts.start);
    const end: usize = @intCast(block.stmts.end());
    for (module.block_stmt_ids.items[start..end]) |stmt_id| {
        if (try compileStmt(context, module.stmts.items[stmt_id])) return;
    }

    if (!returns) return;
    if (block.final_expr) |final_expr| {
        try compileExpr(context, final_expr);
    } else {
        try emit(bytecode, .unit, 0);
    }
    try emit(bytecode, .ret, 0);
}

fn compileStmt(context: *CompileContext, stmt: hir.ir.Stmt) CompileError!bool {
    const bytecode = context.bytecode;
    switch (stmt) {
        .let_stmt => |let_stmt| {
            try compileExpr(context, let_stmt.value);
            if (let_stmt.name) |name| {
                try emit(bytecode, .store_local, try context.localSlot(name));
            } else {
                try emit(bytecode, .pop, 0);
            }
            return false;
        },
        .return_stmt => |return_stmt| {
            if (return_stmt.value) |value| {
                try compileExpr(context, value);
            } else {
                try emit(bytecode, .unit, 0);
            }
            try emit(bytecode, .ret, 0);
            return true;
        },
        .expr_stmt => |expr| {
            try compileExpr(context, expr);
            try emit(bytecode, .pop, 0);
            return false;
        },
        .while_stmt => |while_stmt| {
            const loop_start: u32 = @intCast(bytecode.instructions.items.len);
            const outer_continue = context.continue_target;
            const break_start = context.break_patches.items.len;
            context.continue_target = loop_start;
            defer context.continue_target = outer_continue;

            try compileControlCondition(context, while_stmt.condition);
            const jump_to_end = bytecode.instructions.items.len;
            try emit(bytecode, .jump_if_false, 0);
            try compileBlock(context, while_stmt.body, false);
            try emit(bytecode, .jump, loop_start);
            bytecode.instructions.items[jump_to_end].operand = @intCast(bytecode.instructions.items.len);
            for (context.break_patches.items[break_start..]) |patch| {
                bytecode.instructions.items[patch].operand = @intCast(bytecode.instructions.items.len);
            }
            context.break_patches.shrinkRetainingCapacity(break_start);
            return false;
        },
        .break_stmt => {
            const patch: u32 = @intCast(bytecode.instructions.items.len);
            try emit(bytecode, .jump, 0);
            try context.break_patches.append(bytecode.allocator, patch);
            return false;
        },
        .continue_stmt => {
            try emit(bytecode, .jump, context.continue_target orelse 0);
            return false;
        },
        else => {
            try emit(bytecode, .unsupported, 0);
            return false;
        },
    }
}

fn compileExpr(context: *CompileContext, expr_id: hir.ir.ExprId) CompileError!void {
    const bytecode = context.bytecode;
    const module = context.module;
    switch (module.exprs.items[expr_id]) {
        .int_literal => |span| try emitIntConstant(bytecode, context.source, span),
        .float_literal => try emit(bytecode, .constant_float, 0),
        .string_literal => |span| try emitStringConstant(bytecode, context.source, span),
        .char_literal => try emit(bytecode, .constant_char, 0),
        .bool_literal => |bool_literal| try emit(bytecode, .constant_bool, if (bool_literal.value) 1 else 0),
        .unit_literal => try emit(bytecode, .unit, 0),
        .name => |name| {
            if (context.locals.get(name.symbol)) |slot| {
                try emit(bytecode, .load_local, slot);
            } else {
                try emit(bytecode, .get_name, name.symbol);
            }
        },
        .field => |field| {
            try compileExpr(context, field.base);
            try emit(bytecode, .get_field, field.name);
        },
        .binary => |binary| try compileBinaryExpr(context, binary),
        .call => |call| {
            switch (module.exprs.items[call.callee]) {
                .name => |callee| {
                    if (bytecode.function_names.get(callee.symbol)) |function_index| {
                        const start: usize = @intCast(call.args.start);
                        const end: usize = @intCast(call.args.end());
                        for (module.expr_args.items[start..end]) |arg| {
                            try compileExpr(context, arg);
                        }
                        try emit(bytecode, .call_function, function_index);
                        return;
                    }
                },
                else => {},
            }
            try compileExpr(context, call.callee);
            const start: usize = @intCast(call.args.start);
            const end: usize = @intCast(call.args.end());
            for (module.expr_args.items[start..end]) |arg| {
                try compileExpr(context, arg);
            }
            try emit(bytecode, .call, call.args.len);
        },
        .if_expr => |if_expr| try compileIfExpr(context, if_expr),
        else => try emit(bytecode, .unsupported, 0),
    }
}

fn compileIfExpr(context: *CompileContext, if_expr: anytype) CompileError!void {
    const bytecode = context.bytecode;
    try compileControlCondition(context, if_expr.condition);
    const jump_to_else = bytecode.instructions.items.len;
    try emit(bytecode, .jump_if_false, 0);
    try compileBlockValue(context, if_expr.then_block);
    const jump_to_end = bytecode.instructions.items.len;
    try emit(bytecode, .jump, 0);
    bytecode.instructions.items[jump_to_else].operand = @intCast(bytecode.instructions.items.len);
    if (if_expr.else_block) |else_block| {
        try compileBlockValue(context, else_block);
    } else {
        try emit(bytecode, .unit, 0);
    }
    bytecode.instructions.items[jump_to_end].operand = @intCast(bytecode.instructions.items.len);
}

fn compileBinaryExpr(context: *CompileContext, binary: anytype) CompileError!void {
    const bytecode = context.bytecode;
    const module = context.module;
    if (binary.op == .assign) {
        switch (module.exprs.items[binary.left]) {
            .name => |name| {
                if (context.locals.get(name.symbol)) |slot| {
                    try compileExpr(context, binary.right);
                    try emit(bytecode, .store_local, slot);
                    try emit(bytecode, .load_local, slot);
                    return;
                }
            },
            else => {},
        }
    }

    try compileExpr(context, binary.left);
    try compileExpr(context, binary.right);
    try emit(bytecode, binaryOp(binary.op), 0);
}

fn compileBlockValue(context: *CompileContext, block_id: hir.ir.BlockId) CompileError!void {
    const bytecode = context.bytecode;
    const module = context.module;
    const block = module.blocks.items[block_id];
    const start: usize = @intCast(block.stmts.start);
    const end: usize = @intCast(block.stmts.end());
    for (module.block_stmt_ids.items[start..end]) |stmt_id| {
        if (try compileStmt(context, module.stmts.items[stmt_id])) return;
    }
    if (block.final_expr) |final_expr| {
        try compileExpr(context, final_expr);
    } else {
        try emit(bytecode, .unit, 0);
    }
}

fn compileControlCondition(context: *CompileContext, condition: hir.ir.ControlCondition) CompileError!void {
    switch (condition) {
        .expr => |expr| try compileExpr(context, expr),
        .let_pattern => try emit(context.bytecode, .unsupported, 0),
    }
}

fn binaryOp(op: hir.ir.BinaryOp) Op {
    return switch (op) {
        .add, .add_assign => .add,
        .sub, .sub_assign => .sub,
        .mul, .mul_assign => .mul,
        .div, .div_assign => .div,
        .rem, .rem_assign => .rem,
        .equal => .equal,
        .not_equal => .not_equal,
        .less => .less,
        .less_equal => .less_equal,
        .greater => .greater,
        .greater_equal => .greater_equal,
        .logical_and => .logical_and,
        .logical_or => .logical_or,
        .assign => .assign,
    };
}

fn emit(bytecode: *BytecodeModule, op: Op, operand: u32) Allocator.Error!void {
    try bytecode.instructions.append(bytecode.allocator, .{ .op = op, .operand = operand });
}

fn emitIntConstant(bytecode: *BytecodeModule, source: []const u8, span: base.Span) CompileError!void {
    const start: usize = @intCast(span.start);
    const end: usize = @intCast(span.end());
    const value = std.fmt.parseInt(i64, source[start..end], 10) catch return error.InvalidIntegerLiteral;
    const index: u32 = @intCast(bytecode.int_constants.items.len);
    try bytecode.int_constants.append(bytecode.allocator, value);
    try emit(bytecode, .constant_int, index);
}

fn emitStringConstant(bytecode: *BytecodeModule, source: []const u8, span: base.Span) CompileError!void {
    const start: usize = @intCast(span.start + 1);
    const end: usize = @intCast(span.end() - 1);
    const index: u32 = @intCast(bytecode.string_constants.items.len);
    try bytecode.string_constants.append(bytecode.allocator, .{ .bytes = source[start..end] });
    try emit(bytecode, .constant_string, index);
}

pub fn dumpBytecode(allocator: Allocator, bytecode: *const BytecodeModule, interner: *const base.Interner) DumpError![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();

    try output.writer.writeAll("BytecodeModule\n");
    for (bytecode.functions.items) |function| {
        try output.writer.print("  Function {s} params={d}\n", .{ interner.get(function.name) orelse "<missing>", function.params.len });
        const start: usize = @intCast(function.code.start);
        const end: usize = @intCast(function.code.end());
        for (bytecode.instructions.items[start..end], 0..) |instruction, offset| {
            try output.writer.print("    {d}: {s}", .{ offset, @tagName(instruction.op) });
            switch (instruction.op) {
                .get_name, .get_field => try output.writer.print(" {s}", .{interner.get(instruction.operand) orelse "<missing>"}),
                .load_local, .store_local => try output.writer.print(" {d}", .{instruction.operand}),
                .call, .call_function, .jump, .jump_if_false => try output.writer.print(" {d}", .{instruction.operand}),
                .constant_int => try output.writer.print(" {d}", .{bytecode.int_constants.items[instruction.operand]}),
                .constant_string => try output.writer.print(" \"{s}\"", .{bytecode.string_constants.items[instruction.operand].bytes}),
                .constant_bool => try output.writer.print(" {}", .{instruction.operand != 0}),
                else => {},
            }
            try output.writer.writeByte('\n');
        }
    }

    return output.toOwnedSlice();
}
