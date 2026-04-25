const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const veyl_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "veyl",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addImport("veyl", veyl_mod);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the Veyl CLI");
    run_step.dependOn(&run_cmd.step);

    const tests = b.addTest(.{
        .root_module = veyl_mod,
    });
    const run_tests = b.addRunArtifact(tests);

    const lexer_fixture_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/lexer_fixtures.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    lexer_fixture_tests.root_module.addImport("veyl", veyl_mod);
    const run_lexer_fixture_tests = b.addRunArtifact(lexer_fixture_tests);

    const parser_fixture_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/parser_fixtures.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    parser_fixture_tests.root_module.addImport("veyl", veyl_mod);
    const run_parser_fixture_tests = b.addRunArtifact(parser_fixture_tests);

    const fmt_fixture_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/fmt_fixtures.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    fmt_fixture_tests.root_module.addImport("veyl", veyl_mod);
    const run_fmt_fixture_tests = b.addRunArtifact(fmt_fixture_tests);

    const diagnostic_fixture_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/diagnostic_fixtures.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    diagnostic_fixture_tests.root_module.addImport("veyl", veyl_mod);
    const run_diagnostic_fixture_tests = b.addRunArtifact(diagnostic_fixture_tests);

    const hir_fixture_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/hir_fixtures.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    hir_fixture_tests.root_module.addImport("veyl", veyl_mod);
    const run_hir_fixture_tests = b.addRunArtifact(hir_fixture_tests);

    const resolver_fixture_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/resolver_fixtures.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    resolver_fixture_tests.root_module.addImport("veyl", veyl_mod);
    const run_resolver_fixture_tests = b.addRunArtifact(resolver_fixture_tests);

    const typeck_fixture_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/typeck_fixtures.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    typeck_fixture_tests.root_module.addImport("veyl", veyl_mod);
    const run_typeck_fixture_tests = b.addRunArtifact(typeck_fixture_tests);

    const bytecode_fixture_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/bytecode_fixtures.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    bytecode_fixture_tests.root_module.addImport("veyl", veyl_mod);
    const run_bytecode_fixture_tests = b.addRunArtifact(bytecode_fixture_tests);

    const runtime_fixture_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/runtime_fixtures.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    runtime_fixture_tests.root_module.addImport("veyl", veyl_mod);
    const run_runtime_fixture_tests = b.addRunArtifact(runtime_fixture_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(&run_lexer_fixture_tests.step);
    test_step.dependOn(&run_parser_fixture_tests.step);
    test_step.dependOn(&run_fmt_fixture_tests.step);
    test_step.dependOn(&run_diagnostic_fixture_tests.step);
    test_step.dependOn(&run_hir_fixture_tests.step);
    test_step.dependOn(&run_resolver_fixture_tests.step);
    test_step.dependOn(&run_typeck_fixture_tests.step);
    test_step.dependOn(&run_bytecode_fixture_tests.step);
    test_step.dependOn(&run_runtime_fixture_tests.step);

    const fmt_step = b.step("fmt", "Format Zig source");
    fmt_step.dependOn(&b.addFmt(.{
        .paths = &.{
            "build.zig",
            "src",
            "tests",
        },
    }).step);

    const fmt_check_step = b.step("fmt-check", "Check Zig source formatting");
    fmt_check_step.dependOn(&b.addFmt(.{
        .paths = &.{
            "build.zig",
            "src",
            "tests",
        },
        .check = true,
    }).step);

    const check_step = b.step("check", "Build all artifacts without running tests");
    check_step.dependOn(&exe.step);
    check_step.dependOn(&tests.step);
    check_step.dependOn(&lexer_fixture_tests.step);
    check_step.dependOn(&parser_fixture_tests.step);
    check_step.dependOn(&fmt_fixture_tests.step);
    check_step.dependOn(&diagnostic_fixture_tests.step);
    check_step.dependOn(&hir_fixture_tests.step);
    check_step.dependOn(&resolver_fixture_tests.step);
    check_step.dependOn(&typeck_fixture_tests.step);
    check_step.dependOn(&bytecode_fixture_tests.step);
    check_step.dependOn(&runtime_fixture_tests.step);
    check_step.dependOn(fmt_check_step);
}
