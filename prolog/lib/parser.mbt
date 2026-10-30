///|
/// Tokenizer and parser for a Prolog subset.
///
/// Operator precedences follow Prolog conventions (higher binds looser):
/// `:-` 1200, `;` 1100, `,` 1000, comparisons/`is` 700, `+`/`-` 500,
/// `*`/`//`/`mod` 400, unary minus 500, `\+` (prefix) 900.
/// Compound arguments and list elements are parsed at precedence 999.
///
/// Parsing errors are raised as `Failure` and turned into `None` by
/// `parse_statement`.
priv enum Token {
  TAtom(String)
  TVar(String)
  TNum(Int32)
  TStr(String)
  TPunct(String)
}

///|
fn code_at(s : String, i : Int32) -> Int32 {
  s[i].to_int()
}

///|
fn is_digit(c : Int32) -> Bool {
  c >= 48 && c <= 57
}

///|
fn is_lower(c : Int32) -> Bool {
  c >= 97 && c <= 122
}

///|
fn is_upper(c : Int32) -> Bool {
  c >= 65 && c <= 90
}

///|
fn is_ident_char(c : Int32) -> Bool {
  is_digit(c) || is_lower(c) || is_upper(c) || c == 95
}

///|
fn is_var_start(c : Int32) -> Bool {
  is_upper(c) || c == 95
}

///|
fn is_space(c : Int32) -> Bool {
  c == 32 || c == 9 || c == 10 || c == 13
}

///|
fn slice(s : String, start : Int32, end : Int32) -> String {
  let mut out = ""
  let mut i = start
  while i < end {
    out = out + Int32::unsafe_to_char(code_at(s, i)).to_string()
    i = i + 1
  }
  out
}

///|
/// Trim whitespace, returning a plain String.
pub fn trim(s : String) -> String {
  let mut start = 0
  while start < s.length() && is_space(code_at(s, start)) {
    start = start + 1
  }
  let mut end = s.length()
  while end > start && is_space(code_at(s, end - 1)) {
    end = end - 1
  }
  slice(s, start, end)
}

