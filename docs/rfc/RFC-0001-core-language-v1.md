# RFC-0001: Core Language v1

Status: Draft  
Target version: v1 / Interpreter-first implementation  
Implementation target: Zig bytecode VM  
Language codename: Veyl, provisional  
File extension: `.veyl`, provisional  
Manifest: `veyl.toml`, provisional  

> This RFC defines the first stable design target for the core language.  
> The language name, file extension, package manifest name, and CLI command are still provisional until the project is publicly named.

---

## 0. Summary

This language is a general-purpose, interpreter-first programming language with:

- Rust-like data modeling: `struct`, `enum`, `match`, `Option<T>`, `Result<T, E>`.
- Rust-like local mutability: `let` and `let mut`.
- Value semantics for normal data, implemented with Copy-on-Write when useful.
- No user-visible ownership, borrow checker, lifetimes, or move semantics.
- Result-based error handling with `try` and `catch`.
- Resource cleanup with `defer` and `defer err`.
- A low-friction module system based on `import` and file paths.
- Official formatting from v1.
- No async, macro system, class inheritance, or user-defined resource types in v1.

The first implementation is expected to be written in Zig and executed through a bytecode VM.

---

## 1. Goals

### 1.1 Primary goals

The language should feel like:

```text
Rust's data modeling and pattern matching
+ Zig's explicit error/resource handling
+ Swift-like value semantics
+ Go/Kotlin/Swift-like low-friction modules
- Rust ownership and lifetime burden
- Go's error boilerplate
- TypeScript's null/undefined/any legacy
- Zig's excessive low-level exposure for daily code
```

### 1.2 Design priorities

The design prioritizes:

1. Readability.
2. Low mental overhead.
3. Strong static analyzability.
4. Pattern matching as a first-class control-flow mechanism.
5. Errors as values.
6. Default immutability.
7. Value semantics for normal data.
8. Runtime implementation freedom through Copy-on-Write.
9. Future compatibility with a compiler/JIT/AOT path.
10. Good tooling: formatter, diagnostics, tests, language server.

---

## 2. Non-goals for v1

v1 does not include:

```text
async / await
task groups
macros
compile-time metaprogramming
class inheritance
bare null
truthy / falsy
operator overloading
implicit type conversion
user-visible ownership
borrow checker
lifetime annotations
user-defined resource types
effect system
actors
channels as language syntax
JIT
LLVM backend
native AOT compiler
FFI
```

These can be revisited in future RFCs.

---

## 3. Source files and package layout

### 3.1 File extension

The provisional source file extension is:

```text
.veyl
```

Example:

```text
main.veyl
config.veyl
http/router.veyl
```

The extension may be changed before public release if naming changes.

### 3.2 Package manifest

The provisional manifest file is:

```text
veyl.toml
```

Example:

```toml
[package]
name = "todo-app"
version = "0.1.0"

[deps]
http_client = { package = "http-client", version = "1.2.0" }
```

### 3.3 Recommended package structure

```text
veyl.toml
src/
    lib.veyl
    main.veyl
    config.veyl
    error.veyl
    http.veyl
    http/
        router.veyl
        server.veyl
tests/
    config_test.veyl
```

---

## 4. Lexical conventions and naming

### 4.1 Naming style

| Item | Style | Example |
|---|---|---|
| Variables | `snake_case` | `user_name` |
| Functions | `snake_case` | `load_config` |
| Methods | `snake_case` | `display_name` |
| Modules | `snake_case` | `http_server` |
| Files | `snake_case.veyl` | `user_profile.veyl` |
| Types | `PascalCase` | `UserProfile` |
| Structs | `PascalCase` | `HttpRequest` |
| Enums | `PascalCase` | `HttpError` |
| Enum variants | `PascalCase` | `NotFound` |
| Interfaces | `PascalCase` | `Reader` |
| Type parameters | `PascalCase` or single uppercase letter | `T`, `Error`, `Item` |
| Constants | `SCREAMING_SNAKE_CASE` | `MAX_RETRIES` |
| Registry package names | `kebab-case` | `http-client` |
| Code package aliases | `snake_case` | `http_client` |

### 4.2 Acronyms

Use readable acronym casing:

```rust
HttpClient
JsonValue
UrlParser
SqlDatabase

http_client
json_value
url_parser
sql_database
```

Avoid:

```rust
HTTPClient
JSONValue
URLParser
SQLDatabase
```

### 4.3 Unicode identifiers

The compiler may allow Unicode identifiers:

```rust
let 用户名 = "Ada";
```

However, public APIs, standard library APIs, package names, official docs, and examples should use ASCII identifiers.

Tooling should warn on mixed-script identifiers.

### 4.4 `_`

`_` is the wildcard pattern:

```rust
match event {
    Event.Click { x, y: _ } => print(x),
    _ => print("other"),
}
```

Names beginning with `_` indicate intentional non-use:

```rust
fn handle(_request: Request) {
    todo();
}
```

---

## 5. Keywords

### 5.1 v1 keywords

