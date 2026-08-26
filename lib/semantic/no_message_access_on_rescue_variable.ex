defmodule Credence.Semantic.NoMessageAccessOnRescueVariable do
  @moduledoc """
  Fixes the compiler warning caused by accessing `.message` on a bare-rescue
  variable.

  LLMs frequently write `rescue e -> e.message` but Elixir's type system warns
  that a bare-rescue variable has unknown struct fields; the `.message` access
  triggers "unknown key .message" which fails `--warnings-as-errors`.

  The deterministic fix is `Map.fetch!(e, :message)`, which preserves the
  direct field access's semantics even when a custom exception's `message/1`
  callback differs from its stored `:message` field:

      rescue e -> {:error, e.message}                 # WRONG — warns
      rescue e -> {:error, Map.fetch!(e, :message)}   # correct

  ## Bad

      defmodule ParseCheckNMAORV do
        def run do
          try do
            :ok
          rescue
            e -> {:error, e.message}
          end
        end
      end

  ## Good

      defmodule ParseCheckNMAORV do
        def run do
          try do
            :ok
          rescue
            e -> {:error, Map.fetch!(e, :message)}
          end
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "unknown key .message"
  # The compiler emits this hint only for the `:anonymous_rescue` type check,
  # i.e. a bare `rescue e ->`. Requiring it keeps `match?` from firing on
  # unrelated "unknown key .message" warnings (e.g. a typed map missing the
  # key), which the structural fix would leave untouched anyway — so check and
  # fix agree on exactly the bare-rescue case.
  @rescue_hint "rescue without specifying exception names"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg) and String.contains?(msg, @rescue_hint)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_message_access_on_rescue_variable,
      message: "accessing .message on a bare-rescue variable is unsafe; use Map.fetch!/2",
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source),
         line_no when is_integer(line_no) <- diagnostic_line(diagnostic),
         [_ | _] = candidates <- candidates_on_line(ast, line_no) do
      patches =
        Enum.map(candidates, fn {var, range} ->
          %{range: range, change: "Map.fetch!(#{var}, :message)"}
        end)

      Sourceror.patch_string(source, patches)
    else
      _ -> source
    end
  end

  # Sourceror renders the `rescue:` keyword as a `__block__`-wrapped atom; the
  # plain atom form is handled too for robustness.
  defp rescue_key?({:__block__, _, [:rescue]}), do: true
  defp rescue_key?(:rescue), do: true
  defp rescue_key?(_), do: false

  # Gather accesses only from bare-rescue clauses, then let the compiler's
  # diagnostic line select the one access that actually warned. This avoids
  # changing quoted rescue syntax or another real rescue elsewhere in the file.
  defp candidates_on_line(ast, line_no) do
    {_, candidates} =
      Macro.prewalk(ast, [], fn
        {rescue_key, clauses} = node, acc when is_list(clauses) ->
          if rescue_key?(rescue_key) do
            {node, clause_candidates(clauses, line_no) ++ acc}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    candidates
    |> Enum.reverse()
    |> Enum.uniq_by(fn {_var, range} -> range end)
  end

  defp clause_candidates(clauses, line_no) do
    Enum.flat_map(clauses, fn
      {:->, _, [[{var, _, ctx}], body]} when is_atom(var) and is_atom(ctx) and var != :_ ->
        {_, {found, _rebound?}} =
          Macro.prewalk(body, {[], false}, fn
            {:=, _, [lhs, _rhs]} = node, {acc, rebound?} ->
              {node, {acc, rebound? or binds_var?(lhs, var)}}

            {{:., _, [{^var, _, var_ctx}, :message]}, _, []} = node, {acc, false}
            when is_atom(var_ctx) ->
              case Sourceror.get_range(node) do
                %{start: start} = range ->
                  if start[:line] == line_no,
                    do: {node, {[{var, range} | acc], false}},
                    else: {node, {acc, false}}

                _ ->
                  {node, {acc, false}}
              end

            node, acc ->
              {node, acc}
          end)

        Enum.reverse(found)

      _ ->
        []
    end)
  end

  defp binds_var?(ast, var) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {^var, _, ctx} = node, _found? when is_atom(ctx) -> {node, true}
        node, found? -> {node, found?}
      end)

    found?
  end

  defp diagnostic_line(%{position: {line_no, _col}}), do: line_no
  defp diagnostic_line(%{position: line_no}) when is_integer(line_no), do: line_no
  defp diagnostic_line(_), do: nil

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
