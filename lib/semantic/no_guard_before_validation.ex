defmodule Credence.Semantic.NoGuardBeforeValidation do
  @moduledoc """
  Removes guard conditions that duplicate validation already present in the
  function body.

  LLMs frequently add comparison guards (e.g. `when interval_ms > 0`) to
  function heads that already validate the same condition in the body via
  `raise ArgumentError`. The guard intercepts invalid inputs before the body
  can run, producing a `FunctionClauseError` instead of the intended
  `ArgumentError` — a confusing failure mode for callers.

  The fix strips the redundant guard, letting the body's validation handle
  all invalid inputs uniformly:

      # Before
      def process(data, interval_ms, opts \\ [])
          when is_map(data) and is_integer(interval_ms) and interval_ms > 0 do
        unless interval_ms > 0 do
          raise ArgumentError, "interval_ms must be positive, got: \#{interval_ms}"
        end
        ...
      end

      # After
      def process(data, interval_ms, opts \\ [])
          when is_map(data) and is_integer(interval_ms) do
        unless interval_ms > 0 do
          raise ArgumentError, "interval_ms must be positive, got: \#{interval_ms}"
        end
        ...
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "guard duplicates body validation"

  @impl true
  def match?(%{message: msg, file: file} = _diagnostic)
      when is_binary(msg) and is_binary(file) do
    msg =~ @match_msg and
      case File.read(file) do
        {:ok, source} -> source_has_pattern?(source)
        _ -> false
      end
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_guard_before_validation,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {:def, meta, [head | rest]} = node, acc ->
            case head do
              {:when, when_meta, [pattern, guard]} ->
                body_validations = extract_body_validations(rest)
                guard_comparisons = extract_guard_comparisons(guard)

                redundant =
                  Enum.filter(guard_comparisons, &duplicates_validation?(&1, body_validations))

                case redundant do
                  [] ->
                    {node, acc}

                  _ ->
                    new_guard = Enum.reduce(redundant, guard, &remove_from_and_chain(&2, &1))

                    case new_guard do
                      nil ->
                        clean_meta =
                          Keyword.drop(meta, [:newlines])

                        {{:def, clean_meta, [pattern | rest]}, true}

                      _ ->
                        {{:def, meta, [{:when, when_meta, [pattern, new_guard]} | rest]}, true}
                    end
                end

              _ ->
                {node, acc}
            end

          node, acc ->
            {node, acc}
        end)

      if changed, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  # --- Source pattern detection ---

  defp source_has_pattern?(source) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {_ast, found} =
        Macro.prewalk(ast, false, fn
          {:def, _, [{:when, _, [_pattern, guard]} | rest]} = node, false ->
            body_validations = extract_body_validations(rest)
            guard_comparisons = extract_guard_comparisons(guard)

            redundant? =
              Enum.any?(guard_comparisons, &duplicates_validation?(&1, body_validations))

            {node, redundant?}

          node, acc ->
            {node, acc}
        end)

      found
    else
      _ -> false
    end
  end

  # --- Guard extraction ---

  # Extract all comparison conditions ({var, op, value}) from a guard tree
  # connected by `and`.
  defp extract_guard_comparisons({:and, _, [left, right]}) do
    extract_guard_comparisons(left) ++ extract_guard_comparisons(right)
  end

  defp extract_guard_comparisons(guard) do
    case guard do
      {op, _, [{var, _, nil}, {:__block__, _, [value]}]}
      when op in [:>, :<, :>=, :<=, :==, :!=] and is_integer(value) ->
        [{var, op, value}]

      _ ->
        []
    end
  end

  # --- Body validation extraction ---

  # Extract validation conditions from function body (unless/if with raise).
  # The def args structure is [when_clause, [{{:__block__, _, [:do]}, body}]],
  # so rest is [[{do_pair}]] — we unwrap the outer list first.
  defp extract_body_validations([body_kw]) when is_list(body_kw) do
    case body_kw do
      [{{:__block__, _, [:do]}, body}] -> extract_validations_from_block(body)
      _ -> []
    end
  end

  defp extract_body_validations(_), do: []

  defp extract_validations_from_block({:__block__, _, stmts}) do
    Enum.flat_map(stmts, &extract_validation_from_stmt/1)
  end

  defp extract_validations_from_block(stmt), do: extract_validation_from_stmt(stmt)

  defp extract_validation_from_stmt({:unless, _, [condition, branches]}) do
    case branches do
      [{{:__block__, _, [:do]}, {:raise, _, _}}] ->
        case condition do
          {op, _, [{var, _, nil}, {:__block__, _, [value]}]}
          when op in [:>, :<, :>=, :<=, :==, :!=] and is_integer(value) ->
            [{var, op, value}]

          _ ->
            []
        end

      _ ->
        []
    end
  end

  defp extract_validation_from_stmt(_), do: []

  # --- Guard validation matching ---

  # Check if a guard comparison duplicates a body validation.
  # `unless var > 0 do raise ... end` extracts condition `var > 0` —
  # which is the SAME expression as the guard `when var > 0`. The `unless`
  # keyword handles the inversion semantically (raises when condition is false),
  # so we match directly without inverting.
  defp duplicates_validation?({var, op, value}, validations) do
    Enum.any?(validations, fn {v, vo, vv} -> v == var and vo == op and vv == value end)
  end

  # --- Guard removal ---

  # Remove a comparison from an `and` chain. Returns nil if the chain reduces
  # to nothing.
  defp remove_from_and_chain(guard, {target_var, target_op, target_value}) do
    case guard do
      {:and, meta, [left, right]} ->
        right_match =
          match?(
            {^target_op, _, [{^target_var, _, nil}, {:__block__, _, [^target_value]}]},
            right
          )

        cond do
          right_match ->
            left

          true ->
            case remove_from_and_chain(left, {target_var, target_op, target_value}) do
              nil -> right
              new_left -> {:and, meta, [new_left, right]}
            end
        end

      {^target_op, _, [{^target_var, _, nil}, {:__block__, _, [^target_value]}]} ->
        nil

      _ ->
        guard
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