```rust
import
pub
private
as

struct
enum
type
interface
impl
where

fn
return

let
mut
const

if
else
match
for
in
while
break
continue

try
catch
defer

test

self
Self

true
false
```

### 5.2 Reserved for future versions

```rust
async
await
spawn
yield
macro
resource
```

---

## 6. Module system

### 6.1 Principles

The module system is designed to avoid Rust-like module complexity.

The language does not use:

```rust
mod
mod.rs
crate
super
self
::
```

Instead it uses:

```rust
import std.fs
import config.Config
import http.router.Router
import http_client.Client as HttpClient
```

### 6.2 File path determines module path

Given:

```text
src/lib.veyl             package public root
src/main.veyl            executable entry
src/config.veyl          config
src/error.veyl           error
src/http.veyl            http
src/http/router.veyl     http.router
src/http/server.veyl     http.server
```

A file may import package-local modules from the package root:

```rust
import config.Config
import error.AppError
import http.router.Router
```

No relative import syntax exists.

### 6.3 Import module

```rust
import std.fs
```

The local binding is the final path segment:

```rust
let text = try fs.read_text(path);
```

### 6.4 Import item

```rust
import std.path.Path
import config.Config
import config.ConfigError
```

Usage:

```rust
fn load(path: Path) -> Result<Config, ConfigError> {
    ...
}
```

### 6.5 Grouped import

```rust
import config.{Config, ConfigError}
import auth.{Token, verify_token}
```

Multiline formatting:

```rust
import config.{
    Config,
    ConfigError,
}
```

### 6.6 Aliased import

```rust
import http_client.Client as HttpClient
import std.json as json
```

Usage:

```rust
let client = HttpClient.new();
let user = try json.decode<User>(text);
```

### 6.7 Re-export

```rust
pub import http.router.Router
pub import http.router.Route
pub import http.server.Server
```

Grouped re-export:

```rust
pub import http.router.{Router, Route}
```

### 6.8 Import declarations do not use semicolons

```rust
import std.fs
import std.path.Path

import config.Config
```

`import` is a top-level declaration, not an ordinary statement.

### 6.9 Import roots

The first path segment may be:

```text
std                 standard library
dependency alias    declared in veyl.toml
local module        under src/
```

Example:

```rust
import std.fs
import http_client.Client
import config.Config
```

### 6.10 No relative imports

Not supported:

```rust
import .config
import ..config
import ../config
import super.config
```

Always use root-absolute imports:

```rust
import config.Config
import http.router.Router
```

### 6.11 Dependency aliases

In `veyl.toml`:

```toml
[deps]
http_client = { package = "http-client", version = "1.2.0" }
json_schema = { package = "json-schema", version = "0.4.0" }
```

In code:

```rust
import http_client.Client
import json_schema.Validator
```

Rules:

```text
package = registry/distribution name, may be kebab-case
alias   = code-level name, must be snake_case
```

Dependency aliases must not conflict with local top-level modules.

### 6.12 Public API surface

External packages may only access items reachable through the public surface of `src/lib.veyl`.

Example:

```rust
// src/lib.veyl

pub import config.Config
pub import config.load_config
pub import error.AppError
pub import http.Router
pub import http.Server
```

External usage:

```rust
import todo_app.Config
import todo_app.Router
```

Internal files may use package-local imports directly:

```rust
import config.Config
import http.router.Router
```

---

## 7. Visibility

### 7.1 Default visibility

Declarations are package-internal by default.

```rust
struct Token {
    value: Str,
}

fn normalize_token(token: Token) -> Token {
    ...
}
```

Other files in the same package may import these declarations. External packages may not.

### 7.2 `pub`

`pub` marks declarations as externally visible, provided they are reachable from the package's public surface.

```rust
pub struct Config {
    host: Str,
    port: Int,
}

pub fn load_config(path: Path) -> Result<Config, ConfigError> {
    ...
}
```

### 7.3 `private`

`private` marks declarations as file-private.

```rust
private fn parse_line(line: Str) -> Option<Pair<Str, Str>> {
    ...
}
```

Other files, even in the same package, may not import file-private declarations.

### 7.4 Struct field visibility

Struct fields default to the visibility of the struct.

```rust
pub struct User {
    id: UserId,
    name: Str,
    age: Int,
}
```

A field may be made private:

```rust
pub struct User {
    id: UserId,
    name: Str,
    private password_hash: Str,
}
```

Rules:

```text
A field cannot be more public than its containing type.
private fields are accessible only within the current file.
```

v1 does not support:

```text
public read / private write
protected
friend
```

### 7.5 Enum variant visibility

Enum variants inherit the visibility of the enum.

```rust
pub enum ConfigError {
    NotFound { path: Path },
    InvalidJson { source: JsonError },
}
```

v1 does not support per-variant visibility.

---

## 8. Base types

v1 defines:

```rust
Bool
Int
Float
Char
Str
Bytes
Array<T>
Map<K, V>
Option<T>
Result<T, E>
()
```

`()` is the unit type.

---

## 9. Nullability and absence

There is no bare `null`.

Absence is represented by:

```rust
Option<T>
```

