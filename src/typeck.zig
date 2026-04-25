pub const checker = @import("typeck/checker.zig");

pub const Type = checker.Type;
pub const checkModule = checker.checkModule;

test {
    _ = checker;
}
