const std = @import("std");
const ids = @import("ids.zig");

const Allocator = std.mem.Allocator;

pub const Interner = struct {
    arena: std.heap.ArenaAllocator,
    map: std.StringHashMapUnmanaged(ids.SymbolId) = .empty,
    strings: std.ArrayListUnmanaged([]const u8) = .empty,

    pub fn init(allocator: Allocator) Interner {
        return .{ .arena = std.heap.ArenaAllocator.init(allocator) };
    }

    pub fn deinit(self: *Interner) void {
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn intern(self: *Interner, text: []const u8) Allocator.Error!ids.SymbolId {
        if (self.map.get(text)) |existing| return existing;

        const allocator = self.arena.allocator();
        const owned = try allocator.dupe(u8, text);
        errdefer allocator.free(owned);

        const id: ids.SymbolId = @intCast(self.strings.items.len);
        try self.strings.append(allocator, owned);
        try self.map.put(allocator, owned, id);
        return id;
    }

    pub fn get(self: *const Interner, id: ids.SymbolId) ?[]const u8 {
        if (id >= self.strings.items.len) return null;
        return self.strings.items[id];
    }
};

test "interner returns stable ids and owned text" {
    var interner = Interner.init(std.testing.allocator);
    defer interner.deinit();

    var mutable = [_]u8{ 'u', 's', 'e', 'r' };
    const first = try interner.intern(&mutable);
    mutable[0] = 'x';
    const second = try interner.intern("user");
    const third = try interner.intern("other");

    try std.testing.expectEqual(first, second);
    try std.testing.expect(first != third);
    try std.testing.expectEqualStrings("user", interner.get(first).?);
    try std.testing.expectEqualStrings("other", interner.get(third).?);
}