Definition:

```rust
enum Option<T> {
    Some(T),
    None,
}
```

Example:

```rust
let Some(token) = request.header("Authorization") else {
    return Err(AuthError.MissingToken);
}
```

v1 does not include `T?` shorthand. It may be considered later as syntax sugar for `Option<T>`.

---

## 10. Result

Errors are ordinary values.

```rust
enum Result<T, E> {
    Ok(T),
    Err(E),
}
```

`Ok`, `Err`, `Some`, and `None` are part of the prelude.

Example:

```rust
fn load_config(path: Path) -> Result<Config, ConfigError> {
    ...
}
```

---

## 11. Value semantics

### 11.1 Core rule

Normal data has value semantics.

Assignment, binding, argument passing, return, and pattern binding produce logically independent values.

```rust
let user1 = User {
    name: "Ada",
    age: 32,
};

let mut user2 = user1;

user2.age += 1;

assert(user1.age == 32);
assert(user2.age == 33);
```

### 11.2 Value types

The following are value types:

```text
Int
Float
Bool
Char
Str
Bytes
Array<T>
Map<K, V>
tuple
struct
enum
Option<T>
Result<T, E>
```

User-defined `struct` and `enum` types are value types by default.

### 11.3 Handle types

Resource-like values are handle types:

```text
File
Socket
DbConnection
Process
Mutex
Channel
Timer
```

Handle types have identity and external state. They do not necessarily obey value-type independence.

v1 does not expose user-defined handle/resource types.

### 11.4 Copy-on-Write implementation freedom

Implementations may share storage internally.

```rust
let a = [1, 2, 3];
let mut b = a;
```

The runtime may share the underlying array storage.

On mutation:

```rust
b.push(4);
```

The implementation must preserve value semantics:

```rust
assert(a == [1, 2, 3]);
assert(b == [1, 2, 3, 4]);
```

Internal sharing must not be observable.

### 11.5 Nested value semantics

Value semantics are recursive.

```rust
struct User {
    name: Str,
    tags: Array<Str>,
}

let user1 = User {
    name: "Ada",
    tags: ["admin", "staff"],
};

let mut user2 = user1;

user2.tags.push("owner");

assert(user1.tags == ["admin", "staff"]);
assert(user2.tags == ["admin", "staff", "owner"]);
```

### 11.6 No user-visible move/copy/clone burden

Normal values do not require explicit `copy` or `clone`.

Do not write:

```rust
let mut user2 = user1.clone();
```

Write:

```rust
let mut user2 = user1;
```

Explicit clone-like APIs are reserved for handles, shared references, or future resource types.

---

## 12. Bindings and mutability

### 12.1 Immutable binding

```rust
let name = "Ada";
```

Cannot be reassigned:

```rust
name = "Grace";
// error
```

Cannot mutate fields through immutable binding:

```rust
let user = User {
    name: "Ada",
    age: 32,
};

user.age += 1;
// error
```

### 12.2 Mutable binding

```rust
let mut count = 0;

count += 1;
```

Mutable struct fields through mutable binding:

```rust
let mut user = User {
    name: "Ada",
    age: 32,
};

user.age += 1;
```

### 12.3 No field-level mutability

Not supported:

```rust
struct User {
    name: Str,
    mut age: Int,
}
```

Field mutability is controlled by the mutability of the place being modified.

### 12.4 Shadowing

Shadowing is allowed:

```rust
let input = read_line();
let input = input.trim();
let input = try parse_int(input);
```

Linters may warn on confusing shadowing.

---

## 13. Structs

### 13.1 Definition

```rust
pub struct User {
    id: UserId,
    name: Str,
    age: Int,
}
```

### 13.2 Literal

```rust
let user = User {
    id: UserId.new(),
    name: "Ada",
    age: 32,
};
```

### 13.3 Field shorthand

```rust
let id = UserId.new();
let name = "Ada";
let age = 32;

let user = User {
    id,
    name,
    age,
};
```

### 13.4 Field access

```rust
print(user.name);
```

### 13.5 Field mutation

```rust
let mut user = User {
    name: "Ada",
    age: 32,
};

user.age += 1;
```

If `user` is immutable, this is an error.

---

## 14. Enums

### 14.1 Definition

```rust
pub enum Shape {
    Circle { radius: Float },
    Rect { width: Float, height: Float },
    Point,
}
```

Enums may have:

```text
unit variants
tuple variants
record variants
```

Examples:

```rust
enum Option<T> {
    Some(T),
    None,
}

enum ConfigError {
    NotFound { path: Path },
    PermissionDenied { path: Path },
    InvalidJson { source: JsonError },
}
```

### 14.2 Variant construction

Use dot syntax:

```rust
let shape = Shape.Circle { radius: 10.0 };
let point = Shape.Point;
```

Tuple variant:

```rust
let value = Option.Some(42);
```

Prelude variants may be used directly:

```rust
let value = Some(42);
let result = Ok(user);
```

---

## 15. Type aliases

v1 supports aliases:

```rust
type UserId = Int;
type UserMap = Map<UserId, User>;
```

