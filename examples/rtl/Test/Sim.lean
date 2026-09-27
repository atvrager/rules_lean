import Isa.Decode
import Codegen.Emit
import Rtl.Sim

/-!
Checks of the demo project: arithmetic wraps at the width, netlists evaluate,
the decoder reads the generated table, the emitter renders, and the machine
advances its program counter.
-/

/-- Report one check. -/
def check (name : String) (ok : Bool) : IO Bool := do
  if ok then
    IO.println s!"ok   {name}"
  else
    IO.println s!"FAIL {name}"
  return ok

def main : IO Unit := do
  let eight := Rtl.byte
  let two := Rtl.Word.ofNat eight 2
  let three := Rtl.Word.ofNat eight 3
  let twoFiveSix := Rtl.Word.ofNat eight 256

  let results ← (
    check "wrap" (twoFiveSix.value == 0) >>= fun a =>
    check "xor" ((two.lxor three).value == 1) >>= fun b =>
    check "and" ((two.land three).value == 2) >>= fun c =>
    check "netlist"
      (Rtl.Netlist.run ⟨2, [.gate .lxor (.wire 0) (.wire 1)]⟩ [two, three] ==
        [Rtl.Word.ofNat eight 1]) >>= fun d =>
    check "render" ((Rtl.render ⟨1, [.gate .land (.wire 0) (.wire 0)]⟩).contains "and") >>= fun e =>
    check "decode-addi"
      ((Isa.decode 0x00700093).map (fun i => i.name ++ "/" ++ toString i.rd) == some "addi/1") >>= fun f =>
    check "decode-unknown" ((Isa.decode 0x0000007f).isNone) >>= fun g =>
    check "decode-x0-guard" ((Isa.decode 0x00700013).isNone) >>= fun h =>
    check "pc"
      ((Rtl.Machine.run Rtl.Machine.init [Rtl.Word.ofNat eight 1] 3).pc == 1) >>= fun i =>
    pure [a, b, c, d, e, f, g, h, i])

  if results.all id then
    IO.println s!"rtl demo: {results.length} checks pass"
  else
    IO.println "rtl demo: FAILURES"
    IO.Process.exit 1
