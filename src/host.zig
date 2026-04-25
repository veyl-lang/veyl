pub const filesystem = @import("host/filesystem.zig");

pub const readFileAlloc = filesystem.readFileAlloc;

test {
    _ = filesystem;
}