v1 does not introduce open union types:

```rust
type Id = Int | Str;
// not v1
```

Data modeling should use `enum`.

---

## 16. Functions

### 16.1 Definition

```rust
fn add(a: Int, b: Int) -> Int {
    a + b
}
```

No return value:

```rust
fn log_user(user: User) {
    print(user.name);
}
```

Equivalent to returning `()`.

### 16.2 Final expression return

The last expression without a semicolon is the return value.

```rust
fn status_text(code: Int) -> Str {
    match code {
        200 => "ok",
        404 => "not found",
        500..=599 => "server error",
        _ => "unknown",
    }
}
```

Adding a semicolon turns it into a statement:

```rust
fn add(a: Int, b: Int) -> Int {
    a + b;
}
// error: expected Int, got ()
```

### 16.3 Early return

```rust
fn divide(a: Float, b: Float) -> Result<Float, MathError> {
    if b == 0.0 {
        return Err(MathError.DivideByZero);
    }

    Ok(a / b)
}
```

### 16.4 Mutable parameters

Parameters are immutable by default:

```rust
fn birthday(user: User) -> User {
    user.age += 1;
    // error
}
```

Use `mut` for a mutable local copy:

```rust
fn birthday(mut user: User) -> User {
    user.age += 1;
    user
}
```

This does not mutate the caller's value.

### 16.5 Default parameters

```rust
fn connect(
    url: Str,
    timeout: Duration = 30.seconds(),
    retries: Int = 3,
) -> Result<Connection, NetError> {
    ...
}
```

Call:

```rust
let conn = try connect(
    "https://example.com",
    timeout: 5.seconds(),
    retries: 1,
);
```

### 16.6 Named parameters

Default parameters are overridden by name.

Boolean parameters should be named at call sites:

```rust
open(path, create: true, truncate: false);
```

Avoid:

```rust
open(path, true, false);
```

---

## 17. Methods and impl

### 17.1 Inherent impl

```rust
impl User {
    pub fn new(name: Str, age: Int) -> Self {
        Self {
            name,
            age,
        }
    }

    pub fn display_name(self) -> Str {
        self.name
    }
}
```

### 17.2 `self` and `Self`

```rust
self
```

is the current receiver.

```rust
Self
```

is the current type.

### 17.3 Non-mutating methods

```rust
impl User {
    fn display_name(self) -> Str {
        self.name
    }
}
```

### 17.4 Mutating receiver

```rust
impl User {
    fn birthday(mut self) {
        self.age += 1;
    }
}
```

Call requires a mutable place:

```rust
let user = User.new("Ada", 32);
user.birthday();
// error
```

```rust
let mut user = User.new("Ada", 32);
user.birthday();
// ok
```

If underlying storage is shared, mutation triggers Copy-on-Write.

### 17.5 Non-mutating transformation methods

```rust
impl User {
    fn with_age(self, age: Int) -> Self {
        let mut next = self;
        next.age = age;
        next
    }
}
```

Usage:

```rust
let user1 = User.new("Ada", 32);
let user2 = user1.with_age(33);

assert(user1.age == 32);
assert(user2.age == 33);
```

---

## 18. Generics

### 18.1 Generic functions

```rust
fn identity<T>(value: T) -> T {
    value
}
```

### 18.2 Generic types

```rust
enum Option<T> {
    Some(T),
    None,
}

enum Result<T, E> {
    Ok(T),
    Err(E),
}
```

### 18.3 Explicit type arguments

```rust
let user = try json.decode<User>(text);
```

v1 uses `<T>` syntax. It does not use Rust turbofish:

```rust
json.decode::<User>(text)
// not v1 style
```

### 18.4 Constraints

Simple constraint:

```rust
fn max<T: Ord>(a: T, b: T) -> T {
    if a > b {
        a
    } else {
        b
    }
}
```

Complex constraints:

```rust
fn sort<T>(items: Array<T>) -> Array<T>
where
    T: Ord,
{
    ...
}
```

---

## 19. Interfaces

### 19.1 Definition

```rust
pub interface Reader {
    fn read(mut self, buf: Bytes) -> Result<Int, IoError>;
}
```

Interface methods contain signatures only.

### 19.2 Structural satisfaction

A type satisfies an interface if it has the required methods.

```rust
struct File {
    path: Path,
}

impl File {
    fn read(mut self, buf: Bytes) -> Result<Int, IoError> {
        ...
    }
}
```

Generic usage:

```rust
fn read_all<R: Reader>(mut reader: R) -> Result<Bytes, IoError> {
    ...
}
```

### 19.3 Explicit conformance assertion

```rust
impl Reader for File {
}
```

This requires the compiler to verify that `File` satisfies `Reader`.

v1 does not require methods to be implemented inside conformance blocks, though this may be extended later.

---

## 20. Expressions and statements

### 20.1 Semicolon rules

Ordinary statements use semicolons:

```rust
let x = 1;
print(x);
return Ok(());
```

Top-level declarations do not use semicolons:

```rust
import std.fs

struct User {
    name: Str,
}
```

