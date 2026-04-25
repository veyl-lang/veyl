const std = @import("std");
const veyl = @import("veyl");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer args.deinit();
    _ = args.skip();

    const command = args.next() orelse {
        try usage(io);
        return;
    };

    if (std.mem.eql(u8, command, "check")) {
        const path = args.next() orelse return usage(io);
        try checkFile(io, allocator, path);
    } else if (std.mem.eql(u8, command, "run")) {
        const path = args.next() orelse return usage(io);
        try runFile(io, allocator, path);
    } else if (std.mem.eql(u8, command, "fmt")) {
        const path = args.next() orelse return usage(io);
        try fmtFile(io, allocator, path);
    } else if (std.mem.eql(u8, command, "dump")) {
        const kind = args.next() orelse return usage(io);
        const path = args.next() orelse return usage(io);
        if (std.mem.eql(u8, kind, "tokens")) {
            try dumpTokens(io, allocator, path);
        } else if (std.mem.eql(u8, kind, "ast")) {
            try dumpAst(io, allocator, path);
        } else if (std.mem.eql(u8, kind, "hir")) {
            try dumpHir(io, allocator, path);
        } else if (std.mem.eql(u8, kind, "resolve")) {
            try dumpResolve(io, allocator, path);
        } else if (std.mem.eql(u8, kind, "bytecode")) {
            try dumpBytecode(io, allocator, path);
        } else {
            try usage(io);
        }
    } else if (std.mem.eql(u8, command, "--version") or std.mem.eql(u8, command, "version")) {
        try writeStdout(io, "Veyl " ++ veyl.version ++ "\n");
    } else {
        try usage(io);
    }
}

