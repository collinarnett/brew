{ writeShellApplication, hell, duckdb, findutils }:

# Couples the recap-triage Hell script with its runtime dependencies.
# The skill invokes `recap-triage` by name; all of hell, duckdb, and find
# are reachable on PATH inside the wrapper.
writeShellApplication {
  name = "recap-triage";
  runtimeInputs = [ hell duckdb findutils ];
  text = ''exec hell ${./recap-triage.hell} "$@"'';
}
