const std = @import("std");
const base = @import("../base.zig");

const Allocator = std.mem.Allocator;
const DumpError = Allocator.Error || std.Io.Writer.Error;

pub const DeclId = base.DeclId;
pub const BlockId = u32;
pub const ExprId = base.ExprId;
pub const StmtId = base.StmtId;
pub const TypeId = base.TypeId;
pub const PatternId = u32;

pub const Visibility = enum {
    package,
    public,
    private,
};

pub const PathSegment = struct {
    name: base.SymbolId,
    span: base.Span,
};

pub const ImportDecl = struct {
    visibility: Visibility,
    path: base.Range,
    items: base.Range = .{ .start = 0, .len = 0 },
    alias: ?base.SymbolId = null,
    alias_span: ?base.Span = null,
    span: base.Span,
};

pub const ImportItem = struct {
    name: base.SymbolId,
    name_span: base.Span,
    alias: ?base.SymbolId = null,
    alias_span: ?base.Span = null,
    span: base.Span,
};

pub const TypeAliasDecl = struct {
    visibility: Visibility,
    name: base.SymbolId,
    name_span: base.Span,
    generic_params: base.Range = .{ .start = 0, .len = 0 },
    aliased_type: TypeId,
    span: base.Span,
};

pub const TypeExpr = union(enum) {
    path: struct { segments: base.Range, args: base.Range = .{ .start = 0, .len = 0 }, span: base.Span },
    unit: base.Span,

    pub fn span(self: TypeExpr) base.Span {
        return switch (self) {
            .path => |type_expr| type_expr.span,
            .unit => |span_value| span_value,
        };
    }
};

pub const FnParam = struct {
    is_mut: bool,
    name: base.SymbolId,
    name_span: base.Span,
    type_expr: TypeId,
    default_value: ?ExprId = null,
    span: base.Span,
};

pub const GenericParam = struct {
    name: base.SymbolId,
    name_span: base.Span,
    constraint: ?TypeId = null,
    span: base.Span,
};

pub const WherePredicate = struct {
    subject: TypeId,
    constraint: TypeId,
    span: base.Span,
};

pub const FnDecl = struct {
    visibility: Visibility,
    name: base.SymbolId,
    name_span: base.Span,
    generic_params: base.Range = .{ .start = 0, .len = 0 },
    params: base.Range,
    return_type: ?TypeId = null,
    where_predicates: base.Range = .{ .start = 0, .len = 0 },
    body: BlockId,
    span: base.Span,
};

pub const ImplDecl = struct {
    visibility: Visibility,
    generic_params: base.Range = .{ .start = 0, .len = 0 },
    interface_type: ?TypeId = null,
    self_type: TypeId,
    where_predicates: base.Range = .{ .start = 0, .len = 0 },
    methods: base.Range = .{ .start = 0, .len = 0 },
    span: base.Span,
};

pub const InterfaceMethod = struct {
    visibility: Visibility,
    name: base.SymbolId,
    name_span: base.Span,
    generic_params: base.Range = .{ .start = 0, .len = 0 },
    params: base.Range,
    return_type: ?TypeId = null,
    where_predicates: base.Range = .{ .start = 0, .len = 0 },
    span: base.Span,
};

pub const InterfaceDecl = struct {
    visibility: Visibility,
    name: base.SymbolId,
    name_span: base.Span,
    generic_params: base.Range = .{ .start = 0, .len = 0 },
    where_predicates: base.Range = .{ .start = 0, .len = 0 },
    methods: base.Range = .{ .start = 0, .len = 0 },
    span: base.Span,
};

pub const TestDecl = struct {
    name_span: base.Span,
    body: BlockId,
    span: base.Span,
};

pub const BinaryOp = enum {
    assign,
    add_assign,
    sub_assign,
    mul_assign,
    div_assign,
    rem_assign,
    logical_or,
    logical_and,
    equal,
    not_equal,
    less,
    less_equal,
    greater,
    greater_equal,
    add,
    sub,
    mul,
    div,
    rem,
};

pub const Expr = union(enum) {
    name: struct { symbol: base.SymbolId, span: base.Span },
    int_literal: base.Span,
    float_literal: base.Span,
    string_literal: base.Span,
    char_literal: base.Span,
    bool_literal: struct { value: bool, span: base.Span },
    unit_literal: base.Span,
    binary: struct { op: BinaryOp, left: ExprId, right: ExprId, span: base.Span },
    field: struct { base: ExprId, name: base.SymbolId, name_span: base.Span, span: base.Span },
    call: struct { callee: ExprId, args: base.Range, span: base.Span },
    index: struct { base: ExprId, index: ExprId, span: base.Span },
    array_literal: struct { items: base.Range, span: base.Span },
    struct_literal: struct { type_expr: ExprId, fields: base.Range, span: base.Span },
    if_expr: struct { condition: ControlCondition, then_block: BlockId, else_block: ?BlockId = null, span: base.Span },
    match_expr: MatchExpr,
    try_expr: TryExpr,
    catch_expr: CatchExpr,

    pub fn span(self: Expr) base.Span {
        return switch (self) {
            .name => |expr| expr.span,
            .int_literal => |span_value| span_value,
            .float_literal => |span_value| span_value,
            .string_literal => |span_value| span_value,
            .char_literal => |span_value| span_value,
            .bool_literal => |expr| expr.span,
            .unit_literal => |span_value| span_value,
            .binary => |expr| expr.span,
            .field => |expr| expr.span,
            .call => |expr| expr.span,
            .index => |expr| expr.span,
            .array_literal => |expr| expr.span,
            .struct_literal => |expr| expr.span,
            .if_expr => |expr| expr.span,
            .match_expr => |expr| expr.span,
            .try_expr => |expr| expr.span,
            .catch_expr => |expr| expr.span,
        };
    }
};

pub const Pattern = union(enum) {
    wildcard: base.Span,
    binding: struct { name: base.SymbolId, name_span: base.Span, is_mut: bool = false, span: base.Span },
    int_literal: base.Span,
    float_literal: base.Span,
    string_literal: base.Span,
    char_literal: base.Span,
    bool_literal: struct { value: bool, span: base.Span },
    path: struct { segments: base.Range, span: base.Span },
    tuple: struct { path: base.Range, args: base.Range, span: base.Span },
    record: struct { path: base.Range, fields: base.Range, has_rest: bool = false, span: base.Span },
    array: struct { items: base.Range, span: base.Span },
    rest: struct { name: ?base.SymbolId = null, name_span: ?base.Span = null, span: base.Span },
    range: struct { start: PatternId, end: PatternId, inclusive: bool, span: base.Span },
    or_pattern: struct { patterns: base.Range, span: base.Span },

    pub fn span(self: Pattern) base.Span {
        return switch (self) {
            .wildcard => |span_value| span_value,
            .binding => |pattern| pattern.span,
            .int_literal => |span_value| span_value,
            .float_literal => |span_value| span_value,
            .string_literal => |span_value| span_value,
            .char_literal => |span_value| span_value,
            .bool_literal => |pattern| pattern.span,
            .path => |pattern| pattern.span,
            .tuple => |pattern| pattern.span,
            .record => |pattern| pattern.span,
            .array => |pattern| pattern.span,
            .rest => |pattern| pattern.span,
            .range => |pattern| pattern.span,
            .or_pattern => |pattern| pattern.span,
        };
    }
};

