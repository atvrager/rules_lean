import Generated.FromRule

def main : IO Unit :=
  if fromRule == 42 then IO.println "generated ok" else IO.println "generated wrong"
