/// SLD-resolution engine: depth-first search with backtracking, a choice
/// point stack for exact cut semantics, negation as failure, and builtins.
///
/// The engine is pure: it performs no I/O. `write/1` appends to the `Ctx`
/// output buffer (see `Ctx::take_output`), and `halt/0` sets a flag and
/// stops the search. Hosts drive it through `Ctx::submit` / `Ctx::query`.
///
/// The solver is CPS-based: `search` explores all solutions of its goal
/// list and calls `cont` on every success. Backtracking is implicit in the
/// recursion; substitutions are persistent so no unbinding is needed.
///
/// Cut: each predicate invocation and each disjunction pushes a flag cell
/// onto `choice_stack`. `!` sets every flag above (and including) the
/// marker of the invocation whose body it textually belongs to, which
/// prunes exactly the choice points created since that invocation began.

///|
/// Interpreter state. Create with `Ctx::new()`.
pub struct Ctx {
  clauses : Array[Clause]
  choice_stack : Array[Array[Bool]]
  mut next_var : Int32
  stop : Array[Bool]
  mut output : String
  mut halting : Bool
}

///|
/// Result of submitting one statement to `Ctx::submit`.
pub enum Submit {
  /// The text could not be parsed.
  SyntaxError
  /// A fact or rule was asserted.
  Fact
  /// `halt.` was submitted.
  Halt
  /// A query ran: number of solutions found and whether the solution
  /// callback asked to stop early.
  Query(Int32, Bool)
}

///|
pub fn Ctx::new() -> Ctx {
  let ctx = Ctx::{
    clauses: [],
    choice_stack: [],
    next_var: 0,
    stop: [false],
    output: "",
    halting: false,
  }
  seed(ctx)
  ctx
}

///|
/// Take and clear the text captured by `write/1`, `writeln/1` and `nl/0`.
pub fn Ctx::take_output(self : Ctx) -> String {
  let o = self.output
  self.output = ""
  o
}

///|
/// Parse and run one statement.
///
/// `on_solution` is called for every answer found, with the substitution;
/// return `true` to keep searching, `false` to stop (e.g. an interactive
/// `;` prompt answered with anything but `;`).
pub fn Ctx::submit(
  self : Ctx,
  text : String,
  on_solution : (Array[Term?], Array[(String, Int32)]) -> Bool,
) -> Submit {
  match parse_statement(self, text) {
    None => SyntaxError
    Some(StClause(c)) =>
      match c.head {
        Atom("halt") => {
          self.halting = true
          Halt
        }
        _ => {
          self.clauses.push(c)
          Fact
        }
      }
    Some(StQuery(goals, vars)) => {
      let (n, stopped) = self.query(goals, vars, on_solution)
      Query(n, stopped)
    }
  }
}

///|
/// Run a query, returning `(solutions_found, stopped_early)`.
pub fn Ctx::query(
  self : Ctx,
  goals : Array[Term],
  vars : Array[(String, Int32)],
  on_solution : (Array[Term?], Array[(String, Int32)]) -> Bool,
) -> (Int32, Bool) {
  self.stop[0] = false
  while self.choice_stack.length() > 0 {
    ignore(self.choice_stack.pop())
  }
  let cnt = [0]
  let cont = fn(s : Array[Term?]) -> Unit {
    cnt[0] = cnt[0] + 1
    if !on_solution(s, vars) {
      self.stop[0] = true
    }
  }
  search(self, goals, 0, [], -1, goals.length(), -1, cont)
  (cnt[0], self.stop[0])
}

///|
fn fresh_var(ctx : Ctx) -> Int32 {
  let v = ctx.next_var
  ctx.next_var = v + 1
  v
}

///|
/// Renames variables of a clause to fresh ids before each use, mapping each
/// distinct variable (by its global id) to exactly one fresh id so that
/// variable identity within the clause is preserved.
priv struct Renamer {
  ctx : Ctx
  table : Array[Int32]
}

///|
fn rename_clause(ctx : Ctx, c : Clause) -> Clause {
  let r = Renamer::{ ctx, table: [], }
  let body : Array[Term] = []
  for g in c.body {
    body.push(rename_term(r, g))
  }
  Clause::{ head: rename_term(r, c.head), body, }
}

