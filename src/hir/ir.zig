const std = @import("std");
const base = @import("../base.zig");
const parser = @import("../parser.zig");

const Allocator = std.mem.Allocator;
const DumpError = Allocator.Error || std.Io.Writer.Error;

pub const PathSegment = struct {
    name: base.SymbolId,
    span: base.Span,
};

pub const ImportDecl = struct {
    visibility: parser.Visibility,
    path: base.Range,
    alias: ?base.SymbolId,
    span: base.Span,
};

pub const NamedDecl = struct {
    visibility: parser.Visibility,
    name: base.SymbolId,
    span: base.Span,
};

pub const FunctionDecl = struct {
    visibility: parser.Visibility,
    name: base.SymbolId,
    params_len: u32,
    span: base.Span,
};

pub const ImplDecl = struct {
    visibility: parser.Visibility,
    methods_len: u32,
    span: base.Span,
};

pub const TestDecl = struct {
    name_span: base.Span,
    span: base.Span,
};

pub const Decl = union(enum) {
    import: ImportDecl,
    type_alias: NamedDecl,
    function: FunctionDecl,
    struct_decl: NamedDecl,
    enum_decl: NamedDecl,
    impl_decl: ImplDecl,
    interface_decl: NamedDecl,
    test_decl: TestDecl,
};

pub const Hir = struct {
    allocator: Allocator,
    source: base.SourceId,
    decls: std.ArrayListUnmanaged(Decl) = .empty,
    path_segments: std.ArrayListUnmanaged(PathSegment) = .empty,

    pub fn init(allocator: Allocator, source: base.SourceId) Hir {
        return .{ .allocator = allocator, .source = source };
    }

    pub fn deinit(self: *Hir) void {
        self.decls.deinit(self.allocator);
        self.path_segments.deinit(self.allocator);
        self.* = undefined;
    }
};

pub fn lowerAst(allocator: Allocator, ast: *const parser.Ast) Allocator.Error!Hir {
    var hir = Hir.init(allocator, ast.source);
    errdefer hir.deinit();

    try hir.path_segments.ensureTotalCapacity(allocator, ast.path_segments.items.len);
    for (ast.path_segments.items) |segment| {
        hir.path_segments.appendAssumeCapacity(.{ .name = segment.name, .span = segment.span });
    }

    for (ast.decls.items) |decl| {
        try hir.decls.append(allocator, switch (decl) {
            .import => |import_decl| .{ .import = .{
                .visibility = import_decl.visibility,
                .path = import_decl.path,
                .alias = import_decl.alias,
                .span = import_decl.span,
            } },
            .type_alias => |type_alias| .{ .type_alias = .{
                .visibility = type_alias.visibility,
                .name = type_alias.name,
                .span = type_alias.span,
            } },
            .fn_decl => |fn_decl| .{ .function = .{
                .visibility = fn_decl.visibility,
                .name = fn_decl.name,
                .params_len = fn_decl.params.len,
                .span = fn_decl.span,
            } },
            .struct_decl => |struct_decl| .{ .struct_decl = .{
                .visibility = struct_decl.visibility,
                .name = struct_decl.name,
                .span = struct_decl.span,
            } },
            .enum_decl => |enum_decl| .{ .enum_decl = .{
                .visibility = enum_decl.visibility,
                .name = enum_decl.name,
                .span = enum_decl.span,
            } },
            .impl_decl => |impl_decl| .{ .impl_decl = .{
                .visibility = impl_decl.visibility,
                .methods_len = impl_decl.methods.len,
                .span = impl_decl.span,
            } },
            .interface_decl => |interface_decl| .{ .interface_decl = .{
                .visibility = interface_decl.visibility,
                .name = interface_decl.name,
                .span = interface_decl.span,
            } },
            .test_decl => |test_decl| .{ .test_decl = .{
                .name_span = test_decl.name_span,
                .span = test_decl.span,
            } },
        });
    }

    return hir;
}

pub fn dumpHir(allocator: Allocator, hir: *const Hir, interner: *const base.Interner) DumpError![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();

    try output.writer.writeAll("HirRoot\n");
    for (hir.decls.items) |decl| {
        switch (decl) {
            .import => |import_decl| {
                try output.writer.print("  Import {s} ", .{@tagName(import_decl.visibility)});
                try dumpPath(&output.writer, hir, interner, import_decl.path);
                if (import_decl.alias) |alias| {
                    try output.writer.print(" as {s}", .{interner.get(alias) orelse "<missing>"});
                }
                try output.writer.writeByte('\n');
            },
            .type_alias => |decl_info| try dumpNamed(&output.writer, interner, "TypeAlias", decl_info),
            .function => |function| try output.writer.print("  Function {s} {s} params={d}\n", .{
                @tagName(function.visibility),
                interner.get(function.name) orelse "<missing>",
                function.params_len,
            }),
            .struct_decl => |decl_info| try dumpNamed(&output.writer, interner, "Struct", decl_info),
            .enum_decl => |decl_info| try dumpNamed(&output.writer, interner, "Enum", decl_info),
            .impl_decl => |impl_decl| try output.writer.print("  Impl {s} methods={d}\n", .{ @tagName(impl_decl.visibility), impl_decl.methods_len }),
            .interface_decl => |decl_info| try dumpNamed(&output.writer, interner, "Interface", decl_info),
            .test_decl => try output.writer.writeAll("  Test\n"),
        }
    }

    return output.toOwnedSlice();
}

fn dumpNamed(writer: *std.Io.Writer, interner: *const base.Interner, label: []const u8, decl: NamedDecl) std.Io.Writer.Error!void {
    try writer.print("  {s} {s} {s}\n", .{ label, @tagName(decl.visibility), interner.get(decl.name) orelse "<missing>" });
}

fn dumpPath(writer: *std.Io.Writer, hir: *const Hir, interner: *const base.Interner, path: base.Range) std.Io.Writer.Error!void {
    const start: usize = @intCast(path.start);
    const end: usize = @intCast(path.end());
    for (hir.path_segments.items[start..end], 0..) |segment, index| {
        if (index != 0) try writer.writeByte('.');
        try writer.writeAll(interner.get(segment.name) orelse "<missing>");
    }
}
