///|
test "member enumerates all solutions" {
  let ctx = @lib.Ctx::new()
  let values : Array[String] = []
  let result = ctx.submit("?- member(X, [a, b, c]).", (subst, vars) => {
    values.push(@lib.pretty(subst, @lib.Var(vars[0].1)))
    true
  })
  assert_true(result is Query(3, _))
  assert_eq(values, ["a", "b", "c"])
}

///|
test "cut commits to the first member" {
  let ctx = @lib.Ctx::new()
  let values : Array[String] = []
  let result = ctx.submit("?- member(X, [a, b, c]), !.", (subst, vars) => {
    values.push(@lib.pretty(subst, @lib.Var(vars[0].1)))
    true
  })
  assert_true(result is Query(1, _))
  assert_eq(values, ["a"])
}

///|
test "occurs check rejects recursive substitution" {
  assert_true(
    @lib.unify(@lib.Var(0), @lib.Compound("f", [@lib.Var(0)]), [None]) is None,
  )
}
