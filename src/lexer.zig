pub const token = @import("lexer/token.zig");
pub const scanner = @import("lexer/scanner.zig");
pub const dump = @import("lexer/dump.zig");

pub const Token = token.Token;
pub const TokenKind = token.TokenKind;
pub const TokenList = scanner.TokenList;
pub const lex = scanner.lex;
pub const dumpTokens = dump.dumpTokens;

test {
    _ = token;
    _ = scanner;
    _ = dump;
}