pub const PatternRecordField = struct {
    name: base.SymbolId,
    name_span: base.Span,
    pattern: ?PatternId = null,
    span: base.Span,
};

pub const MatchArmBody = union(enum) {
    expr: ExprId,
    block: BlockId,

    pub fn span(self: MatchArmBody, ast: *const Ast) base.Span {
        return switch (self) {
            .expr => |expr_id| ast.exprs.items[expr_id].span(),
            .block => |block_id| ast.blocks.items[block_id].span,
        };
    }
};

pub const MatchArm = struct {
    pattern: PatternId,
    guard: ?ExprId = null,
    body: MatchArmBody,
    span: base.Span,
};

pub const MatchExpr = struct {
    value: ExprId,
    arms: base.Range,
    span: base.Span,
};

pub const StructLiteralField = struct {
    name: base.SymbolId,
    name_span: base.Span,
    value: ?ExprId = null,
    span: base.Span,
};

pub const ControlCondition = union(enum) {
    expr: ExprId,
    let_pattern: struct { pattern: PatternId, value: ExprId, span: base.Span },

    pub fn span(self: ControlCondition, ast: *const Ast) base.Span {
        return switch (self) {
            .expr => |expr_id| ast.exprs.items[expr_id].span(),
            .let_pattern => |condition| condition.span,
        };
    }
};

pub const TryExpr = struct {
    value: ExprId,
    span: base.Span,
};

pub const CatchBinding = struct {
    name: base.SymbolId,
    span: base.Span,
};

pub const CatchHandler = union(enum) {
    expr: ExprId,
    block: BlockId,

    pub fn span(self: CatchHandler, ast: *const Ast) base.Span {
        return switch (self) {
            .expr => |expr_id| ast.exprs.items[expr_id].span(),
            .block => |block_id| ast.blocks.items[block_id].span,
        };
    }
};

pub const CatchExpr = struct {
    value: ExprId,
    binding: ?CatchBinding = null,
    handler: CatchHandler,
    span: base.Span,
};

pub const LetStmt = struct {
    pattern: PatternId,
    value: ExprId,
    else_block: ?BlockId = null,
    span: base.Span,
};

pub const ReturnStmt = struct {
    value: ?ExprId,
    span: base.Span,
};

pub const WhileStmt = struct {
    condition: ControlCondition,
    body: BlockId,
    span: base.Span,
};

pub const ForStmt = struct {
    pattern: PatternId,
    iterable: ExprId,
    body: BlockId,
    span: base.Span,
};

pub const DeferKind = enum {
    always,
    err,
};

pub const DeferStmt = struct {
    kind: DeferKind,
    body: BlockId,
    span: base.Span,
};

pub const Stmt = union(enum) {
    let_stmt: LetStmt,
    return_stmt: ReturnStmt,
    while_stmt: WhileStmt,
    for_stmt: ForStmt,
    defer_stmt: DeferStmt,
    break_stmt: base.Span,
    continue_stmt: base.Span,
    expr_stmt: ExprId,
};

pub const Block = struct {
    stmts: base.Range,
    final_expr: ?ExprId = null,
    span: base.Span,
};

pub const StructField = struct {
    visibility: Visibility,
    name: base.SymbolId,
    name_span: base.Span,
    type_expr: TypeId,
    span: base.Span,
};

pub const StructDecl = struct {
    visibility: Visibility,
    name: base.SymbolId,
    name_span: base.Span,
    generic_params: base.Range = .{ .start = 0, .len = 0 },
    where_predicates: base.Range = .{ .start = 0, .len = 0 },
    fields: base.Range,
    span: base.Span,
};

pub const EnumField = struct {
    name: ?base.SymbolId = null,
    name_span: ?base.Span = null,
    type_expr: TypeId,
    span: base.Span,
};

pub const EnumVariantKind = enum {
    unit,
    tuple,
    record,
};

pub const EnumVariant = struct {
    name: base.SymbolId,
    name_span: base.Span,
    kind: EnumVariantKind,
    fields: base.Range = .{ .start = 0, .len = 0 },
    span: base.Span,
};

pub const EnumDecl = struct {
    visibility: Visibility,
    name: base.SymbolId,
    name_span: base.Span,
    generic_params: base.Range = .{ .start = 0, .len = 0 },
    where_predicates: base.Range = .{ .start = 0, .len = 0 },
    variants: base.Range,
    span: base.Span,
};

pub const Decl = union(enum) {
    import: ImportDecl,
    type_alias: TypeAliasDecl,
    fn_decl: FnDecl,
    impl_decl: ImplDecl,
    interface_decl: InterfaceDecl,
    test_decl: TestDecl,
    struct_decl: StructDecl,
    enum_decl: EnumDecl,

    pub fn span(self: Decl) base.Span {
        return switch (self) {
            .import => |decl| decl.span,
            .type_alias => |decl| decl.span,
            .fn_decl => |decl| decl.span,
            .impl_decl => |decl| decl.span,
            .interface_decl => |decl| decl.span,
            .test_decl => |decl| decl.span,
            .struct_decl => |decl| decl.span,
            .enum_decl => |decl| decl.span,
        };
    }
};

