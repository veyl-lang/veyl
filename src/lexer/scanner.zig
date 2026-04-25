const std = @import("std");
const base = @import("../base.zig");
const diag = @import("../diag.zig");
const token_mod = @import("token.zig");

const Allocator = std.mem.Allocator;

pub const TokenList = struct {
    allocator: Allocator,
    tokens: std.ArrayListUnmanaged(token_mod.Token) = .empty,

    pub fn init(allocator: Allocator) TokenList {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *TokenList) void {
        self.tokens.deinit(self.allocator);
        self.* = undefined;
    }
};

pub fn lex(
    allocator: Allocator,
    source_id: base.SourceId,
    text: []const u8,
    diagnostics: *diag.DiagnosticBag,
) Allocator.Error!TokenList {
    var lexer = Lexer{
        .source_id = source_id,
        .text = text,
        .diagnostics = diagnostics,
        .result = TokenList.init(allocator),
    };
    errdefer lexer.result.deinit();

    try lexer.scanAll();
    return lexer.result;
}

const Lexer = struct {
    source_id: base.SourceId,
    text: []const u8,
    diagnostics: *diag.DiagnosticBag,
    result: TokenList,
    pos: usize = 0,

    fn scanAll(self: *Lexer) Allocator.Error!void {
        while (!self.atEnd()) {
            self.skipWhitespace();
            if (self.atEnd()) break;

            const start = self.pos;
            const byte = self.advance();
            switch (byte) {
                'a'...'z', 'A'...'Z' => try self.finishIdentifierOrRawString(start, byte),
                '_' => try self.finishUnderscoreOrIdentifier(start),
                '0'...'9' => try self.finishNumber(start),
                '"' => try self.finishString(start),
                '\'' => try self.finishChar(start),
                '/' => try self.finishSlashOrComment(start),
                '(' => try self.add(.l_paren, start),
                ')' => try self.add(.r_paren, start),
                '{' => try self.add(.l_brace, start),
                '}' => try self.add(.r_brace, start),
                '[' => try self.add(.l_bracket, start),
                ']' => try self.add(.r_bracket, start),
                ',' => try self.add(.comma, start),
                ':' => try self.add(.colon, start),
                ';' => try self.add(.semicolon, start),
                '.' => try self.finishDot(start),
                '-' => try self.add(if (self.match('=')) .minus_equal else if (self.match('>')) .arrow else .minus, start),
                '+' => try self.add(if (self.match('=')) .plus_equal else .plus, start),
                '*' => try self.add(if (self.match('=')) .star_equal else .star, start),
                '%' => try self.add(if (self.match('=')) .percent_equal else .percent, start),
                '=' => try self.add(if (self.match('=')) .equal_equal else if (self.match('>')) .fat_arrow else .equal, start),
                '!' => try self.add(if (self.match('=')) .bang_equal else .bang, start),
                '<' => try self.add(if (self.match('=')) .less_equal else .less, start),
                '>' => try self.add(if (self.match('=')) .greater_equal else .greater, start),
                '|' => try self.add(if (self.match('|')) .pipe_pipe else .pipe, start),
                '&' => try self.add(if (self.match('&')) .amp_amp else .amp, start),
                else => {
                    try self.addDiagnostic(start, 1, "invalid character");
                    try self.add(.invalid, start);
                },
            }
        }

        try self.add(.eof, self.pos);
    }

    fn finishIdentifierOrRawString(self: *Lexer, start: usize, first: u8) Allocator.Error!void {
        if (first == 'r' and (self.peek() == '"' or self.peek() == '#')) {
            if (try self.tryFinishRawString(start)) return;
        }

        while (isIdentContinue(self.peek())) _ = self.advance();
        const text = self.text[start..self.pos];
        try self.add(token_mod.keywordKind(text) orelse .identifier, start);
    }

    fn finishUnderscoreOrIdentifier(self: *Lexer, start: usize) Allocator.Error!void {
        if (!isIdentContinue(self.peek())) {
            try self.add(.underscore, start);
            return;
        }

        while (isIdentContinue(self.peek())) _ = self.advance();
        try self.add(.identifier, start);
    }

    fn finishNumber(self: *Lexer, start: usize) Allocator.Error!void {
        while (isDigit(self.peek())) _ = self.advance();

        var kind: token_mod.TokenKind = .int_literal;
        if (self.peek() == '.' and isDigit(self.peekAt(1))) {
            kind = .float_literal;
            _ = self.advance();
            while (isDigit(self.peek())) _ = self.advance();
        }

        try self.add(kind, start);
    }

    fn finishString(self: *Lexer, start: usize) Allocator.Error!void {
        var terminated = false;
        while (!self.atEnd()) {
            const byte = self.advance();
            if (byte == '\\' and !self.atEnd()) {
                _ = self.advance();
                continue;
            }
            if (byte == '"') {
                terminated = true;
                break;
            }
            if (byte == '\n' or byte == '\r') break;
        }

        if (!terminated) try self.addDiagnostic(start, self.pos - start, "unterminated string literal");
        try self.add(.string_literal, start);
    }

    fn finishChar(self: *Lexer, start: usize) Allocator.Error!void {
        var terminated = false;
        while (!self.atEnd()) {
            const byte = self.advance();
            if (byte == '\\' and !self.atEnd()) {
                _ = self.advance();
                continue;
            }
            if (byte == '\'') {
                terminated = true;
                break;
            }
            if (byte == '\n' or byte == '\r') break;
        }

        if (!terminated) try self.addDiagnostic(start, self.pos - start, "unterminated character literal");
        try self.add(.char_literal, start);
    }

    fn tryFinishRawString(self: *Lexer, start: usize) Allocator.Error!bool {
        var hashes: usize = 0;
        while (self.peek() == '#') {
            hashes += 1;
            _ = self.advance();
        }

        if (!self.match('"')) {
            self.pos = start + 1;
            return false;
        }

        var terminated = false;
        while (!self.atEnd()) {
            if (self.advance() != '"') continue;

            var matched_hashes: usize = 0;
            while (matched_hashes < hashes and self.peekAt(matched_hashes) == '#') {
                matched_hashes += 1;
            }
            if (matched_hashes == hashes) {
                self.pos += matched_hashes;
                terminated = true;
                break;
            }
        }

        if (!terminated) try self.addDiagnostic(start, self.pos - start, "unterminated raw string literal");
        try self.add(.string_literal, start);
        return true;
    }

    fn finishSlashOrComment(self: *Lexer, start: usize) Allocator.Error!void {
        if (self.match('=')) {
            try self.add(.slash_equal, start);
        } else if (self.match('/')) {
            const kind: token_mod.TokenKind = if (self.match('/')) .doc_line_comment else if (self.match('!')) .module_doc_comment else .line_comment;
            while (!self.atEnd() and self.peek() != '\n' and self.peek() != '\r') _ = self.advance();
            try self.add(kind, start);
        } else if (self.match('*')) {
            const kind: token_mod.TokenKind = if (self.match('*')) .doc_block_comment else if (self.match('!')) .module_doc_comment else .block_comment;
            var depth: usize = 1;
            while (!self.atEnd() and depth > 0) {
                if (self.match('/') and self.match('*')) {
                    depth += 1;
                } else if (self.match('*') and self.match('/')) {
                    depth -= 1;
                } else {
                    _ = self.advance();
                }
            }

            if (depth != 0) try self.addDiagnostic(start, self.pos - start, "unterminated block comment");
            try self.add(kind, start);
        } else {
            try self.add(.slash, start);
        }
    }

    fn finishDot(self: *Lexer, start: usize) Allocator.Error!void {
        if (self.match('.')) {
            try self.add(if (self.match('=')) .dot_dot_equal else .dot_dot, start);
        } else {
            try self.add(.dot, start);
        }
    }

    fn skipWhitespace(self: *Lexer) void {
        while (!self.atEnd()) {
            switch (self.peek()) {
                ' ', '\t', '\n', '\r' => _ = self.advance(),
                else => return,
            }
        }
    }

    fn add(self: *Lexer, kind: token_mod.TokenKind, start: usize) Allocator.Error!void {
        try self.result.tokens.append(self.result.allocator, .{
            .kind = kind,
            .span = .{
                .source = self.source_id,
                .start = @intCast(start),
                .len = @intCast(self.pos - start),
            },
        });
    }

    fn addDiagnostic(self: *Lexer, start: usize, len: usize, message: []const u8) Allocator.Error!void {
        try self.diagnostics.add(.{
            .severity = .err,
            .span = .{
                .source = self.source_id,
                .start = @intCast(start),
                .len = @intCast(@max(len, 1)),
            },
            .message = message,
        });
    }

    fn atEnd(self: *const Lexer) bool {
        return self.pos >= self.text.len;
    }

    fn peek(self: *const Lexer) u8 {
        return self.peekAt(0);
    }

    fn peekAt(self: *const Lexer, offset: usize) u8 {
        const index = self.pos + offset;
        if (index >= self.text.len) return 0;
        return self.text[index];
    }

    fn advance(self: *Lexer) u8 {
        const byte = self.text[self.pos];
        self.pos += 1;
        return byte;
    }

    fn match(self: *Lexer, expected: u8) bool {
        if (self.peek() != expected) return false;
        _ = self.advance();
        return true;
    }
};

