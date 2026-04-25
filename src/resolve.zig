pub const symbols = @import("resolve/symbols.zig");

pub const Symbol = symbols.Symbol;
pub const SymbolKind = symbols.SymbolKind;
pub const ResolvedModule = symbols.ResolvedModule;
pub const resolveModule = symbols.resolveModule;
pub const dumpResolvedModule = symbols.dumpResolvedModule;

test {
    _ = symbols;
}