///|
fn tokenize(src : String) -> Array[Token] raise Failure {
  let toks : Array[Token] = []
  let mut i = 0
  while i < src.length() {
    let c = code_at(src, i)
    if is_space(c) {
      i = i + 1
      continue
    }
    if c == 37 {
      // % comment to end of line
      while i < src.length() && code_at(src, i) != 10 {
        i = i + 1
      }
      continue
    }
    if is_digit(c) {
      let mut n = 0
      while i < src.length() && is_digit(code_at(src, i)) {
        n = n * 10 + (code_at(src, i) - 48)
        i = i + 1
      }
      toks.push(TNum(n))
      continue
    }
    if is_lower(c) || is_upper(c) || c == 95 {
      let start = i
      while i < src.length() && is_ident_char(code_at(src, i)) {
        i = i + 1
      }
      let name = slice(src, start, i)
      if is_var_start(c) {
        toks.push(TVar(name))
      } else {
        toks.push(TAtom(name))
      }
      continue
    }
    if c == 34 || c == 39 {
      // "string" or 'quoted atom'
      let quote = c
      let mut s = ""
      i = i + 1
      let mut closed = false
      while i < src.length() {
        let d = code_at(src, i)
        if d == 92 && i + 1 < src.length() {
          let e = code_at(src, i + 1)
          if e == 110 {
            s = s + "\n"
          } else if e == 116 {
            s = s + "\t"
          } else if e == 92 {
            s = s + "\\"
          } else {
            s = s + Int32::unsafe_to_char(e).to_string()
          }
          i = i + 2
          continue
        }
        if d == quote {
          closed = true
          i = i + 1
          break
        }
        s = s + Int32::unsafe_to_char(d).to_string()
        i = i + 1
      }
      if !closed {
        raise Failure("unterminated string")
      }
      if quote == 34 {
        toks.push(TStr(s))
      } else {
        toks.push(TAtom(s))
      }
      continue
    }
    // Operators and punctuation.
    let c2 = if i + 1 < src.length() { code_at(src, i + 1) } else { 32 }
    let c3 = if i + 2 < src.length() { code_at(src, i + 2) } else { 32 }
    if c == 58 {
      if c2 == 45 {
        toks.push(TPunct(":-"))
        i = i + 2
      } else {
        raise Failure("unexpected ':'")
      }
      continue
    }
    if c == 92 {
      if c2 == 43 {
        toks.push(TPunct("\\+"))
        i = i + 2
      } else if c2 == 61 && c3 == 61 {
        toks.push(TPunct("\\=="))
        i = i + 3
      } else if c2 == 61 {
        toks.push(TPunct("\\="))
        i = i + 2
      } else {
        raise Failure("unexpected '\\'")
      }
      continue
    }
    if c == 61 {
      if c2 == 58 && c3 == 61 {
        toks.push(TPunct("=:="))
        i = i + 3
      } else if c2 == 92 && c3 == 61 {
        toks.push(TPunct("=\\="))
        i = i + 3
      } else if c2 == 61 {
        toks.push(TPunct("=="))
        i = i + 2
      } else if c2 == 60 {
        toks.push(TPunct("=<"))
        i = i + 2
      } else {
        toks.push(TPunct("="))
        i = i + 1
      }
      continue
    }
    if c == 62 {
      if c2 == 61 {
        toks.push(TPunct(">="))
        i = i + 2
      } else {
        toks.push(TPunct(">"))
        i = i + 1
      }
      continue
    }
    if c == 60 {
      toks.push(TPunct("<"))
      i = i + 1
      continue
    }
    if c == 43 {
      toks.push(TPunct("+"))
      i = i + 1
      continue
    }
    if c == 45 {
      toks.push(TPunct("-"))
      i = i + 1
      continue
    }
    if c == 42 {
      toks.push(TPunct("*"))
      i = i + 1
      continue
    }
    if c == 47 {
      if c2 == 47 {
        toks.push(TPunct("//"))
        i = i + 2
      } else {
        toks.push(TPunct("/"))
        i = i + 1
      }
      continue
    }
    if c == 40 {
      toks.push(TPunct("("))
      i = i + 1
      continue
    }
    if c == 41 {
      toks.push(TPunct(")"))
      i = i + 1
      continue
    }
    if c == 91 {
      toks.push(TPunct("["))
      i = i + 1
      continue
    }
    if c == 93 {
      toks.push(TPunct("]"))
      i = i + 1
      continue
    }
    if c == 123 {
      toks.push(TPunct("{"))
      i = i + 1
      continue
    }
    if c == 125 {
      toks.push(TPunct("}"))
      i = i + 1
      continue
    }
    if c == 44 {
      toks.push(TPunct(","))
      i = i + 1
      continue
    }
    if c == 59 {
      toks.push(TPunct(";"))
      i = i + 1
      continue
    }
    if c == 33 {
      toks.push(TPunct("!"))
      i = i + 1
      continue
    }
    if c == 124 {
      toks.push(TPunct("|"))
      i = i + 1
      continue
    }
    if c == 46 {
      toks.push(TPunct("."))
      i = i + 1
      continue
    }
    if c == 63 {
      if c2 == 45 {
        toks.push(TPunct("?-"))
        i = i + 2
      } else {
        raise Failure("unexpected '?'")
      }
      continue
    }
    raise Failure("unexpected character")
  }
  toks
}

///|
/// A clause: `head :- body.` (body is the flattened goal list; empty for facts).
pub struct Clause {
  head : Term
  body : Array[Term]
}

///|
pub enum Statement {
  StClause(Clause)
  StQuery(Array[Term], Array[(String, Int32)])
}

///|
priv struct Parser {
  toks : Array[Token]
  mut pos : Int32
  ctx : Ctx
  vars : Array[(String, Int32)]
}

///|
fn peek(p : Parser) -> Token? {
  if p.pos < p.toks.length() {
    Some(p.toks[p.pos])
  } else {
    None
  }
}

///|
fn next(p : Parser) -> Token? {
  if p.pos < p.toks.length() {
    let t = p.toks[p.pos]
    p.pos = p.pos + 1
    Some(t)
  } else {
    None
  }
}

///|
fn expect_punct(p : Parser, s : String) -> Unit raise Failure {
  match next(p) {
    Some(TPunct(t)) => if t == s { () } else { raise Failure("expected \{s}") }
    _ => raise Failure("expected \{s}")
  }
}

