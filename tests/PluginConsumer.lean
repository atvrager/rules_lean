import Plugin

def main : IO Unit := do
  if pluginSecretNumber == 42 then
    IO.println "Plugin loaded successfully."
  else
    throw (IO.userError "Plugin verification failed")