///|
fn rename_term(r : Renamer, t : Term) -> Term {
  match t {
    Var(v) =>
      if v < r.table.length() && r.table[v] >= 0 {
        Var(r.table[v])
      } else {
        let nv = fresh_var(r.ctx)
        while r.table.length() <= v {
          r.table.push(-1)
        }
        r.table[v] = nv
        Var(nv)
      }
    Compound(f, args) => {
      let ns : Array[Term] = []
      for a in args {
        ns.push(rename_term(r, a))
      }
      Compound(f, ns)
    }
    _ => t
  }
}

///|
/// Set every cut flag from the top of the choice stack down through `marker`.
fn cut_through(ctx : Ctx, marker : Int32) -> Unit {
  let mut i = ctx.choice_stack.length() - 1
  while i >= marker && i >= 0 {
    ctx.choice_stack[i][0] = true
    i = i - 1
  }
}

///|
/// Deep-copy a dereferenced term, giving unbound variables fresh ids
/// (used by `findall/3` so each collected answer is independent).
fn copy_term(ctx : Ctx, subst : Array[Term?], t : Term) -> Term {
  match deref(subst, t) {
    Var(_) => Var(fresh_var(ctx))
    Atom(a) => Atom(a)
    Num(n) => Num(n)
    Str(s) => Str(s)
    Compound(f, args) => {
      let ns : Array[Term] = []
      for a in args {
        ns.push(copy_term(ctx, subst, a))
      }
      Compound(f, ns)
    }
  }
}

///|
/// Build a list term from a solution collection (order preserved).
fn build_list(items : Array[Term]) -> Term {
  let mut result = Atom("[]")
  let mut i = items.length() - 1
  while i >= 0 {
    result = Compound(".", [items[i], result])
    i = i - 1
    continue
  }
  result
}

///|
fn rest_of(goals : Array[Term], idx : Int32) -> Array[Term] {
  let ns : Array[Term] = []
  let mut i = idx
  while i < goals.length() {
    ns.push(goals[i])
    i = i + 1
  }
  ns
}

///|
fn prep1(g : Term, rest : Array[Term]) -> Array[Term] {
  let ns : Array[Term] = []
  ns.push(g)
  for x in rest {
    ns.push(x)
  }
  ns
}

///|
fn prep2(a : Term, b : Term, rest : Array[Term]) -> Array[Term] {
  let ns : Array[Term] = []
  ns.push(a)
  ns.push(b)
  for x in rest {
    ns.push(x)
  }
  ns
}

///|
fn cont_search(
  ctx : Ctx,
  goals : Array[Term],
  idx : Int32,
  subst : Array[Term?],
  marker : Int32,
  bdy : Int32,
  outer : Int32,
  cont : (Array[Term?]) -> Unit,
) -> Unit {
  search(ctx, goals, idx + 1, subst, marker, bdy, outer, cont)
}

///|
/// The main loop. `marker` is the cut marker for goals in the "body part"
/// (positions < bdy) of the current list; `outer` is the marker for the
/// "rest part" (positions >= bdy), which belongs to the caller.
fn search(
  ctx : Ctx,
  goals : Array[Term],
  idx : Int32,
  subst : Array[Term?],
  marker : Int32,
  bdy : Int32,
  outer : Int32,
  cont : (Array[Term?]) -> Unit,
) -> Unit {
  if ctx.stop[0] {
    return
  }
  if idx >= goals.length() {
    cont(subst)
    return
  }
  match deref(subst, goals[idx]) {
    Atom("true") => search(ctx, goals, idx + 1, subst, marker, bdy, outer, cont)
    Atom("fail") => ()
    Atom("halt") => {
      ctx.halting = true
      ctx.stop[0] = true
    }
    Atom(a) =>
      call_user(ctx, a, [], goals, idx, subst, marker, bdy, outer, cont)
    Compound(f, args) =>
      handle_compound(ctx, f, args, goals, idx, subst, marker, bdy, outer, cont)
    _ => ()
  }
}

