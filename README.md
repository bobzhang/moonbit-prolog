# MoonBit Prolog

A small but real Prolog interpreter written in MoonBit. It implements a
tokenizer, a precedence-climbing parser with Prolog operator precedences,
first-order unification with occurs check, and an SLD-resolution engine with
depth-first search, backtracking, and correct cut semantics — plus a REPL.

Published on mooncakes.io: run it without installing anything:

```
$ echo '?- member(X, [a, b, c]).' | moonx bobzhang/prolog
```

Or build it yourself (a `moon.work` workspace with two modules):

```
$ moon build --target native
$ ./_build/native/debug/build/bobzhang/prolog/prolog.exe            # async REPL (wasm & native)
$ ./_build/native/debug/build/bobzhang/prolog-repl/cmd/repl/repl.exe  # interactive `;` REPL (native)
$ ./_build/native/debug/build/bobzhang/prolog/prolog.exe < examples/family.pl
```

## Workspace layout

* `prolog/` — module `bobzhang/prolog` (published to mooncakes.io):
  * top-level package: the REPL entry point that `moonx bobzhang/prolog`
    runs, built on `moonbitlang/async` stdio so it works on wasm and native;
  * `lib/` package: the pure engine — terms, unification, parser, SLD
    resolution. No I/O: `write/1` captures into the `Ctx` output buffer and
    `halt/0` sets a flag. Use it with
    `import { "bobzhang/prolog/lib" @lib }`.
* `repl/` — local module `bobzhang/prolog-repl`: the interactive native REPL
  with `;` prompting (libc `getchar`, so native-only).

## Language

```prolog
% Facts, rules, queries — each statement ends with `.` and may span lines.
parent(john, mary).
grandparent(X, Y) :- parent(X, Z), parent(Z, Y).
?- grandparent(G, ann).
```

* Terms: atoms, integers, strings (`"..."`), variables (`X`, `_`, `_Anon`),
  compound terms `f(a, b)`, lists `[a, b | T]` (real `.`/`[]` cons terms).
* Operators with Prolog precedences: `:-` 1200, `;` 1100, `,` 1000,
  comparisons/`is` 700, `+`/`-` 500, `*`/`//`/`mod`/`div` 400, unary `-`,
  prefix `\+`. Compound arguments and list elements parse at precedence 999.
* Quoted atoms `'Hello, world'`, `%` comments (quote-aware).

## Builtins

| Category | Predicates |
| --- | --- |
| Control | `true/0`, `fail/0`, `!/0` (cut), `;/2`, `,/2`, `call/1`, `\+/1` (negation as failure), `repeat/0`, `halt/0` |
| Unification | `=/2` (occurs check), `\=/2`, `==/2`, `\==/2` |
| Arithmetic | `is/2`, `=:=/2`, `=\=/2`, `</2`, `>/2`, `=</2`, `>=/2` |
| Term tests | `var/1`, `nonvar/1`, `atom/1`, `number/1`, `integer/1`, `atomic/1`, `compound/1` |
| I/O | `write/1`, `writeln/1`, `nl/0` |
| Meta | `findall/3`, `assert/1`, `assertz/1` |
| Generation | `between/3`, `length/2` (both directions; generates `0, 1, 2, ...` with both arguments unbound, like real Prolog) |

`member/2`, `append/3` and `reverse/2` are preloaded as ordinary Prolog
clauses — feel free to redefine them.

## REPL

* `prolog> ` prompt; statements accumulate until a line ends with `.`.
* In a terminal, after each answer you are asked for `;` (next solution) —
  any other input stops. Piped input prints all solutions automatically.
* `halt.` exits.

```
prolog> sibling(X, Y) :- parent(P, X), parent(P, Y), X \= Y.
prolog> sibling(S1, S2).

S1 = mary
S2 = peter

S1 = peter
S2 = mary

false.
```

## How it works

* `parser.mbt` — tokenizer + Pratt parser; parse errors are raised as
  `Failure` and become `None` in `parse_statement`.
* `term.mbt` — terms, persistent substitutions (copy-on-write, so
  backtracking is free), unification with occurs check, pretty-printer,
  arithmetic evaluation.
* `engine.mbt` — CPS-based SLD resolution. Each predicate invocation and
  disjunction pushes a flag onto a choice-point stack; `!` sets every flag
  from the top of the stack down through the marker of the invocation whose
  body it textually belongs to, which prunes exactly the choice points
  created since that invocation began.
* `main.mbt` — the REPL, using `extern "c"` FFI (`getchar`/`putchar`) for
  byte-wise stdin/stdout so no dependencies are needed beyond core.

## Deliberate divergences from ISO Prolog

* `==/2` is variant equality (two unbound variables compare equal), not
  identity comparison.
* `p :- a ; b.` parses as `:-(p, ;(a, b))` rather than `(:-(p,a)) ; b`.
* Arithmetic errors (e.g. `X is 1 + Y` with `Y` unbound) fail silently
  instead of raising instantiation errors.
* Chained `=` is left-associative rather than a syntax error.
* No floats, no strings-as-lists, no operator declarations, no DCGs.

## Running the examples

```bash
./_build/native/debug/build/cmd/main/main.exe < examples/family.pl
```
