pub const vm = @import("runtime/vm.zig");

pub const Value = vm.Value;
pub const Vm = vm.Vm;
pub const VmError = vm.VmError;

test {
    _ = vm;
}
