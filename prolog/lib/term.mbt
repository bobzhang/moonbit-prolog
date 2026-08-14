/// Prolog terms.
///
/// Variables are represented by unique integer ids (assigned by the parser
/// and by clause renaming). Atoms, integers and strings are atomic
/// constants; `Compound(f, args)` is a structure with functor `f`.
pub(all) enum Term {
  Var(Int)
  Atom(String)
  Num(Int)
  Str(String)
  Compound(String, Array[Term])
}

/// Substitutions map variable ids to terms. Index `v` holds the binding of
/// variable `v`; `None` (or an index beyond the array) means unbound.
/// Substitutions are persistent: `bind` returns a modified copy.

/// Follow the binding chain of `t` and return its head.
pub fn deref(subst : Array[Option[Term]], t : Term) -> Term {
  match t {
    Var(v) => {
      if v < subst.length() {
        match subst[v] {
          Some(b) => deref(subst, b)
          None => t
        }
      } else {
        t
      }
    }
    _ => t
  }
}

/// Occurs check: does variable `v` appear inside `t`?
fn occurs(subst : Array[Option[Term]], v : Int, t : Term) -> Bool {
  match deref(subst, t) {
    Var(w) => w == v
    Compound(_, args) => occurs_args(subst, v, args, 0)
    _ => false
  }
}

fn occurs_args(subst : Array[Option[Term]], v : Int, args : Array[Term], i : Int) -> Bool {
  if i >= args.length() {
    false
  } else if occurs(subst, v, args[i]) {
    true
  } else {
    occurs_args(subst, v, args, i + 1)
  }
}

/// Bind `v` to `t` in a fresh copy of the substitution (copy-on-write, so
/// backtracking is just using the old substitution). Fails on occurs check.
fn bind(subst : Array[Option[Term]], v : Int, t : Term) -> Option[Array[Option[Term]]] {
  if occurs(subst, v, t) {
    None
  } else {
    let s : Array[Option[Term]] = []
    for x in subst {
      s.push(x)
    }
    while s.length() <= v {
      s.push(None)
    }
    s[v] = Some(t)
    Some(s)
  }
}

/// First-order unification with occurs check.
/// Returns the extended substitution, or `None` on failure.
pub fn unify(a : Term, b : Term, subst : Array[Option[Term]]) -> Option[Array[Option[Term]]] {
  let a2 = deref(subst, a)
  let b2 = deref(subst, b)
  match (a2, b2) {
    (Var(x), Var(y)) => if x == y { Some(subst) } else { bind(subst, x, b2) }
    (Var(x), _) => bind(subst, x, b2)
    (_, Var(y)) => bind(subst, y, a2)
    (Atom(s1), Atom(s2)) => if s1 == s2 { Some(subst) } else { None }
    (Num(n1), Num(n2)) => if n1 == n2 { Some(subst) } else { None }
    (Str(s1), Str(s2)) => if s1 == s2 { Some(subst) } else { None }
    (Compound(f1, a1), Compound(f2, a2)) => {
      if f1 == f2 && a1.length() == a2.length() {
        unify_args(a1, a2, subst, 0)
      } else {
        None
      }
    }
    _ => None
  }
}

fn unify_args(a1 : Array[Term], a2 : Array[Term], subst : Array[Option[Term]], i : Int) -> Option[Array[Option[Term]]] {
  if i >= a1.length() {
    Some(subst)
  } else {
    match unify(a1[i], a2[i], subst) {
      None => None
      Some(s) => unify_args(a1, a2, s, i + 1)
    }
  }
}

/// Structural equality for `==/2`: variables compare positionally
/// (an unbound variable equals any other unbound variable), so this is
/// variant equality rather than ISO identity comparison.
pub fn term_equal(subst : Array[Option[Term]], a : Term, b : Term) -> Bool {
  let a2 = deref(subst, a)
  let b2 = deref(subst, b)
  match (a2, b2) {
    (Var(_), Var(_)) => true
    (Atom(s1), Atom(s2)) => s1 == s2
    (Num(n1), Num(n2)) => n1 == n2
    (Str(s1), Str(s2)) => s1 == s2
    (Compound(f1, a1), Compound(f2, a2)) => {
      f1 == f2 && a1.length() == a2.length() && args_equal(subst, a1, a2, 0)
    }
    _ => false
  }
}

fn args_equal(subst : Array[Option[Term]], a1 : Array[Term], a2 : Array[Term], i : Int) -> Bool {
  if i >= a1.length() {
    true
  } else if term_equal(subst, a1[i], a2[i]) {
    args_equal(subst, a1, a2, i + 1)
  } else {
    false
  }
}