Final expressions do not use semicolons:

```rust
fn add(a: Int, b: Int) -> Int {
    a + b
}
```

### 20.2 Block expressions

Blocks may produce values:

```rust
let x = {
    let a = 1;
    let b = 2;
    a + b
};
```

### 20.3 If expressions

```rust
let label = if age >= 18 {
    "adult"
} else {
    "minor"
};
```

If used as an expression, `else` is required.

As a statement, `else` is optional:

```rust
if age >= 18 {
    print("adult");
}
```

Conditions must be `Bool`.

No truthy/falsy:

```rust
if name {
    ...
}
// error
```

Use:

```rust
if name != "" {
    ...
}
```

### 20.4 Match expressions

```rust
let text = match code {
    200 => "ok",
    404 => "not found",
    500..=599 => "server error",
    _ => "unknown",
};
```

`match` is an expression.

---

## 21. Pattern matching

### 21.1 Match syntax

```rust
match value {
    pattern => expr,
    pattern if guard => expr,
    _ => fallback,
}
```

Example:

```rust
match event {
    Event.Click { x, y } => handle_click(x, y),
    Event.Key { code } if code == "Escape" => close_window(),
    Event.Close => return Ok(()),
}
```

### 21.2 Pattern kinds

Literal:

```rust
match code {
    200 => "ok",
    404 => "not found",
    _ => "unknown",
}
```

Or-pattern:

```rust
match n {
    1 | 2 | 3 => "small",
    _ => "large",
}
```

Range:

```rust
match code {
    200..=299 => "success",
    400..=499 => "client error",
    500..=599 => "server error",
    _ => "other",
}
```

Enum:

```rust
match result {
    Ok(value) => value,
    Err(err) => return Err(err),
}
```

Struct:

```rust
match user {
    User { name, age } => print("{name}: {age}"),
}
```

Array:

```rust
match parts {
    ["users", id] => handle_user(id),
    ["assets", ..rest] => handle_asset(rest),
    _ => not_found(),
}
```

Wildcard:

```rust
_
```

Guard:

```rust
match user {
    User { age, .. } if age >= 18 => "adult",
    _ => "minor",
}
```

### 21.3 Exhaustiveness

Enum matches must be exhaustive.

```rust
enum Shape {
    Circle { radius: Float },
    Rect { width: Float, height: Float },
    Point,
}

fn area(shape: Shape) -> Float {
    match shape {
        Shape.Circle { radius } => 3.14159 * radius * radius,
        Shape.Rect { width, height } => width * height,
        // error: missing Shape.Point
    }
}
```

Wildcard is allowed:

```rust
match shape {
    Shape.Circle { radius } => ...,
    _ => ...,
}
```

### 21.4 Match does not consume

Pattern matching does not move, copy, or clone in user-visible semantics.

```rust
match user {
    User { name, age } => {
        print(name);
        print(age);
    },
}

print(user);
// ok
```

### 21.5 Pattern bindings

Pattern bindings are normal bindings.

```rust
let User { name, age } = user;
```

To make a bound local mutable:

```rust
let User { name: mut name, age } = user;

name.push_str(" Lovelace");
```

This mutates only the local binding `name`, not `user.name`.

### 21.6 `if let`

```rust
if let Some(token) = request.header("Authorization") {
    use_token(token);
}
```

With `else`:

```rust
if let Some(token) = maybe_token {
    use_token(token);
} else {
    return Err(AuthError.MissingToken);
}
```

### 21.7 `while let`

```rust
while let Some(item) = stream.next() {
    handle(item);
}
```

### 21.8 `let ... else`

```rust
let Some(token) = request.header("Authorization") else {
    return Err(AuthError.MissingToken);
}

let user = try auth.verify(token);
```

Rules:

```text
If the pattern matches, bindings enter the outer scope.
If the pattern fails, the else block runs.
The else block must diverge.
```

Allowed divergence:

```rust
return
break
continue
panic(...)
```

Invalid:

```rust
let Some(token) = maybe_token else {
    print("missing");
}

use_token(token);
// error
```

### 21.9 `let ... else` semicolon rule

`let ... else` does not require a trailing semicolon after the `else` block:

```rust
let Some(token) = maybe_token else {
    return Err(Error.MissingToken);
}
```

Ordinary `let` does require a semicolon:

```rust
let token = get_token();
```

---

## 22. Error handling

### 22.1 Result-based errors

Recoverable errors use `Result<T, E>`.

```rust
fn load_config(path: Path) -> Result<Config, ConfigError> {
    ...
}
```

### 22.2 `try`

```rust
let text = try fs.read_text(path);
```

Equivalent to:

```rust
let text = match fs.read_text(path) {
    Ok(value) => value,
    Err(err) => return Err(err),
};
```

`try` works on `Result<T, E>`.

v1 does not apply `try` to `Option<T>`.

### 22.3 No implicit error conversion

If error types match:

```rust
fn read_user(path: Path) -> Result<User, IoError> {
    let text = try fs.read_text(path);
    parse_user(text)
}
```

If error types differ, map explicitly:

