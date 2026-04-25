const std = @import("std");
const ast_mod = @import("ast.zig");
const base = @import("../base.zig");
const diag = @import("../diag.zig");
const lexer = @import("../lexer.zig");

const Allocator = std.mem.Allocator;

pub fn parse(
    allocator: Allocator,
    source_id: base.SourceId,
    source: []const u8,
    tokens: []const lexer.Token,
    interner: *base.Interner,
    diagnostics: *diag.DiagnosticBag,
) Allocator.Error!ast_mod.Ast {
    var parser = Parser{
        .source = source,
        .tokens = tokens,
        .interner = interner,
        .diagnostics = diagnostics,
        .tree = ast_mod.Ast.init(allocator, source_id),
    };
    errdefer parser.tree.deinit();

    try parser.parseRoot();
    return parser.tree;
}

const Parser = struct {
    source: []const u8,
    tokens: []const lexer.Token,
    interner: *base.Interner,
    diagnostics: *diag.DiagnosticBag,
    tree: ast_mod.Ast,
    index: usize = 0,

    fn parseRoot(self: *Parser) Allocator.Error!void {
        while (true) {
            self.skipTrivia();
            if (self.peekKind() == .eof) break;

            var visibility: ast_mod.Visibility = .package;
            var start_span = self.peek().span;
            if (self.match(.keyword_pub)) |token| {
                visibility = .public;
                start_span = token.span;
            } else if (self.match(.keyword_private)) |token| {
                visibility = .private;
                start_span = token.span;
            }

            if (self.peekKind() == .keyword_import) {
                try self.parseImport(visibility, start_span);
            } else if (self.peekKind() == .keyword_struct) {
                try self.parseStruct(visibility, start_span);
            } else {
                try self.addError(self.peek().span, "expected top-level declaration");
                _ = self.advance();
            }
        }
    }

    fn parseImport(self: *Parser, visibility: ast_mod.Visibility, start_span: base.Span) Allocator.Error!void {
        const import_token = (try self.expect(.keyword_import, "expected import declaration")) orelse return;
        var end_span = import_token.span;

        const path_start = self.tree.reservePath();
        var path_len: u32 = 0;

        while (true) {
            const segment_token = (try self.expectIdentifier("expected import path segment")) orelse break;
            end_span = segment_token.span;

            try self.tree.addPathSegment(.{
                .name = try self.internToken(segment_token),
                .span = segment_token.span,
            });
            path_len += 1;

            if (self.match(.dot) == null) break;
            end_span = self.previous().span;
        }

        var alias: ?base.SymbolId = null;
        var alias_span: ?base.Span = null;
        if (self.match(.keyword_as)) |_| {
            const alias_token = (try self.expectIdentifier("expected import alias after `as`")) orelse return;
            alias = try self.internToken(alias_token);
            alias_span = alias_token.span;
            end_span = alias_token.span;
        }

        if (path_len == 0) return;
        _ = try self.tree.addDecl(.{ .import = .{
            .visibility = visibility,
            .path = .{ .start = path_start, .len = path_len },
            .alias = alias,
            .alias_span = alias_span,
            .span = base.Span.join(start_span, end_span),
        } });
    }

    fn parseStruct(self: *Parser, visibility: ast_mod.Visibility, start_span: base.Span) Allocator.Error!void {
        _ = (try self.expect(.keyword_struct, "expected struct declaration")) orelse return;
        const name_token = (try self.expectIdentifier("expected struct name")) orelse return;
        const name = try self.internToken(name_token);

        _ = (try self.expect(.l_brace, "expected `{` after struct name")) orelse return;

        const fields_start = self.tree.reserveStructFields();
        var fields_len: u32 = 0;
        var end_span = name_token.span;

        while (self.peekKind() != .r_brace and self.peekKind() != .eof) {
            self.skipTrivia();
            if (self.peekKind() == .r_brace or self.peekKind() == .eof) break;

            const field_visibility = if (self.match(.keyword_private) != null)
                ast_mod.Visibility.private
            else
                visibility;

            const field_name_token = (try self.expectIdentifier("expected struct field name")) orelse return;
            _ = (try self.expect(.colon, "expected `:` after struct field name")) orelse return;

            const type_path = try self.parsePath("expected struct field type");
            const field_end = self.previous().span;
            try self.tree.addStructField(.{
                .visibility = field_visibility,
                .name = try self.internToken(field_name_token),
                .name_span = field_name_token.span,
                .type_path = type_path,
                .span = base.Span.join(field_name_token.span, field_end),
            });
            fields_len += 1;
            end_span = field_end;

            if (self.match(.comma)) |comma| {
                end_span = comma.span;
            }
        }

        if (self.match(.r_brace)) |brace| {
            end_span = brace.span;
        } else {
            try self.addError(self.peek().span, "expected `}` after struct fields");
        }

        _ = try self.tree.addDecl(.{ .struct_decl = .{
            .visibility = visibility,
            .name = name,
            .name_span = name_token.span,
            .fields = .{ .start = fields_start, .len = fields_len },
            .span = base.Span.join(start_span, end_span),
        } });
    }

    fn parsePath(self: *Parser, message: []const u8) Allocator.Error!base.Range {
        const path_start = self.tree.reservePath();
        var path_len: u32 = 0;

        while (true) {
            const segment_token = (try self.expectIdentifier(message)) orelse break;
            try self.tree.addPathSegment(.{
                .name = try self.internToken(segment_token),
                .span = segment_token.span,
            });
            path_len += 1;

            if (self.match(.dot) == null) break;
        }

        return .{ .start = path_start, .len = path_len };
    }

    fn expect(self: *Parser, kind: lexer.TokenKind, message: []const u8) Allocator.Error!?lexer.Token {
        if (self.match(kind)) |token| return token;
        try self.addError(self.peek().span, message);
        return null;
    }

    fn expectIdentifier(self: *Parser, message: []const u8) Allocator.Error!?lexer.Token {
        if (self.peekKind() == .identifier) return self.advance();
        try self.addError(self.peek().span, message);
        return null;
    }

    fn internToken(self: *Parser, token: lexer.Token) Allocator.Error!base.SymbolId {
        const start: usize = token.span.start;
        const end: usize = token.span.end();
        return self.interner.intern(self.source[start..end]);
    }

    fn addError(self: *Parser, span: base.Span, message: []const u8) Allocator.Error!void {
        try self.diagnostics.add(.{
            .severity = .err,
            .span = span,
            .message = message,
        });
    }

    fn skipTrivia(self: *Parser) void {
        while (true) {
            switch (self.peekKind()) {
                .line_comment,
                .block_comment,
                .doc_line_comment,
                .doc_block_comment,
                .module_doc_comment,
                => self.index += 1,
                else => return,
            }
        }
    }

    fn match(self: *Parser, kind: lexer.TokenKind) ?lexer.Token {
        if (self.peekKind() != kind) return null;
        return self.advance();
    }

    fn advance(self: *Parser) lexer.Token {
        const token = self.peek();
        if (self.index < self.tokens.len) self.index += 1;
        return token;
    }

    fn previous(self: *const Parser) lexer.Token {
        return self.tokens[self.index - 1];
    }

    fn peekKind(self: *const Parser) lexer.TokenKind {
        return self.peek().kind;
    }

    fn peek(self: *const Parser) lexer.Token {
        if (self.index >= self.tokens.len) return self.tokens[self.tokens.len - 1];
        return self.tokens[self.index];
    }
};

