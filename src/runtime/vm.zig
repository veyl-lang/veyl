const std = @import("std");
const bytecode = @import("../bytecode.zig");

const Allocator = std.mem.Allocator;

pub const Value = union(enum) {
    unit,
    bool: bool,
    int: i64,
};

pub const VmError = error{
    EmptyModule,
    StackUnderflow,
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
        return self.runFunction(module, module.functions.items[0]);
    }

    fn runFunction(self: *Vm, module: *const bytecode.BytecodeModule, function: bytecode.Function) VmError!Value {
        const locals = try self.allocator.alloc(Value, function.local_count);
        defer self.allocator.free(locals);
        for (locals) |*local| local.* = .unit;

        const start: usize = @intCast(function.code.start);
        const end: usize = @intCast(function.code.end());
        var ip = start;
        while (ip < end) : (ip += 1) {
            const instruction = module.instructions.items[ip];
            switch (instruction.op) {
                .unit => try self.stack.append(self.allocator, .unit),
                .constant_int => try self.stack.append(self.allocator, .{ .int = module.int_constants.items[instruction.operand] }),
                .constant_bool => try self.stack.append(self.allocator, .{ .bool = instruction.operand != 0 }),
                .load_local => try self.stack.append(self.allocator, locals[instruction.operand]),
                .store_local => locals[instruction.operand] = try self.pop(),
                .add => try self.binaryInt(.add),
                .sub => try self.binaryInt(.sub),
                .mul => try self.binaryInt(.mul),
                .div => try self.binaryInt(.div),
                .rem => try self.binaryInt(.rem),
                .equal => try self.binaryCompare(.equal),
                .not_equal => try self.binaryCompare(.not_equal),
                .less => try self.binaryCompare(.less),
                .less_equal => try self.binaryCompare(.less_equal),
                .greater => try self.binaryCompare(.greater),
                .greater_equal => try self.binaryCompare(.greater_equal),
                .pop => _ = try self.pop(),
                .ret => return try self.pop(),
                else => return error.UnsupportedInstruction,
            }
        }
        return error.UnsupportedInstruction;
    }

    fn pop(self: *Vm) VmError!Value {
        return self.stack.pop() orelse error.StackUnderflow;
    }

    fn binaryInt(self: *Vm, op: bytecode.Op) VmError!void {
        const right = try self.popInt();
        const left = try self.popInt();
        const result = switch (op) {
            .add => left + right,
            .sub => left - right,
            .mul => left * right,
            .div => if (right == 0) return error.IntegerDivideByZero else @divTrunc(left, right),
            .rem => if (right == 0) return error.IntegerDivideByZero else @rem(left, right),
            else => return error.UnsupportedInstruction,
        };
        try self.stack.append(self.allocator, .{ .int = result });
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

    fn popInt(self: *Vm) VmError!i64 {
        return switch (try self.pop()) {
            .int => |value| value,
            else => error.TypeMismatch,
        };
    }
};
