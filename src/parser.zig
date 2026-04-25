pub const ast = @import("parser/ast.zig");
pub const parser = @import("parser/parser.zig");

pub const Ast = ast.Ast;
pub const Decl = ast.Decl;
pub const DeclId = ast.DeclId;
pub const Visibility = ast.Visibility;
pub const PathSegment = ast.PathSegment;
pub const ImportDecl = ast.ImportDecl;
pub const StructDecl = ast.StructDecl;
pub const StructField = ast.StructField;
pub const dumpAst = ast.dumpAst;
pub const parse = parser.parse;

test {
    _ = ast;
    _ = parser;
}