fn isDigit(byte: u8) bool {
    return byte >= '0' and byte <= '9';
}

fn isIdentContinue(byte: u8) bool {
    return isIdentStart(byte) or isDigit(byte);
}

fn isIdentStart(byte: u8) bool {
    return (byte >= 'a' and byte <= 'z') or (byte >= 'A' and byte <= 'Z') or byte == '_';
}

test "lexer scans keywords literals comments and punctuation" {
    var diagnostics = diag.DiagnosticBag.init(std.testing.allocator);
    defer diagnostics.deinit();

    var tokens = try lex(std.testing.allocator, 0, "pub fn main() { // doc\nlet mut x = 1..=3; }", &diagnostics);
    defer tokens.deinit();

    const expected = [_]token_mod.TokenKind{
        .keyword_pub,
        .keyword_fn,
        .identifier,
        .l_paren,
        .r_paren,
        .l_brace,
        .line_comment,
        .keyword_let,
        .keyword_mut,
        .identifier,
        .equal,
        .int_literal,
        .dot_dot_equal,
        .int_literal,
        .semicolon,
        .r_brace,
        .eof,
    };

    try std.testing.expect(!diagnostics.hasErrors());
    try std.testing.expectEqual(expected.len, tokens.tokens.items.len);
    for (expected, tokens.tokens.items) |kind, token| {
        try std.testing.expectEqual(kind, token.kind);
    }
}

