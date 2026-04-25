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
    get_name,
    get_field,
    call,
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
};

pub const BytecodeModule = struct {
    allocator: Allocator,
    functions: std.ArrayListUnmanaged(Function) = .empty,
    instructions: std.ArrayListUnmanaged(Instruction) = .empty,

    pub fn init(allocator: Allocator) BytecodeModule {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *BytecodeModule) void {
        self.functions.deinit(self.allocator);
        self.instructions.deinit(self.allocator);
        self.* = undefined;
    }
};

pub fn compileHir(allocator: Allocator, module: *const hir.Hir) Allocator.Error!BytecodeModule {
    var bytecode = BytecodeModule.init(allocator);
    errdefer bytecode.deinit();

    for (module.decls.items) |decl| {
        switch (decl) {
            .function => |function| try compileFunction(&bytecode, module, function),
            .impl_decl => |impl_decl| {
                const start: usize = @intCast(impl_decl.methods.start);
                const end: usize = @intCast(impl_decl.methods.end());
                for (module.impl_methods.items[start..end]) |method| {
                    try compileFunction(&bytecode, module, method);
                }
            },
            else => {},
        }
    }

    return bytecode;
}

fn compileFunction(bytecode: *BytecodeModule, module: *const hir.Hir, function: hir.ir.FunctionDecl) Allocator.Error!void {
    const code_start: u32 = @intCast(bytecode.instructions.items.len);
    try compileBlock(bytecode, module, function.body, true);
    try bytecode.functions.append(bytecode.allocator, .{
        .name = function.name,
        .params = function.params,
        .code = .{ .start = code_start, .len = @intCast(bytecode.instructions.items.len - code_start) },
    });
}

fn compileBlock(bytecode: *BytecodeModule, module: *const hir.Hir, block_id: hir.ir.BlockId, returns: bool) Allocator.Error!void {
    const block = module.blocks.items[block_id];
    const start: usize = @intCast(block.stmts.start);
    const end: usize = @intCast(block.stmts.end());
    for (module.block_stmt_ids.items[start..end]) |stmt_id| {
        if (try compileStmt(bytecode, module, module.stmts.items[stmt_id])) return;
    }

    if (!returns) return;
    if (block.final_expr) |final_expr| {
        try compileExpr(bytecode, module, final_expr);
    } else {
        try emit(bytecode, .unit, 0);
    }
    try emit(bytecode, .ret, 0);
}

fn compileStmt(bytecode: *BytecodeModule, module: *const hir.Hir, stmt: hir.ir.Stmt) Allocator.Error!bool {
    switch (stmt) {
        .let_stmt => |let_stmt| {
            try compileExpr(bytecode, module, let_stmt.value);
            try emit(bytecode, .pop, 0);
            return false;
        },
        .return_stmt => |return_stmt| {
            if (return_stmt.value) |value| {
                try compileExpr(bytecode, module, value);
            } else {
                try emit(bytecode, .unit, 0);
            }
            try emit(bytecode, .ret, 0);
            return true;
        },
        .expr_stmt => |expr| {
            try compileExpr(bytecode, module, expr);
            try emit(bytecode, .pop, 0);
            return false;
        },
        else => {
            try emit(bytecode, .unsupported, 0);
            return false;
        },
    }
}

fn compileExpr(bytecode: *BytecodeModule, module: *const hir.Hir, expr_id: hir.ir.ExprId) Allocator.Error!void {
    switch (module.exprs.items[expr_id]) {
        .int_literal => try emit(bytecode, .constant_int, 0),
        .float_literal => try emit(bytecode, .constant_float, 0),
        .string_literal => try emit(bytecode, .constant_string, 0),
        .char_literal => try emit(bytecode, .constant_char, 0),
        .bool_literal => |bool_literal| try emit(bytecode, .constant_bool, if (bool_literal.value) 1 else 0),
        .unit_literal => try emit(bytecode, .unit, 0),
        .name => |name| try emit(bytecode, .get_name, name.symbol),
        .field => |field| {
            try compileExpr(bytecode, module, field.base);
            try emit(bytecode, .get_field, field.name);
        },
        .call => |call| {
            try compileExpr(bytecode, module, call.callee);
            const start: usize = @intCast(call.args.start);
            const end: usize = @intCast(call.args.end());
            for (module.expr_args.items[start..end]) |arg| {
                try compileExpr(bytecode, module, arg);
            }
            try emit(bytecode, .call, call.args.len);
        },
        else => try emit(bytecode, .unsupported, 0),
    }
}

fn emit(bytecode: *BytecodeModule, op: Op, operand: u32) Allocator.Error!void {
    try bytecode.instructions.append(bytecode.allocator, .{ .op = op, .operand = operand });
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
                .call => try output.writer.print(" {d}", .{instruction.operand}),
                .constant_bool => try output.writer.print(" {}", .{instruction.operand != 0}),
                else => {},
            }
            try output.writer.writeByte('\n');
        }
    }

    return output.toOwnedSlice();
}
