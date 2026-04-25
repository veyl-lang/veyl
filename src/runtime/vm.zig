const std = @import("std");
const bytecode = @import("../bytecode.zig");

const Allocator = std.mem.Allocator;

pub const Value = union(enum) {
    unit,
    bool: bool,
};

pub const VmError = error{
    EmptyModule,
    StackUnderflow,
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
        const start: usize = @intCast(function.code.start);
        const end: usize = @intCast(function.code.end());
        var ip = start;
        while (ip < end) : (ip += 1) {
            const instruction = module.instructions.items[ip];
            switch (instruction.op) {
                .unit => try self.stack.append(self.allocator, .unit),
                .constant_bool => try self.stack.append(self.allocator, .{ .bool = instruction.operand != 0 }),
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
};
