defmodule Credence.Semantic.FixFnArityInKeywordValue do
  @moduledoc """
  Fixes `function: :func/N` in keyword arguments passed to `raise`.

  LLMs write `raise FunctionClauseError, function: :push/4` using Elixir
  doc-notation `/N` for arity inside keyword args. Elixir parses `/` as
  `Kernel.//2`, producing `:push / 4` (atom ÷ integer), which the type
  checker flags with:

      incompatible types given to Kernel.//2

  (and which would raise `ArithmeticError` at runtime). The fix splits
  `function: :foo/N` into `function: :foo, arity: N`, building the exception
  the author asked for.

  ## Matching vs fixing

  `match?/1` sees only the diagnostic (no source), so it claims every
  `incompatible types given to Kernel.//2` warning; `fix/2` then verifies the
  source actually has the shape above and no-ops otherwise, and the
  `should_report?/2` phase hook keeps `analyze` honest by reporting an issue
  only when the fix would rewrite the source.

  ## Deliberately skipped (no fix)

  - Exceptions other than `FunctionClauseError` / `UndefinedFunctionError`:
    only those stdlib structs define both `:function` and `:arity` fields, so
    splitting the pair for e.g. `ArgumentError` would trade the intended
    exception for a `KeyError` at raise-time.
  - Non-literal operands (`function: name/4`, `function: :push/n`) and
    negative "arities" (`function: :push/-1`): no literal atom/arity pair to
    split into.
  - `raise` sites on lines other than the diagnostic's: each offending site
    gets its own compiler diagnostic, so line-scoped rewrites still cover
    every site.

  ## Bad

      defmodule FixFnArityExampleFFAIKV do
        def push(server, name, value, window_size) do
          unless is_number(value) do
            raise FunctionClauseError, function: :push/4
          end
          :ok
        end
      end

  ## Good

      defmodule FixFnArityExampleFFAIKV do
        def push(_server, _name, value, _window_size) do
          unless is_number(value) do
            raise FunctionClauseError, function: :push, arity: 4
          end

          :ok
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_substring "incompatible types given to Kernel.//2"

  # Stdlib exceptions whose structs define both :function and :arity fields,
  # so `function: :foo, arity: N` builds exactly the exception the author
  # asked for. Any other module would raise KeyError from struct!/2 instead.
  @fixable_exceptions [:FunctionClauseError, :UndefinedFunctionError]

  @impl true
  def match?(%{severity: severity, message: msg})
      when severity in [:warning, :error] and is_binary(msg) do
    String.contains?(msg, @match_substring)
  end

  def match?(_), do: false

  @doc """
  Phase hook (`Credence.Semantic.match_rules/2`): report an issue only when
  `fix/2` would actually rewrite the source. `match?/1` sees just the
  diagnostic, so without this gate every incompatible-`Kernel.//2` warning in
  a file (plain arithmetic type errors included) would be attributed to this
  rule.
  """
  def should_report?(diagnostic, source) do
    fix(source, diagnostic) != source
  end

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_fn_arity_in_keyword_value,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, diagnostic) do
    with line_no when is_integer(line_no) <- line(diagnostic),
         {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, {changed, _quote_depth}} =
        Macro.traverse(
          ast,
          {false, 0},
          fn
            {:quote, _, _} = node, {changed, quote_depth} ->
              {node, {changed, quote_depth + 1}}

            {:raise, raise_meta, [{:__aliases__, _, [ex]} = exception, kw_list]}, acc
            when ex in @fixable_exceptions and is_list(kw_list) and elem(acc, 1) == 0 ->
              {_changed, quote_depth} = acc

              case fix_keyword_arity(kw_list, line_no) do
                {:ok, new_kw} -> {{:raise, raise_meta, [exception, new_kw]}, {true, quote_depth}}
                :unchanged -> {{:raise, raise_meta, [exception, kw_list]}, acc}
              end

            node, acc ->
              {node, acc}
          end,
          fn
            {:quote, _, _} = node, {changed, quote_depth} ->
              {node, {changed, quote_depth - 1}}

            node, acc ->
              {node, acc}
          end
        )

      if changed, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  # Walk keyword pairs and split `function: :foo/N` into `function: :foo,
  # arity: N`, but only for the pair whose `/` sits on the diagnostic's line.
  defp fix_keyword_arity(kw_list, line_no) do
    {new_pairs, changed} =
      Enum.flat_map_reduce(kw_list, false, fn
        {{:__block__, key_meta, [:function]} = key, {:/, slash_meta, [atom_node, int_node]}} =
            pair,
        changed ->
          with :keyword <- key_meta[:format],
               ^line_no <- slash_meta[:line],
               {:ok, fun} <- literal_atom(atom_node),
               {:ok, arity} <- literal_arity(int_node) do
            function_pair = {key, {:__block__, [token: inspect(fun)], [fun]}}

            arity_meta =
              key_meta
              |> Keyword.put(:format, :keyword)
              |> Keyword.put(:credence_generated, true)

            arity_key = {:__block__, arity_meta, [:arity]}
            arity_pair = {arity_key, {:__block__, [token: Integer.to_string(arity)], [arity]}}

            {[function_pair, arity_pair], true}
          else
            _ -> {[pair], changed}
          end

        pair, changed ->
          {[pair], changed}
      end)

    if changed do
      {:ok, remove_duplicate_arities(new_pairs)}
    else
      :unchanged
    end
  end

  # The generated arity immediately follows the repaired function pair. Any
  # later arity would win when the exception struct is built, so discard it.
  defp remove_duplicate_arities(pairs) do
    Enum.flat_map(pairs, fn
      {{:__block__, meta, [:arity]}, value} = pair ->
        cond do
          Keyword.get(meta, :credence_generated) == true ->
            [{{:__block__, Keyword.delete(meta, :credence_generated), [:arity]}, value}]

          Keyword.get(meta, :format) == :keyword ->
            []

          true ->
            [pair]
        end

      pair ->
        [pair]
    end)
  end

  # Tagged tuples, not a nil sentinel: `nil` is itself an atom, so a bare-nil
  # failure value would let non-literal operands slip past an `is_atom/1`
  # guard and be rewritten into the literal `nil`.
  defp literal_atom({:__block__, _, [atom]}) when is_atom(atom), do: {:ok, atom}
  defp literal_atom(_), do: :error

  defp literal_arity({:__block__, _, [int]}) when is_integer(int) and int >= 0, do: {:ok, int}
  defp literal_arity(_), do: :error

  defp line(%{position: {line, _col}}) when is_integer(line), do: line
  defp line(%{position: line}) when is_integer(line), do: line
  defp line(_), do: nil
end
