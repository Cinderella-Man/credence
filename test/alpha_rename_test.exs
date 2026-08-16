defmodule Credence.AlphaRenameTest do
  @moduledoc """
  Rule Standard requirement 7 — the generality bar (docs/12 **C12**(a)).

  A rule must fire on the *construct*, not on the variable names in the snippet
  it was generated from. Over-fitting was the dominant defect signature in the
  auto-generated bursts, and a name-keyed matcher is invisible to every ordinary
  test: the author wrote the fixtures too, so they agree by construction. The
  rule then never fires on real code and costs a slot in the hot loop forever.

  Renaming a rule's own fixture is the cheapest way to ask, and it is the same
  move as the self-corruption oracle — *find an input the author did not
  choose* — pointed at naming instead of byte scope.

  **The result is zero, and that is a finding rather than a formality.** No
  Pattern rule in the tree is keyed to a variable name. docs/12 C12 named three
  rules as over-fit (`prefer_map_intersect_over_mapset_intersection`,
  `prefer_lookup_for_digit_conversion`,
  `prefer_string_slice_for_trim_last_char`) and all three pass this bar: they
  are over-fit in **shape** — a hard-coded pipeline, a byte-exact 16-clause hex
  table — which is a real problem and a different one. Requirement 7 asks about
  names, and names are clean. The shape half is C12(c), still open.
  """
  use ExUnit.Case, async: true

  alias Credence.AlphaRename

  # EMPTY, and it starts empty. The controls below therefore carry the whole
  # weight of proving the gate works — which is the T3.10a lesson applied at
  # construction rather than retrofitted when a ledger finally empties.
  @ledger []

  describe "no Pattern rule is keyed to variable names" do
    test "the ledger only grows by argument" do
      offenders = AlphaRename.offenders() |> Enum.map(&elem(&1, 0))

      assert offenders -- @ledger == [],
             """
             These rules fire on a fixture and stop firing once its variables are
             consistently renamed, so the matcher is keyed to a NAME rather than
             to the construct (docs/12 C12, Rule Standard requirement 7):

               #{Enum.map_join(offenders -- @ledger, "\n  ", &inspect/1)}

             Generalise the matcher to the idiom. A rule that legitimately keys
             on names — one *about* naming — belongs on @ledger with a reason.
             """
    end
  end

  describe "the renamer itself" do
    test "renames variables consistently, in order of first appearance" do
      assert AlphaRename.rename("Enum.map(list, fn item -> item * 2 end)") ==
               {:ok, "Enum.map(v1, fn v2 -> v2 * 2 end)"}
    end

    test "keeps the leading underscore, because it carries meaning" do
      assert AlphaRename.rename("def f(_unused, x), do: x") == {:ok, "def f(_v1, v2), do: v2"}
    end

    # Both of these produced false accusations before they were excluded: an
    # attribute REFERENCE and a zero-arity definition name both parse as
    # `{name, meta, nil}` — the exact shape of a variable.
    test "does not rename a module attribute reference" do
      {:ok, out} =
        AlphaRename.rename("""
        defmodule M do
          @re ~r/^[a-z]+$/
          def f(x), do: @re =~ x
        end
        """)

      assert out =~ "@re =~ v1"
    end

    test "does not rename the name in a definition head, but does rename its args" do
      {:ok, out} = AlphaRename.rename("defmodule M do\n  defp get_items?(acc), do: [acc]\nend\n")

      assert out =~ "defp get_items?(v1)"
      assert out =~ "[v1]"
    end

    test "a definition whose only variable-shaped token IS its name is unchanged" do
      assert AlphaRename.rename("defmodule M do\n  defp get_items?, do: [1]\nend\n") == :unchanged
    end

    test "source with no variables reports :unchanged, not a false pass" do
      assert AlphaRename.rename("IO.puts(\"hi\")") == :unchanged
    end

    test "unparseable source reports :error" do
      assert AlphaRename.rename("def f(") == :error
    end
  end

  describe "the machinery is provable with the ledger empty" do
    defp scan(rules), do: AlphaRename.offenders(rules, fn _ -> [AlphaProbe.fixture()] end)

    test "a rule keyed to a variable NAME is caught" do
      assert [{AlphaProbe.NameKeyed, [_]}] = scan([AlphaProbe.NameKeyed])
    end

    test "a rule keyed to the CONSTRUCT is not" do
      assert scan([AlphaProbe.ConstructKeyed]) == []
    end

    test "a rule that never fires at all is not reported as name-keyed" do
      assert scan([AlphaProbe.Silent]) == []
    end

    test "a raising rule is skipped rather than counted" do
      assert scan([AlphaProbe.Raiser]) == []
    end
  end
end

# Fabricated rules for the controls — deliberately not `use
# Credence.Pattern.Rule`, so `discover_rules/1` can never pick them up. The
# scanner only ever calls `check/2`.
defmodule AlphaProbe do
  def fixture, do: "Enum.map(items, fn item -> item * 2 end)\n"
end

defmodule AlphaProbe.NameKeyed do
  # Keys on the variable being called `items` — survives its own fixture, dies
  # on any real code that calls it anything else.
  def check(ast, _opts) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        {:items, _, ctx} = node, _ when is_atom(ctx) -> {node, true}
        node, acc -> {node, acc}
      end)

    if found, do: [%Credence.Issue{rule: :probe, message: "m", meta: %{line: 1}}], else: []
  end
end

defmodule AlphaProbe.ConstructKeyed do
  # Keys on `Enum.map/2` — indifferent to what the arguments are called.
  def check(ast, _opts) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        {{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _, _} = node, _ -> {node, true}
        node, acc -> {node, acc}
      end)

    if found, do: [%Credence.Issue{rule: :probe, message: "m", meta: %{line: 1}}], else: []
  end
end

defmodule AlphaProbe.Silent do
  def check(_ast, _opts), do: []
end

defmodule AlphaProbe.Raiser do
  def check(_ast, _opts), do: raise("probe")
end
