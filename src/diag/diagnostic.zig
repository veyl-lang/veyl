const std = @import("std");
const base = @import("../base.zig");

const Allocator = std.mem.Allocator;
const RenderError = Allocator.Error || std.Io.Writer.Error;

pub const Severity = enum {
    note,
    warning,
    err,

    pub fn name(self: Severity) []const u8 {
        return switch (self) {
            .note => "note",
            .warning => "warning",
            .err => "error",
        };
    }
};

pub const Label = struct {
    span: base.Span,
    message: []const u8,
};

pub const LabelRange = struct {
    start: u32,
    len: u32,
};

pub const Diagnostic = struct {
    severity: Severity,
    span: base.Span,
    message: []const u8,
    labels: LabelRange = .{ .start = 0, .len = 0 },
    hint: ?[]const u8 = null,
};

pub const DiagnosticSpec = struct {
    severity: Severity,
    span: base.Span,
    message: []const u8,
    labels: []const Label = &.{},
    hint: ?[]const u8 = null,
};

pub const DiagnosticBag = struct {
    allocator: Allocator,
    diagnostics: std.ArrayListUnmanaged(Diagnostic) = .empty,
    labels: std.ArrayListUnmanaged(Label) = .empty,

    pub fn init(allocator: Allocator) DiagnosticBag {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *DiagnosticBag) void {
        self.diagnostics.deinit(self.allocator);
        self.labels.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn add(self: *DiagnosticBag, spec: DiagnosticSpec) Allocator.Error!void {
        const label_start: u32 = @intCast(self.labels.items.len);
        try self.labels.appendSlice(self.allocator, spec.labels);
        errdefer self.labels.items.len = label_start;

        try self.diagnostics.append(self.allocator, .{
            .severity = spec.severity,
            .span = spec.span,
            .message = spec.message,
            .labels = .{
                .start = label_start,
                .len = @intCast(spec.labels.len),
            },
            .hint = spec.hint,
        });
    }

    pub fn hasErrors(self: *const DiagnosticBag) bool {
        for (self.diagnostics.items) |diagnostic| {
            if (diagnostic.severity == .err) return true;
        }
        return false;
    }

    pub fn diagnosticLabels(self: *const DiagnosticBag, diagnostic: Diagnostic) []const Label {
        const start: usize = @intCast(diagnostic.labels.start);
        const end = start + diagnostic.labels.len;
        return self.labels.items[start..end];
    }

    pub fn render(self: *const DiagnosticBag, allocator: Allocator, sources: *const base.SourceMap) RenderError![]u8 {
        var output: std.Io.Writer.Allocating = .init(allocator);
        errdefer output.deinit();

        for (self.diagnostics.items, 0..) |diagnostic, index| {
            if (index != 0) try output.writer.writeByte('\n');
            try renderDiagnostic(&output.writer, sources, diagnostic, self.diagnosticLabels(diagnostic));
        }

        return output.toOwnedSlice();
    }
};

fn renderDiagnostic(
    writer: *std.Io.Writer,
    sources: *const base.SourceMap,
    diagnostic: Diagnostic,
    labels: []const Label,
) std.Io.Writer.Error!void {
    const location = sources.lineCol(diagnostic.span);
    const source_file = sources.file(diagnostic.span.source);

    try writer.print("{s}: {s}\n", .{ diagnostic.severity.name(), diagnostic.message });
    if (location) |loc| {
        const path = if (source_file) |file| file.path else "<unknown>";
        try writer.print("  --> {s}:{d}:{d}\n", .{ path, loc.line, loc.column });
        if (sources.lineText(diagnostic.span.source, loc.line)) |line_text| {
            try writer.print("   |\n{d: >3} | {s}\n   | ", .{ loc.line, line_text });
            try writeUnderline(writer, loc.column, diagnostic.span.len);
            try writer.writeByte('\n');
        }
    }

    for (labels) |label| {
        if (sources.lineCol(label.span)) |label_loc| {
            try writer.print("label: {d}:{d}: {s}\n", .{ label_loc.line, label_loc.column, label.message });
        }
    }

    if (diagnostic.hint) |hint| {
        try writer.print("help: {s}\n", .{hint});
    }
}

fn writeUnderline(writer: *std.Io.Writer, column: u32, len: u32) std.Io.Writer.Error!void {
    var current: u32 = 1;
    while (current < column) : (current += 1) {
        try writer.writeByte(' ');
    }

    const caret_count = @max(len, 1);
    var written: u32 = 0;
    while (written < caret_count) : (written += 1) {
        try writer.writeByte('^');
    }
}

test "diagnostic bag records errors and renders spans" {
    var sources = base.SourceMap.init(std.testing.allocator);
    defer sources.deinit();
    const source_id = try sources.add("bad.veyl", "let user = User { age: 32 };\nuser.age += 1;\n");

    var bag = DiagnosticBag.init(std.testing.allocator);
    defer bag.deinit();

    try bag.add(.{
        .severity = .err,
        .span = .{ .source = source_id, .start = 29, .len = 4 },
        .message = "cannot mutate immutable binding",
        .hint = "declare it as `let mut user`",
    });

    try std.testing.expect(bag.hasErrors());

    const rendered = try bag.render(std.testing.allocator, &sources);
    defer std.testing.allocator.free(rendered);

    try std.testing.expect(std.mem.indexOf(u8, rendered, "error: cannot mutate immutable binding") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "--> bad.veyl:2:1") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "help: declare it as `let mut user`") != null);
}
