const std = @import("std");
const base = @import("../base.zig");
const diag = @import("../diag.zig");
const hir = @import("../hir.zig");

const Allocator = std.mem.Allocator;
const DumpError = Allocator.Error || std.Io.Writer.Error;

pub const SymbolKind = enum {
    import,
    function,
    type_alias,
    struct_type,
    enum_type,
    interface_type,
};

pub const Symbol = struct {
    name: base.SymbolId,
    kind: SymbolKind,
    span: base.Span,
};

pub const ResolvedModule = struct {
    allocator: Allocator,
    symbols: std.ArrayListUnmanaged(Symbol) = .empty,

    pub fn init(allocator: Allocator) ResolvedModule {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *ResolvedModule) void {
        self.symbols.deinit(self.allocator);
        self.* = undefined;
    }
};

pub fn resolveModule(
    allocator: Allocator,
    module: *const hir.Hir,
    diagnostics: *diag.DiagnosticBag,
) Allocator.Error!ResolvedModule {
    var resolved = ResolvedModule.init(allocator);
    errdefer resolved.deinit();

    var seen = std.AutoHashMapUnmanaged(base.SymbolId, base.Span){};
    defer seen.deinit(allocator);

    for (module.decls.items) |decl| {
        switch (decl) {
            .import => |import_decl| try addImportSymbols(allocator, module, import_decl, &seen, &resolved, diagnostics),
            else => if (topLevelSymbol(decl)) |symbol| {
                try addSymbol(allocator, symbol, &seen, &resolved, diagnostics);
            },
        }
    }

    return resolved;
}

fn addImportSymbols(
    allocator: Allocator,
    module: *const hir.Hir,
    import_decl: hir.ir.ImportDecl,
    seen: *std.AutoHashMapUnmanaged(base.SymbolId, base.Span),
    resolved: *ResolvedModule,
    diagnostics: *diag.DiagnosticBag,
) Allocator.Error!void {
    if (import_decl.items.len == 0) {
        const binding = import_decl.alias orelse finalPathSegment(module, import_decl.path).?.name;
        const span = if (import_decl.alias != null) import_decl.span else finalPathSegment(module, import_decl.path).?.span;
        try addSymbol(allocator, .{ .name = binding, .kind = .import, .span = span }, seen, resolved, diagnostics);
        return;
    }

    const start: usize = @intCast(import_decl.items.start);
    const end: usize = @intCast(import_decl.items.end());
    for (module.import_items.items[start..end]) |item| {
        try addSymbol(allocator, .{
            .name = item.alias orelse item.name,
            .kind = .import,
            .span = item.span,
        }, seen, resolved, diagnostics);
    }
}

fn finalPathSegment(module: *const hir.Hir, path: base.Range) ?hir.ir.PathSegment {
    if (path.len == 0) return null;
    const index: usize = @intCast(path.start + path.len - 1);
    return module.path_segments.items[index];
}

fn addSymbol(
    allocator: Allocator,
    symbol: Symbol,
    seen: *std.AutoHashMapUnmanaged(base.SymbolId, base.Span),
    resolved: *ResolvedModule,
    diagnostics: *diag.DiagnosticBag,
) Allocator.Error!void {
    if (seen.get(symbol.name)) |first_span| {
        try diagnostics.add(.{
            .severity = .err,
            .span = symbol.span,
            .message = "duplicate top-level declaration",
            .labels = &.{.{ .span = first_span, .message = "first declaration is here" }},
        });
        return;
    }

    try seen.put(allocator, symbol.name, symbol.span);
    try resolved.symbols.append(allocator, symbol);
}

fn topLevelSymbol(decl: hir.Decl) ?Symbol {
    return switch (decl) {
        .function => |function| .{ .name = function.name, .kind = .function, .span = function.span },
        .type_alias => |type_alias| .{ .name = type_alias.name, .kind = .type_alias, .span = type_alias.span },
        .struct_decl => |struct_decl| .{ .name = struct_decl.name, .kind = .struct_type, .span = struct_decl.span },
        .enum_decl => |enum_decl| .{ .name = enum_decl.name, .kind = .enum_type, .span = enum_decl.span },
        .interface_decl => |interface_decl| .{ .name = interface_decl.name, .kind = .interface_type, .span = interface_decl.span },
        else => null,
    };
}

pub fn dumpResolvedModule(
    allocator: Allocator,
    resolved: *const ResolvedModule,
    interner: *const base.Interner,
) DumpError![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();

    try output.writer.writeAll("ResolvedModule\n");
    for (resolved.symbols.items) |symbol| {
        try output.writer.print("  Symbol {s} {s}\n", .{
            @tagName(symbol.kind),
            interner.get(symbol.name) orelse "<missing>",
        });
    }

    return output.toOwnedSlice();
}
