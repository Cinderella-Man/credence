defmodule Credence.Pattern.NoRedundantBinarySyntax do
  @moduledoc """
  Detects string literals needlessly wrapped in `<<>>` binary syntax.

  In Elixir, strings are already UTF-8 encoded binaries. Wrapping a
  string literal in `<<>>` is completely redundant — `<<"hello">>` is
  identical to `"hello"`. LLMs often add this wrapper when working with
  graphemes or character lists, carrying over intuitions from languages
  where strings and byte sequences are distinct types.

  ## Bad

      defmodule Greeting do
        def hello, do: <<"hello">>
        def letters, do: [<<"b">>, <<"a">>, <<"n">>]
      end

  ## Good

      defmodule Greeting do
        def hello, do: "hello"
        def letters, do: ["b", "a", "n"]
      end

  ## What is flagged

  Any `<<>>` binary form containing a single string literal with no type
  specifiers. Multi-segment binaries (`<<"a", "b">>`), byte values
  (`<<1, 2, 3>>`), and typed segments (`<<x::utf8>>`, `<<"a"::binary>>`)
  are not flagged.

  Sigil internals (`~r/pattern/`, `~s(text)`, `~w(words)`, etc.) are
  never flagged — their `<<>>` nodes are AST implementation details,
  not user-written binary syntax.

  A `<<"literal">>` in a clause head is also left alone when a sibling clause
  of the same `case`/`fn` matches a real binary pattern (`<<"/", rest::binary>>`)
  — there the binary syntax is deliberately kept parallel, not redundant:

      case url do
        <<"/">> -> root()                 # kept — parallels the next clause
        <<"/", rest::binary>> -> sub(rest)
      end

  ## Auto-fix

  Unwraps the string literal by removing the surrounding `<<` and `>>`.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    exempt = parallel_binary_exemptions(ast)

    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, acc ->
        cond do
          sigil_node?(node) ->
            # Replace with an opaque atom so prewalk does not recurse into
            # the sigil's children — their <<>> is an AST implementation
            # detail, not user-written binary syntax.
            {:__sigil_skip__, acc}

          MapSet.member?(exempt, node) ->
            {node, acc}

          true ->
            case detect_pattern(node) do
              {:ok, meta} -> {node, [build_issue(meta) | acc]}
              :skip -> {node, acc}
            end
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    exempt = parallel_binary_exemptions(ast)

    {_ast, patches} =
      Macro.prewalk(ast, [], fn node, acc ->
        cond do
          sigil_node?(node) ->
            # Same trick as `check/2`: replace with an opaque atom so
            # prewalk doesn't descend into the sigil's internal <<>>.
            {:__sigil_skip__, acc}

          MapSet.member?(exempt, node) ->
            {node, acc}

          patch = detect_for_patch(node) ->
            {node, [patch | acc]}

          true ->
            {node, acc}
        end
      end)

    Enum.reverse(patches)
  end

  # A `<<"literal">>` written to visually line up with a sibling clause that
  # genuinely needs binary syntax (`<<"/", rest::binary>>`) is intentional, not
  # redundant. Collect every such literal — a single-string `<<>>` in a clause
  # head of a `case`/`fn`/… whose construct has another clause head matching a
  # real (multi-segment / typed / byte) binary — so the rule leaves them, and
  # only them, alone. Keyed by the node itself; Sourceror nodes carry position
  # metadata, so a literal elsewhere in the source is a different value.
  defp parallel_binary_exemptions(ast) do
    {_ast, exempt} =
      Macro.prewalk(ast, MapSet.new(), fn
        # `fn`'s clauses are the node's args, which prewalk does not revisit as a
        # standalone list — handle it directly. `case`/`cond`/… hold their clause
        # list as a `do:` value, which prewalk *does* visit as a list (below).
        {:fn, _meta, clauses} = node, acc when is_list(clauses) ->
          {node, if(clause_list?(clauses), do: exempt_clause_heads(clauses, acc), else: acc)}

        list, acc when is_list(list) ->
          if clause_list?(list), do: {list, exempt_clause_heads(list, acc)}, else: {list, acc}

        node, acc ->
          {node, acc}
      end)

    exempt
  end

  defp clause_list?(list), do: list != [] and Enum.all?(list, &match?({:->, _, _}, &1))

  defp exempt_clause_heads(clauses, acc) do
    heads = Enum.map(clauses, &clause_head/1)

    if Enum.any?(heads, &contains_real_binary?/1) do
      heads
      |> Enum.flat_map(&single_literal_binaries/1)
      |> Enum.reduce(acc, fn node, set -> MapSet.put(set, node) end)
    else
      acc
    end
  end

  defp clause_head({:->, _, [head, _body]}), do: head
  defp clause_head(_), do: []

  # Any `<<>>` in `head` that is NOT a lone string literal — a real binary match.
  defp contains_real_binary?(head) do
    {_ast, found} =
      Macro.prewalk(head, false, fn
        {:<<>>, _, _} = n, acc -> {n, acc or not single_literal_binary?(n)}
        n, acc -> {n, acc}
      end)

    found
  end

  defp single_literal_binaries(head) do
    {_ast, found} =
      Macro.prewalk(head, [], fn
        {:<<>>, _, _} = n, acc ->
          if single_literal_binary?(n), do: {n, [n | acc]}, else: {n, acc}

        n, acc ->
          {n, acc}
      end)

    found
  end

  defp single_literal_binary?({:<<>>, _, [child]}), do: binary_literal?(child)
  defp single_literal_binary?(_), do: false

  # Sourceror's AST wraps the binary literal in :__block__ to carry
  # position metadata. Standard AST has the raw binary. Handle both.
  defp detect_for_patch({:<<>>, _meta, [child]} = node) do
    if binary_literal?(child) do
      %{
        range: Sourceror.get_range(node),
        change: Sourceror.to_string(child)
      }
    end
  end

  defp detect_for_patch(_), do: nil

  defp binary_literal?({:__block__, _, [str]}) when is_binary(str), do: true
  defp binary_literal?(_), do: false

  # <<>> with a single child that is a plain string literal (binary).
  # This excludes: multi-segment binaries, byte values, variables,
  # and any segment with a type specifier (::).
  defp detect_pattern({:<<>>, meta, [child]}) do
    if binary_literal?(child), do: {:ok, meta}, else: :skip
  end

  defp detect_pattern(_), do: :skip

  # All sigils (built-in and custom) are {:sigil_X, meta, children}
  # where X is a letter. Their first child is always a <<>> node that
  # holds the sigil content — we must not inspect it.
  defp sigil_node?({name, _, _}) when is_atom(name) do
    case Atom.to_string(name) do
      "sigil_" <> _ -> true
      _ -> false
    end
  end

  defp sigil_node?(_), do: false

  defp build_issue(meta) do
    %Issue{
      rule: :no_redundant_binary_syntax,
      message: """
      Wrapping a string literal in `<<>>` is redundant — strings \
      are already binaries in Elixir.

      Replace with the bare string literal:

          <<"hello">>    →    "hello"
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