test "parser builds import AST" {
    const source =
        \\//! docs
        \\pub import std.fs
        \\import config.Config as AppConfig
        \\
    ;

    var diagnostics = diag.DiagnosticBag.init(std.testing.allocator);
    defer diagnostics.deinit();

    var tokens = try lexer.lex(std.testing.allocator, 0, source, &diagnostics);
    defer tokens.deinit();
    try std.testing.expect(!diagnostics.hasErrors());

    var interner = base.Interner.init(std.testing.allocator);
    defer interner.deinit();

    var tree = try parse(std.testing.allocator, 0, source, tokens.tokens.items, &interner, &diagnostics);
    defer tree.deinit();

    try std.testing.expect(!diagnostics.hasErrors());
    try std.testing.expectEqual(@as(usize, 2), tree.decls.items.len);

    const dumped = try ast_mod.dumpAst(std.testing.allocator, &tree, &interner);
    defer std.testing.allocator.free(dumped);

    try std.testing.expectEqualStrings(
        "Root\n" ++
            "  ImportDecl public\n" ++
            "    path std.fs\n" ++
            "  ImportDecl package\n" ++
            "    path config.Config\n" ++
            "    alias AppConfig\n",
        dumped,
    );
}

test "parser builds struct AST" {
    const source =
        \\pub struct User {
        \\    name: Str,
        \\    private password_hash: Str,
        \\}
        \\
    ;

    var diagnostics = diag.DiagnosticBag.init(std.testing.allocator);
    defer diagnostics.deinit();

    var tokens = try lexer.lex(std.testing.allocator, 0, source, &diagnostics);
    defer tokens.deinit();
    try std.testing.expect(!diagnostics.hasErrors());

    var interner = base.Interner.init(std.testing.allocator);
    defer interner.deinit();

    var tree = try parse(std.testing.allocator, 0, source, tokens.tokens.items, &interner, &diagnostics);
    defer tree.deinit();

    try std.testing.expect(!diagnostics.hasErrors());

    const dumped = try ast_mod.dumpAst(std.testing.allocator, &tree, &interner);
    defer std.testing.allocator.free(dumped);

    try std.testing.expectEqualStrings(
        "Root\n" ++
            "  StructDecl public User\n" ++
            "    Field public name: Str\n" ++
            "    Field private password_hash: Str\n",
        dumped,
    );
}