```rust
fn load_config(path: Path) -> Result<Config, ConfigError> {
    let text = fs.read_text(path) catch |err| {
        return Err(ConfigError.ReadFailed {
            path,
            source: err,
        });
    };

    json.decode<Config>(text) catch |err| {
        return Err(ConfigError.InvalidJson {
            source: err,
        });
    }
}
```

v1 does not include implicit `From`/`Into`-style conversions.

### 22.4 `catch`

Fallback value:

```rust
let port = parse_int(env.get("PORT")) catch 8080;
```

Error binding:

```rust
let text = fs.read_text(path) catch |err| {
    return Err(ConfigError.ReadFailed {
        path,
        source: err,
    });
};
```

`catch` is an expression.

### 22.5 `panic`

`panic` is for unrecoverable errors and programmer bugs:

```rust
panic("impossible state");
```

It should not be used for normal business errors.

---

## 23. Defer

### 23.1 `defer`

`defer` registers a cleanup block that runs when the current lexical scope exits.

```rust
let file = try fs.open(path);

defer {
    file.close();
}

let text = try file.read_all();
```

Multiple defers run in LIFO order.

```rust
defer {
    print("first");
}

defer {
    print("second");
}

// prints "second", then "first"
```

### 23.2 `defer err`

`defer err` runs only when the current scope exits through a `Result.Err` path.

```rust
fn save_user(user: User) -> Result<(), DbError> {
    let tx = try db.begin();

    defer err {
        tx.rollback();
    }

    try tx.insert("users", user);
    try tx.commit();

    Ok(())
}
```

If the function returns `Ok`, rollback does not run.

If the function returns `Err`, or `try` propagates an `Err`, rollback runs.

### 23.3 `defer err` restrictions

v1 rules:

```text
defer err may only appear in functions returning Result.
defer err reacts to Result error paths.
panic behavior for defer err is not guaranteed in v1.
plain defer runs on normal and error returns.
```

### 23.4 Scope

`defer` is bound to the current lexical scope.

```rust
fn example() -> Result<(), Error> {
    {
        defer {
            print("leave inner");
        }

        print("inside");
    }

    print("outside");

    Ok(())
}
```

Output:

```text
inside
leave inner
outside
```

---

## 24. Control flow

### 24.1 `for`

```rust
for item in items {
    handle(item);
}
```

`items` must be iterable.

### 24.2 `while`

```rust
while count < 10 {
    count += 1;
}
```

Condition must be `Bool`.

### 24.3 `break` and `continue`

```rust
for item in items {
    if item.is_empty() {
        continue;
    }

    if item == "stop" {
        break;
    }
}
```

v1 does not include labeled break.

---

## 25. Strings

### 25.1 String literal

```rust
let name = "Ada";
```

### 25.2 Character literal

```rust
let c = 'a';
```

### 25.3 Interpolation

```rust
let message = "hello {name}";
let message = "user {user.id} logged in";
let message = "next age = {user.age + 1}";
```

Escaped braces:

```rust
let text = "{{ not interpolation }}";
```

Output:

```text
{ not interpolation }
```

### 25.4 Raw strings

```rust
let regex = r"\d+\.\d+";
let json = r#"{"name": "Ada"}"#;
```

Additional `#` delimiters may be supported.

---

## 26. Comments and documentation

### 26.1 Line comment

```rust
// this is a comment
```

### 26.2 Block comment

```rust
/*
this is a block comment
*/
```

Nested block comments should be supported:

```rust
/*
outer
    /*
    inner
    */
*/
```

### 26.3 Documentation comments

```rust
/// Loads a config file from disk.
///
/// Returns `ConfigError.NotFound` if the file does not exist.
pub fn load_config(path: Path) -> Result<Config, ConfigError> {
    ...
}
```

Module docs:

```rust
//! Configuration loading utilities.
```

Documentation uses Markdown.

---

## 27. Prelude

The prelude is intentionally small.

Included:

```rust
Bool
Int
Float
Char
Str
Bytes
Array<T>
Map<K, V>

Option<T>
Some
None

Result<T, E>
Ok
Err

print
assert
panic
```

Not included:

```rust
fs
json
http
time
process
thread
path
```

Those require explicit imports:

```rust
import std.fs
import std.json
import std.path.Path
```

---

## 28. Tests

### 28.1 Test block

v1 has built-in test blocks instead of macros.

```rust
test "birthday increments age" {
    let user = User.new("Ada", 32);
    let mut next = user;

    next.birthday();

    assert(user.age == 32);
    assert(next.age == 33);
}
```

### 28.2 `try` in tests

```rust
test "load config" {
    let config = try load_config("fixtures/app.json");

    assert(config.port == 8080);
}
```

If `try` produces `Err`, the test fails.

### 28.3 Test file layout

Recommended:

```text
tests/
    config_test.veyl
```

External tests import the package public API:

```rust
import todo_app.Config
import todo_app.load_config
```

Internal tests may live beside source code.

---

## 29. Formatting

v1 requires an official formatter.

Principles:

```text
One official style.
Minimal configuration.
Formatter output is canonical.
```

