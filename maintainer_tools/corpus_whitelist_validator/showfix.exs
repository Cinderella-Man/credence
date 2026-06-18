# showfix.exs — print the REAL before/after of a single rule's fix on a corpus
# file, so a validator can judge whether the fix is intended or broken.
#
# Usage:
#   mix run maintainer_tools/corpus_whitelist_validator/showfix.exs <rule> <corpus-relative-path> [line]
#
# Read-only: it never writes to the corpus or the repo.
[rule, rel | rest] = System.argv()

line =
  case rest do
    [l | _] -> String.to_integer(l)
    _ -> nil
  end

path = Path.join(Credence.Corpus.root(), rel)
src = File.read!(path)
module = Credence.RuleName.derive(to_string(rule), :pattern).rule_module

fixed =
  try do
    Credence.RuleHelpers.apply_rule_fix(module, src)
  rescue
    e ->
      IO.puts("!! fix raised: #{Exception.message(e)}")
      src
  end

IO.puts("=== #{rel}:#{line}  #{rule} ===")

if fixed == src do
  IO.puts("\n[NO CHANGE] fix is a no-op or self-reverted (check-only here).")
else
  if line do
    o = String.split(src, "\n")
    lo = max(line - 4, 1)
    hi = min(line + 6, length(o))
    IO.puts("\n--- ORIGINAL (context) ---")
    Enum.each(lo..hi, fn i ->
      IO.puts(String.pad_leading("#{i}", 5) <> "| " <> Enum.at(o, i - 1, ""))
    end)
  end

  IO.puts("\n--- DIFF (unified) ---")
  ta = Path.join(System.tmp_dir!(), "cwv_showfix_a.ex")
  tb = Path.join(System.tmp_dir!(), "cwv_showfix_b.ex")
  File.write!(ta, src)
  File.write!(tb, fixed)
  {out, _} = System.cmd("diff", ["-U2", ta, tb], stderr_to_stdout: true)
  IO.puts(out)
end