///|
fn handle_compound(
  ctx : Ctx,
  f : String,
  args : Array[Term],
  goals : Array[Term],
  idx : Int32,
  subst : Array[Term?],
  marker : Int32,
  bdy : Int32,
  outer : Int32,
  cont : (Array[Term?]) -> Unit,
) -> Unit {
  if f == "," && args.length() == 2 {
    let nbdy = if idx < bdy { bdy - idx + 2 } else { 0 }
    search(
      ctx,
      prep2(args[0], args[1], rest_of(goals, idx + 1)),
      0,
      subst,
      marker,
      nbdy,
      outer,
      cont,
    )
    return
  }
  if f == ";" && args.length() == 2 {
    let nbdy = if idx < bdy { bdy - idx + 1 } else { 0 }
    let fcell = [false]
    ctx.choice_stack.push(fcell)
    search(
      ctx,
      prep1(args[0], rest_of(goals, idx + 1)),
      0,
      subst,
      marker,
      nbdy,
      outer,
      cont,
    )
    if !ctx.stop[0] && !fcell[0] {
      search(
        ctx,
        prep1(args[1], rest_of(goals, idx + 1)),
        0,
        subst,
        marker,
        nbdy,
        outer,
        cont,
      )
    }
    ignore(ctx.choice_stack.pop())
    return
  }
  if f == "!" && args.length() == 0 {
    if idx < bdy {
      cut_through(ctx, marker)
    } else {
      cut_through(ctx, outer)
    }
    cont_search(ctx, goals, idx, subst, marker, bdy, outer, cont)
    return
  }
  if f == "\\+" && args.length() == 1 {
    let om = if idx < bdy { marker } else { outer }
    let cnt = [0]
    let inner = fn(_s : Array[Term?]) -> Unit { cnt[0] = cnt[0] + 1 }
    search(ctx, [args[0]], 0, subst, om, 1, om, inner)
    if cnt[0] == 0 {
      cont_search(ctx, goals, idx, subst, marker, bdy, outer, cont)
    }
    return
  }
  if f == "call" && args.length() == 1 {
    let nbdy = if idx < bdy { bdy - idx + 1 } else { 0 }
    search(
      ctx,
      prep1(args[0], rest_of(goals, idx + 1)),
      0,
      subst,
      marker,
      nbdy,
      outer,
      cont,
    )
    return
  }
  if f == "=" && args.length() == 2 {
    match unify(args[0], args[1], subst) {
      Some(s) => cont_search(ctx, goals, idx, s, marker, bdy, outer, cont)
      None => ()
    }
    return
  }
  if f == "\\=" && args.length() == 2 {
    if unify(args[0], args[1], subst) is None {
      cont_search(ctx, goals, idx, subst, marker, bdy, outer, cont)
    }
    return
  }
  if f == "==" && args.length() == 2 {
    if term_equal(subst, args[0], args[1]) {
      cont_search(ctx, goals, idx, subst, marker, bdy, outer, cont)
    }
    return
  }
  if f == "\\==" && args.length() == 2 {
    if !term_equal(subst, args[0], args[1]) {
      cont_search(ctx, goals, idx, subst, marker, bdy, outer, cont)
    }
    return
  }
  if f == "is" && args.length() == 2 {
    match eval(subst, args[1]) {
      Some(n) =>
        match unify(args[0], Num(n), subst) {
          Some(s) => cont_search(ctx, goals, idx, s, marker, bdy, outer, cont)
          None => ()
        }
      None => ()
    }
    return
  }
  if (
      f == "=:=" ||
      f == "=\\=" ||
      f == "<" ||
      f == ">" ||
      f == "=<" ||
      f == ">="
    ) &&
    args.length() == 2 {
    match eval2(subst, args[0], args[1]) {
      Some((x, y)) => {
        let ok = if f == "=:=" {
          x == y
        } else if f == "=\\=" {
          x != y
        } else if f == "<" {
          x < y
        } else if f == ">" {
          x > y
        } else if f == "=<" {
          x <= y
        } else {
          x >= y
        }
        if ok {
          cont_search(ctx, goals, idx, subst, marker, bdy, outer, cont)
        }
      }
      _ => ()
    }
    return
  }
  if f == "write" && args.length() == 1 {
    ctx.output = ctx.output + write_term(subst, args[0])
    cont_search(ctx, goals, idx, subst, marker, bdy, outer, cont)
    return
  }
  if f == "writeln" && args.length() == 1 {
    ctx.output = ctx.output + write_term(subst, args[0])
    ctx.output = ctx.output + "\n"
    cont_search(ctx, goals, idx, subst, marker, bdy, outer, cont)
    return
  }
  if f == "nl" && args.length() == 0 {
    ctx.output = ctx.output + "\n"
    cont_search(ctx, goals, idx, subst, marker, bdy, outer, cont)
    return
  }
  if f == "var" && args.length() == 1 {
    match deref(subst, args[0]) {
      Var(_) => cont_search(ctx, goals, idx, subst, marker, bdy, outer, cont)
      _ => ()
    }
    return
  }
  if f == "nonvar" && args.length() == 1 {
    match deref(subst, args[0]) {
      Var(_) => ()
      _ => cont_search(ctx, goals, idx, subst, marker, bdy, outer, cont)
    }
    return
  }
  if f == "atom" && args.length() == 1 {
    match deref(subst, args[0]) {
      Atom(_) => cont_search(ctx, goals, idx, subst, marker, bdy, outer, cont)
      _ => ()
    }
    return
  }
  if (f == "number" || f == "integer") && args.length() == 1 {
    match deref(subst, args[0]) {
      Num(_) => cont_search(ctx, goals, idx, subst, marker, bdy, outer, cont)
      _ => ()
    }
    return
  }
  if f == "atomic" && args.length() == 1 {
    match deref(subst, args[0]) {
      Atom(_) => cont_search(ctx, goals, idx, subst, marker, bdy, outer, cont)
      Num(_) => cont_search(ctx, goals, idx, subst, marker, bdy, outer, cont)
      Str(_) => cont_search(ctx, goals, idx, subst, marker, bdy, outer, cont)
      _ => ()
    }
    return
  }
  if f == "compound" && args.length() == 1 {
    match deref(subst, args[0]) {
      Compound(_, _) =>
        cont_search(ctx, goals, idx, subst, marker, bdy, outer, cont)
      _ => ()
    }
    return
  }
  if f == "between" && args.length() == 3 {
    match eval2(subst, args[0], args[1]) {
      Some((lo, hi)) => {
        let fcell = [false]
        ctx.choice_stack.push(fcell)
        let mut i = lo
        while i <= hi {
          if ctx.stop[0] || fcell[0] {
            break
          }
          match unify(args[2], Num(i), subst) {
            Some(s) => cont_search(ctx, goals, idx, s, marker, bdy, outer, cont)
            None => ()
          }
          i = i + 1
          continue
        }
        ignore(ctx.choice_stack.pop())
      }
      _ => ()
    }
    return
  }
  if f == "repeat" && args.length() == 0 {
    let fcell = [false]
    ctx.choice_stack.push(fcell)
    cont_search(ctx, goals, idx, subst, marker, bdy, outer, cont)
    if !ctx.stop[0] && !fcell[0] {
      search(ctx, goals, idx, subst, marker, bdy, outer, cont)
    }
    ignore(ctx.choice_stack.pop())
    return
  }
  if f == "findall" && args.length() == 3 {
    let acc : Array[Term] = []
    let om = if idx < bdy { marker } else { outer }
    let inner = fn(s : Array[Term?]) -> Unit {
      acc.push(copy_term(ctx, s, args[0]))
    }
    search(ctx, [args[1]], 0, subst, om, 1, om, inner)
    match unify(args[2], build_list(acc), subst) {
      Some(s) => cont_search(ctx, goals, idx, s, marker, bdy, outer, cont)
      None => ()
    }
    return
  }
  if (f == "assert" || f == "assertz") && args.length() == 1 {
    ctx.clauses.push(term_to_clause(args[0]))
    cont_search(ctx, goals, idx, subst, marker, bdy, outer, cont)
    return
  }
  if f == "length" && args.length() == 2 {
    length_builtin(ctx, args, goals, idx, subst, marker, bdy, outer, cont)
    return
  }
  call_user(ctx, f, args, goals, idx, subst, marker, bdy, outer, cont)
}

