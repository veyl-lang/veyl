pub const ir = @import("hir/ir.zig");

pub const Hir = ir.Hir;
pub const Decl = ir.Decl;
pub const lowerAst = ir.lowerAst;
pub const dumpHir = ir.dumpHir;

test {
    _ = ir;
}
