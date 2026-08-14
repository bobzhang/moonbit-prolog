/// Interactive native REPL for `bobzhang/prolog`.
///
/// On a TTY, after each answer you are asked for `;` (next solution) —
/// any other input stops. Piped input prints all solutions automatically.
/// Uses libc `getchar`/`putchar` directly, so this module is native-only.

extern "c" fn getchar() -> Int = "getchar"

extern "c" fn putchar(c : Int) -> Int = "putchar"

extern "c" fn fflush(stream : Int) -> Int = "fflush"

extern "c" fn isatty(fd : Int) -> Int = "isatty"

/// Write a string without a trailing newline.
fn print_s(s : String) -> Unit {
  let mut i = 0
  while i < s.length() {
    ignore(putchar(s[i].to_int()))
    i = i + 1
  }
}

fn flush() -> Unit {
  ignore(fflush(0))
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

/// Flush the text captured by `write/1` & friends to stdout (exact, no
/// extra newline).
fn flush_output(ctx : @lib.Ctx) -> Unit {
  let out = ctx.take_output()
  if out.length() > 0 {
    print_s(out)
  }
}

fn main {
  let ctx = @lib.Ctx::new()
  let interactive = isatty(0) != 0
  let mut buf = ""
  while true {
    if interactive {
      print_s("prolog> ")
      flush()
    }
    let line = read_line()
    match line {
      None => {
        flush_output(ctx)
        print_s("\n")
        return
      }
      Some(l) => buf = buf + l
    }
    let stripped = @lib.strip_comments(buf)
    let t = @lib.trim(stripped)
    if t.length() == 0 {
      buf = ""
      continue
    }
    if t[t.length() - 1].to_int() == 46 {
      let on_solution = fn(s : Array[Option[@lib.Term]], qvars : Array[(String, Int)]) -> Bool {
        flush_output(ctx)
        print_s("\n")
        if qvars.length() == 0 {
          println("true.")
          false
        } else {
          for pair in qvars {
            let (name, id) = pair
            println("\{name} = \{@lib.pretty(s, @lib.Var(id))}")
          }
          if interactive {
            print_s(" ;")
            flush()
            match read_line() {
              None => false
              Some(a) => @lib.trim(a) == ";"
            }
          } else {
            true
          }
        }
      }
      let r = ctx.submit(t, on_solution)
      flush_output(ctx)
      match r {
        Fact => ()
        Halt => return
        SyntaxError => println("Syntax error")
        Query(_, stopped) => if !stopped { print_s("\n"); println("false.") }
      }
      buf = ""
    }
    continue
  }
}