///|
/// Resolve a call to a user-defined predicate (arity 0 calls arrive here
/// from `search` with `args = []`).
fn call_user(
  ctx : Ctx,
  f : String,
  args : Array[Term],
  goals : Array[Term],
  idx : Int32,
  subst : Array[Term?],
  marker : Int32,
  bdy : Int32,
  outer : Int32,
  cont : (Array[Term?]) -> Unit,
) -> Unit {
  let candidates : Array[Clause] = []
  for c in ctx.clauses {
    match c.head {
      Compound(hf, hargs) =>
        if hf == f && hargs.length() == args.length() {
          candidates.push(c)
        }
      Atom(ha) => if ha == f && args.length() == 0 { candidates.push(c) }
      _ => ()
    }
  }
  if candidates.length() == 0 {
    return
  }
  // The marker for goals in the caller's rest part.
  let om = if idx < bdy { marker } else { outer }
  let fcell = [false]
  ctx.choice_stack.push(fcell)
  let fmarker = ctx.choice_stack.length() - 1
  let g = if args.length() == 0 { Atom(f) } else { Compound(f, args) }
  for c in candidates {
    if ctx.stop[0] || fcell[0] {
      break
    }
    let c2 = rename_clause(ctx, c)
    match unify(c2.head, g, subst) {
      None => ()
      Some(s) => {
        let ns : Array[Term] = []
        for b in c2.body {
          ns.push(b)
        }
        for r in rest_of(goals, idx + 1) {
          ns.push(r)
        }
        search(ctx, ns, 0, s, fmarker, c2.body.length(), om, cont)
      }
    }
  }
  ignore(ctx.choice_stack.pop())
}

