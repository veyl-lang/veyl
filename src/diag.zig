pub const diagnostic = @import("diag/diagnostic.zig");

pub const Severity = diagnostic.Severity;
pub const Label = diagnostic.Label;
pub const Diagnostic = diagnostic.Diagnostic;
pub const DiagnosticBag = diagnostic.DiagnosticBag;

test {
    _ = diagnostic;
}
