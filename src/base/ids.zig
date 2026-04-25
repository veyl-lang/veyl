pub const SourceId = u32;
pub const ModuleId = u32;
pub const SymbolId = u32;
pub const TokenId = u32;
pub const ExprId = u32;
pub const StmtId = u32;
pub const DeclId = u32;
pub const TypeId = u32;
pub const FunctionId = u32;
pub const LocalId = u32;
pub const ConstId = u32;
pub const LabelId = u32;

pub const invalid_source_id: SourceId = std.math.maxInt(SourceId);
pub const invalid_symbol_id: SymbolId = std.math.maxInt(SymbolId);

const std = @import("std");

test "invalid ids use max integer sentinels only at boundaries" {
    try std.testing.expectEqual(@as(SourceId, std.math.maxInt(SourceId)), invalid_source_id);
    try std.testing.expectEqual(@as(SymbolId, std.math.maxInt(SymbolId)), invalid_symbol_id);
}