///|
fn op_prec(op : String) -> Int32 {
  if op == ":-" {
    1200
  } else if op == ";" {
    1100
  } else if op == "," {
    1000
  } else if op == "=" ||
    op == "\\=" ||
    op == "==" ||
    op == "\\==" ||
    op == "=:=" ||
    op == "=\\=" ||
    op == "is" ||
    op == "<" ||
    op == ">" ||
    op == "=<" ||
    op == ">=" {
    700
  } else if op == "+" || op == "-" {
    500
  } else if op == "*" || op == "/" || op == "//" || op == "mod" || op == "div" {
    400
  } else {
    0
  }
}

///|
fn peek_op_prec(p : Parser) -> Int32 {
  match peek(p) {
    Some(TPunct(op)) => op_prec(op)
    Some(TAtom(op)) =>
      if op == "is" || op == "mod" || op == "div" {
        op_prec(op)
      } else {
        0
      }
    _ => 0
  }
}

///|
fn consume_op(p : Parser) -> String? {
  match next(p) {
    Some(TPunct(op)) => Some(op)
    Some(TAtom(op)) =>
      if op == "is" || op == "mod" || op == "div" {
        Some(op)
      } else {
        None
      }
    _ => None
  }
}

///|
/// Get the id of variable `name` within this statement (same name = same
/// variable), allocating a fresh id otherwise. `_` is always anonymous.
/// Ids come from the global counter in `ctx` so that parser ids, clause
/// renamings and `findall` copies never collide.
fn fresh_or_lookup(p : Parser, name : String) -> Int32 {
  if name == "_" {
    let v = p.ctx.next_var
    p.ctx.next_var = v + 1
    return v
  }
  for pair in p.vars {
    let (n, id) = pair
    if n == name {
      return id
    }
  }
  let v = p.ctx.next_var
  p.ctx.next_var = v + 1
  p.vars.push((name, v))
  v
}

///|
/// Precedence-climbing expression parser: consumes operators whose
/// precedence is at most `max_prec` (higher precedence = looser binding).
fn parse_expr(p : Parser, max_prec : Int32) -> Term raise Failure {
  let tok = match next(p) {
    Some(t) => t
    None => raise Failure("unexpected end of input")
  }
  let mut lhs = parse_prefix(p, tok)
  // Functor application: an atom followed by '(' is a compound term.
  match lhs {
    Atom(f) =>
      match peek(p) {
        Some(TPunct("(")) => {
          ignore(next(p))
          lhs = Compound(f, parse_arg_list(p))
        }
        _ => ()
      }
    _ => ()
  }
  while true {
    let prec = peek_op_prec(p)
    if prec <= 0 || prec > max_prec {
      break
    }
    let op = match consume_op(p) {
      Some(o) => o
      None => raise Failure("expected operator")
    }
    let right = parse_expr(p, prec - 1)
    lhs = Compound(op, [lhs, right])
    continue
  }
  lhs
}

///|
/// Parse `t1, t2, ... , tn )` (the opening `(` is already consumed).
fn parse_arg_list(p : Parser) -> Array[Term] raise Failure {
  let args : Array[Term] = []
  while true {
    let t = parse_expr(p, 999)
    args.push(t)
    match peek(p) {
      Some(TPunct(",")) => {
        ignore(next(p))
        continue
      }
      Some(TPunct(")")) => {
        ignore(next(p))
        return args
      }
      _ => raise Failure("expected ',' or ')'")
    }
  }
  raise Failure("unreachable")
}

///|
fn parse_prefix(p : Parser, tok : Token) -> Term raise Failure {
  match tok {
    TAtom(a) => Atom(a)
    TVar(name) => Var(fresh_or_lookup(p, name))
    TNum(n) => Num(n)
    TStr(s) => Str(s)
    TPunct("(") => {
      let t = parse_expr(p, 1200)
      expect_punct(p, ")")
      t
    }
    TPunct("[") => parse_list(p)
    TPunct("{") => {
      let t = parse_expr(p, 1200)
      expect_punct(p, "}")
      Compound("{}", [t])
    }
    TPunct("-") => {
      let inner = parse_expr(p, 500)
      match inner {
        Num(n) => Num(-n)
        other => Compound("-", [other])
      }
    }
    TPunct("\\+") => {
      let inner = parse_expr(p, 899)
      Compound("\\+", [inner])
    }
    TPunct("!") => Compound("!", [])
    _ => raise Failure("syntax error")
  }
}

