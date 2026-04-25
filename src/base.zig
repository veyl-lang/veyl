pub const ids = @import("base/ids.zig");
pub const span = @import("base/span.zig");
pub const source_map = @import("base/source_map.zig");
pub const interner = @import("base/interner.zig");

pub const SourceId = ids.SourceId;
pub const ModuleId = ids.ModuleId;
pub const SymbolId = ids.SymbolId;
pub const TokenId = ids.TokenId;
pub const ExprId = ids.ExprId;
pub const StmtId = ids.StmtId;
pub const DeclId = ids.DeclId;
pub const TypeId = ids.TypeId;
pub const FunctionId = ids.FunctionId;
pub const LocalId = ids.LocalId;
pub const ConstId = ids.ConstId;
pub const LabelId = ids.LabelId;

pub const Span = span.Span;
pub const LineCol = span.LineCol;
pub const SourceMap = source_map.SourceMap;
pub const SourceFile = source_map.SourceFile;
pub const Interner = interner.Interner;

test {
    _ = ids;
    _ = span;
    _ = source_map;
    _ = interner;
}
