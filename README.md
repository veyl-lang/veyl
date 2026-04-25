# Veyl

Veyl is a value-oriented general-purpose programming language.

It combines Rust-like data modeling and pattern matching with a low-friction
runtime model based on value semantics and copy-on-write. Veyl treats errors as
values, keeps normal data immutable by default, and avoids exposing ownership or
lifetimes in everyday code.

The first implementation is written in Zig and runs Veyl through a bytecode VM.
