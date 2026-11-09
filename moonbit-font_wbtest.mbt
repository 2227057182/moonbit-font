///|
test "wrap16 keeps idDelta inside the 16-bit range" {
  inspect(wrap16(0), content="0")
  inspect(wrap16(1234), content="1234")
  inspect(wrap16(-1), content="65535")
  inspect(wrap16(-300), content="65236")
  inspect(wrap16(70000), content="4464")
}

///|
test "floor_of rounds toward negative infinity, not toward zero" {
  inspect(floor_of(3.7), content="3")
  inspect(floor_of(3.0), content="3")
  inspect(floor_of(-3.2), content="-4")
  inspect(floor_of(-4.0), content="-4")
  inspect(floor_of(0.0), content="0")
}

///|
test "flatten_quad emits a single point when the control point is on the chord" {
  let xs : Array[Double] = []
  let ys : Array[Double] = []
  flatten_quad(0.0, 0.0, 5.0, 5.0, 10.0, 10.0, xs, ys)
  inspect(xs.length(), content="1")
  inspect(xs[0] == 10.0, content="true")
  inspect(ys[0] == 10.0, content="true")
}

///|
test "flatten_quad subdivides a curved segment and stays inside its hull" {
  let xs : Array[Double] = []
  let ys : Array[Double] = []
  flatten_quad(0.0, 0.0, 50.0, 100.0, 100.0, 0.0, xs, ys)
  inspect(xs.length() > 2, content="true")
  inspect(xs[xs.length() - 1] == 100.0, content="true")
  inspect(ys[ys.length() - 1] == 0.0, content="true")
  let mid_y = ys[ys.length() / 2]
  // The curve bulges upward but never reaches the control point height.
  inspect(mid_y > 0.0 && mid_y < 100.0, content="true")
}