pub const Ast = struct {
    allocator: Allocator,
    source: base.SourceId,
    decls: std.ArrayListUnmanaged(Decl) = .empty,
    path_segments: std.ArrayListUnmanaged(PathSegment) = .empty,
    import_items: std.ArrayListUnmanaged(ImportItem) = .empty,
    types: std.ArrayListUnmanaged(TypeExpr) = .empty,
    type_args: std.ArrayListUnmanaged(TypeId) = .empty,
    fn_params: std.ArrayListUnmanaged(FnParam) = .empty,
    generic_params: std.ArrayListUnmanaged(GenericParam) = .empty,
    where_predicates: std.ArrayListUnmanaged(WherePredicate) = .empty,
    impl_methods: std.ArrayListUnmanaged(FnDecl) = .empty,
    interface_methods: std.ArrayListUnmanaged(InterfaceMethod) = .empty,
    exprs: std.ArrayListUnmanaged(Expr) = .empty,
    expr_args: std.ArrayListUnmanaged(ExprId) = .empty,
    struct_literal_fields: std.ArrayListUnmanaged(StructLiteralField) = .empty,
    patterns: std.ArrayListUnmanaged(Pattern) = .empty,
    pattern_args: std.ArrayListUnmanaged(PatternId) = .empty,
    pattern_record_fields: std.ArrayListUnmanaged(PatternRecordField) = .empty,
    match_arms: std.ArrayListUnmanaged(MatchArm) = .empty,
    blocks: std.ArrayListUnmanaged(Block) = .empty,
    stmts: std.ArrayListUnmanaged(Stmt) = .empty,
    block_stmt_ids: std.ArrayListUnmanaged(StmtId) = .empty,
    struct_fields: std.ArrayListUnmanaged(StructField) = .empty,
    enum_variants: std.ArrayListUnmanaged(EnumVariant) = .empty,
    enum_fields: std.ArrayListUnmanaged(EnumField) = .empty,

    pub fn init(allocator: Allocator, source: base.SourceId) Ast {
        return .{
            .allocator = allocator,
            .source = source,
        };
    }

    pub fn deinit(self: *Ast) void {
        self.decls.deinit(self.allocator);
        self.path_segments.deinit(self.allocator);
        self.import_items.deinit(self.allocator);
        self.types.deinit(self.allocator);
        self.type_args.deinit(self.allocator);
        self.fn_params.deinit(self.allocator);
        self.generic_params.deinit(self.allocator);
        self.where_predicates.deinit(self.allocator);
        self.impl_methods.deinit(self.allocator);
        self.interface_methods.deinit(self.allocator);
        self.exprs.deinit(self.allocator);
        self.expr_args.deinit(self.allocator);
        self.struct_literal_fields.deinit(self.allocator);
        self.patterns.deinit(self.allocator);
        self.pattern_args.deinit(self.allocator);
        self.pattern_record_fields.deinit(self.allocator);
        self.match_arms.deinit(self.allocator);
        self.blocks.deinit(self.allocator);
        self.stmts.deinit(self.allocator);
        self.block_stmt_ids.deinit(self.allocator);
        self.struct_fields.deinit(self.allocator);
        self.enum_variants.deinit(self.allocator);
        self.enum_fields.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn addDecl(self: *Ast, decl: Decl) Allocator.Error!DeclId {
        const id: DeclId = @intCast(self.decls.items.len);
        try self.decls.append(self.allocator, decl);
        return id;
    }

    pub fn addPathSegment(self: *Ast, segment: PathSegment) Allocator.Error!void {
        try self.path_segments.append(self.allocator, segment);
    }

    pub fn reservePath(self: *const Ast) u32 {
        return @intCast(self.path_segments.items.len);
    }

    pub fn reserveImportItems(self: *const Ast) u32 {
        return @intCast(self.import_items.items.len);
    }

    pub fn addImportItem(self: *Ast, item: ImportItem) Allocator.Error!void {
        try self.import_items.append(self.allocator, item);
    }

    pub fn addType(self: *Ast, type_expr: TypeExpr) Allocator.Error!TypeId {
        const id: TypeId = @intCast(self.types.items.len);
        try self.types.append(self.allocator, type_expr);
        return id;
    }

    pub fn reserveTypeArgs(self: *const Ast) u32 {
        return @intCast(self.type_args.items.len);
    }

    pub fn addTypeArg(self: *Ast, type_expr: TypeId) Allocator.Error!void {
        try self.type_args.append(self.allocator, type_expr);
    }

    pub fn reserveStructFields(self: *const Ast) u32 {
        return @intCast(self.struct_fields.items.len);
    }

    pub fn reserveFnParams(self: *const Ast) u32 {
        return @intCast(self.fn_params.items.len);
    }

    pub fn addFnParam(self: *Ast, param: FnParam) Allocator.Error!void {
        try self.fn_params.append(self.allocator, param);
    }

    pub fn reserveGenericParams(self: *const Ast) u32 {
        return @intCast(self.generic_params.items.len);
    }

    pub fn addGenericParam(self: *Ast, param: GenericParam) Allocator.Error!void {
        try self.generic_params.append(self.allocator, param);
    }

    pub fn reserveWherePredicates(self: *const Ast) u32 {
        return @intCast(self.where_predicates.items.len);
    }

    pub fn addWherePredicate(self: *Ast, predicate: WherePredicate) Allocator.Error!void {
        try self.where_predicates.append(self.allocator, predicate);
    }

    pub fn reserveImplMethods(self: *const Ast) u32 {
        return @intCast(self.impl_methods.items.len);
    }

    pub fn addImplMethod(self: *Ast, method: FnDecl) Allocator.Error!void {
        try self.impl_methods.append(self.allocator, method);
    }

    pub fn reserveInterfaceMethods(self: *const Ast) u32 {
        return @intCast(self.interface_methods.items.len);
    }

    pub fn addInterfaceMethod(self: *Ast, method: InterfaceMethod) Allocator.Error!void {
        try self.interface_methods.append(self.allocator, method);
    }

    pub fn addExpr(self: *Ast, expr: Expr) Allocator.Error!ExprId {
        const id: ExprId = @intCast(self.exprs.items.len);
        try self.exprs.append(self.allocator, expr);
        return id;
    }

    pub fn reserveExprArgs(self: *const Ast) u32 {
        return @intCast(self.expr_args.items.len);
    }

    pub fn addExprArg(self: *Ast, expr: ExprId) Allocator.Error!void {
        try self.expr_args.append(self.allocator, expr);
    }

    pub fn reserveStructLiteralFields(self: *const Ast) u32 {
        return @intCast(self.struct_literal_fields.items.len);
    }

    pub fn addStructLiteralField(self: *Ast, field: StructLiteralField) Allocator.Error!void {
        try self.struct_literal_fields.append(self.allocator, field);
    }

    pub fn addPattern(self: *Ast, pattern: Pattern) Allocator.Error!PatternId {
        const id: PatternId = @intCast(self.patterns.items.len);
        try self.patterns.append(self.allocator, pattern);
        return id;
    }

    pub fn reservePatternArgs(self: *const Ast) u32 {
        return @intCast(self.pattern_args.items.len);
    }

    pub fn addPatternArg(self: *Ast, pattern: PatternId) Allocator.Error!void {
        try self.pattern_args.append(self.allocator, pattern);
    }

    pub fn reservePatternRecordFields(self: *const Ast) u32 {
        return @intCast(self.pattern_record_fields.items.len);
    }

    pub fn addPatternRecordField(self: *Ast, field: PatternRecordField) Allocator.Error!void {
        try self.pattern_record_fields.append(self.allocator, field);
    }

    pub fn reserveMatchArms(self: *const Ast) u32 {
        return @intCast(self.match_arms.items.len);
    }

    pub fn addMatchArm(self: *Ast, arm: MatchArm) Allocator.Error!void {
        try self.match_arms.append(self.allocator, arm);
    }

    pub fn reserveBlockStmtIds(self: *const Ast) u32 {
        return @intCast(self.block_stmt_ids.items.len);
    }

    pub fn addBlockStmtId(self: *Ast, stmt_id: StmtId) Allocator.Error!void {
        try self.block_stmt_ids.append(self.allocator, stmt_id);
    }

    pub fn addStmt(self: *Ast, stmt: Stmt) Allocator.Error!StmtId {
        const id: StmtId = @intCast(self.stmts.items.len);
        try self.stmts.append(self.allocator, stmt);
        return id;
    }

    pub fn reserveStmts(self: *const Ast) u32 {
        return @intCast(self.stmts.items.len);
    }

    pub fn addBlock(self: *Ast, block: Block) Allocator.Error!BlockId {
        const id: BlockId = @intCast(self.blocks.items.len);
        try self.blocks.append(self.allocator, block);
        return id;
    }

    pub fn addStructField(self: *Ast, field: StructField) Allocator.Error!void {
        try self.struct_fields.append(self.allocator, field);
    }

    pub fn reserveEnumVariants(self: *const Ast) u32 {
        return @intCast(self.enum_variants.items.len);
    }

    pub fn addEnumVariant(self: *Ast, variant: EnumVariant) Allocator.Error!void {
        try self.enum_variants.append(self.allocator, variant);
    }

    pub fn reserveEnumFields(self: *const Ast) u32 {
        return @intCast(self.enum_fields.items.len);
    }

    pub fn addEnumField(self: *Ast, field: EnumField) Allocator.Error!void {
        try self.enum_fields.append(self.allocator, field);
    }
};

pub fn dumpAst(allocator: Allocator, ast: *const Ast, interner: *const base.Interner) DumpError![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();

    try output.writer.writeAll("Root\n");
    for (ast.decls.items) |decl| {
        switch (decl) {
            .import => |import_decl| try dumpImport(&output.writer, ast, interner, import_decl),
            .type_alias => |type_alias| try dumpTypeAlias(&output.writer, ast, interner, type_alias),
            .fn_decl => |fn_decl| try dumpFn(&output.writer, ast, interner, fn_decl),
            .impl_decl => |impl_decl| try dumpImpl(&output.writer, ast, interner, impl_decl),
            .interface_decl => |interface_decl| try dumpInterface(&output.writer, ast, interner, interface_decl),
            .test_decl => |test_decl| try dumpTest(&output.writer, ast, interner, test_decl),
            .struct_decl => |struct_decl| try dumpStruct(&output.writer, ast, interner, struct_decl),
            .enum_decl => |enum_decl| try dumpEnum(&output.writer, ast, interner, enum_decl),
        }
    }

    return output.toOwnedSlice();
}

fn dumpFn(
    writer: *std.Io.Writer,
    ast: *const Ast,
    interner: *const base.Interner,
    fn_decl: FnDecl,
) std.Io.Writer.Error!void {
    try dumpFnLike(writer, ast, interner, fn_decl, 1, "FnDecl");
}

fn dumpFnLike(
    writer: *std.Io.Writer,
    ast: *const Ast,
    interner: *const base.Interner,
    fn_decl: FnDecl,
    indent: usize,
    label: []const u8,
) std.Io.Writer.Error!void {
    try writeIndent(writer, indent);
    try writer.print("{s} {s} {s}\n", .{
        label,
        @tagName(fn_decl.visibility),
        interner.get(fn_decl.name) orelse "<missing>",
    });

    try dumpGenericParams(writer, ast, interner, fn_decl.generic_params, indent + 1);
    try dumpWherePredicates(writer, ast, interner, fn_decl.where_predicates, indent + 1);

    const start: usize = @intCast(fn_decl.params.start);
    const end: usize = @intCast(fn_decl.params.end());
    for (ast.fn_params.items[start..end]) |param| {
        try writeIndent(writer, indent + 1);
        try writer.print("Param {s}{s}: ", .{
            if (param.is_mut) "mut " else "",
            interner.get(param.name) orelse "<missing>",
        });
        try dumpTypeExpr(writer, ast, interner, param.type_expr);
        if (param.default_value) |default_value| {
            try writer.writeAll(" =\n");
            try dumpExpr(writer, ast, interner, default_value, indent + 2);
        } else {
            try writer.writeByte('\n');
        }
    }

    try writeIndent(writer, indent + 1);
    try writer.writeAll("Return ");
    if (fn_decl.return_type) |return_type| {
        try dumpTypeExpr(writer, ast, interner, return_type);
    } else {
        try writer.writeAll("()");
    }
    try writer.writeByte('\n');

    try dumpBlock(writer, ast, interner, ast.blocks.items[fn_decl.body], indent + 1);
}

fn dumpBlock(
    writer: *std.Io.Writer,
    ast: *const Ast,
    interner: *const base.Interner,
    block: Block,
    indent: usize,
) std.Io.Writer.Error!void {
    try writeIndent(writer, indent);
    try writer.writeAll("Block\n");

    const start: usize = @intCast(block.stmts.start);
    const end: usize = @intCast(block.stmts.end());
    for (ast.block_stmt_ids.items[start..end]) |stmt_id| {
        try dumpStmt(writer, ast, interner, ast.stmts.items[stmt_id], indent + 1);
    }

    if (block.final_expr) |final_expr| {
        try writeIndent(writer, indent + 1);
        try writer.writeAll("FinalExpr\n");
        try dumpExpr(writer, ast, interner, final_expr, indent + 2);
    }
}

fn dumpStmt(
    writer: *std.Io.Writer,
    ast: *const Ast,
    interner: *const base.Interner,
    stmt: Stmt,
    indent: usize,
) std.Io.Writer.Error!void {
    switch (stmt) {
        .let_stmt => |let_stmt| {
            try writeIndent(writer, indent);
            const pattern = ast.patterns.items[let_stmt.pattern];
            if (pattern == .binding and let_stmt.else_block == null) {
                const binding = pattern.binding;
                try writer.print("LetStmt {s}{s}\n", .{
                    if (binding.is_mut) "mut " else "",
                    interner.get(binding.name) orelse "<missing>",
                });
                try dumpExpr(writer, ast, interner, let_stmt.value, indent + 1);
            } else {
                try writer.writeAll("LetStmt\n");
                try dumpPattern(writer, ast, interner, let_stmt.pattern, indent + 1);
                try writeIndent(writer, indent + 1);
                try writer.writeAll("Value\n");
                try dumpExpr(writer, ast, interner, let_stmt.value, indent + 2);
                if (let_stmt.else_block) |else_block| {
                    try writeIndent(writer, indent + 1);
                    try writer.writeAll("Else\n");
                    try dumpBlock(writer, ast, interner, ast.blocks.items[else_block], indent + 2);
                }
            }
        },
        .return_stmt => |return_stmt| {
            try writeIndent(writer, indent);
            try writer.writeAll("ReturnStmt\n");
            if (return_stmt.value) |value| {
                try dumpExpr(writer, ast, interner, value, indent + 1);
            }
        },
        .while_stmt => |while_stmt| {
            try writeIndent(writer, indent);
            try writer.writeAll("WhileStmt\n");
            try writeIndent(writer, indent + 1);
            try writer.writeAll("Condition\n");
            try dumpControlCondition(writer, ast, interner, while_stmt.condition, indent + 2);
            try dumpBlock(writer, ast, interner, ast.blocks.items[while_stmt.body], indent + 1);
        },
        .for_stmt => |for_stmt| {
            try writeIndent(writer, indent);
            try writer.writeAll("ForStmt\n");
            try writeIndent(writer, indent + 1);
            try writer.writeAll("Pattern\n");
            try dumpPattern(writer, ast, interner, for_stmt.pattern, indent + 2);
            try writeIndent(writer, indent + 1);
            try writer.writeAll("Iterable\n");
            try dumpExpr(writer, ast, interner, for_stmt.iterable, indent + 2);
            try dumpBlock(writer, ast, interner, ast.blocks.items[for_stmt.body], indent + 1);
        },
        .defer_stmt => |defer_stmt| {
            try writeIndent(writer, indent);
            try writer.print("DeferStmt {s}\n", .{@tagName(defer_stmt.kind)});
            try dumpBlock(writer, ast, interner, ast.blocks.items[defer_stmt.body], indent + 1);
        },
        .break_stmt => {
            try writeIndent(writer, indent);
            try writer.writeAll("BreakStmt\n");
        },
        .continue_stmt => {
            try writeIndent(writer, indent);
            try writer.writeAll("ContinueStmt\n");
        },
        .expr_stmt => |expr| {
            try writeIndent(writer, indent);
            try writer.writeAll("ExprStmt\n");
            try dumpExpr(writer, ast, interner, expr, indent + 1);
        },
    }
}

fn dumpExpr(
    writer: *std.Io.Writer,
    ast: *const Ast,
    interner: *const base.Interner,
    expr_id: ExprId,
    indent: usize,
) std.Io.Writer.Error!void {
    const expr = ast.exprs.items[expr_id];
    try writeIndent(writer, indent);
    switch (expr) {
        .name => |name| try writer.print("Name {s}\n", .{interner.get(name.symbol) orelse "<missing>"}),
        .int_literal => try writer.writeAll("IntLiteral\n"),
        .float_literal => try writer.writeAll("FloatLiteral\n"),
        .string_literal => try writer.writeAll("StringLiteral\n"),
        .char_literal => try writer.writeAll("CharLiteral\n"),
        .bool_literal => |bool_expr| try writer.print("BoolLiteral {}\n", .{bool_expr.value}),
        .unit_literal => try writer.writeAll("UnitLiteral\n"),
        .binary => |binary| {
            try writer.print("Binary {s}\n", .{@tagName(binary.op)});
            try dumpExpr(writer, ast, interner, binary.left, indent + 1);
            try dumpExpr(writer, ast, interner, binary.right, indent + 1);
        },
        .field => |field| {
            try writer.print("Field {s}\n", .{interner.get(field.name) orelse "<missing>"});
            try dumpExpr(writer, ast, interner, field.base, indent + 1);
        },
        .call => |call| {
            try writer.writeAll("Call\n");
            try dumpExpr(writer, ast, interner, call.callee, indent + 1);
            const start: usize = @intCast(call.args.start);
            const end: usize = @intCast(call.args.end());
            for (ast.expr_args.items[start..end]) |arg| {
                try dumpExpr(writer, ast, interner, arg, indent + 1);
            }
        },
        .index => |index| {
            try writer.writeAll("Index\n");
            try dumpExpr(writer, ast, interner, index.base, indent + 1);
            try dumpExpr(writer, ast, interner, index.index, indent + 1);
        },
        .array_literal => |array_literal| {
            try writer.writeAll("ArrayLiteral\n");
            const start: usize = @intCast(array_literal.items.start);
            const end: usize = @intCast(array_literal.items.end());
            for (ast.expr_args.items[start..end]) |item| {
                try dumpExpr(writer, ast, interner, item, indent + 1);
            }
        },
        .struct_literal => |literal| {
            try writer.writeAll("StructLiteral\n");
            try dumpExpr(writer, ast, interner, literal.type_expr, indent + 1);
            const start: usize = @intCast(literal.fields.start);
            const end: usize = @intCast(literal.fields.end());
            for (ast.struct_literal_fields.items[start..end]) |field| {
                try writeIndent(writer, indent + 1);
                try writer.print("Field {s}\n", .{interner.get(field.name) orelse "<missing>"});
                if (field.value) |value| {
                    try dumpExpr(writer, ast, interner, value, indent + 2);
                }
            }
        },
        .if_expr => |if_expr| {
            try writer.writeAll("IfExpr\n");
            try writeIndent(writer, indent + 1);
            try writer.writeAll("Condition\n");
            try dumpControlCondition(writer, ast, interner, if_expr.condition, indent + 2);
            try writeIndent(writer, indent + 1);
            try writer.writeAll("Then\n");
            try dumpBlock(writer, ast, interner, ast.blocks.items[if_expr.then_block], indent + 2);
            if (if_expr.else_block) |else_block| {
                try writeIndent(writer, indent + 1);
                try writer.writeAll("Else\n");
                try dumpBlock(writer, ast, interner, ast.blocks.items[else_block], indent + 2);
            }
        },
        .match_expr => |match_expr| {
            try writer.writeAll("MatchExpr\n");
            try writeIndent(writer, indent + 1);
            try writer.writeAll("Value\n");
            try dumpExpr(writer, ast, interner, match_expr.value, indent + 2);
            const start: usize = @intCast(match_expr.arms.start);
            const end: usize = @intCast(match_expr.arms.end());
            for (ast.match_arms.items[start..end]) |arm| {
                try writeIndent(writer, indent + 1);
                try writer.writeAll("Arm\n");
                try dumpPattern(writer, ast, interner, arm.pattern, indent + 2);
                if (arm.guard) |guard| {
                    try writeIndent(writer, indent + 2);
                    try writer.writeAll("Guard\n");
                    try dumpExpr(writer, ast, interner, guard, indent + 3);
                }
                try writeIndent(writer, indent + 2);
                try writer.writeAll("Body\n");
                switch (arm.body) {
                    .expr => |arm_expr| try dumpExpr(writer, ast, interner, arm_expr, indent + 3),
                    .block => |block_id| try dumpBlock(writer, ast, interner, ast.blocks.items[block_id], indent + 3),
                }
            }
        },
        .try_expr => |try_expr| {
            try writer.writeAll("TryExpr\n");
            try dumpExpr(writer, ast, interner, try_expr.value, indent + 1);
        },
        .catch_expr => |catch_expr| {
            try writer.writeAll("CatchExpr\n");
            try writeIndent(writer, indent + 1);
            try writer.writeAll("Value\n");
            try dumpExpr(writer, ast, interner, catch_expr.value, indent + 2);
            if (catch_expr.binding) |binding| {
                try writeIndent(writer, indent + 1);
                try writer.print("Binding {s}\n", .{interner.get(binding.name) orelse "<missing>"});
            }
            try writeIndent(writer, indent + 1);
            try writer.writeAll("Handler\n");
            switch (catch_expr.handler) {
                .expr => |handler_expr| try dumpExpr(writer, ast, interner, handler_expr, indent + 2),
                .block => |block_id| try dumpBlock(writer, ast, interner, ast.blocks.items[block_id], indent + 2),
            }
        },
    }
}

fn dumpControlCondition(
    writer: *std.Io.Writer,
    ast: *const Ast,
    interner: *const base.Interner,
    condition: ControlCondition,
    indent: usize,
) std.Io.Writer.Error!void {
    switch (condition) {
        .expr => |expr_id| try dumpExpr(writer, ast, interner, expr_id, indent),
        .let_pattern => |let_condition| {
            try writeIndent(writer, indent);
            try writer.writeAll("LetCondition\n");
            try dumpPattern(writer, ast, interner, let_condition.pattern, indent + 1);
            try writeIndent(writer, indent + 1);
            try writer.writeAll("Value\n");
            try dumpExpr(writer, ast, interner, let_condition.value, indent + 2);
        },
    }
}

fn writeIndent(writer: *std.Io.Writer, indent: usize) std.Io.Writer.Error!void {
    var i: usize = 0;
    while (i < indent) : (i += 1) {
        try writer.writeAll("  ");
    }
}

fn dumpPattern(
    writer: *std.Io.Writer,
    ast: *const Ast,
    interner: *const base.Interner,
    pattern_id: PatternId,
    indent: usize,
) std.Io.Writer.Error!void {
    const pattern = ast.patterns.items[pattern_id];
    try writeIndent(writer, indent);
    switch (pattern) {
        .wildcard => try writer.writeAll("Pattern Wildcard\n"),
        .binding => |binding| try writer.print("Pattern Binding {s}{s}\n", .{
            if (binding.is_mut) "mut " else "",
            interner.get(binding.name) orelse "<missing>",
        }),
        .int_literal => try writer.writeAll("Pattern IntLiteral\n"),
        .float_literal => try writer.writeAll("Pattern FloatLiteral\n"),
        .string_literal => try writer.writeAll("Pattern StringLiteral\n"),
        .char_literal => try writer.writeAll("Pattern CharLiteral\n"),
        .bool_literal => |bool_pattern| try writer.print("Pattern BoolLiteral {}\n", .{bool_pattern.value}),
        .path => |path_pattern| {
            try writer.writeAll("Pattern Path ");
            try dumpPath(writer, ast, interner, path_pattern.segments);
            try writer.writeByte('\n');
        },
        .tuple => |tuple| {
            try writer.writeAll("Pattern Tuple ");
            try dumpPath(writer, ast, interner, tuple.path);
            try writer.writeByte('\n');
            const start: usize = @intCast(tuple.args.start);
            const end: usize = @intCast(tuple.args.end());
            for (ast.pattern_args.items[start..end]) |arg| {
                try dumpPattern(writer, ast, interner, arg, indent + 1);
            }
        },
        .record => |record| {
            try writer.writeAll("Pattern Record ");
            try dumpPath(writer, ast, interner, record.path);
            if (record.has_rest) try writer.writeAll(" rest");
            try writer.writeByte('\n');
            const start: usize = @intCast(record.fields.start);
            const end: usize = @intCast(record.fields.end());
            for (ast.pattern_record_fields.items[start..end]) |field| {
                try writeIndent(writer, indent + 1);
                try writer.print("Field {s}\n", .{interner.get(field.name) orelse "<missing>"});
                if (field.pattern) |field_pattern| {
                    try dumpPattern(writer, ast, interner, field_pattern, indent + 2);
                }
            }
        },
        .array => |array| {
            try writer.writeAll("Pattern Array\n");
            const start: usize = @intCast(array.items.start);
            const end: usize = @intCast(array.items.end());
            for (ast.pattern_args.items[start..end]) |item| {
                try dumpPattern(writer, ast, interner, item, indent + 1);
            }
        },
        .rest => |rest| {
            if (rest.name) |name| {
                try writer.print("Pattern Rest {s}\n", .{interner.get(name) orelse "<missing>"});
            } else {
                try writer.writeAll("Pattern Rest\n");
            }
        },
        .range => |range| {
            try writer.print("Pattern Range {s}\n", .{if (range.inclusive) "inclusive" else "exclusive"});
            try dumpPattern(writer, ast, interner, range.start, indent + 1);
            try dumpPattern(writer, ast, interner, range.end, indent + 1);
        },
        .or_pattern => |or_pattern| {
            try writer.writeAll("Pattern Or\n");
            const start: usize = @intCast(or_pattern.patterns.start);
            const end: usize = @intCast(or_pattern.patterns.end());
            for (ast.pattern_args.items[start..end]) |item| {
                try dumpPattern(writer, ast, interner, item, indent + 1);
            }
        },
    }
}

fn dumpTypeAlias(
    writer: *std.Io.Writer,
    ast: *const Ast,
    interner: *const base.Interner,
    type_alias: TypeAliasDecl,
) std.Io.Writer.Error!void {
    try writer.print("  TypeAliasDecl {s} {s} = ", .{
        @tagName(type_alias.visibility),
        interner.get(type_alias.name) orelse "<missing>",
    });
    try dumpTypeExpr(writer, ast, interner, type_alias.aliased_type);
    try writer.writeByte('\n');
    try dumpGenericParams(writer, ast, interner, type_alias.generic_params, 2);
}

fn dumpGenericParams(
    writer: *std.Io.Writer,
    ast: *const Ast,
    interner: *const base.Interner,
    params: base.Range,
    indent: usize,
) std.Io.Writer.Error!void {
    const start: usize = @intCast(params.start);
    const end: usize = @intCast(params.end());
    for (ast.generic_params.items[start..end]) |param| {
        try writeIndent(writer, indent);
        try writer.print("GenericParam {s}", .{interner.get(param.name) orelse "<missing>"});
        if (param.constraint) |constraint| {
            try writer.writeAll(": ");
            try dumpTypeExpr(writer, ast, interner, constraint);
        }
        try writer.writeByte('\n');
    }
}

fn dumpImpl(
    writer: *std.Io.Writer,
    ast: *const Ast,
    interner: *const base.Interner,
    impl_decl: ImplDecl,
) std.Io.Writer.Error!void {
    try writer.print("  ImplDecl {s} ", .{@tagName(impl_decl.visibility)});
    if (impl_decl.interface_type) |interface_type| {
        try dumpTypeExpr(writer, ast, interner, interface_type);
        try writer.writeAll(" for ");
    }
    try dumpTypeExpr(writer, ast, interner, impl_decl.self_type);
    try writer.writeByte('\n');

    try dumpGenericParams(writer, ast, interner, impl_decl.generic_params, 2);
    try dumpWherePredicates(writer, ast, interner, impl_decl.where_predicates, 2);

    const start: usize = @intCast(impl_decl.methods.start);
    const end: usize = @intCast(impl_decl.methods.end());
    for (ast.impl_methods.items[start..end]) |method| {
        try dumpFnLike(writer, ast, interner, method, 2, "Method");
    }
}

fn dumpInterface(
    writer: *std.Io.Writer,
    ast: *const Ast,
    interner: *const base.Interner,
    interface_decl: InterfaceDecl,
) std.Io.Writer.Error!void {
    try writer.print("  InterfaceDecl {s} {s}\n", .{
        @tagName(interface_decl.visibility),
        interner.get(interface_decl.name) orelse "<missing>",
    });

    try dumpGenericParams(writer, ast, interner, interface_decl.generic_params, 2);
    try dumpWherePredicates(writer, ast, interner, interface_decl.where_predicates, 2);

    const start: usize = @intCast(interface_decl.methods.start);
    const end: usize = @intCast(interface_decl.methods.end());
    for (ast.interface_methods.items[start..end]) |method| {
        try dumpInterfaceMethod(writer, ast, interner, method, 2);
    }
}

fn dumpInterfaceMethod(
    writer: *std.Io.Writer,
    ast: *const Ast,
    interner: *const base.Interner,
    method: InterfaceMethod,
    indent: usize,
) std.Io.Writer.Error!void {
    try writeIndent(writer, indent);
    try writer.print("Method {s} {s}\n", .{
        @tagName(method.visibility),
        interner.get(method.name) orelse "<missing>",
    });
    try dumpGenericParams(writer, ast, interner, method.generic_params, indent + 1);
    try dumpWherePredicates(writer, ast, interner, method.where_predicates, indent + 1);

    const start: usize = @intCast(method.params.start);
    const end: usize = @intCast(method.params.end());
    for (ast.fn_params.items[start..end]) |param| {
        try writeIndent(writer, indent + 1);
        try writer.print("Param {s}{s}: ", .{
            if (param.is_mut) "mut " else "",
            interner.get(param.name) orelse "<missing>",
        });
        try dumpTypeExpr(writer, ast, interner, param.type_expr);
        if (param.default_value) |default_value| {
            try writer.writeAll(" =\n");
            try dumpExpr(writer, ast, interner, default_value, indent + 2);
        } else {
            try writer.writeByte('\n');
        }
    }

    try writeIndent(writer, indent + 1);
    try writer.writeAll("Return ");
    if (method.return_type) |return_type| {
        try dumpTypeExpr(writer, ast, interner, return_type);
    } else {
        try writer.writeAll("()");
    }
    try writer.writeByte('\n');
}

fn dumpTest(
    writer: *std.Io.Writer,
    ast: *const Ast,
    interner: *const base.Interner,
    test_decl: TestDecl,
) std.Io.Writer.Error!void {
    try writer.writeAll("  TestDecl\n");
    try dumpBlock(writer, ast, interner, ast.blocks.items[test_decl.body], 2);
}

fn dumpWherePredicates(
    writer: *std.Io.Writer,
    ast: *const Ast,
    interner: *const base.Interner,
    predicates: base.Range,
    indent: usize,
) std.Io.Writer.Error!void {
    const start: usize = @intCast(predicates.start);
    const end: usize = @intCast(predicates.end());
    for (ast.where_predicates.items[start..end]) |predicate| {
        try writeIndent(writer, indent);
        try writer.writeAll("Where ");
        try dumpTypeExpr(writer, ast, interner, predicate.subject);
        try writer.writeAll(": ");
        try dumpTypeExpr(writer, ast, interner, predicate.constraint);
        try writer.writeByte('\n');
    }
}

fn dumpEnum(
    writer: *std.Io.Writer,
    ast: *const Ast,
    interner: *const base.Interner,
    enum_decl: EnumDecl,
) std.Io.Writer.Error!void {
    try writer.print("  EnumDecl {s} {s}\n", .{
        @tagName(enum_decl.visibility),
        interner.get(enum_decl.name) orelse "<missing>",
    });

    try dumpGenericParams(writer, ast, interner, enum_decl.generic_params, 2);
    try dumpWherePredicates(writer, ast, interner, enum_decl.where_predicates, 2);

    const start: usize = @intCast(enum_decl.variants.start);
    const end: usize = @intCast(enum_decl.variants.end());
    for (ast.enum_variants.items[start..end]) |variant| {
        try writer.print("    Variant {s} {s}\n", .{
            @tagName(variant.kind),
            interner.get(variant.name) orelse "<missing>",
        });

        const field_start: usize = @intCast(variant.fields.start);
        const field_end: usize = @intCast(variant.fields.end());
        for (ast.enum_fields.items[field_start..field_end]) |field| {
            try writer.writeAll("      Field ");
            if (field.name) |name| {
                try writer.print("{s}: ", .{interner.get(name) orelse "<missing>"});
            } else {
                try writer.writeAll("_: ");
            }
            try dumpTypeExpr(writer, ast, interner, field.type_expr);
            try writer.writeByte('\n');
        }
    }
}

fn dumpStruct(
    writer: *std.Io.Writer,
    ast: *const Ast,
    interner: *const base.Interner,
    struct_decl: StructDecl,
) std.Io.Writer.Error!void {
    try writer.print("  StructDecl {s} {s}\n", .{
        @tagName(struct_decl.visibility),
        interner.get(struct_decl.name) orelse "<missing>",
    });

    try dumpGenericParams(writer, ast, interner, struct_decl.generic_params, 2);
    try dumpWherePredicates(writer, ast, interner, struct_decl.where_predicates, 2);

    const start: usize = @intCast(struct_decl.fields.start);
    const end: usize = @intCast(struct_decl.fields.end());
    for (ast.struct_fields.items[start..end]) |field| {
        try writer.print("    Field {s} {s}: ", .{
            @tagName(field.visibility),
            interner.get(field.name) orelse "<missing>",
        });
        try dumpTypeExpr(writer, ast, interner, field.type_expr);
        try writer.writeByte('\n');
    }
}

fn dumpImport(
    writer: *std.Io.Writer,
    ast: *const Ast,
    interner: *const base.Interner,
    import_decl: ImportDecl,
) std.Io.Writer.Error!void {
    try writer.print("  ImportDecl {s}\n", .{@tagName(import_decl.visibility)});
    try writer.writeAll("    path ");
    try dumpPath(writer, ast, interner, import_decl.path);
    try writer.writeByte('\n');
    if (import_decl.items.len != 0) {
        try writer.writeAll("    items\n");
        const start: usize = @intCast(import_decl.items.start);
        const end: usize = @intCast(import_decl.items.end());
        for (ast.import_items.items[start..end]) |item| {
            try writer.print("      {s}\n", .{interner.get(item.name) orelse "<missing>"});
            if (item.alias) |alias| {
                try writer.print("        alias {s}\n", .{interner.get(alias) orelse "<missing>"});
            }
        }
    }
    if (import_decl.alias) |alias| {
        try writer.print("    alias {s}\n", .{interner.get(alias) orelse "<missing>"});
    }
}

fn dumpPath(
    writer: *std.Io.Writer,
    ast: *const Ast,
    interner: *const base.Interner,
    path: base.Range,
) std.Io.Writer.Error!void {
    const start: usize = @intCast(path.start);
    const end: usize = @intCast(path.end());
    for (ast.path_segments.items[start..end], 0..) |segment, index| {
        if (index != 0) try writer.writeByte('.');
        try writer.writeAll(interner.get(segment.name) orelse "<missing>");
    }
}

fn dumpTypeExpr(
    writer: *std.Io.Writer,
    ast: *const Ast,
    interner: *const base.Interner,
    type_id: TypeId,
) std.Io.Writer.Error!void {
    const type_expr = ast.types.items[type_id];
    switch (type_expr) {
        .unit => try writer.writeAll("()"),
        .path => |path_type| {
            try dumpPath(writer, ast, interner, path_type.segments);
            if (path_type.args.len != 0) {
                try writer.writeByte('<');
                const start: usize = @intCast(path_type.args.start);
                const end: usize = @intCast(path_type.args.end());
                for (ast.type_args.items[start..end], 0..) |arg, index| {
                    if (index != 0) try writer.writeAll(", ");
                    try dumpTypeExpr(writer, ast, interner, arg);
                }
                try writer.writeByte('>');
            }
        },
    }
}

test "AST dump renders import declarations" {
    var interner = base.Interner.init(std.testing.allocator);
    defer interner.deinit();

    var tree = Ast.init(std.testing.allocator, 0);
    defer tree.deinit();

    const start = tree.reservePath();
    try tree.addPathSegment(.{ .name = try interner.intern("std"), .span = .{ .source = 0, .start = 7, .len = 3 } });
    try tree.addPathSegment(.{ .name = try interner.intern("fs"), .span = .{ .source = 0, .start = 11, .len = 2 } });
    _ = try tree.addDecl(.{ .import = .{
        .visibility = .public,
        .path = .{ .start = start, .len = 2 },
        .span = .{ .source = 0, .start = 0, .len = 13 },
    } });

    const dumped = try dumpAst(std.testing.allocator, &tree, &interner);
    defer std.testing.allocator.free(dumped);

    try std.testing.expectEqualStrings(
        "Root\n" ++
            "  ImportDecl public\n" ++
            "    path std.fs\n",
        dumped,
    );
}

test "AST dump renders type alias declarations" {
    var interner = base.Interner.init(std.testing.allocator);
    defer interner.deinit();

    var tree = Ast.init(std.testing.allocator, 0);
    defer tree.deinit();

    const int_type_start = tree.reservePath();
    try tree.addPathSegment(.{ .name = try interner.intern("Int"), .span = .{ .source = 0, .start = 14, .len = 3 } });
    const int_type = try tree.addType(.{ .path = .{
        .segments = .{ .start = int_type_start, .len = 1 },
        .span = .{ .source = 0, .start = 14, .len = 3 },
    } });
    _ = try tree.addDecl(.{ .type_alias = .{
        .visibility = .package,
        .name = try interner.intern("UserId"),
        .name_span = .{ .source = 0, .start = 5, .len = 6 },
        .aliased_type = int_type,
        .span = .{ .source = 0, .start = 0, .len = 17 },
    } });

    const dumped = try dumpAst(std.testing.allocator, &tree, &interner);
    defer std.testing.allocator.free(dumped);

    try std.testing.expectEqualStrings(
        "Root\n" ++
            "  TypeAliasDecl package UserId = Int\n",
        dumped,
    );
}

test "AST dump renders function declarations" {
    var interner = base.Interner.init(std.testing.allocator);
    defer interner.deinit();

    var tree = Ast.init(std.testing.allocator, 0);
    defer tree.deinit();

    const user_type_start = tree.reservePath();
    try tree.addPathSegment(.{ .name = try interner.intern("User"), .span = .{ .source = 0, .start = 22, .len = 4 } });
    const user_type = try tree.addType(.{ .path = .{
        .segments = .{ .start = user_type_start, .len = 1 },
        .span = .{ .source = 0, .start = 22, .len = 4 },
    } });

    const params_start = tree.reserveFnParams();
    try tree.addFnParam(.{
        .is_mut = true,
        .name = try interner.intern("user"),
        .name_span = .{ .source = 0, .start = 16, .len = 4 },
        .type_expr = user_type,
        .span = .{ .source = 0, .start = 12, .len = 14 },
    });

    _ = try tree.addExpr(.{ .name = .{
        .symbol = try interner.intern("user"),
        .span = .{ .source = 0, .start = 38, .len = 4 },
    } });
    const stmts_start = tree.reserveBlockStmtIds();
    const body = try tree.addBlock(.{
        .stmts = .{ .start = stmts_start, .len = 0 },
        .span = .{ .source = 0, .start = 35, .len = 2 },
    });

    _ = try tree.addDecl(.{ .fn_decl = .{
        .visibility = .public,
        .name = try interner.intern("birthday"),
        .name_span = .{ .source = 0, .start = 7, .len = 8 },
        .params = .{ .start = params_start, .len = 1 },
        .return_type = user_type,
        .body = body,
        .span = .{ .source = 0, .start = 0, .len = 37 },
    } });

    const dumped = try dumpAst(std.testing.allocator, &tree, &interner);
    defer std.testing.allocator.free(dumped);

    try std.testing.expectEqualStrings(
        "Root\n" ++
            "  FnDecl public birthday\n" ++
            "    Param mut user: User\n" ++
            "    Return User\n" ++
            "    Block\n",
        dumped,
    );
}

test "AST dump renders struct declarations" {
    var interner = base.Interner.init(std.testing.allocator);
    defer interner.deinit();

    var tree = Ast.init(std.testing.allocator, 0);
    defer tree.deinit();

    const name_type_start = tree.reservePath();
    try tree.addPathSegment(.{ .name = try interner.intern("Str"), .span = .{ .source = 0, .start = 23, .len = 3 } });
    const name_type = try tree.addType(.{ .path = .{
        .segments = .{ .start = name_type_start, .len = 1 },
        .span = .{ .source = 0, .start = 23, .len = 3 },
    } });
    const fields_start = tree.reserveStructFields();
    try tree.addStructField(.{
        .visibility = .public,
        .name = try interner.intern("name"),
        .name_span = .{ .source = 0, .start = 17, .len = 4 },
        .type_expr = name_type,
        .span = .{ .source = 0, .start = 17, .len = 9 },
    });
    _ = try tree.addDecl(.{ .struct_decl = .{
        .visibility = .public,
        .name = try interner.intern("User"),
        .name_span = .{ .source = 0, .start = 11, .len = 4 },
        .fields = .{ .start = fields_start, .len = 1 },
        .span = .{ .source = 0, .start = 0, .len = 29 },
    } });

    const dumped = try dumpAst(std.testing.allocator, &tree, &interner);
    defer std.testing.allocator.free(dumped);

    try std.testing.expectEqualStrings(
        "Root\n" ++
            "  StructDecl public User\n" ++
            "    Field public name: Str\n",
        dumped,
    );
}

test "AST dump renders enum declarations" {
    var interner = base.Interner.init(std.testing.allocator);
    defer interner.deinit();

    var tree = Ast.init(std.testing.allocator, 0);
    defer tree.deinit();

    const variants_start = tree.reserveEnumVariants();
    const fields_start = tree.reserveEnumFields();
    const int_type_start = tree.reservePath();
    try tree.addPathSegment(.{ .name = try interner.intern("Int"), .span = .{ .source = 0, .start = 22, .len = 3 } });
    const int_type = try tree.addType(.{ .path = .{
        .segments = .{ .start = int_type_start, .len = 1 },
        .span = .{ .source = 0, .start = 22, .len = 3 },
    } });
    try tree.addEnumField(.{
        .type_expr = int_type,
        .span = .{ .source = 0, .start = 22, .len = 3 },
    });
    try tree.addEnumVariant(.{
        .name = try interner.intern("Some"),
        .name_span = .{ .source = 0, .start = 17, .len = 4 },
        .kind = .tuple,
        .fields = .{ .start = fields_start, .len = 1 },
        .span = .{ .source = 0, .start = 17, .len = 9 },
    });
    try tree.addEnumVariant(.{
        .name = try interner.intern("None"),
        .name_span = .{ .source = 0, .start = 29, .len = 4 },
        .kind = .unit,
        .span = .{ .source = 0, .start = 29, .len = 4 },
    });
    _ = try tree.addDecl(.{ .enum_decl = .{
        .visibility = .package,
        .name = try interner.intern("MaybeInt"),
        .name_span = .{ .source = 0, .start = 5, .len = 8 },
        .variants = .{ .start = variants_start, .len = 2 },
        .span = .{ .source = 0, .start = 0, .len = 36 },
    } });

    const dumped = try dumpAst(std.testing.allocator, &tree, &interner);
    defer std.testing.allocator.free(dumped);

    try std.testing.expectEqualStrings(
        "Root\n" ++
            "  EnumDecl package MaybeInt\n" ++
            "    Variant tuple Some\n" ++
            "      Field _: Int\n" ++
            "    Variant unit None\n",
        dumped,
    );
}
