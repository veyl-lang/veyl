pub const token = @import("lexer/token.zig");
pub const scanner = @import("lexer/scanner.zig");

pub const Token = token.Token;
pub const TokenKind = token.TokenKind;
pub const TokenList = scanner.TokenList;
pub const lex = scanner.lex;

test {
    _ = token;
    _ = scanner;
}