/// Evaluate an arithmetic expression to an integer (for `is/2`, `=:=/2`,
/// comparisons, `between/3`).
pub fn eval(subst : Array[Option[Term]], t : Term) -> Option[Int] {
  match deref(subst, t) {
    Num(n) => Some(n)
    Compound(f, args) => {
      if args.length() == 1 && f == "-" {
        match eval(subst, args[0]) {
          Some(n) => Some(-n)
          None => None
        }
      } else if args.length() == 2 {
        match eval2(subst, args[0], args[1]) {
          Some((x, y)) => {
            if f == "+" {
              Some(x + y)
            } else if f == "-" {
              Some(x - y)
            } else if f == "*" {
              Some(x * y)
            } else if f == "/" || f == "//" || f == "div" {
              if y == 0 { None } else { Some(x / y) }
            } else if f == "mod" {
              if y == 0 { None } else { Some(x % y) }
            } else {
              None
            }
          }
          _ => None
        }
      } else {
        None
      }
    }
    _ => None
  }
}

/// Evaluate two arithmetic expressions together (for comparisons).
pub fn eval2(subst : Array[Option[Term]], a : Term, b : Term) -> Option[(Int, Int)] {
  match (eval(subst, a), eval(subst, b)) {
    (Some(x), Some(y)) => Some((x, y))
    _ => None
  }
}

/// Pretty-print a term for answers (`writeq` style: strings quoted).
pub fn pretty(subst : Array[Option[Term]], t : Term) -> String {
  pretty_q(subst, t, true)
}

/// Print a term for `write/1` (strings unquoted).
pub fn write_term(subst : Array[Option[Term]], t : Term) -> String {
  pretty_q(subst, t, false)
}

fn pretty_q(subst : Array[Option[Term]], t : Term, quoted : Bool) -> String {
  match deref(subst, t) {
    Var(v) => "_G" + v.to_string()
    Atom(a) => a
    Num(n) => n.to_string()
    Str(s) => if quoted { "\"" + escape(s) + "\"" } else { s }
    Compound(f, args) => {
      if f == "." && args.length() == 2 {
        list_pretty(subst, args[0], args[1], quoted)
      } else if f == ":-" && args.length() == 2 {
        pretty_q(subst, args[0], quoted) + " :- " + pretty_q(subst, args[1], quoted)
      } else if f == "\\+" && args.length() == 1 {
        "\\+ " + pretty_q(subst, args[0], quoted)
      } else if f == "-" && args.length() == 1 {
        "-" + pretty_q(subst, args[0], quoted)
      } else if args.length() == 2 && is_infix(f) {
        pretty_q(subst, args[0], quoted) + " " + f + " " + pretty_q(subst, args[1], quoted)
      } else {
        f + "(" + join_args(subst, args, quoted, 0) + ")"
      }
    }
  }
}

fn is_infix(f : String) -> Bool {
  f == "=" || f == "\\=" || f == "==" || f == "\\==" || f == "=:=" || f == "=\\=" ||
    f == "is" || f == "<" || f == ">" || f == "=<" || f == ">=" || f == "+" || f == "-" ||
    f == "*" || f == "/" || f == "//" || f == "mod" || f == "," || f == ";"
}

fn join_args(subst : Array[Option[Term]], args : Array[Term], quoted : Bool, i : Int) -> String {
  if i >= args.length() {
    ""
  } else if i == args.length() - 1 {
    pretty_q(subst, args[i], quoted)
  } else {
    pretty_q(subst, args[i], quoted) + ", " + join_args(subst, args, quoted, i + 1)
  }
}

fn list_pretty(subst : Array[Option[Term]], h : Term, t : Term, quoted : Bool) -> String {
  match deref(subst, t) {
    Atom("[]") => "[" + pretty_q(subst, h, quoted) + "]"
    Compound(".", args) => "[" + pretty_q(subst, h, quoted) + ", " + list_rest(subst, args, quoted)
    _ => "[" + pretty_q(subst, h, quoted) + "|" + pretty_q(subst, t, quoted) + "]"
  }
}

fn list_rest(subst : Array[Option[Term]], args : Array[Term], quoted : Bool) -> String {
  match deref(subst, args[1]) {
    Atom("[]") => pretty_q(subst, args[0], quoted) + "]"
    Compound(".", args2) => pretty_q(subst, args[0], quoted) + ", " + list_rest(subst, args2, quoted)
    _ => pretty_q(subst, args[0], quoted) + "|" + pretty_q(subst, args[1], quoted) + "]"
  }
}

fn escape(s : String) -> String {
  let mut out = ""
  let mut i = 0
  while i < s.length() {
    let c = code_at(s, i)
    if c == 34 {
      out = out + "\\\""
    } else if c == 92 {
      out = out + "\\\\"
    } else if c == 10 {
      out = out + "\\n"
    } else if c == 9 {
      out = out + "\\t"
    } else {
      out = out + Int::unsafe_to_char(c).to_string()
    }
    i = i + 1
    continue
  }
  out
}
