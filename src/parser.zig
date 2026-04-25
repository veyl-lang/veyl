pub const ast = @import("parser/ast.zig");
pub const parser = @import("parser/parser.zig");

pub const Ast = ast.Ast;
pub const Decl = ast.Decl;
pub const DeclId = ast.DeclId;
pub const Visibility = ast.Visibility;
pub const PathSegment = ast.PathSegment;
pub const ImportDecl = ast.ImportDecl;
pub const TypeAliasDecl = ast.TypeAliasDecl;
pub const FnDecl = ast.FnDecl;
pub const FnParam = ast.FnParam;
pub const Block = ast.Block;
pub const Stmt = ast.Stmt;
pub const WhileStmt = ast.WhileStmt;
pub const DeferStmt = ast.DeferStmt;
pub const DeferKind = ast.DeferKind;
pub const Expr = ast.Expr;
pub const ExprId = ast.ExprId;
pub const BinaryOp = ast.BinaryOp;
pub const StructLiteralField = ast.StructLiteralField;
pub const TryExpr = ast.TryExpr;
pub const CatchExpr = ast.CatchExpr;
pub const CatchHandler = ast.CatchHandler;
pub const CatchBinding = ast.CatchBinding;
pub const StructDecl = ast.StructDecl;
pub const StructField = ast.StructField;
pub const EnumDecl = ast.EnumDecl;
pub const EnumVariant = ast.EnumVariant;
pub const EnumField = ast.EnumField;
pub const dumpAst = ast.dumpAst;
pub const parse = parser.parse;

test {
    _ = ast;
    _ = parser;
}
