/// MoonBit Prolog: a small Prolog interpreter.
///
/// Statements (facts, rules, queries) end with a period and may span
/// several lines. Type `halt.` to quit. Lines starting with `%` are
/// comments (also after a statement).
///
/// Run:  moon build --target native && ./_build/native/.../main.exe
///   or  moon run cmd/main          (with preferred_target = "native")

extern "c" fn getchar() -> Int = "getchar"

extern "c" fn putchar(c : Int) -> Int = "putchar"

extern "c" fn fflush(stream : Int) -> Int = "fflush"

extern "c" fn exit_proc(code : Int) -> Unit = "exit"

extern "c" fn isatty(fd : Int) -> Int = "isatty"

/// Write a string without a trailing newline.
fn print_s(s : String) -> Unit {
  let mut i = 0
  while i < s.length() {
    ignore(putchar(s[i].to_int()))
    i = i + 1
  }
}

/// Read one line from stdin (byte-wise; `None` at EOF).
fn read_line() -> Option[String] {
  let mut buf = ""
  while true {
    let c = getchar()
    if c == -1 {
      if buf.length() == 0 {
        return None
      }
      return Some(buf)
    }
    if c == 10 {
      return Some(buf)
    }
    if c != 13 {
      buf = buf + Int::unsafe_to_char(c).to_string()
    }
    continue
  }
  None
}

fn flush() -> Unit {
  ignore(fflush(0))
}

/// Remove `%` comments (outside of quotes) from a possibly multi-line buffer.
fn strip_comments(s : String) -> String {
  let mut out = ""
  let mut in_str = false
  let mut i = 0
  while i < s.length() {
    let c = code_at(s, i)
    if c == 34 || c == 39 {
      if i == 0 || code_at(s, i - 1) != 92 {
        in_str = !in_str
      }
      out = out + Int::unsafe_to_char(c).to_string()
      i = i + 1
      continue
    }
    if c == 37 && !in_str {
      while i < s.length() && code_at(s, i) != 10 {
        i = i + 1
      }
      continue
    }
    out = out + Int::unsafe_to_char(c).to_string()
    i = i + 1
    continue
  }
  out
}

fn handle(ctx : Ctx, st : Statement) -> Unit {
  match st {
    StClause(c) => {
      match c.head {
        Atom("halt") => {
          flush()
          exit_proc(0)
        }
        _ => ctx.clauses.push(c)
      }
    }
    StQuery(goals, vars) => run_query(ctx, goals, vars)
  }
}

fn repl(ctx : Ctx) -> Unit {
  let mut buf = ""
  while true {
    print_s("prolog> ")
    flush()
    let line = read_line()
    match line {
      None => {
        print_s("\n")
        return
      }
      Some(l) => buf = buf + l
    }
    let stripped = strip_comments(buf)
    let t = trim(stripped)
    if t.length() == 0 {
      buf = ""
      continue
    }
    if code_at(t, t.length() - 1) == 46 {
      match parse_statement(ctx, t) {
        Some(st) => handle(ctx, st)
        None => println("Syntax error")
      }
      buf = ""
    }
    continue
  }
}

fn main {
  let ctx = Ctx::{ clauses: [], choice_stack: [], next_var: 0, stop: [false], interactive: isatty(0) != 0 }
  seed(ctx)
  println("MoonBit Prolog — a Prolog interpreter written in MoonBit")
  println("Assert facts/rules, query with ?-, 'halt.' to quit.")
  repl(ctx)
}
