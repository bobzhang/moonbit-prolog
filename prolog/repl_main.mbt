/// MoonBit Prolog — a Prolog interpreter REPL built on `moonbitlang/async`
/// stdio, so the same source runs on the wasm and native backends.
///
/// Facts, rules and queries end with `.` and may span several lines.
/// Type `halt.` to quit. When stdin is piped, every solution of each query
/// is printed automatically.
///
/// This package is the one `moonx bobzhang/prolog` executes.

///|
/// Flush the text captured by `write/1` & friends to stdout.
fn flush_output(ctx : @lib.Ctx) -> Unit {
  let out = ctx.take_output()
  if out.length() > 0 {
    // Drop trailing newlines: println adds its own.
    let mut n = out.length()
    while n > 0 && out[n - 1].to_int() == 10 {
      n = n - 1
    }
    let mut text = ""
    let mut i = 0
    while i < n {
      text = text + Int32::unsafe_to_char(out[i].to_int()).to_string()
      i = i + 1
    }
    println(text)
  }
}

///|
async fn main {
  let ctx = @lib.Ctx::new()
  let mut buf = ""
  while true {
    match @stdio.stdin.read_until("\n") {
      None => {
        flush_output(ctx)
        return
      }
      Some(line) => buf = buf + line
    }
    let stripped = @lib.strip_comments(buf)
    let t = @lib.trim(stripped)
    if t.length() == 0 {
      buf = ""
      continue
    }
    if t[t.length() - 1].to_int() == 46 {
      let on_solution = fn(
        _s : Array[@lib.Term?],
        qvars : Array[(String, Int32)],
      ) -> Bool {
        flush_output(ctx)
        println("")
        if qvars.length() == 0 {
          println("true.")
        } else {
          for pair in qvars {
            let (name, id) = pair
            println("\{name} = \{@lib.pretty(_s, @lib.Var(id))}")
          }
        }
        true
      }
      let r = ctx.submit(t, on_solution)
      flush_output(ctx)
      match r {
        Fact => ()
        Halt => return
        SyntaxError => println("Syntax error")
        Query(_, stopped) =>
          if !stopped {
            println("")
            println("false.")
          }
      }
      buf = ""
    }
    continue
  }
  ()
}
