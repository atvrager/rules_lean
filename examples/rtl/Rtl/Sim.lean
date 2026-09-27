import Rtl.Netlist

/-!
A one-instruction-per-cycle machine, the shape of a small CPU: a register file,
a program counter, and a step function.
-/

namespace Rtl

/-- Machine state. `regs` is the register file, 32 registers of one word. -/
structure Machine where
  regs : List Word
  pc : Nat
  deriving Repr

namespace Machine

/-- A machine with 32 zero registers and the program counter at zero. -/
def init : Machine := { regs := List.replicate 32 ⟨0, byte⟩, pc := 0 }

/-- Read a register. An index outside the file reads as zero. -/
def reg (m : Machine) (i : Nat) : Word := m.regs[i]?.getD ⟨0, byte⟩

/-- Write a register. An index outside the file leaves the state alone. -/
def setReg (m : Machine) (i : Nat) (v : Word) : Machine :=
  if i < m.regs.length then { m with regs := m.regs.set i v } else m

/-- One cycle. The instruction is the word the program counter points at. -/
def step (m : Machine) (program : List Word) : Machine :=
  match program[m.pc]? with
  | none => m
  | some instr => { m with pc := m.pc + 1, regs := (m.setReg 0 instr).regs }

end Machine

/-- Run `cycles` cycles. Stops early when the program ends. -/
def Machine.run (m : Machine) (program : List Word) : Nat → Machine
  | 0 => m
  | n + 1 =>
    if m.pc ≥ program.length then m else Machine.run (m.step program) program n

end Rtl