fn fmtFile(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !void {
    var compilation = try parseFile(io, allocator, path);
    defer compilation.deinit();

    if (compilation.diagnostics.hasErrors()) {
        try printDiagnostics(allocator, &compilation.sources, &compilation.diagnostics);
        std.process.exit(1);
    }

    const source = compilation.sources.file(compilation.source_id).?.text;
    const formatted = try veyl.fmt.formatAst(allocator, &compilation.tree.?, &compilation.interner, source);
    defer allocator.free(formatted);
    try writeStdout(io, formatted);
}

fn checkFile(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !void {
    var compilation = try parseFile(io, allocator, path);
    defer compilation.deinit();

    if (compilation.diagnostics.hasErrors()) {
        try printDiagnostics(allocator, &compilation.sources, &compilation.diagnostics);
        std.process.exit(1);
    }

    var hir = try veyl.hir.lowerAst(allocator, &compilation.tree.?);
    defer hir.deinit();

    var resolved = try veyl.resolve.resolveModule(allocator, &hir, &compilation.interner, &compilation.diagnostics);
    defer resolved.deinit();

    if (!compilation.diagnostics.hasErrors()) {
        try veyl.typeck.checkModule(allocator, &hir, &compilation.interner, &compilation.diagnostics);
    }

    if (compilation.diagnostics.hasErrors()) {
        try printDiagnostics(allocator, &compilation.sources, &compilation.diagnostics);
        std.process.exit(1);
    }
}

fn runFile(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !void {
    var compilation = try parseFile(io, allocator, path);
    defer compilation.deinit();

    if (compilation.diagnostics.hasErrors()) {
        try printDiagnostics(allocator, &compilation.sources, &compilation.diagnostics);
        std.process.exit(1);
    }

    var hir = try veyl.hir.lowerAst(allocator, &compilation.tree.?);
    defer hir.deinit();

    var resolved = try veyl.resolve.resolveModule(allocator, &hir, &compilation.interner, &compilation.diagnostics);
    defer resolved.deinit();

    if (!compilation.diagnostics.hasErrors()) {
        try veyl.typeck.checkModule(allocator, &hir, &compilation.interner, &compilation.diagnostics);
    }

    if (compilation.diagnostics.hasErrors()) {
        try printDiagnostics(allocator, &compilation.sources, &compilation.diagnostics);
        std.process.exit(1);
    }

    var bytecode = try veyl.bytecode.compileHir(allocator, &hir);
    defer bytecode.deinit();

    var vm = veyl.runtime.Vm.init(allocator);
    defer vm.deinit();

    _ = vm.runFirst(&bytecode) catch |err| {
        std.debug.print("runtime error: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
}

fn dumpTokens(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !void {
    var compilation = try lexFile(io, allocator, path);
    defer compilation.deinit();

    if (compilation.diagnostics.hasErrors()) {
        try printDiagnostics(allocator, &compilation.sources, &compilation.diagnostics);
        std.process.exit(1);
    }

    const source = compilation.sources.file(compilation.source_id).?.text;
    const dumped = try veyl.lexer.dumpTokens(allocator, source, compilation.tokens.tokens.items);
    defer allocator.free(dumped);
    try writeStdout(io, dumped);
}

fn dumpAst(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !void {
    var compilation = try parseFile(io, allocator, path);
    defer compilation.deinit();

    if (compilation.diagnostics.hasErrors()) {
        try printDiagnostics(allocator, &compilation.sources, &compilation.diagnostics);
        std.process.exit(1);
    }

    const dumped = try veyl.parser.dumpAst(allocator, &compilation.tree.?, &compilation.interner);
    defer allocator.free(dumped);
    try writeStdout(io, dumped);
}

fn dumpHir(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !void {
    var compilation = try parseFile(io, allocator, path);
    defer compilation.deinit();

    if (compilation.diagnostics.hasErrors()) {
        try printDiagnostics(allocator, &compilation.sources, &compilation.diagnostics);
        std.process.exit(1);
    }

    var hir = try veyl.hir.lowerAst(allocator, &compilation.tree.?);
    defer hir.deinit();

    const dumped = try veyl.hir.dumpHir(allocator, &hir, &compilation.interner);
    defer allocator.free(dumped);
    try writeStdout(io, dumped);
}

fn dumpResolve(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !void {
    var compilation = try parseFile(io, allocator, path);
    defer compilation.deinit();

    if (compilation.diagnostics.hasErrors()) {
        try printDiagnostics(allocator, &compilation.sources, &compilation.diagnostics);
        std.process.exit(1);
    }

    var hir = try veyl.hir.lowerAst(allocator, &compilation.tree.?);
    defer hir.deinit();

    var resolved = try veyl.resolve.resolveModule(allocator, &hir, &compilation.interner, &compilation.diagnostics);
    defer resolved.deinit();

    if (compilation.diagnostics.hasErrors()) {
        try printDiagnostics(allocator, &compilation.sources, &compilation.diagnostics);
        std.process.exit(1);
    }

    const dumped = try veyl.resolve.dumpResolvedModule(allocator, &resolved, &compilation.interner);
    defer allocator.free(dumped);
    try writeStdout(io, dumped);
}

fn dumpBytecode(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !void {
    var compilation = try parseFile(io, allocator, path);
    defer compilation.deinit();

    if (compilation.diagnostics.hasErrors()) {
        try printDiagnostics(allocator, &compilation.sources, &compilation.diagnostics);
        std.process.exit(1);
    }

    var hir = try veyl.hir.lowerAst(allocator, &compilation.tree.?);
    defer hir.deinit();

    var bytecode = try veyl.bytecode.compileHir(allocator, &hir);
    defer bytecode.deinit();

    const dumped = try veyl.bytecode.dumpBytecode(allocator, &bytecode, &compilation.interner);
    defer allocator.free(dumped);
    try writeStdout(io, dumped);
}

const Compilation = struct {
    allocator: std.mem.Allocator,
    sources: veyl.base.SourceMap,
    diagnostics: veyl.diag.DiagnosticBag,
    interner: veyl.base.Interner,
    source_id: veyl.base.SourceId,
    tokens: veyl.lexer.TokenList,
    tree: ?veyl.parser.Ast = null,

    fn deinit(self: *Compilation) void {
        if (self.tree) |*tree| tree.deinit();
        self.tokens.deinit();
        self.interner.deinit();
        self.diagnostics.deinit();
        self.sources.deinit();
        self.* = undefined;
    }
};

fn lexFile(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !Compilation {
    var sources = veyl.base.SourceMap.init(allocator);
    errdefer sources.deinit();

    var diagnostics = veyl.diag.DiagnosticBag.init(allocator);
    errdefer diagnostics.deinit();

    var interner = veyl.base.Interner.init(allocator);
    errdefer interner.deinit();

    const text = try veyl.host.readFileAlloc(io, allocator, path);
    defer allocator.free(text);

    const source_id = try sources.add(path, text);
    const source_text = sources.file(source_id).?.text;
    var tokens = try veyl.lexer.lex(allocator, source_id, source_text, &diagnostics);
    errdefer tokens.deinit();

    return .{
        .allocator = allocator,
        .sources = sources,
        .diagnostics = diagnostics,
        .interner = interner,
        .source_id = source_id,
        .tokens = tokens,
    };
}

fn parseFile(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !Compilation {
    var compilation = try lexFile(io, allocator, path);
    errdefer compilation.deinit();

    if (!compilation.diagnostics.hasErrors()) {
        const source = compilation.sources.file(compilation.source_id).?.text;
        compilation.tree = try veyl.parser.parse(
            allocator,
            compilation.source_id,
            source,
            compilation.tokens.tokens.items,
            &compilation.interner,
            &compilation.diagnostics,
        );
    }

    return compilation;
}

fn printDiagnostics(
    allocator: std.mem.Allocator,
    sources: *const veyl.base.SourceMap,
    diagnostics: *const veyl.diag.DiagnosticBag,
) !void {
    const rendered = try diagnostics.render(allocator, sources);
    defer allocator.free(rendered);
    std.debug.print("{s}", .{rendered});
}

fn usage(io: std.Io) !void {
    try writeStdout(io,
        \\Veyl commands:
        \\  veyl check <file>
        \\  veyl run <file>
        \\  veyl fmt <file>
        \\  veyl dump tokens <file>
        \\  veyl dump ast <file>
        \\  veyl dump hir <file>
        \\  veyl dump resolve <file>
        \\  veyl dump bytecode <file>
        \\  veyl version
        \\
    );
}

fn writeStdout(io: std.Io, bytes: []const u8) !void {
    var buffer: [4096]u8 = undefined;
    var writer = std.Io.File.stdout().writer(io, &buffer);
    try writer.interface.writeAll(bytes);
    try writer.interface.flush();
}
