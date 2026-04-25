const std = @import("std");
const bytecode = @import("../bytecode.zig");

const Allocator = std.mem.Allocator;

pub const Value = union(enum) {
    unit,
    bool: bool,
    int: i64,
    float: f64,
    char: u21,
    string: []const u8,
};

pub const VmError = error{
    EmptyModule,
    StackUnderflow,
    InvalidFunctionIndex,
    AssertionFailed,
    TypeMismatch,
    IntegerDivideByZero,
    UnsupportedInstruction,
} || Allocator.Error;

pub const Vm = struct {
    allocator: Allocator,
    stack: std.ArrayListUnmanaged(Value) = .empty,

    pub fn init(allocator: Allocator) Vm {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Vm) void {
        self.stack.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn runFirst(self: *Vm, module: *const bytecode.BytecodeModule) VmError!Value {
        if (module.functions.items.len == 0) return error.EmptyModule;
        return self.runFunction(module, module.functions.items[module.entry_function], &.{});
    }

    pub fn runTests(self: *Vm, module: *const bytecode.BytecodeModule) VmError!u32 {
        var passed: u32 = 0;
        for (module.functions.items) |function| {
            if (!function.is_test) continue;
            _ = try self.runFunction(module, function, &.{});
            passed += 1;
        }
        return passed;
    }

    fn runFunction(self: *Vm, module: *const bytecode.BytecodeModule, function: bytecode.Function, args: []const Value) VmError!Value {
        const locals = try self.allocator.alloc(Value, function.local_count);
        defer self.allocator.free(locals);
        for (locals) |*local| local.* = .unit;
        for (args, 0..) |arg, index| locals[index] = arg;

        const start: usize = @intCast(function.code.start);
        const end: usize = @intCast(function.code.end());
        var ip = start;
        while (ip < end) {
            const instruction = module.instructions.items[ip];
            switch (instruction.op) {
                .unit => try self.stack.append(self.allocator, .unit),
                .constant_int => try self.stack.append(self.allocator, .{ .int = module.int_constants.items[instruction.operand] }),
                .constant_float => try self.stack.append(self.allocator, .{ .float = module.float_constants.items[instruction.operand] }),
                .constant_char => try self.stack.append(self.allocator, .{ .char = module.char_constants.items[instruction.operand] }),
                .constant_string => try self.stack.append(self.allocator, .{ .string = module.string_constants.items[instruction.operand].bytes }),
                .constant_bool => try self.stack.append(self.allocator, .{ .bool = instruction.operand != 0 }),
                .load_local => try self.stack.append(self.allocator, locals[instruction.operand]),
                .store_local => locals[instruction.operand] = try self.pop(),
                .call_function => try self.callFunction(module, instruction.operand),
                .builtin_assert => try self.assertBuiltin(instruction.operand),
                .add => try self.binaryNumber(.add),
                .sub => try self.binaryNumber(.sub),
                .mul => try self.binaryNumber(.mul),
                .div => try self.binaryNumber(.div),
                .rem => try self.binaryNumber(.rem),
                .equal => try self.binaryCompare(.equal),
                .not_equal => try self.binaryCompare(.not_equal),
                .less => try self.binaryCompare(.less),
                .less_equal => try self.binaryCompare(.less_equal),
                .greater => try self.binaryCompare(.greater),
                .greater_equal => try self.binaryCompare(.greater_equal),
                .logical_and => try self.binaryBool(.logical_and),
                .logical_or => try self.binaryBool(.logical_or),
                .jump => {
                    ip = @intCast(instruction.operand);
                    continue;
                },
                .jump_if_false => {
                    if (!try self.popBool()) {
                        ip = @intCast(instruction.operand);
                        continue;
                    }
                },
                .pop => _ = try self.pop(),
                .ret => return try self.pop(),
                else => return error.UnsupportedInstruction,
            }
            ip += 1;
        }
        return error.UnsupportedInstruction;
    }

    fn pop(self: *Vm) VmError!Value {
        return self.stack.pop() orelse error.StackUnderflow;
    }

    fn callFunction(self: *Vm, module: *const bytecode.BytecodeModule, function_index: u32) VmError!void {
        const index: usize = @intCast(function_index);
        if (index >= module.functions.items.len) return error.InvalidFunctionIndex;
        const function = module.functions.items[index];
        const arg_count: usize = @intCast(function.params.len);
        const args = try self.allocator.alloc(Value, arg_count);
        defer self.allocator.free(args);
        var remaining = arg_count;
        while (remaining != 0) {
            remaining -= 1;
            args[remaining] = try self.pop();
        }
        try self.stack.append(self.allocator, try self.runFunction(module, function, args));
    }

    fn assertBuiltin(self: *Vm, arg_count: u32) VmError!void {
        if (arg_count != 1) return error.TypeMismatch;
        if (!try self.popBool()) return error.AssertionFailed;
        try self.stack.append(self.allocator, .unit);
    }

    fn binaryNumber(self: *Vm, op: bytecode.Op) VmError!void {
        const right = try self.pop();
        const left = try self.pop();
        switch (left) {
            .int => |left_int| switch (right) {
                .int => |right_int| {
                    const result = switch (op) {
                        .add => left_int + right_int,
                        .sub => left_int - right_int,
                        .mul => left_int * right_int,
                        .div => if (right_int == 0) return error.IntegerDivideByZero else @divTrunc(left_int, right_int),
                        .rem => if (right_int == 0) return error.IntegerDivideByZero else @rem(left_int, right_int),
                        else => return error.UnsupportedInstruction,
                    };
                    try self.stack.append(self.allocator, .{ .int = result });
                },
                else => return error.TypeMismatch,
            },
            .float => |left_float| switch (right) {
                .float => |right_float| {
                    const result = switch (op) {
                        .add => left_float + right_float,
                        .sub => left_float - right_float,
                        .mul => left_float * right_float,
                        .div => left_float / right_float,
                        else => return error.TypeMismatch,
                    };
                    try self.stack.append(self.allocator, .{ .float = result });
                },
                else => return error.TypeMismatch,
            },
            else => return error.TypeMismatch,
        }
    }

    fn binaryCompare(self: *Vm, op: bytecode.Op) VmError!void {
        const right = try self.pop();
        const left = try self.pop();
        const result = switch (left) {
            .int => |left_int| switch (right) {
                .int => |right_int| switch (op) {
                    .equal => left_int == right_int,
                    .not_equal => left_int != right_int,
                    .less => left_int < right_int,
                    .less_equal => left_int <= right_int,
                    .greater => left_int > right_int,
                    .greater_equal => left_int >= right_int,
                    else => return error.UnsupportedInstruction,
                },
                else => return error.TypeMismatch,
            },
            .float => |left_float| switch (right) {
                .float => |right_float| switch (op) {
                    .equal => left_float == right_float,
                    .not_equal => left_float != right_float,
                    .less => left_float < right_float,
                    .less_equal => left_float <= right_float,
                    .greater => left_float > right_float,
                    .greater_equal => left_float >= right_float,
                    else => return error.UnsupportedInstruction,
                },
                else => return error.TypeMismatch,
            },
            .bool => |left_bool| switch (right) {
                .bool => |right_bool| switch (op) {
                    .equal => left_bool == right_bool,
                    .not_equal => left_bool != right_bool,
                    else => return error.TypeMismatch,
                },
                else => return error.TypeMismatch,
            },
            else => return error.TypeMismatch,
        };
        try self.stack.append(self.allocator, .{ .bool = result });
    }

    fn binaryBool(self: *Vm, op: bytecode.Op) VmError!void {
        const right = try self.popBool();
        const left = try self.popBool();
        const result = switch (op) {
            .logical_and => left and right,
            .logical_or => left or right,
            else => return error.UnsupportedInstruction,
        };
        try self.stack.append(self.allocator, .{ .bool = result });
    }

    fn popBool(self: *Vm) VmError!bool {
        return switch (try self.pop()) {
            .bool => |value| value,
            else => error.TypeMismatch,
        };
    }
};
