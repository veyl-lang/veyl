const std = @import("std");

const Allocator = std.mem.Allocator;

pub const max_source_bytes = 16 * 1024 * 1024;

pub fn readFileAlloc(io: std.Io, allocator: Allocator, path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(max_source_bytes));
}
