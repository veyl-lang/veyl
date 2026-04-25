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
    allow_struct_literal: bool = true,

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
            } else if (self.peekKind() == .keyword_type) {
                try self.parseTypeAlias(visibility, start_span);
            } else if (self.peekKind() == .keyword_fn) {
                try self.parseFn(visibility, start_span);
            } else if (self.peekKind() == .keyword_struct) {
                try self.parseStruct(visibility, start_span);
            } else if (self.peekKind() == .keyword_enum) {
                try self.parseEnum(visibility, start_span);
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

    fn parseFn(self: *Parser, visibility: ast_mod.Visibility, start_span: base.Span) Allocator.Error!void {
        _ = (try self.expect(.keyword_fn, "expected function declaration")) orelse return;
        const name_token = (try self.expectIdentifier("expected function name")) orelse return;
        _ = (try self.expect(.l_paren, "expected `(` after function name")) orelse return;

        const params_start = self.tree.reserveFnParams();
        var params_len: u32 = 0;
        while (self.peekKind() != .r_paren and self.peekKind() != .eof) {
            const param = try self.parseFnParam();
            try self.tree.addFnParam(param);
            params_len += 1;
            if (self.match(.comma) == null) break;
        }

        _ = (try self.expect(.r_paren, "expected `)` after function parameters")) orelse return;

        var return_type: ?base.Range = null;
        if (self.match(.arrow) != null) {
            return_type = try self.parsePath("expected function return type");
        }

        const body = try self.parseBlock();
        _ = try self.tree.addDecl(.{ .fn_decl = .{
            .visibility = visibility,
            .name = try self.internToken(name_token),
            .name_span = name_token.span,
            .params = .{ .start = params_start, .len = params_len },
            .return_type = return_type,
            .body = body,
            .span = base.Span.join(start_span, self.tree.blocks.items[body].span),
        } });
    }

    fn parseFnParam(self: *Parser) Allocator.Error!ast_mod.FnParam {
        var is_mut = false;
        var start_span = self.peek().span;
        if (self.match(.keyword_mut)) |mut_token| {
            is_mut = true;
            start_span = mut_token.span;
        }

        const name_token = (try self.expectIdentifier("expected function parameter name")) orelse return .{
            .is_mut = is_mut,
            .name = try self.interner.intern("<error>"),
            .name_span = start_span,
            .type_path = .{ .start = self.tree.reservePath(), .len = 0 },
            .span = start_span,
        };
        _ = (try self.expect(.colon, "expected `:` after function parameter name")) orelse return .{
            .is_mut = is_mut,
            .name = try self.internToken(name_token),
            .name_span = name_token.span,
            .type_path = .{ .start = self.tree.reservePath(), .len = 0 },
            .span = name_token.span,
        };

        const type_path = try self.parsePath("expected function parameter type");
        return .{
            .is_mut = is_mut,
            .name = try self.internToken(name_token),
            .name_span = name_token.span,
            .type_path = type_path,
            .span = base.Span.join(start_span, self.previous().span),
        };
    }

    fn parseBlock(self: *Parser) Allocator.Error!ast_mod.BlockId {
        const open = (try self.expect(.l_brace, "expected function body")) orelse return self.emptyBlock(self.peek().span);
        var block_stmt_ids: std.ArrayListUnmanaged(ast_mod.StmtId) = .empty;
        defer block_stmt_ids.deinit(self.tree.allocator);
        var final_expr: ?ast_mod.ExprId = null;
        var end_span = open.span;

        while (self.peekKind() != .r_brace and self.peekKind() != .eof) {
            self.skipTrivia();
            if (self.peekKind() == .r_brace or self.peekKind() == .eof) break;

            if (self.peekKind() == .keyword_let) {
                const stmt = try self.parseLetStmt();
                try block_stmt_ids.append(self.tree.allocator, try self.tree.addStmt(.{ .let_stmt = stmt }));
                end_span = stmt.span;
            } else if (self.peekKind() == .keyword_return) {
                const stmt = try self.parseReturnStmt();
                try block_stmt_ids.append(self.tree.allocator, try self.tree.addStmt(.{ .return_stmt = stmt }));
                end_span = stmt.span;
            } else if (self.peekKind() == .keyword_while) {
                const stmt = try self.parseWhileStmt();
                try block_stmt_ids.append(self.tree.allocator, try self.tree.addStmt(.{ .while_stmt = stmt }));
                end_span = stmt.span;
            } else if (self.peekKind() == .keyword_defer) {
                const stmt = try self.parseDeferStmt();
                try block_stmt_ids.append(self.tree.allocator, try self.tree.addStmt(.{ .defer_stmt = stmt }));
                end_span = stmt.span;
            } else if (self.peekKind() == .keyword_break) {
                const token = self.advance();
                try block_stmt_ids.append(self.tree.allocator, try self.tree.addStmt(.{ .break_stmt = token.span }));
                end_span = token.span;
                _ = self.match(.semicolon);
            } else if (self.peekKind() == .keyword_continue) {
                const token = self.advance();
                try block_stmt_ids.append(self.tree.allocator, try self.tree.addStmt(.{ .continue_stmt = token.span }));
                end_span = token.span;
                _ = self.match(.semicolon);
            } else {
                const expr = try self.parseExpression(@intFromEnum(Precedence.lowest));
                end_span = self.tree.exprs.items[expr].span();
                if (self.match(.semicolon)) |semicolon| {
                    try block_stmt_ids.append(self.tree.allocator, try self.tree.addStmt(.{ .expr_stmt = expr }));
                    end_span = semicolon.span;
                } else {
                    final_expr = expr;
                    break;
                }
            }
        }

        if (self.match(.r_brace)) |brace| {
            end_span = brace.span;
        } else {
            try self.addError(self.peek().span, "expected `}` after block");
        }

        const stmts_start = self.tree.reserveBlockStmtIds();
        for (block_stmt_ids.items) |stmt_id| {
            try self.tree.addBlockStmtId(stmt_id);
        }

        return self.tree.addBlock(.{
            .stmts = .{ .start = stmts_start, .len = @intCast(block_stmt_ids.items.len) },
            .final_expr = final_expr,
            .span = base.Span.join(open.span, end_span),
        });
    }

    fn emptyBlock(self: *Parser, span: base.Span) Allocator.Error!ast_mod.BlockId {
        return self.tree.addBlock(.{
            .stmts = .{ .start = self.tree.reserveBlockStmtIds(), .len = 0 },
            .span = span,
        });
    }

    fn parseLetStmt(self: *Parser) Allocator.Error!ast_mod.LetStmt {
        const let_token = (try self.expect(.keyword_let, "expected let statement")) orelse return error.OutOfMemory;
        var is_mut = false;
        if (self.match(.keyword_mut) != null) is_mut = true;

        const name_token = (try self.expectIdentifier("expected binding name")) orelse return error.OutOfMemory;
        _ = (try self.expect(.equal, "expected `=` after binding name")) orelse return error.OutOfMemory;

        const value = try self.parseExpression(@intFromEnum(Precedence.lowest));
        var end_span = self.tree.exprs.items[value].span();
        if (self.match(.semicolon)) |semicolon| {
            end_span = semicolon.span;
        } else {
            try self.addError(self.peek().span, "expected `;` after let statement");
        }

        return .{
            .is_mut = is_mut,
            .name = try self.internToken(name_token),
            .name_span = name_token.span,
            .value = value,
            .span = base.Span.join(let_token.span, end_span),
        };
    }

    fn parseReturnStmt(self: *Parser) Allocator.Error!ast_mod.ReturnStmt {
        const return_token = (try self.expect(.keyword_return, "expected return statement")) orelse return error.OutOfMemory;
        var value: ?ast_mod.ExprId = null;
        var end_span = return_token.span;
        if (self.peekKind() != .semicolon and self.peekKind() != .r_brace and self.peekKind() != .eof) {
            value = try self.parseExpression(@intFromEnum(Precedence.lowest));
            end_span = self.tree.exprs.items[value.?].span();
        }
        if (self.match(.semicolon)) |semicolon| {
            end_span = semicolon.span;
        }
        return .{ .value = value, .span = base.Span.join(return_token.span, end_span) };
    }

    fn parseWhileStmt(self: *Parser) Allocator.Error!ast_mod.WhileStmt {
        const while_token = (try self.expect(.keyword_while, "expected while statement")) orelse return error.OutOfMemory;
        const old_allow_struct_literal = self.allow_struct_literal;
        self.allow_struct_literal = false;
        defer self.allow_struct_literal = old_allow_struct_literal;
        const condition = try self.parseExpression(@intFromEnum(Precedence.lowest));

        const body = try self.parseBlock();
        return .{
            .condition = condition,
            .body = body,
            .span = base.Span.join(while_token.span, self.tree.blocks.items[body].span),
        };
    }

    fn parseDeferStmt(self: *Parser) Allocator.Error!ast_mod.DeferStmt {
        const defer_token = (try self.expect(.keyword_defer, "expected defer statement")) orelse return error.OutOfMemory;
        var kind: ast_mod.DeferKind = .always;
        if (self.peekKind() == .identifier and std.mem.eql(u8, self.tokenText(self.peek()), "err")) {
            _ = self.advance();
            kind = .err;
        }

        const body = try self.parseBlock();
        return .{
            .kind = kind,
            .body = body,
            .span = base.Span.join(defer_token.span, self.tree.blocks.items[body].span),
        };
    }

    const Precedence = enum(u8) {
        lowest = 0,
        assignment = 1,
        logical_or = 2,
        logical_and = 3,
        equality = 4,
        comparison = 5,
        term = 6,
        factor = 7,
    };

    fn parseExpression(self: *Parser, min_precedence: u8) Allocator.Error!ast_mod.ExprId {
        var left = try self.parsePostfix();

        while (binaryOp(self.peekKind())) |op_info| {
            if (@intFromEnum(op_info.precedence) < min_precedence) break;
            _ = self.advance();

            const next_min = if (op_info.right_associative)
                @intFromEnum(op_info.precedence)
            else
                nextPrecedence(op_info.precedence);
            const right = try self.parseExpression(next_min);

            const span = base.Span.join(self.tree.exprs.items[left].span(), self.tree.exprs.items[right].span());
            left = try self.tree.addExpr(.{ .binary = .{
                .op = op_info.op,
                .left = left,
                .right = right,
                .span = span,
            } });
        }

        return left;
    }

    fn parsePostfix(self: *Parser) Allocator.Error!ast_mod.ExprId {
        var expr = try self.parsePrimary();

        while (true) {
            if (self.match(.dot)) |_| {
                const name_token = (try self.expectIdentifier("expected field name after `.`")) orelse return expr;
                const span = base.Span.join(self.tree.exprs.items[expr].span(), name_token.span);
                expr = try self.tree.addExpr(.{ .field = .{
                    .base = expr,
                    .name = try self.internToken(name_token),
                    .name_span = name_token.span,
                    .span = span,
                } });
            } else if (self.match(.l_paren)) |_| {
                const args_start = self.tree.reserveExprArgs();
                var args_len: u32 = 0;
                var end_span = self.tree.exprs.items[expr].span();
                while (self.peekKind() != .r_paren and self.peekKind() != .eof) {
                    const arg = try self.parseExpression(@intFromEnum(Precedence.lowest));
                    try self.tree.addExprArg(arg);
                    args_len += 1;
                    end_span = self.tree.exprs.items[arg].span();
                    if (self.match(.comma) == null) break;
                }
                if (self.match(.r_paren)) |paren| {
                    end_span = paren.span;
                } else {
                    try self.addError(self.peek().span, "expected `)` after call arguments");
                }
                expr = try self.tree.addExpr(.{ .call = .{
                    .callee = expr,
                    .args = .{ .start = args_start, .len = args_len },
                    .span = base.Span.join(self.tree.exprs.items[expr].span(), end_span),
                } });
            } else if (self.allow_struct_literal and self.match(.l_brace) != null) {
                const fields_start = self.tree.reserveStructLiteralFields();
                var fields_len: u32 = 0;
                var end_span = self.tree.exprs.items[expr].span();

                while (self.peekKind() != .r_brace and self.peekKind() != .eof) {
                    const field_name = (try self.expectIdentifier("expected struct literal field name")) orelse break;
                    var value: ?ast_mod.ExprId = null;
                    var field_end = field_name.span;
                    if (self.match(.colon) != null) {
                        value = try self.parseExpression(@intFromEnum(Precedence.lowest));
                        field_end = self.tree.exprs.items[value.?].span();
                    }
                    try self.tree.addStructLiteralField(.{
                        .name = try self.internToken(field_name),
                        .name_span = field_name.span,
                        .value = value,
                        .span = base.Span.join(field_name.span, field_end),
                    });
                    fields_len += 1;
                    end_span = field_end;
                    if (self.match(.comma) == null) break;
                }

                if (self.match(.r_brace)) |brace| {
                    end_span = brace.span;
                } else {
                    try self.addError(self.peek().span, "expected `}` after struct literal fields");
                }
                expr = try self.tree.addExpr(.{ .struct_literal = .{
                    .type_expr = expr,
                    .fields = .{ .start = fields_start, .len = fields_len },
                    .span = base.Span.join(self.tree.exprs.items[expr].span(), end_span),
                } });
            } else {
                break;
            }
        }

        return expr;
    }

    fn parsePrimary(self: *Parser) Allocator.Error!ast_mod.ExprId {
        const token = self.advance();
        switch (token.kind) {
            .identifier => return self.tree.addExpr(.{ .name = .{
                .symbol = try self.internToken(token),
                .span = token.span,
            } }),
            .int_literal => return self.tree.addExpr(.{ .int_literal = token.span }),
            .float_literal => return self.tree.addExpr(.{ .float_literal = token.span }),
            .string_literal => return self.tree.addExpr(.{ .string_literal = token.span }),
            .char_literal => return self.tree.addExpr(.{ .char_literal = token.span }),
            .keyword_true => return self.tree.addExpr(.{ .bool_literal = .{ .value = true, .span = token.span } }),
            .keyword_false => return self.tree.addExpr(.{ .bool_literal = .{ .value = false, .span = token.span } }),
            .keyword_if => return self.parseIfExpr(token.span),
            .l_paren => {
                const expr = try self.parseExpression(@intFromEnum(Precedence.lowest));
                _ = try self.expect(.r_paren, "expected `)` after expression");
                return expr;
            },
            else => {
                try self.addError(token.span, "expected expression");
                return self.tree.addExpr(.{ .name = .{
                    .symbol = try self.interner.intern("<error>"),
                    .span = token.span,
                } });
            },
        }
    }

    fn parseIfExpr(self: *Parser, start_span: base.Span) Allocator.Error!ast_mod.ExprId {
        const old_allow_struct_literal = self.allow_struct_literal;
        self.allow_struct_literal = false;
        defer self.allow_struct_literal = old_allow_struct_literal;
        const condition = try self.parseExpression(@intFromEnum(Precedence.lowest));

        const then_block = try self.parseBlock();
        var else_block: ?ast_mod.BlockId = null;
        var end_span = self.tree.blocks.items[then_block].span;

        if (self.match(.keyword_else) != null) {
            else_block = try self.parseBlock();
            end_span = self.tree.blocks.items[else_block.?].span;
        }

        return self.tree.addExpr(.{ .if_expr = .{
            .condition = condition,
            .then_block = then_block,
            .else_block = else_block,
            .span = base.Span.join(start_span, end_span),
        } });
    }

    const BinaryOpInfo = struct {
        op: ast_mod.BinaryOp,
        precedence: Precedence,
        right_associative: bool = false,
    };

    fn binaryOp(kind: lexer.TokenKind) ?BinaryOpInfo {
        return switch (kind) {
            .equal => .{ .op = .assign, .precedence = .assignment, .right_associative = true },
            .plus_equal => .{ .op = .add_assign, .precedence = .assignment, .right_associative = true },
            .minus_equal => .{ .op = .sub_assign, .precedence = .assignment, .right_associative = true },
            .star_equal => .{ .op = .mul_assign, .precedence = .assignment, .right_associative = true },
            .slash_equal => .{ .op = .div_assign, .precedence = .assignment, .right_associative = true },
            .percent_equal => .{ .op = .rem_assign, .precedence = .assignment, .right_associative = true },
            .pipe_pipe => .{ .op = .logical_or, .precedence = .logical_or },
            .amp_amp => .{ .op = .logical_and, .precedence = .logical_and },
            .equal_equal => .{ .op = .equal, .precedence = .equality },
            .bang_equal => .{ .op = .not_equal, .precedence = .equality },
            .less => .{ .op = .less, .precedence = .comparison },
            .less_equal => .{ .op = .less_equal, .precedence = .comparison },
            .greater => .{ .op = .greater, .precedence = .comparison },
            .greater_equal => .{ .op = .greater_equal, .precedence = .comparison },
            .plus => .{ .op = .add, .precedence = .term },
            .minus => .{ .op = .sub, .precedence = .term },
            .star => .{ .op = .mul, .precedence = .factor },
            .slash => .{ .op = .div, .precedence = .factor },
            .percent => .{ .op = .rem, .precedence = .factor },
            else => null,
        };
    }

    fn nextPrecedence(precedence: Precedence) u8 {
        return @intFromEnum(precedence) + 1;
    }

    fn parseTypeAlias(self: *Parser, visibility: ast_mod.Visibility, start_span: base.Span) Allocator.Error!void {
        _ = (try self.expect(.keyword_type, "expected type alias declaration")) orelse return;
        const name_token = (try self.expectIdentifier("expected type alias name")) orelse return;
        _ = (try self.expect(.equal, "expected `=` after type alias name")) orelse return;

        const aliased_type = try self.parsePath("expected aliased type");
        var end_span = self.previous().span;
        if (self.match(.semicolon)) |semicolon| {
            end_span = semicolon.span;
        }

        _ = try self.tree.addDecl(.{ .type_alias = .{
            .visibility = visibility,
            .name = try self.internToken(name_token),
            .name_span = name_token.span,
            .aliased_type = aliased_type,
            .span = base.Span.join(start_span, end_span),
        } });
    }

    fn parseEnum(self: *Parser, visibility: ast_mod.Visibility, start_span: base.Span) Allocator.Error!void {
        _ = (try self.expect(.keyword_enum, "expected enum declaration")) orelse return;
        const name_token = (try self.expectIdentifier("expected enum name")) orelse return;
        const name = try self.internToken(name_token);

        _ = (try self.expect(.l_brace, "expected `{` after enum name")) orelse return;

        const variants_start = self.tree.reserveEnumVariants();
        var variants_len: u32 = 0;
        var end_span = name_token.span;

        while (self.peekKind() != .r_brace and self.peekKind() != .eof) {
            self.skipTrivia();
            if (self.peekKind() == .r_brace or self.peekKind() == .eof) break;

            const variant = try self.parseEnumVariant();
            try self.tree.addEnumVariant(variant);
            variants_len += 1;
            end_span = variant.span;

            if (self.match(.comma)) |comma| {
                end_span = comma.span;
            }
        }

        if (self.match(.r_brace)) |brace| {
            end_span = brace.span;
        } else {
            try self.addError(self.peek().span, "expected `}` after enum variants");
        }

        _ = try self.tree.addDecl(.{ .enum_decl = .{
            .visibility = visibility,
            .name = name,
            .name_span = name_token.span,
            .variants = .{ .start = variants_start, .len = variants_len },
            .span = base.Span.join(start_span, end_span),
        } });
    }

    fn parseEnumVariant(self: *Parser) Allocator.Error!ast_mod.EnumVariant {
        const name_token = (try self.expectIdentifier("expected enum variant name")) orelse return .{
            .name = try self.interner.intern("<error>"),
            .name_span = self.peek().span,
            .kind = .unit,
            .span = self.peek().span,
        };
        const name = try self.internToken(name_token);

        if (self.match(.l_paren) != null) {
            const fields_start = self.tree.reserveEnumFields();
            var fields_len: u32 = 0;
            var end_span = name_token.span;

            while (self.peekKind() != .r_paren and self.peekKind() != .eof) {
                const type_path = try self.parsePath("expected tuple variant field type");
                const field_end = self.previous().span;
                try self.tree.addEnumField(.{
                    .type_path = type_path,
                    .span = field_end,
                });
                fields_len += 1;
                end_span = field_end;

                if (self.match(.comma) == null) break;
            }

            if (self.match(.r_paren)) |paren| {
                end_span = paren.span;
            } else {
                try self.addError(self.peek().span, "expected `)` after tuple variant fields");
            }

            return .{
                .name = name,
                .name_span = name_token.span,
                .kind = .tuple,
                .fields = .{ .start = fields_start, .len = fields_len },
                .span = base.Span.join(name_token.span, end_span),
            };
        }

        if (self.match(.l_brace) != null) {
            const fields_start = self.tree.reserveEnumFields();
            var fields_len: u32 = 0;
            var end_span = name_token.span;

            while (self.peekKind() != .r_brace and self.peekKind() != .eof) {
                const field_name_token = (try self.expectIdentifier("expected record variant field name")) orelse break;
                _ = (try self.expect(.colon, "expected `:` after record variant field name")) orelse return .{
                    .name = name,
                    .name_span = name_token.span,
                    .kind = .record,
                    .fields = .{ .start = fields_start, .len = fields_len },
                    .span = name_token.span,
                };

                const type_path = try self.parsePath("expected record variant field type");
                const field_end = self.previous().span;
                try self.tree.addEnumField(.{
                    .name = try self.internToken(field_name_token),
                    .name_span = field_name_token.span,
                    .type_path = type_path,
                    .span = base.Span.join(field_name_token.span, field_end),
                });
                fields_len += 1;
                end_span = field_end;

                if (self.match(.comma) == null) break;
            }

            if (self.match(.r_brace)) |brace| {
                end_span = brace.span;
            } else {
                try self.addError(self.peek().span, "expected `}` after record variant fields");
            }

            return .{
                .name = name,
                .name_span = name_token.span,
                .kind = .record,
                .fields = .{ .start = fields_start, .len = fields_len },
                .span = base.Span.join(name_token.span, end_span),
            };
        }

        return .{
            .name = name,
            .name_span = name_token.span,
            .kind = .unit,
            .span = name_token.span,
        };
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
        return self.interner.intern(self.tokenText(token));
    }

    fn tokenText(self: *Parser, token: lexer.Token) []const u8 {
        const start: usize = token.span.start;
        const end: usize = token.span.end();
        return self.source[start..end];
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

test "parser builds type alias AST" {
    const source =
        \\pub type UserId = Int;
        \\type ConfigMap = Map;
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
            "  TypeAliasDecl public UserId = Int\n" ++
            "  TypeAliasDecl package ConfigMap = Map\n",
        dumped,
    );
}

test "parser builds function declaration AST" {
    const source =
        \\pub fn birthday(mut user: User) -> User {
        \\    user
        \\}
        \\fn log_user(user: User) {}
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
            "  FnDecl public birthday\n" ++
            "    Param mut user: User\n" ++
            "    Return User\n" ++
            "    Block\n" ++
            "      FinalExpr\n" ++
            "        Name user\n" ++
            "  FnDecl package log_user\n" ++
            "    Param user: User\n" ++
            "    Return ()\n" ++
            "    Block\n",
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

test "parser builds enum AST" {
    const source =
        \\pub enum Shape {
        \\    Circle { radius: Float },
        \\    Pair(Int, Int),
        \\    Point,
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
            "  EnumDecl public Shape\n" ++
            "    Variant record Circle\n" ++
            "      Field radius: Float\n" ++
            "    Variant tuple Pair\n" ++
            "      Field _: Int\n" ++
            "      Field _: Int\n" ++
            "    Variant unit Point\n",
        dumped,
    );
}