///|
/// Seed a few classic library predicates, parsed like any user input.
/// (`length/2` is a builtin so it works in both directions.)
fn seed(ctx : Ctx) -> Unit {
  let lib = [
    "member(X, [X|_]).", "member(X, [_|T]) :- member(X, T).", "append([], L, L).",
    "append([H|T], L, [H|R]) :- append(T, L, R).", "reverse([], []).", "reverse([H|T], R) :- reverse(T, RT), append(RT, [H], R).",
  ]
  for s in lib {
    match parse_statement(ctx, s) {
      Some(StClause(c)) => ctx.clauses.push(c)
      _ => ()
    }
  }
}

///|
/// Build the list term [_G, _G, ..., _G] with `n` fresh variables.
fn var_list(ctx : Ctx, n : Int32) -> Term {
  let mut t = Atom("[]")
  let mut i = 0
  while i < n {
    t = Compound(".", [Var(fresh_var(ctx)), t])
    i = i + 1
  }
  t
}

///|
/// `length/2` builtin: works with the list, the length, or both given
/// (with both unbound it generates 0, 1, 2, ... like real Prolog).
fn length_builtin(
  ctx : Ctx,
  args : Array[Term],
  goals : Array[Term],
  idx : Int32,
  subst : Array[Term?],
  marker : Int32,
  bdy : Int32,
  outer : Int32,
  cont : (Array[Term?]) -> Unit,
) -> Unit {
  let a = deref(subst, args[0])
  let b = deref(subst, args[1])
  match (a, b) {
    (Atom("[]"), _) =>
      match unify(args[1], Num(0), subst) {
        Some(s) => cont_search(ctx, goals, idx, s, marker, bdy, outer, cont)
        None => ()
      }
    (Compound(".", cons), Num(n)) =>
      // List non-empty and length given: peel one element.
      if n > 0 {
        let ns : Array[Term] = []
        ns.push(Compound("length", [cons[1], Num(n - 1)]))
        for r in rest_of(goals, idx + 1) {
          ns.push(r)
        }
        search(ctx, ns, 0, subst, marker, bdy, outer, cont)
      }
    (Compound(".", cons), Var(_)) => {
      // Count up: length(T, M), N is M + 1. Terminates (the list is finite).
      let mv = fresh_var(ctx)
      let ns : Array[Term] = []
      ns.push(Compound("length", [cons[1], Var(mv)]))
      ns.push(Compound("is", [args[1], Compound("+", [Var(mv), Num(1)])]))
      for r in rest_of(goals, idx + 1) {
        ns.push(r)
      }
      search(ctx, ns, 0, subst, marker, bdy, outer, cont)
    }
    (Var(_), Num(n)) =>
      // List unbound, length given: build a list of n fresh variables.
      if n >= 0 {
        match unify(args[0], var_list(ctx, n), subst) {
          Some(s) => cont_search(ctx, goals, idx, s, marker, bdy, outer, cont)
          None => ()
        }
      }
    (Var(_), Var(_)) => {
      // Both unbound: generate [], [_], [_, _], ...
      let fcell = [false]
      ctx.choice_stack.push(fcell)
      let mut i = 0
      while true {
        if ctx.stop[0] || fcell[0] {
          break
        }
        match unify(args[0], var_list(ctx, i), subst) {
          Some(s1) =>
            match unify(args[1], Num(i), s1) {
              Some(s2) =>
                cont_search(ctx, goals, idx, s2, marker, bdy, outer, cont)
              None => ()
            }
          None => ()
        }
        i = i + 1
        continue
      }
      ignore(ctx.choice_stack.pop())
    }
    _ => ()
  }
}