///|
fn parse_list(p : Parser) -> Term raise Failure {
  match peek(p) {
    Some(TPunct("]")) => {
      ignore(next(p))
      Atom("[]")
    }
    _ => {
      let h = parse_expr(p, 999)
      parse_list_tail(p, h)
    }
  }
}

///|
fn parse_list_tail(p : Parser, h : Term) -> Term raise Failure {
  match peek(p) {
    Some(TPunct(",")) => {
      ignore(next(p))
      let h2 = parse_expr(p, 999)
      let t = parse_list_tail(p, h2)
      Compound(".", [h, t])
    }
    Some(TPunct("|")) => {
      ignore(next(p))
      let t = parse_expr(p, 999)
      expect_punct(p, "]")
      Compound(".", [h, t])
    }
    Some(TPunct("]")) => {
      ignore(next(p))
      Compound(".", [h, Atom("[]")])
    }
    _ => raise Failure("expected ']'")
  }
}

///|
/// Flatten a conjunction term `,(a, ,(b, c))` into [a, b, c].
fn flatten_conj(t : Term) -> Array[Term] {
  match t {
    Compound(",", args) => {
      let out = flatten_conj(args[0])
      for g in flatten_conj(args[1]) {
        out.push(g)
      }
      out
    }
    _ => [t]
  }
}

///|
/// Convert a parsed term into a clause: `:-(H, B)` is a rule, anything else
/// is a fact. Also used by `assertz/1`.
fn term_to_clause(t : Term) -> Clause {
  match t {
    Compound(":-", args) =>
      Clause::{ head: args[0], body: flatten_conj(args[1]), }
    _ => Clause::{ head: t, body: [], }
  }
}

///|
fn collect_vars(p : Parser, goals : Array[Term]) -> Array[(String, Int32)] {
  let out : Array[(String, Int32)] = []
  for g in goals {
    collect_term(p, g, out)
  }
  out
}

///|
fn collect_term(p : Parser, t : Term, out : Array[(String, Int32)]) -> Unit {
  match t {
    Var(id) => {
      let mut found = false
      for pair in out {
        let (_, i2) = pair
        if i2 == id {
          found = true
        }
      }
      if !found {
        let mut name = "_"
        for pair in p.vars {
          let (n, i2) = pair
          if i2 == id {
            name = n
          }
        }
        if name.length() > 0 && code_at(name, 0) != 95 {
          out.push((name, id))
        }
      }
    }
    Compound(_, args) =>
      for a in args {
        collect_term(p, a, out)
      }
    _ => ()
  }
}

///|
fn parse_stmt(p : Parser) -> Statement raise Failure {
  match peek(p) {
    Some(TPunct("?-")) => {
      ignore(next(p))
      let g = parse_expr(p, 1200)
      expect_punct(p, ".")
      let goals = flatten_conj(g)
      let qvars = collect_vars(p, goals)
      StQuery(goals, qvars)
    }
    _ => {
      let t = parse_expr(p, 1200)
      expect_punct(p, ".")
      StClause(term_to_clause(t))
    }
  }
}

///|
/// Parse a complete statement (fact, rule or query) from one line of text.
/// Returns `None` on any syntax error.
pub fn parse_statement(ctx : Ctx, text : String) -> Statement? {
  try {
    let toks = tokenize(text)
    let p = Parser::{ toks, pos: 0, ctx, vars: [], }
    Some(parse_stmt(p))
  } catch {
    _ => None
  }
}

///|
/// Remove `%` comments (outside of quotes) from a possibly multi-line buffer.
pub fn strip_comments(s : String) -> String {
  let mut out = ""
  let mut in_str = false
  let mut i = 0
  while i < s.length() {
    let c = code_at(s, i)
    if c == 34 || c == 39 {
      if i == 0 || code_at(s, i - 1) != 92 {
        in_str = !in_str
      }
      out = out + Int32::unsafe_to_char(c).to_string()
      i = i + 1
      continue
    }
    if c == 37 && !in_str {
      while i < s.length() && code_at(s, i) != 10 {
        i = i + 1
      }
      continue
    }
    out = out + Int32::unsafe_to_char(c).to_string()
    i = i + 1
    continue
  }
  out
}
