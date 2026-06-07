defmodule Credence.MetaTestSupport do
  @moduledoc """
  Shared machinery for the per-rule test-file gates (`CheckMetaTest`,
  `FixMetaTest`). Each walks a rule's test file and asserts it is real and
  substantive — not hollow, not testing the wrong rule, not a stub.

  Test files are introspected with **Sourceror**, like everything else in this
  project (no `Code.string_to_quoted`). Because heredoc fixtures are string
  literals in the tree, code *inside* them (a `check`, a `=~`, an `Enum.count`)
  is invisible to these walks — only real test-logic nodes are seen.
  """

  @doc "Every discovered Pattern rule."
  def rules, do: Credence.RuleHelpers.discover_rules(Credence.Pattern.Rule)

  @doc "The rule's short name, e.g. `NoManualFind`."
  def short(rule), do: rule |> Module.split() |> List.last()

  @doc "Conventional path of a rule's test file for `kind` in (\"check\" | \"fix\" | ...)."
  def test_path(rule, kind), do: "test/pattern/#{Macro.underscore(short(rule))}_#{kind}_test.exs"

  @doc "Parse the file at `path` with Sourceror; `:error` if it is absent."
  def load_ast(path) do
    if File.exists?(path),
      do: {:ok, path |> File.read!() |> Sourceror.parse_string!()},
      else: :error
  end

  @doc "Does `ast` contain a bare (unqualified) call to any name in `names`?"
  def calls_any?(ast, names) do
    walk_any?(ast, fn
      {name, _, args} when is_atom(name) and is_list(args) -> name in names
      _ -> false
    end)
  end

  @doc """
  Does any module reference (`__aliases__`) end in `last_atom`? Catches both
  `alias Credence.Pattern.NoFoo` and a bare `NoFoo` use. The test module's own
  name ends in `NoFooCheckTest`/`NoFooFixTest`, so it never matches the rule atom.
  """
  def references_rule?(ast, last_atom) do
    walk_any?(ast, fn
      {:__aliases__, _, parts} when is_list(parts) -> List.last(parts) == last_atom
      _ -> false
    end)
  end

  @doc "True if `pred` holds for any node in `ast`."
  def walk_any?(ast, pred) do
    {_, found} = Macro.prewalk(ast, false, fn node, acc -> {node, acc or pred.(node)} end)
    found
  end

  @doc "Count the nodes in `ast` for which `pred` is true."
  def count_nodes(ast, pred) do
    {_, n} =
      Macro.prewalk(ast, 0, fn node, acc -> {node, if(pred.(node), do: acc + 1, else: acc)} end)

    n
  end

  @doc "Render a node back to source text (for value comparisons)."
  def src(node), do: Macro.to_string(node)

  @doc "Is `node` an `==` comparison with an empty-list operand (`x == []`)?"
  def equals_empty_list?({:==, _, [a, b]}), do: src(a) == "[]" or src(b) == "[]"
  def equals_empty_list?(_), do: false

  def bullets(entries, line), do: Enum.map_join(entries, "\n", &("  - " <> line.(&1)))
end
