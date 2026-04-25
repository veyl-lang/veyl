const std = @import("std");
const ids = @import("ids.zig");
const span_mod = @import("span.zig");

const Allocator = std.mem.Allocator;

pub const SourceFile = struct {
    id: ids.SourceId,
    path: []const u8,
    text: []const u8,
    line_starts: []u32,

    pub fn deinit(self: *SourceFile, allocator: Allocator) void {
        allocator.free(self.path);
        allocator.free(self.text);
        allocator.free(self.line_starts);
        self.* = undefined;
    }
};

pub const SourceMap = struct {
    allocator: Allocator,
    files: std.ArrayListUnmanaged(SourceFile) = .empty,

    pub fn init(allocator: Allocator) SourceMap {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *SourceMap) void {
        for (self.files.items) |*source_file| {
            source_file.deinit(self.allocator);
        }
        self.files.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn add(self: *SourceMap, path: []const u8, text: []const u8) Allocator.Error!ids.SourceId {
        const id: ids.SourceId = @intCast(self.files.items.len);
        const owned_path = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(owned_path);

        const owned_text = try self.allocator.dupe(u8, text);
        errdefer self.allocator.free(owned_text);

        const line_starts = try buildLineStarts(self.allocator, owned_text);
        errdefer self.allocator.free(line_starts);

        try self.files.append(self.allocator, .{
            .id = id,
            .path = owned_path,
            .text = owned_text,
            .line_starts = line_starts,
        });

        return id;
    }

    pub fn file(self: *const SourceMap, id: ids.SourceId) ?*const SourceFile {
        if (id >= self.files.items.len) return null;
        return &self.files.items[id];
    }

    pub fn lineCol(self: *const SourceMap, span: span_mod.Span) ?span_mod.LineCol {
        const source_file = self.file(span.source) orelse return null;
        if (span.start > source_file.text.len) return null;

        const line_index = findLineIndex(source_file.line_starts, span.start);
        const line_start = source_file.line_starts[line_index];
        return .{
            .line = @intCast(line_index + 1),
            .column = span.start - line_start + 1,
        };
    }

    pub fn lineText(self: *const SourceMap, source: ids.SourceId, line: u32) ?[]const u8 {
        const source_file = self.file(source) orelse return null;
        if (line == 0 or line > source_file.line_starts.len) return null;

        const line_index: usize = @intCast(line - 1);
        const start: usize = source_file.line_starts[line_index];
        var end: usize = if (line_index + 1 < source_file.line_starts.len)
            source_file.line_starts[line_index + 1] - 1
        else
            source_file.text.len;

        if (end > start and source_file.text[end - 1] == '\r') {
            end -= 1;
        }

        return source_file.text[start..end];
    }
};

fn buildLineStarts(allocator: Allocator, text: []const u8) Allocator.Error![]u32 {
    var starts: std.ArrayListUnmanaged(u32) = .empty;
    errdefer starts.deinit(allocator);

    try starts.append(allocator, 0);
    for (text, 0..) |byte, index| {
        if (byte == '\n') {
            try starts.append(allocator, @intCast(index + 1));
        }
    }

    return starts.toOwnedSlice(allocator);
}

fn findLineIndex(line_starts: []const u32, offset: u32) usize {
    var low: usize = 0;
    var high: usize = line_starts.len;
    while (low + 1 < high) {
        const mid = low + (high - low) / 2;
        if (line_starts[mid] <= offset) {
            low = mid;
        } else {
            high = mid;
        }
    }
    return low;
}

test "source map maps byte offsets to one-based line columns" {
    var sources = SourceMap.init(std.testing.allocator);
    defer sources.deinit();

    const id = try sources.add("main.veyl", "let x = 1;\r\nlet y = x;\n");

    try std.testing.expectEqual(@as(ids.SourceId, 0), id);
    try std.testing.expectEqualStrings("main.veyl", sources.file(id).?.path);

    const location = sources.lineCol(.{ .source = id, .start = 12, .len = 3 }).?;
    try std.testing.expectEqual(@as(u32, 2), location.line);
    try std.testing.expectEqual(@as(u32, 1), location.column);
    try std.testing.expectEqualStrings("let x = 1;", sources.lineText(id, 1).?);
    try std.testing.expectEqualStrings("let y = x;", sources.lineText(id, 2).?);
}