test "lexer preserves nested block comments and reports unterminated tokens" {
    var diagnostics = diag.DiagnosticBag.init(std.testing.allocator);
    defer diagnostics.deinit();

    var tokens = try lex(std.testing.allocator, 0, "/** outer /* inner */ */ \"unterminated", &diagnostics);
    defer tokens.deinit();

    try std.testing.expectEqual(token_mod.TokenKind.doc_block_comment, tokens.tokens.items[0].kind);
    try std.testing.expectEqual(token_mod.TokenKind.string_literal, tokens.tokens.items[1].kind);
    try std.testing.expect(diagnostics.hasErrors());
}

test "lexer recognizes raw strings and reserved future keywords" {
    var diagnostics = diag.DiagnosticBag.init(std.testing.allocator);
    defer diagnostics.deinit();

    var tokens = try lex(std.testing.allocator, 0, "async r#\"raw\"# _ name_1", &diagnostics);
    defer tokens.deinit();

    try std.testing.expect(!diagnostics.hasErrors());
    try std.testing.expectEqual(token_mod.TokenKind.keyword_async, tokens.tokens.items[0].kind);
    try std.testing.expectEqual(token_mod.TokenKind.string_literal, tokens.tokens.items[1].kind);
    try std.testing.expectEqual(token_mod.TokenKind.underscore, tokens.tokens.items[2].kind);
    try std.testing.expectEqual(token_mod.TokenKind.identifier, tokens.tokens.items[3].kind);
}
