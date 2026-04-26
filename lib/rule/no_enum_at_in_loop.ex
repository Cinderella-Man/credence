defmodule Credence.Rule.NoEnumAtInLoop do
  @moduledoc """
  Detects `Enum.at/2` or `Enum.at/3` calls inside iterating Enum callbacks.

  ## Why this matters

  `Enum.at/2` is O(n) on linked lists — it must traverse from the head
  to the target index on every call.  Inside a loop that runs m times,
  this becomes O(n × m).  LLMs generate this pattern constantly because
  they think in array indices, translating Python's `list[i]` into
  `Enum.at(list, i)` inside an `Enum.reduce` or `Enum.map`.

      # Flagged — O(n²) or worse
      Enum.reduce(0..(n - 1), acc, fn i, acc ->
        val = Enum.at(graphemes, i)
        ...
      end)

      # Idiomatic — use Enum.with_index, Enum.zip, pattern matching,
      # or restructure to avoid index-based access entirely

  ## Flagged patterns

  `Enum.at` appearing anywhere in the callback of:
  `Enum.reduce`, `Enum.reduce_while`, `Enum.map`, `Enum.flat_map`,
  `Enum.filter`, `Enum.reject`, `Enum.each`, `Enum.any?`, `Enum.all?`,
  `Enum.take_while`, `Enum.drop_while`, `Enum.map_reduce`,
  `Enum.scan`, `Enum.find`, `Enum.find_value`, `Enum.count`.

  ## Severity

  `:warning`
  """

  @behaviour Credence.Rule
  alias Credence.Issue

  # 2-arg iterators: Enum.map(enum, callback) or enum |> Enum.map(callback)
  @two_arg_iterators [
    :map,
    :flat_map,
    :filter,
    :reject,
    :each,
    :any?,
    :all?,
    :take_while,
    :drop_while,
    :find,
    :find_value,
    :count
  ]

  # 3-arg iterators: Enum.reduce(enum, acc, callback) or enum |> Enum.reduce(acc, callback)
  @three_arg_iterators [:reduce, :reduce_while, :map_reduce, :scan]

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        case check_node(node) do
          {:ok, new_issues} -> {node, new_issues ++ issues}
          :error -> {node, issues}
        end
      end)

    issues
    |> Enum.uniq_by(fn issue -> issue.meta[:line] end)
    |> Enum.sort_by(fn issue -> issue.meta[:line] || 0 end)
  end

  # ------------------------------------------------------------
  # NODE MATCHING
  # ------------------------------------------------------------

  defp check_node({{:., _, [mod, fn_name]}, _meta, args} = _node)
       when is_list(args) do
    if enum_module?(mod) do
      case extract_callback(fn_name, args) do
        {:ok, callback} -> find_enum_at_in_callback(callback)
        :error -> :error
      end
    else
      :error
    end
  end

  defp check_node(_), do: :error

  # ------------------------------------------------------------
  # CALLBACK EXTRACTION
  #
  # In direct calls, all arguments are present.
  # In pipeline calls, the piped argument is implicit (absent).
  #
  # 2-arg iterators:
  #   Direct:   Enum.map(enum, callback)     → args = [enum, callback]
  #   Pipeline: enum |> Enum.map(callback)   → args = [callback]
  #
  # 3-arg iterators:
  #   Direct:   Enum.reduce(enum, acc, cb)   → args = [enum, acc, cb]
  #   Pipeline: enum |> Enum.reduce(acc, cb) → args = [acc, cb]
  # ------------------------------------------------------------

  defp extract_callback(fn_name, args) when fn_name in @two_arg_iterators do
    case args do
      [_enum, callback] -> {:ok, callback}
      [callback] -> {:ok, callback}
      _ -> :error
    end
  end

  defp extract_callback(fn_name, args) when fn_name in @three_arg_iterators do
    case args do
      [_enum, _acc, callback] -> {:ok, callback}
      [_acc, callback] -> {:ok, callback}
      _ -> :error
    end
  end

  defp extract_callback(_, _), do: :error

  # ------------------------------------------------------------
  # CALLBACK INSPECTION
  # ------------------------------------------------------------

  defp find_enum_at_in_callback(callback) do
    {_ast, at_calls} =
      Macro.prewalk(callback, [], fn node, acc ->
        case node do
          {{:., meta, [mod, :at]}, _, args}
          when is_list(args) and length(args) in [1, 2] ->
            if enum_module?(mod) do
              {node, [meta | acc]}
            else
              {node, acc}
            end

          _ ->
            {node, acc}
        end
      end)

    case at_calls do
      [] ->
        :error

      metas ->
        issues =
          Enum.map(metas, fn meta ->
            %Issue{
              rule: :no_enum_at_in_loop,
              severity: :warning,
              message: build_message(),
              meta: %{line: Keyword.get(meta, :line)}
            }
          end)

        {:ok, issues}
    end
  end

  # ------------------------------------------------------------
  # HELPERS
  # ------------------------------------------------------------

  defp enum_module?({:__aliases__, _, [:Enum]}), do: true
  defp enum_module?(_), do: false

  # ------------------------------------------------------------
  # MESSAGE GENERATION
  # ------------------------------------------------------------

  defp build_message do
    """
    `Enum.at/2` called inside an iterating function.

    `Enum.at` is O(n) on linked lists. Inside a loop this becomes \
    O(n × m) or worse. Restructure to avoid index-based access:

    • Use `Enum.with_index/1` to pair elements with indices
    • Use `Enum.zip/2` to walk multiple lists in parallel
    • Convert to a tuple with `List.to_tuple/1` if random access is needed
    • Rethink the algorithm to process elements sequentially
    """
  end
end
