const std = @import("std");
const base = @import("../base.zig");
const diag = @import("../diag.zig");
const hir = @import("../hir.zig");

const Allocator = std.mem.Allocator;
const DumpError = Allocator.Error || std.Io.Writer.Error;

pub const SymbolKind = enum {
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
        if (topLevelSymbol(decl)) |symbol| {
            if (seen.get(symbol.name)) |first_span| {
                try diagnostics.add(.{
                    .severity = .err,
                    .span = symbol.span,
                    .message = "duplicate top-level declaration",
                    .labels = &.{.{ .span = first_span, .message = "first declaration is here" }},
                });
                continue;
            }

            try seen.put(allocator, symbol.name, symbol.span);
            try resolved.symbols.append(allocator, symbol);
        }
    }

    return resolved;
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