### 29.1 Indentation

4 spaces.

```rust
fn main() {
    print("hello");
}
```

### 29.2 Line width

Default maximum line width:

```text
100
```

### 29.3 Braces

K&R style:

```rust
if age >= 18 {
    print("adult");
} else {
    print("minor");
}
```

Not:

```rust
if age >= 18
{
    ...
}
```

### 29.4 Conditions do not use parentheses

```rust
if count > 0 {
    ...
}
```

Not:

```rust
if (count > 0) {
    ...
}
```

### 29.5 Multiline trailing commas

Struct literal:

```rust
let user = User {
    id,
    name,
    age,
};
```

Function call:

```rust
let response = try client.request(
    Method.Post,
    "/users",
    RequestBody.Json(user),
);
```

Function definition:

```rust
fn create_user(
    name: Str,
    email: Email,
    role: UserRole,
) -> Result<User, UserError> {
    ...
}
```

### 29.6 Match formatting

Single-line arms:

```rust
match event {
    Event.Click { x, y } => handle_click(x, y),
    Event.Close => return Ok(()),
}
```

Multiline arms:

```rust
match result {
    Ok(user) => {
        log.info("loaded user");
        Ok(user)
    },
    Err(err) => {
        log.error("failed to load user");
        Err(err)
    },
}
```

### 29.7 Import sorting

Formatter groups imports:

```rust
import std.fs
import std.json
import std.path.Path

import http_client.Client
import json_schema.Validator

import config.Config
import error.AppError
```

Order:

```text
1. std
2. third-party dependencies
3. current package modules
```

Items are sorted alphabetically within each group.

---

## 30. Standard library path style

Standard library root:

```rust
std
```

Examples:

```rust
import std.fs
import std.json
import std.path.Path
import std.time.Duration
```

Usage:

```rust
let text = try fs.read_text(path);
let config = try json.decode<Config>(text);
```

---

## 31. Main function

### 31.1 Plain main

```rust
fn main() {
    print("hello");
}
```

### 31.2 Result main

```rust
fn main() -> Result<(), AppError> {
    let config = try load_config("app.json");
    run_app(config)
}
```

If `main` returns `Err`, the runner prints the error and exits with a non-zero code.

---

## 32. Complete example

### 32.1 `veyl.toml`

```toml
[package]
name = "todo-app"
version = "0.1.0"

[deps]
http_client = { package = "http-client", version = "1.2.0" }
```

### 32.2 `src/lib.veyl`

```rust
//! Public API for todo-app.

pub import config.Config
pub import config.ConfigError
pub import config.load_config

pub import error.AppError

pub import http.Router
pub import http.Route
pub import http.Server
```

### 32.3 `src/error.veyl`

```rust
pub enum AppError {
    ConfigFailed { source: ConfigError },
    ServerFailed { source: ServerError },
}
```

### 32.4 `src/config.veyl`

```rust
import std.fs
import std.json
import std.path.Path

pub struct Config {
    host: Str,
    port: Int,
}

pub enum ConfigError {
    NotFound { path: Path },
    ReadFailed { path: Path, source: IoError },
    InvalidJson { source: JsonError },
}

pub fn load_config(path: Path) -> Result<Config, ConfigError> {
    let text = fs.read_text(path) catch |err| {
        return Err(ConfigError.ReadFailed {
            path,
            source: err,
        });
    };

    json.decode<Config>(text) catch |err| {
        return Err(ConfigError.InvalidJson {
            source: err,
        });
    }
}
```

### 32.5 `src/http/router.veyl`

```rust
pub struct Router {
    routes: Array<Route>,
}

pub enum Route {
    Home,
    User { id: UserId },
    Asset { path: Str },
}

impl Router {
    pub fn new() -> Self {
        Self {
            routes: [],
        }
    }

    pub fn add(mut self, route: Route) {
        self.routes.push(route);
    }

    pub fn parse(self, path: Str) -> Option<Route> {
        match path.split("/") {
            [""] | ["", ""] => Some(Route.Home),
            ["", "users", id] => Some(Route.User {
                id: UserId.parse(id),
            }),
            ["", "assets", ..parts] => Some(Route.Asset {
                path: parts.join("/"),
            }),
            _ => None,
        }
    }
}
```

### 32.6 `src/http/server.veyl`

```rust
import http.router.Router

pub struct Server {
    router: Router,
    config: Config,
}

pub enum ServerError {
    BindFailed { host: Str, port: Int },
    RuntimeFailed { message: Str },
}

impl Server {
    pub fn new(config: Config) -> Self {
        let mut router = Router.new();

        router.add(Route.Home);
        router.add(Route.Asset {
            path: "public".to_str(),
        });

        Self {
            router,
            config,
        }
    }

    pub fn run(mut self) -> Result<(), ServerError> {
        print("listening on {self.config.host}:{self.config.port}");

        Ok(())
    }
}
```

### 32.7 `src/http.veyl`

```rust
pub import http.router.Router
pub import http.router.Route
pub import http.server.Server
pub import http.server.ServerError
```

