## lib/syntax/close_unclosed_brace.ex — 2026-08-18 (added, rule_syntax)
- concern: lib/syntax/close_unclosed_brace.ex:160 — the "result must parse" guard only refuses an ambiguous `}` placement when the alternative placement would make the appended candidate unparseable; when the line after the unclosed literal begins with a binary operator both placements parse and mean different things, and the rule silently commits one. On `x = {1, 2` followed by a line `|> IO.inspect()` before `end`, the rule emits `x = {1, 2\n|> IO.inspect()}` — the tuple `{1, IO.inspect(2)}` — where the author plausibly meant `x = {1, 2}` piped into `IO.inspect`, i.e. `IO.inspect({1, 2})`. The output parses and compiles, so neither ProgressGuard nor the all-or-nothing commit can catch a wrong choice, and no test in the battery covers an operator-continuation line (the "ambiguous placement" tests only cover the case where the wrong placement fails to parse). The moduledoc (lines 35–44) says the rule "stays silent rather than picking a placement" for either-line ambiguities, which overstates the guard. The tokenizer-faithful placement is a defensible documented policy, but a human should decide whether to also refuse (or at least pin with a test) when the following line starts with an operator, since that is exactly the shape where the LLM's dropped `}` belongs one line up.
- experiment: settles the concern above — run the rule on the operator-continuation fixture and inspect which placement it commits: mix run -e 'IO.puts Credence.Syntax.CloseUnclosedBrace.fix("defmodule Example do\n  def foo do\n    x = {1, 2\n    |> IO.inspect()\n  end\nend\n")'

  - **Experiment executed 2026-08-18 (by the orchestrator, memory-capped):
    confirmed.** The rule emits `x = {1, 2\n    |> IO.inspect()}` — the tuple
    `{1, IO.inspect(2)}` — on the operator-continuation input above. Both
    placements parse; the rule silently commits the tokenizer-faithful one,
    and no test pins this shape.

