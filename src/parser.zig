pub const ast = @import("parser/ast.zig");

pub const Ast = ast.Ast;
pub const Decl = ast.Decl;
pub const DeclId = ast.DeclId;
pub const Visibility = ast.Visibility;
pub const PathSegment = ast.PathSegment;
pub const ImportDecl = ast.ImportDecl;
pub const dumpAst = ast.dumpAst;

test {
    _ = ast;
}