### 32.8 `src/main.veyl`

```rust
import config.load_config
import error.AppError
import http.Server

fn main() -> Result<(), AppError> {
    let config = load_config("app.json") catch |err| {
        return Err(AppError.ConfigFailed {
            source: err,
        });
    };

    let mut server = Server.new(config);

    server.run() catch |err| {
        return Err(AppError.ServerFailed {
            source: err,
        });
    }
}
```

### 32.9 Value semantics test

```rust
test "config value semantics" {
    let config1 = Config {
        host: "localhost",
        port: 8080,
    };

    let mut config2 = config1;

    config2.port = 3000;

    assert(config1.port == 8080);
    assert(config2.port == 3000);
}
```

---

## 33. Rationale by language influence

This RFC borrows:

```text
Rust:
    let / let mut
    struct / enum
    match
    if let / while let / let else
    Result / Option
    final-expression returns
    default immutability

Zig:
    try / catch direction
    defer / errdefer direction
    explicit error flow

Swift:
    value semantics
    Copy-on-Write-friendly runtime model
    low-friction module boundary

Go:
    low ceremony
    package-internal visibility intuition
    simple tooling expectations

Kotlin:
    import path as Alias
    default and named parameters

TypeScript:
    structural interface intuition
    lightweight scripting ergonomics
```

This RFC rejects:

```text
Rust:
    user-visible ownership
    borrow checker
    lifetimes
    crate/mod/mod.rs module model
    macro_rules

Go:
    uppercase export rule
    if err != nil boilerplate
    string import paths

Zig:
    @import("...")
    excessive low-level exposure in user code
    v1 async complexity

TypeScript:
    any
    null/undefined split
    truthy/falsy
    relative string imports
    JavaScript historical baggage

Kotlin/Java:
    class inheritance
    package header detached from file layout
```

---

## 34. v1 decisions

This RFC fixes the following decisions:

```text
1. Use let / let mut.
2. Do not support field-level mut.
3. Normal data has value semantics.
4. Implementations may use Copy-on-Write.
5. Pattern matching does not consume values.
6. Do not expose copy/clone/ref/move in normal code.
7. Handle/resource types are exceptions, but user-defined resources are not v1.
8. Use struct and enum as the main data modeling tools.
9. Use final-expression function returns.
10. Use <T> generics.
11. Use structural interfaces with optional explicit conformance assertions.
12. Use Result<T, E>, try, and catch for errors.
13. Use defer and defer err for cleanup.
14. Do not implement async in v1.
15. Do not implement macros in v1.
16. Use import, not use.
17. Do not use crate, mod, super, self, or :: in the module system.
18. Use . for paths, variants, associated functions, fields, and methods.
19. File paths determine module paths.
20. Imports are root-absolute.
21. No relative imports.
22. Default visibility is package-internal.
23. pub means externally visible.
24. private means file-private.
25. Official formatting is part of v1.
```

---

## 35. Future RFCs

Suggested follow-up RFCs:

```text
RFC-0002: Lexer, parser, and concrete grammar
RFC-0003: Pattern matching and exhaustiveness
RFC-0004: Type system, generics, and interfaces
RFC-0005: Standard library v1
RFC-0006: Package manager and version resolution
RFC-0007: Handle/resource types
RFC-0008: Async, task groups, and cancellation
RFC-0009: Runtime, bytecode, and VM semantics
RFC-0010: Formatter specification
RFC-0011: Diagnostics and language server protocol
RFC-0012: Future compiler backend / JIT / AOT path
```

---

## 36. Implementation notes

The first implementation should:

```text
1. Be written in Zig.
2. Use a bytecode VM, not a long-term tree-walk interpreter.
3. Store compilation-time data in arenas.
4. Represent AST/HIR/type/module graphs using IDs, not pointer trees.
5. Store runtime values in a RuntimeHeap.
6. Implement normal values with refcount + Copy-on-Write.
7. Keep host I/O behind a host abstraction layer.
8. Keep Zig std.Io usage out of the core compiler and VM.
9. Build formatter and diagnostics early.
10. Avoid async/JIT/GC/macros until v1 semantics are stable.
```

---

## 37. Minimal v1 implementation milestones

```text
M0: Zig project skeleton
M1: SourceMap, Span, Diagnostic, Interner
M2: Lexer
M3: Parser and AST dump
M4: Formatter skeleton
M5: HIR lowering
M6: Module resolution
M7: Minimal type checker
M8: Bytecode compiler
M9: Stack VM
M10: Runtime Value and COW semantics
M11: Result, try, catch
M12: defer and defer err
M13: test runner
M14: package-local imports
M15: std.fs / std.json prototypes
```

---

## 38. Final statement

The language defined by this RFC is:

```text
Rust-like in data modeling,
Swift-like in value semantics,
Zig-like in error and cleanup control,
Go/Kotlin-like in low-friction modules,
and intentionally not Rust-like in ownership complexity.
```

Its core identity is:

```text
match-rich,
value-oriented,
error-explicit,
immutable-by-default,
runtime-pragmatic,
tooling-first.
```
