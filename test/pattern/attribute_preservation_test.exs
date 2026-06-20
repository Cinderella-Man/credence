defmodule Credence.Pattern.AttributePreservationTest do
  @moduledoc """
  No rule's fix may MANGLE a module attribute — turning a `@some_attr` in a
  rewritten clause head into an undefined `@_some_attr`. See
  `Credence.AttributeProbe` for the method (inject `@probe_attr` into every
  rule's own firing fixtures, then check the fix never introduces an
  `@_`-prefixed attribute).

  This currently FAILS for `prefer_guard_over_if` — the only rule that rewrites
  the ORIGINAL function head, so the only one that can underscore an attribute
  sitting in it. The 116 other fixable rules either don't touch the head or
  synthesize fresh clauses, so the user's attributes are left alone. When
  `prefer_guard_over_if` is narrowed, this goes green and guards against any
  future rule introducing the same bug.
  """
  use ExUnit.Case, async: true

  alias Credence.AttributeProbe

  test "no rule's fix mangles a module attribute in code it rewrites" do
    {mangling, coverage} = AttributeProbe.run()

    IO.puts(
      "\n  [attr-probe] #{coverage.variants} attribute-injected variants across " <>
        "#{coverage.rules} rules; #{coverage.fired} fired; #{length(mangling)} mangled."
    )

    assert mangling == [], report(mangling)
  end

  defp report(mangling) do
    by_rule =
      mangling
      |> Enum.group_by(fn {rule, _, _} -> rule end)
      |> Enum.sort_by(fn {_, v} -> -length(v) end)

    body =
      Enum.map_join(by_rule, "\n\n", fn {rule, items} ->
        short = rule |> Module.split() |> List.last()
        names = items |> Enum.flat_map(fn {_, n, _} -> n end) |> Enum.uniq()
        {_, _, example} = hd(items)

        "  #{short} — #{length(items)} variant(s), introduced #{inspect(names)}\n" <>
          "  example output:\n" <>
          (example |> String.split("\n") |> Enum.map_join("\n", &("    " <> &1)))
      end)

    """
    #{length(mangling)} fix variant(s) mangled a module attribute (`@x` -> `@_x`,
    an undefined attribute that evaluates to nil and breaks the match):

    #{body}
    """
  end
end
