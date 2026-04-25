pub const ir = @import("bytecode/ir.zig");

pub const BytecodeModule = ir.BytecodeModule;
pub const Function = ir.Function;
pub const Instruction = ir.Instruction;
pub const Op = ir.Op;
pub const compileHir = ir.compileHir;
pub const dumpBytecode = ir.dumpBytecode;

test {
    _ = ir;
}
