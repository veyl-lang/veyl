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
            } else if (self.peekKind() == .keyword_impl) {
                try self.parseImpl(visibility, start_span);
            } else if (self.peekKind() == .keyword_interface) {
                try self.parseInterface(visibility, start_span);
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
        var items_start: u32 = 0;
        var items_len: u32 = 0;

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
            if (self.match(.l_brace)) |_| {
                items_start = self.tree.reserveImportItems();
                while (self.peekKind() != .r_brace and self.peekKind() != .eof) {
                    const item_token = (try self.expectIdentifier("expected grouped import item")) orelse break;
                    var item_end = item_token.span;
                    var alias: ?base.SymbolId = null;
                    var alias_span: ?base.Span = null;
                    if (self.match(.keyword_as) != null) {
                        const alias_token = (try self.expectIdentifier("expected import alias after `as`")) orelse break;
                        alias = try self.internToken(alias_token);
                        alias_span = alias_token.span;
                        item_end = alias_token.span;
                    }

                    try self.tree.addImportItem(.{
                        .name = try self.internToken(item_token),
                        .name_span = item_token.span,
                        .alias = alias,
                        .alias_span = alias_span,
                        .span = base.Span.join(item_token.span, item_end),
                    });
                    items_len += 1;
                    end_span = item_end;

                    if (self.match(.comma)) |comma| {
                        end_span = comma.span;
                        continue;
                    }
                    break;
                }

                if (self.match(.r_brace)) |brace| {
                    end_span = brace.span;
                } else {
                    try self.addError(self.peek().span, "expected `}` after grouped import items");
                }
                break;
            }
        }

        var alias: ?base.SymbolId = null;
        var alias_span: ?base.Span = null;
        if (items_len == 0 and self.match(.keyword_as) != null) {
            const alias_token = (try self.expectIdentifier("expected import alias after `as`")) orelse return;
            alias = try self.internToken(alias_token);
            alias_span = alias_token.span;
            end_span = alias_token.span;
        }

        if (path_len == 0) return;
        _ = try self.tree.addDecl(.{ .import = .{
            .visibility = visibility,
            .path = .{ .start = path_start, .len = path_len },
            .items = .{ .start = items_start, .len = items_len },
            .alias = alias,
            .alias_span = alias_span,
            .span = base.Span.join(start_span, end_span),
        } });
    }

    fn parseFn(self: *Parser, visibility: ast_mod.Visibility, start_span: base.Span) Allocator.Error!void {
        _ = try self.tree.addDecl(.{ .fn_decl = try self.parseFnDecl(visibility, start_span) });
    }

    fn parseFnDecl(self: *Parser, visibility: ast_mod.Visibility, start_span: base.Span) Allocator.Error!ast_mod.FnDecl {
        _ = (try self.expect(.keyword_fn, "expected function declaration")) orelse return self.errorFnDecl(visibility, start_span);
        const name_token = (try self.expectIdentifier("expected function name")) orelse return self.errorFnDecl(visibility, start_span);
        const generic_params = try self.parseGenericParams();
        _ = (try self.expect(.l_paren, "expected `(` after function name")) orelse return self.errorFnDecl(visibility, start_span);

        const params_start = self.tree.reserveFnParams();
        var params_len: u32 = 0;
        while (self.peekKind() != .r_paren and self.peekKind() != .eof) {
            const param = try self.parseFnParam();
            try self.tree.addFnParam(param);
            params_len += 1;
            if (self.match(.comma) == null) break;
        }

        _ = (try self.expect(.r_paren, "expected `)` after function parameters")) orelse return self.errorFnDecl(visibility, start_span);

        var return_type: ?ast_mod.TypeId = null;
        if (self.match(.arrow) != null) {
            return_type = try self.parseTypeExpr("expected function return type");
        }

        const where_predicates = try self.parseWhereClause();

        const body = try self.parseBlock();
        return .{
            .visibility = visibility,
            .name = try self.internToken(name_token),
            .name_span = name_token.span,
            .generic_params = generic_params,
            .params = .{ .start = params_start, .len = params_len },
            .return_type = return_type,
            .where_predicates = where_predicates,
            .body = body,
            .span = base.Span.join(start_span, self.tree.blocks.items[body].span),
        };
    }

    fn errorFnDecl(self: *Parser, visibility: ast_mod.Visibility, span: base.Span) Allocator.Error!ast_mod.FnDecl {
        const body = try self.emptyBlock(span);
        return .{
            .visibility = visibility,
            .name = try self.interner.intern("<error>"),
            .name_span = span,
            .params = .{ .start = self.tree.reserveFnParams(), .len = 0 },
            .body = body,
            .span = span,
        };
    }

    fn parseImpl(self: *Parser, visibility: ast_mod.Visibility, start_span: base.Span) Allocator.Error!void {
        _ = (try self.expect(.keyword_impl, "expected impl declaration")) orelse return;
        const generic_params = try self.parseGenericParams();

        const first_type = try self.parseTypeExpr("expected impl type");
        var interface_type: ?ast_mod.TypeId = null;
        var self_type = first_type;
        if (self.match(.keyword_for) != null) {
            interface_type = first_type;
            self_type = try self.parseTypeExpr("expected impl target type after `for`");
        }

        const where_predicates = try self.parseWhereClause();
        _ = (try self.expect(.l_brace, "expected `{` after impl type")) orelse return;

        const methods_start = self.tree.reserveImplMethods();
        var methods_len: u32 = 0;
        var end_span = self.tree.types.items[self_type].span();
        while (self.peekKind() != .r_brace and self.peekKind() != .eof) {
            self.skipTrivia();
            if (self.peekKind() == .r_brace or self.peekKind() == .eof) break;

            var method_visibility: ast_mod.Visibility = .package;
            var method_start = self.peek().span;
            if (self.match(.keyword_pub)) |token| {
                method_visibility = .public;
                method_start = token.span;
            } else if (self.match(.keyword_private)) |token| {
                method_visibility = .private;
                method_start = token.span;
            }

            if (self.peekKind() != .keyword_fn) {
                try self.addError(self.peek().span, "expected method declaration");
                _ = self.advance();
                continue;
            }

            const method = try self.parseFnDecl(method_visibility, method_start);
            try self.tree.addImplMethod(method);
            methods_len += 1;
            end_span = method.span;
        }

        if (self.match(.r_brace)) |brace| {
            end_span = brace.span;
        } else {
            try self.addError(self.peek().span, "expected `}` after impl body");
        }

        _ = try self.tree.addDecl(.{ .impl_decl = .{
            .visibility = visibility,
            .generic_params = generic_params,
            .interface_type = interface_type,
            .self_type = self_type,
            .where_predicates = where_predicates,
            .methods = .{ .start = methods_start, .len = methods_len },
            .span = base.Span.join(start_span, end_span),
        } });
    }

    fn parseInterface(self: *Parser, visibility: ast_mod.Visibility, start_span: base.Span) Allocator.Error!void {
        _ = (try self.expect(.keyword_interface, "expected interface declaration")) orelse return;
        const name_token = (try self.expectIdentifier("expected interface name")) orelse return;
        const generic_params = try self.parseGenericParams();
        const where_predicates = try self.parseWhereClause();
        _ = (try self.expect(.l_brace, "expected `{` after interface name")) orelse return;

        const methods_start = self.tree.reserveInterfaceMethods();
        var methods_len: u32 = 0;
        var end_span = name_token.span;
        while (self.peekKind() != .r_brace and self.peekKind() != .eof) {
            self.skipTrivia();
            if (self.peekKind() == .r_brace or self.peekKind() == .eof) break;

            var method_visibility: ast_mod.Visibility = .package;
            var method_start = self.peek().span;
            if (self.match(.keyword_pub)) |token| {
                method_visibility = .public;
                method_start = token.span;
            } else if (self.match(.keyword_private)) |token| {
                method_visibility = .private;
                method_start = token.span;
            }

            if (self.peekKind() != .keyword_fn) {
                try self.addError(self.peek().span, "expected interface method declaration");
                _ = self.advance();
                continue;
            }

            const method = try self.parseInterfaceMethod(method_visibility, method_start);
            try self.tree.addInterfaceMethod(method);
            methods_len += 1;
            end_span = method.span;
        }

        if (self.match(.r_brace)) |brace| {
            end_span = brace.span;
        } else {
            try self.addError(self.peek().span, "expected `}` after interface body");
        }

        _ = try self.tree.addDecl(.{ .interface_decl = .{
            .visibility = visibility,
            .name = try self.internToken(name_token),
            .name_span = name_token.span,
            .generic_params = generic_params,
            .where_predicates = where_predicates,
            .methods = .{ .start = methods_start, .len = methods_len },
            .span = base.Span.join(start_span, end_span),
        } });
    }

    fn parseInterfaceMethod(self: *Parser, visibility: ast_mod.Visibility, start_span: base.Span) Allocator.Error!ast_mod.InterfaceMethod {
        _ = (try self.expect(.keyword_fn, "expected interface method declaration")) orelse return self.errorInterfaceMethod(visibility, start_span);
        const name_token = (try self.expectIdentifier("expected interface method name")) orelse return self.errorInterfaceMethod(visibility, start_span);
        const generic_params = try self.parseGenericParams();
        _ = (try self.expect(.l_paren, "expected `(` after interface method name")) orelse return self.errorInterfaceMethod(visibility, start_span);

        const params_start = self.tree.reserveFnParams();
        var params_len: u32 = 0;
        while (self.peekKind() != .r_paren and self.peekKind() != .eof) {
            const param = try self.parseFnParam();
            try self.tree.addFnParam(param);
            params_len += 1;
            if (self.match(.comma) == null) break;
        }

        _ = (try self.expect(.r_paren, "expected `)` after interface method parameters")) orelse return self.errorInterfaceMethod(visibility, start_span);

        var return_type: ?ast_mod.TypeId = null;
        if (self.match(.arrow) != null) {
            return_type = try self.parseTypeExpr("expected interface method return type");
        }
        const where_predicates = try self.parseWhereClause();

        var end_span = self.previous().span;
        if (self.match(.semicolon)) |semicolon| {
            end_span = semicolon.span;
        } else {
            try self.addError(self.peek().span, "expected `;` after interface method signature");
        }

        return .{
            .visibility = visibility,
            .name = try self.internToken(name_token),
            .name_span = name_token.span,
            .generic_params = generic_params,
            .params = .{ .start = params_start, .len = params_len },
            .return_type = return_type,
            .where_predicates = where_predicates,
            .span = base.Span.join(start_span, end_span),
        };
    }

    fn errorInterfaceMethod(self: *Parser, visibility: ast_mod.Visibility, span: base.Span) Allocator.Error!ast_mod.InterfaceMethod {
        return .{
            .visibility = visibility,
            .name = try self.interner.intern("<error>"),
            .name_span = span,
            .params = .{ .start = self.tree.reserveFnParams(), .len = 0 },
            .span = span,
        };
    }

    fn parseFnParam(self: *Parser) Allocator.Error!ast_mod.FnParam {
        var is_mut = false;
        var start_span = self.peek().span;
        if (self.match(.keyword_mut)) |mut_token| {
            is_mut = true;
            start_span = mut_token.span;
        }

        const name_token = (try self.expectParamName("expected function parameter name")) orelse return .{
            .is_mut = is_mut,
            .name = try self.interner.intern("<error>"),
            .name_span = start_span,
            .type_expr = try self.tree.addType(.{ .unit = start_span }),
            .span = start_span,
        };
        if (name_token.kind == .keyword_self and self.peekKind() != .colon) {
            const self_type_start = self.tree.reservePath();
            try self.tree.addPathSegment(.{
                .name = try self.interner.intern("Self"),
                .span = name_token.span,
            });
            const self_type = try self.tree.addType(.{ .path = .{
                .segments = .{ .start = self_type_start, .len = 1 },
                .span = name_token.span,
            } });
            return .{
                .is_mut = is_mut,
                .name = try self.internToken(name_token),
                .name_span = name_token.span,
                .type_expr = self_type,
                .span = base.Span.join(start_span, name_token.span),
            };
        }
        _ = (try self.expect(.colon, "expected `:` after function parameter name")) orelse return .{
            .is_mut = is_mut,
            .name = try self.internToken(name_token),
            .name_span = name_token.span,
            .type_expr = try self.tree.addType(.{ .unit = name_token.span }),
            .span = name_token.span,
        };

        const type_expr = try self.parseTypeExpr("expected function parameter type");
        return .{
            .is_mut = is_mut,
            .name = try self.internToken(name_token),
            .name_span = name_token.span,
            .type_expr = type_expr,
            .span = base.Span.join(start_span, self.previous().span),
        };
    }

    fn parseGenericParams(self: *Parser) Allocator.Error!base.Range {
        if (self.match(.less) == null) return .{ .start = 0, .len = 0 };

        const params_start = self.tree.reserveGenericParams();
        var params_len: u32 = 0;
        while (self.peekKind() != .greater and self.peekKind() != .eof) {
            const name_token = (try self.expectTypeSegment("expected generic parameter name")) orelse break;
            var constraint: ?ast_mod.TypeId = null;
            var end_span = name_token.span;
            if (self.match(.colon) != null) {
                constraint = try self.parseTypeExpr("expected generic parameter constraint");
                end_span = self.tree.types.items[constraint.?].span();
            }

            try self.tree.addGenericParam(.{
                .name = try self.internToken(name_token),
                .name_span = name_token.span,
                .constraint = constraint,
                .span = base.Span.join(name_token.span, end_span),
            });
            params_len += 1;

            if (self.match(.comma) == null) break;
        }

        _ = try self.expect(.greater, "expected `>` after generic parameters");
        return .{ .start = params_start, .len = params_len };
    }

    fn parseWhereClause(self: *Parser) Allocator.Error!base.Range {
        if (self.match(.keyword_where) == null) return .{ .start = 0, .len = 0 };

        const predicates_start = self.tree.reserveWherePredicates();
        var predicates_len: u32 = 0;
        while (self.peekKind() != .l_brace and self.peekKind() != .semicolon and self.peekKind() != .eof) {
            const subject = try self.parseTypeExpr("expected where-clause subject");
            _ = (try self.expect(.colon, "expected `:` in where clause")) orelse break;
            const constraint = try self.parseTypeExpr("expected where-clause constraint");

            try self.tree.addWherePredicate(.{
                .subject = subject,
                .constraint = constraint,
                .span = base.Span.join(self.tree.types.items[subject].span(), self.tree.types.items[constraint].span()),
            });
            predicates_len += 1;

            if (self.match(.comma) == null) break;
        }

        return .{ .start = predicates_start, .len = predicates_len };
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
                } else if (self.tree.exprs.items[expr] == .if_expr and self.peekKind() != .r_brace and self.peekKind() != .eof) {
                    try block_stmt_ids.append(self.tree.allocator, try self.tree.addStmt(.{ .expr_stmt = expr }));
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
        const pattern = try self.parsePattern();
        _ = (try self.expect(.equal, "expected `=` after let pattern")) orelse return error.OutOfMemory;

        const value = try self.parseExpression(@intFromEnum(Precedence.lowest));
        var end_span = self.tree.exprs.items[value].span();
        var else_block: ?ast_mod.BlockId = null;
        if (self.match(.keyword_else) != null) {
            else_block = try self.parseBlock();
            end_span = self.tree.blocks.items[else_block.?].span;
        } else if (self.match(.semicolon)) |semicolon| {
            end_span = semicolon.span;
        } else {
            try self.addError(self.peek().span, "expected `;` after let statement");
        }

        return .{
            .pattern = pattern,
            .value = value,
            .else_block = else_block,
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
        const condition = try self.parseControlCondition();

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
        catch_expr = 2,
        logical_or = 3,
        logical_and = 4,
        equality = 5,
        comparison = 6,
        term = 7,
        factor = 8,
    };

    fn parseExpression(self: *Parser, min_precedence: u8) Allocator.Error!ast_mod.ExprId {
        var left = try self.parsePostfix();

        while (true) {
            if (self.peekKind() == .keyword_catch) {
                if (@intFromEnum(Precedence.catch_expr) < min_precedence) break;
                _ = self.advance();
                left = try self.parseCatchExpr(left);
                continue;
            }

            const op_info = binaryOp(self.peekKind()) orelse break;
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

    fn parseCatchExpr(self: *Parser, value: ast_mod.ExprId) Allocator.Error!ast_mod.ExprId {
        var binding: ?ast_mod.CatchBinding = null;
        if (self.match(.pipe)) |open_pipe| {
            const binding_token = (try self.expectIdentifier("expected catch binding name")) orelse return value;
            var binding_span = binding_token.span;
            if (self.match(.pipe)) |close_pipe| {
                binding_span = base.Span.join(open_pipe.span, close_pipe.span);
            } else {
                try self.addError(self.peek().span, "expected `|` after catch binding");
            }
            binding = .{
                .name = try self.internToken(binding_token),
                .span = binding_span,
            };
        }

        const handler: ast_mod.CatchHandler = if (self.peekKind() == .l_brace) handler: {
            break :handler .{ .block = try self.parseBlock() };
        } else handler: {
            break :handler .{ .expr = try self.parseExpression(nextPrecedence(.catch_expr)) };
        };

        const span = base.Span.join(self.tree.exprs.items[value].span(), handler.span(&self.tree));
        return self.tree.addExpr(.{ .catch_expr = .{
            .value = value,
            .binding = binding,
            .handler = handler,
            .span = span,
        } });
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
            } else if (self.match(.l_bracket)) |_| {
                const index_expr = try self.parseExpression(@intFromEnum(Precedence.lowest));
                var end_span = self.tree.exprs.items[index_expr].span();
                if (self.match(.r_bracket)) |bracket| {
                    end_span = bracket.span;
                } else {
                    try self.addError(self.peek().span, "expected `]` after index expression");
                }
                expr = try self.tree.addExpr(.{ .index = .{
                    .base = expr,
                    .index = index_expr,
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
            .identifier, .keyword_self, .keyword_Self => return self.tree.addExpr(.{ .name = .{
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
            .keyword_match => return self.parseMatchExpr(token.span),
            .keyword_try => return self.parseTryExpr(token.span),
            .l_bracket => return self.parseArrayLiteral(token.span),
            .l_paren => {
                if (self.match(.r_paren)) |close| {
                    return self.tree.addExpr(.{ .unit_literal = base.Span.join(token.span, close.span) });
                }
                const expr = try self.parseExpression(@intFromEnum(Precedence.lowest));
                _ = try self.expect(.r_paren, "expected `)` after expression");
                return expr;
            },
            else => {
                try self.addError(token.span, "expected expression");
                return self.errorExpr(token.span);
            },
        }
    }

    fn errorExpr(self: *Parser, span: base.Span) Allocator.Error!ast_mod.ExprId {
        return self.tree.addExpr(.{ .name = .{
            .symbol = try self.interner.intern("<error>"),
            .span = span,
        } });
    }

    fn parseTryExpr(self: *Parser, start_span: base.Span) Allocator.Error!ast_mod.ExprId {
        const value = try self.parseExpression(nextPrecedence(.factor));
        return self.tree.addExpr(.{ .try_expr = .{
            .value = value,
            .span = base.Span.join(start_span, self.tree.exprs.items[value].span()),
        } });
    }

    fn parseArrayLiteral(self: *Parser, start_span: base.Span) Allocator.Error!ast_mod.ExprId {
        const items_start = self.tree.reserveExprArgs();
        var items_len: u32 = 0;
        var end_span = start_span;

        while (self.peekKind() != .r_bracket and self.peekKind() != .eof) {
            const item = try self.parseExpression(@intFromEnum(Precedence.lowest));
            try self.tree.addExprArg(item);
            items_len += 1;
            end_span = self.tree.exprs.items[item].span();
            if (self.match(.comma) == null) break;
        }

        if (self.match(.r_bracket)) |bracket| {
            end_span = bracket.span;
        } else {
            try self.addError(self.peek().span, "expected `]` after array literal");
        }

        return self.tree.addExpr(.{ .array_literal = .{
            .items = .{ .start = items_start, .len = items_len },
            .span = base.Span.join(start_span, end_span),
        } });
    }

    fn parseIfExpr(self: *Parser, start_span: base.Span) Allocator.Error!ast_mod.ExprId {
        const old_allow_struct_literal = self.allow_struct_literal;
        self.allow_struct_literal = false;
        defer self.allow_struct_literal = old_allow_struct_literal;
        const condition = try self.parseControlCondition();

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

    fn parseControlCondition(self: *Parser) Allocator.Error!ast_mod.ControlCondition {
        if (self.match(.keyword_let)) |let_token| {
            const pattern = try self.parsePattern();
            _ = (try self.expect(.equal, "expected `=` after condition pattern")) orelse return .{ .let_pattern = .{
                .pattern = pattern,
                .value = try self.errorExpr(let_token.span),
                .span = base.Span.join(let_token.span, self.tree.patterns.items[pattern].span()),
            } };
            const value = try self.parseExpression(@intFromEnum(Precedence.lowest));
            return .{ .let_pattern = .{
                .pattern = pattern,
                .value = value,
                .span = base.Span.join(let_token.span, self.tree.exprs.items[value].span()),
            } };
        }

        return .{ .expr = try self.parseExpression(@intFromEnum(Precedence.lowest)) };
    }

    fn parseMatchExpr(self: *Parser, start_span: base.Span) Allocator.Error!ast_mod.ExprId {
        const old_allow_struct_literal = self.allow_struct_literal;
        self.allow_struct_literal = false;
        const value = try self.parseExpression(@intFromEnum(Precedence.lowest));
        self.allow_struct_literal = old_allow_struct_literal;
        _ = (try self.expect(.l_brace, "expected `{` after match value")) orelse return value;

        const arms_start = self.tree.reserveMatchArms();
        var arms_len: u32 = 0;
        var end_span = self.tree.exprs.items[value].span();

        while (self.peekKind() != .r_brace and self.peekKind() != .eof) {
            self.skipTrivia();
            if (self.peekKind() == .r_brace or self.peekKind() == .eof) break;

            const arm = try self.parseMatchArm();
            try self.tree.addMatchArm(arm);
            arms_len += 1;
            end_span = arm.span;
            if (self.match(.comma)) |comma| {
                end_span = comma.span;
            }
        }

        if (self.match(.r_brace)) |brace| {
            end_span = brace.span;
        } else {
            try self.addError(self.peek().span, "expected `}` after match arms");
        }

        return self.tree.addExpr(.{ .match_expr = .{
            .value = value,
            .arms = .{ .start = arms_start, .len = arms_len },
            .span = base.Span.join(start_span, end_span),
        } });
    }

    fn parseMatchArm(self: *Parser) Allocator.Error!ast_mod.MatchArm {
        const pattern = try self.parsePattern();
        var guard: ?ast_mod.ExprId = null;
        if (self.match(.keyword_if) != null) {
            guard = try self.parseExpression(@intFromEnum(Precedence.lowest));
        }
        _ = (try self.expect(.fat_arrow, "expected `=>` after match pattern")) orelse {
            const span = self.tree.patterns.items[pattern].span();
            const error_expr = try self.tree.addExpr(.{ .name = .{
                .symbol = try self.interner.intern("<error>"),
                .span = span,
            } });
            return .{
                .pattern = pattern,
                .guard = guard,
                .body = .{ .expr = error_expr },
                .span = span,
            };
        };

        const body: ast_mod.MatchArmBody = if (self.peekKind() == .l_brace) body: {
            break :body .{ .block = try self.parseBlock() };
        } else body: {
            break :body .{ .expr = try self.parseExpression(@intFromEnum(Precedence.lowest)) };
        };

        return .{
            .pattern = pattern,
            .guard = guard,
            .body = body,
            .span = base.Span.join(self.tree.patterns.items[pattern].span(), body.span(&self.tree)),
        };
    }

    fn parsePattern(self: *Parser) Allocator.Error!ast_mod.PatternId {
        const first = try self.parseRangePattern();
        if (self.peekKind() != .pipe) return first;

        const patterns_start = self.tree.reservePatternArgs();
        try self.tree.addPatternArg(first);
        var patterns_len: u32 = 1;
        var end_span = self.tree.patterns.items[first].span();

        while (self.match(.pipe) != null) {
            const item = try self.parseRangePattern();
            try self.tree.addPatternArg(item);
            patterns_len += 1;
            end_span = self.tree.patterns.items[item].span();
        }

        return self.tree.addPattern(.{ .or_pattern = .{
            .patterns = .{ .start = patterns_start, .len = patterns_len },
            .span = base.Span.join(self.tree.patterns.items[first].span(), end_span),
        } });
    }

    fn parseRangePattern(self: *Parser) Allocator.Error!ast_mod.PatternId {
        const start = try self.parsePrimaryPattern();
        if (self.match(.dot_dot_equal)) |_| {
            const end = try self.parsePrimaryPattern();
            return self.tree.addPattern(.{ .range = .{
                .start = start,
                .end = end,
                .inclusive = true,
                .span = base.Span.join(self.tree.patterns.items[start].span(), self.tree.patterns.items[end].span()),
            } });
        }
        if (self.match(.dot_dot)) |_| {
            const end = try self.parsePrimaryPattern();
            return self.tree.addPattern(.{ .range = .{
                .start = start,
                .end = end,
                .inclusive = false,
                .span = base.Span.join(self.tree.patterns.items[start].span(), self.tree.patterns.items[end].span()),
            } });
        }
        return start;
    }

    fn parsePrimaryPattern(self: *Parser) Allocator.Error!ast_mod.PatternId {
        const token = self.advance();
        switch (token.kind) {
            .underscore => return self.tree.addPattern(.{ .wildcard = token.span }),
            .keyword_mut => {
                const name_token = (try self.expectIdentifier("expected binding name after `mut`")) orelse return self.tree.addPattern(.{ .wildcard = token.span });
                return self.tree.addPattern(.{ .binding = .{
                    .name = try self.internToken(name_token),
                    .name_span = name_token.span,
                    .is_mut = true,
                    .span = base.Span.join(token.span, name_token.span),
                } });
            },
            .int_literal => return self.tree.addPattern(.{ .int_literal = token.span }),
            .float_literal => return self.tree.addPattern(.{ .float_literal = token.span }),
            .string_literal => return self.tree.addPattern(.{ .string_literal = token.span }),
            .char_literal => return self.tree.addPattern(.{ .char_literal = token.span }),
            .keyword_true => return self.tree.addPattern(.{ .bool_literal = .{ .value = true, .span = token.span } }),
            .keyword_false => return self.tree.addPattern(.{ .bool_literal = .{ .value = false, .span = token.span } }),
            .dot_dot => return self.parseRestPattern(token.span),
            .l_bracket => return self.parseArrayPattern(token.span),
            .identifier, .keyword_Self => return self.parsePathPattern(token),
            else => {
                try self.addError(token.span, "expected pattern");
                return self.tree.addPattern(.{ .wildcard = token.span });
            },
        }
    }

    fn parseRestPattern(self: *Parser, start_span: base.Span) Allocator.Error!ast_mod.PatternId {
        var name: ?base.SymbolId = null;
        var name_span: ?base.Span = null;
        var end_span = start_span;
        if (self.peekKind() == .identifier) {
            const name_token = self.advance();
            name = try self.internToken(name_token);
            name_span = name_token.span;
            end_span = name_token.span;
        }
        return self.tree.addPattern(.{ .rest = .{
            .name = name,
            .name_span = name_span,
            .span = base.Span.join(start_span, end_span),
        } });
    }

    fn parseArrayPattern(self: *Parser, start_span: base.Span) Allocator.Error!ast_mod.PatternId {
        const items_start = self.tree.reservePatternArgs();
        var items_len: u32 = 0;
        var end_span = start_span;
        while (self.peekKind() != .r_bracket and self.peekKind() != .eof) {
            const item = try self.parsePattern();
            try self.tree.addPatternArg(item);
            items_len += 1;
            end_span = self.tree.patterns.items[item].span();
            if (self.match(.comma) == null) break;
        }
        if (self.match(.r_bracket)) |bracket| {
            end_span = bracket.span;
        } else {
            try self.addError(self.peek().span, "expected `]` after array pattern");
        }
        return self.tree.addPattern(.{ .array = .{
            .items = .{ .start = items_start, .len = items_len },
            .span = base.Span.join(start_span, end_span),
        } });
    }

    fn parsePathPattern(self: *Parser, first_token: lexer.Token) Allocator.Error!ast_mod.PatternId {
        const path_start = self.tree.reservePath();
        var path_len: u32 = 0;
        try self.tree.addPathSegment(.{
            .name = try self.internToken(first_token),
            .span = first_token.span,
        });
        path_len += 1;
        var end_span = first_token.span;

        while (self.match(.dot) != null) {
            const segment_token = (try self.expectPatternPathSegment("expected pattern path segment after `.`")) orelse break;
            try self.tree.addPathSegment(.{
                .name = try self.internToken(segment_token),
                .span = segment_token.span,
            });
            path_len += 1;
            end_span = segment_token.span;
        }

        const path = base.Range{ .start = path_start, .len = path_len };
        if (self.match(.l_paren)) |_| return self.finishTuplePattern(path, first_token.span);
        if (self.match(.l_brace)) |_| return self.finishRecordPattern(path, first_token.span);

        if (path_len == 1 and isBindingPatternName(self.tokenText(first_token))) {
            return self.tree.addPattern(.{ .binding = .{
                .name = try self.internToken(first_token),
                .name_span = first_token.span,
                .span = first_token.span,
            } });
        }

        return self.tree.addPattern(.{ .path = .{
            .segments = path,
            .span = base.Span.join(first_token.span, end_span),
        } });
    }

    fn finishTuplePattern(self: *Parser, path: base.Range, start_span: base.Span) Allocator.Error!ast_mod.PatternId {
        const args_start = self.tree.reservePatternArgs();
        var args_len: u32 = 0;
        var end_span = start_span;
        while (self.peekKind() != .r_paren and self.peekKind() != .eof) {
            const arg = try self.parsePattern();
            try self.tree.addPatternArg(arg);
            args_len += 1;
            end_span = self.tree.patterns.items[arg].span();
            if (self.match(.comma) == null) break;
        }
        if (self.match(.r_paren)) |paren| {
            end_span = paren.span;
        } else {
            try self.addError(self.peek().span, "expected `)` after tuple pattern");
        }
        return self.tree.addPattern(.{ .tuple = .{
            .path = path,
            .args = .{ .start = args_start, .len = args_len },
            .span = base.Span.join(start_span, end_span),
        } });
    }

    fn finishRecordPattern(self: *Parser, path: base.Range, start_span: base.Span) Allocator.Error!ast_mod.PatternId {
        const fields_start = self.tree.reservePatternRecordFields();
        var fields_len: u32 = 0;
        var has_rest = false;
        var end_span = start_span;
        while (self.peekKind() != .r_brace and self.peekKind() != .eof) {
            if (self.match(.dot_dot)) |dot_dot| {
                has_rest = true;
                end_span = dot_dot.span;
                break;
            }

            const field_token = (try self.expectIdentifier("expected record pattern field")) orelse break;
            var field_pattern: ?ast_mod.PatternId = null;
            var field_end = field_token.span;
            if (self.match(.colon) != null) {
                field_pattern = try self.parsePattern();
                field_end = self.tree.patterns.items[field_pattern.?].span();
            }
            try self.tree.addPatternRecordField(.{
                .name = try self.internToken(field_token),
                .name_span = field_token.span,
                .pattern = field_pattern,
                .span = base.Span.join(field_token.span, field_end),
            });
            fields_len += 1;
            end_span = field_end;

            if (self.match(.comma) == null) break;
        }
        if (self.match(.r_brace)) |brace| {
            end_span = brace.span;
        } else {
            try self.addError(self.peek().span, "expected `}` after record pattern");
        }
        return self.tree.addPattern(.{ .record = .{
            .path = path,
            .fields = .{ .start = fields_start, .len = fields_len },
            .has_rest = has_rest,
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
        const generic_params = try self.parseGenericParams();
        _ = (try self.expect(.equal, "expected `=` after type alias name")) orelse return;

        const aliased_type = try self.parseTypeExpr("expected aliased type");
        var end_span = self.previous().span;
        if (self.match(.semicolon)) |semicolon| {
            end_span = semicolon.span;
        }

        _ = try self.tree.addDecl(.{ .type_alias = .{
            .visibility = visibility,
            .name = try self.internToken(name_token),
            .name_span = name_token.span,
            .generic_params = generic_params,
            .aliased_type = aliased_type,
            .span = base.Span.join(start_span, end_span),
        } });
    }

    fn parseEnum(self: *Parser, visibility: ast_mod.Visibility, start_span: base.Span) Allocator.Error!void {
        _ = (try self.expect(.keyword_enum, "expected enum declaration")) orelse return;
        const name_token = (try self.expectIdentifier("expected enum name")) orelse return;
        const name = try self.internToken(name_token);
        const generic_params = try self.parseGenericParams();
        const where_predicates = try self.parseWhereClause();

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
            .generic_params = generic_params,
            .where_predicates = where_predicates,
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
                const type_expr = try self.parseTypeExpr("expected tuple variant field type");
                const field_end = self.previous().span;
                try self.tree.addEnumField(.{
                    .type_expr = type_expr,
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

                const type_expr = try self.parseTypeExpr("expected record variant field type");
                const field_end = self.previous().span;
                try self.tree.addEnumField(.{
                    .name = try self.internToken(field_name_token),
                    .name_span = field_name_token.span,
                    .type_expr = type_expr,
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
        const generic_params = try self.parseGenericParams();
        const where_predicates = try self.parseWhereClause();

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

            const type_expr = try self.parseTypeExpr("expected struct field type");
            const field_end = self.previous().span;
            try self.tree.addStructField(.{
                .visibility = field_visibility,
                .name = try self.internToken(field_name_token),
                .name_span = field_name_token.span,
                .type_expr = type_expr,
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
            .generic_params = generic_params,
            .where_predicates = where_predicates,
            .fields = .{ .start = fields_start, .len = fields_len },
            .span = base.Span.join(start_span, end_span),
        } });
    }

    fn parseTypeExpr(self: *Parser, message: []const u8) Allocator.Error!ast_mod.TypeId {
        if (self.match(.l_paren)) |open| {
            if (self.match(.r_paren)) |close| {
                return self.tree.addType(.{ .unit = base.Span.join(open.span, close.span) });
            }

            try self.addError(self.peek().span, "expected `)` after unit type");
            return self.tree.addType(.{ .unit = open.span });
        }

        const path_start = self.tree.reservePath();
        var path_len: u32 = 0;
        const first_segment = (try self.expectTypeSegment(message)) orelse return self.tree.addType(.{ .unit = self.peek().span });
        try self.tree.addPathSegment(.{
            .name = try self.internToken(first_segment),
            .span = first_segment.span,
        });
        path_len += 1;
        var end_span = first_segment.span;

        while (self.match(.dot) != null) {
            const segment_token = (try self.expectTypeSegment("expected type path segment after `.`")) orelse break;
            try self.tree.addPathSegment(.{
                .name = try self.internToken(segment_token),
                .span = segment_token.span,
            });
            path_len += 1;
            end_span = segment_token.span;
        }

        const args_start = self.tree.reserveTypeArgs();
        var args_len: u32 = 0;
        if (self.match(.less) != null) {
            while (self.peekKind() != .greater and self.peekKind() != .eof) {
                const arg = try self.parseTypeExpr("expected type argument");
                try self.tree.addTypeArg(arg);
                args_len += 1;
                end_span = self.tree.types.items[arg].span();
                if (self.match(.comma) == null) break;
            }

            if (self.match(.greater)) |greater| {
                end_span = greater.span;
            } else {
                try self.addError(self.peek().span, "expected `>` after type arguments");
            }
        }

        return self.tree.addType(.{ .path = .{
            .segments = .{ .start = path_start, .len = path_len },
            .args = .{ .start = args_start, .len = args_len },
            .span = base.Span.join(first_segment.span, end_span),
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

    fn expectTypeSegment(self: *Parser, message: []const u8) Allocator.Error!?lexer.Token {
        return switch (self.peekKind()) {
            .identifier, .keyword_Self => self.advance(),
            else => {
                try self.addError(self.peek().span, message);
                return null;
            },
        };
    }

    fn expectPatternPathSegment(self: *Parser, message: []const u8) Allocator.Error!?lexer.Token {
        return switch (self.peekKind()) {
            .identifier, .keyword_Self => self.advance(),
            else => {
                try self.addError(self.peek().span, message);
                return null;
            },
        };
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

    fn expectParamName(self: *Parser, message: []const u8) Allocator.Error!?lexer.Token {
        return switch (self.peekKind()) {
            .identifier, .keyword_self => self.advance(),
            else => {
                try self.addError(self.peek().span, message);
                return null;
            },
        };
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

fn isBindingPatternName(text: []const u8) bool {
    if (text.len == 0) return false;
    return text[0] == '_' or (text[0] >= 'a' and text[0] <= 'z');
}

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
