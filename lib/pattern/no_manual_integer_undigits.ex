defmodule Credence.Pattern.NoManualIntegerUndigits do
  @moduledoc """
  Detects manual digit-list-to-integer conversion that can be replaced with
  `Integer.undigits/1` or `Integer.undigits/2`.

  Two patterns are detected:

  1. **Reduce pattern** — `Enum.reduce(digits, 0, fn digit, acc -> acc * base + digit end)`
     → `Integer.undigits(digits, base)`.

  2. **Join pattern** — `Enum.join() |> String.to_integer()` (or the nested
     form `String.to_integer(Enum.join(list))`) → `Integer.undigits(list)`.
     `Enum.join/1` concatenates digit representations into a string that is
     then parsed; `Integer.undigits/1` does the same arithmetic without the
     intermediate string.

  ## Bad

      Enum.reduce(digits, 0, fn digit, acc -> acc * 2 + digit end)
      Enum.reduce(digits, 0, fn digit, acc -> digit + acc * 10 end)
      digits |> Enum.join() |> String.to_integer()
      digits |> Enum.join("") |> String.to_integer()
      String.to_integer(Enum.join(digits))

  ## Good

      Integer.undigits(digits, 2)
      Integer.undigits(digits, 10)
      Integer.undigits(digits)
  """
  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def priority, do: 501

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Direct call: Enum.reduce(digits, 0, fn digit, acc -> acc * base + digit end)
        {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, meta, [_digits, zero, lambda]} = node,
        issues ->
          case undigits_body?(zero, lambda) do
            {:ok, _base} -> {node, [build_issue(meta) | issues]}
            :error -> {node, issues}
          end

        # Pipeline: digits |> Enum.reduce(0, fn digit, acc -> acc * base + digit end)
        {:|>, _,
         [
           _digits,
           {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, meta, [zero, lambda]}
         ]} = node,
        issues ->
          case undigits_body?(zero, lambda) do
            {:ok, _base} -> {node, [build_issue(meta) | issues]}
            :error -> {node, issues}
          end

        # Nested: String.to_integer(Enum.join(list))
        {{:., meta, [{:__aliases__, _, [:String]}, :to_integer]}, _,
         [{{:., _, [{:__aliases__, _, [:Enum]}, :join]}, _, join_args}]} = node,
        issues when length(join_args) in [1, 2] ->
          if join_no_separator?(join_args) do
            {node, [build_join_issue(meta) | issues]}
          else
            {node, issues}
          end

        # Pipeline 3-step: list |> Enum.join() |> String.to_integer()
        # In pipe form, join_args is only the separator (list comes from pipe)
        {:|>, _,
         [
           {:|>, _, [_list, {{:., _, [{:__aliases__, _, [:Enum]}, :join]}, _, join_args}]},
           {{:., meta, [{:__aliases__, _, [:String]}, :to_integer]}, _, _}
         ]} = node,
        issues ->
          if pipe_join_no_separator?(join_args) do
            {node, [build_join_issue(meta) | issues]}
          else
            {node, issues}
          end

        # Pipeline 2-step: Enum.join(list) |> String.to_integer()
        # In direct-call form, join_args includes the list as first element
        {:|>, _,
         [
           {{:., _, [{:__aliases__, _, [:Enum]}, :join]}, _, join_args},
           {{:., meta, [{:__aliases__, _, [:String]}, :to_integer]}, _, _}
         ]} = node,
        issues when length(join_args) in [1, 2] ->
          if join_no_separator?(join_args) do
            {node, [build_join_issue(meta) | issues]}
          else
            {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      # Direct call form — Enum.reduce
      {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, [digits, zero, lambda]} = node ->
        case undigits_body?(zero, lambda) do
          {:ok, base} -> integer_undigits_call(digits, base)
          :error -> node
        end

      # Pipeline form — Enum.reduce
      {:|>, pipe_meta,
       [
         digits,
         {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, [zero, lambda]}
       ]} = node ->
        case undigits_body?(zero, lambda) do
          {:ok, base} -> {:|>, pipe_meta, [digits, integer_undigits_pipe_call(base)]}
          :error -> node
        end

      # Nested: String.to_integer(Enum.join(list)) → Integer.undigits(list) (no separator)
      {{:., _, [{:__aliases__, _, [:String]}, :to_integer]}, _,
       [{{:., _, [{:__aliases__, _, [:Enum]}, :join]}, _, [list]}]} ->
        integer_undigits_call_1(list)

      # Nested: String.to_integer(Enum.join(list, "")) → Integer.undigits(list) (empty separator)
      {{:., _, [{:__aliases__, _, [:String]}, :to_integer]}, _,
       [{{:., _, [{:__aliases__, _, [:Enum]}, :join]}, _, [list, sep]}]}
      when sep == "" or (is_tuple(sep) and elem(sep, 2) == [""]) ->
        integer_undigits_call_1(list)

      # Pipeline 3-step: list |> Enum.join() |> String.to_integer() → list |> Integer.undigits()
      # No-arg join: list |> Enum.join() |> String.to_integer()
      {:|>, pipe_meta,
       [
         {:|>, _, [list, {{:., _, [{:__aliases__, _, [:Enum]}, :join]}, _, []}]},
         {{:., _, [{:__aliases__, _, [:String]}, :to_integer]}, _, _}
       ]} ->
        {:|>, pipe_meta, [list, integer_undigits_pipe_call_1()]}

      # Empty-string-arg join: list |> Enum.join("") |> String.to_integer()
      {:|>, pipe_meta,
       [
         {:|>, _, [list, {{:., _, [{:__aliases__, _, [:Enum]}, :join]}, _, [sep]}]},
         {{:., _, [{:__aliases__, _, [:String]}, :to_integer]}, _, _}
       ]}
      when sep == "" or (is_tuple(sep) and elem(sep, 2) == [""]) ->
        {:|>, pipe_meta, [list, integer_undigits_pipe_call_1()]}

      # Pipeline 2-step: Enum.join(list) |> String.to_integer() → Integer.undigits(list) (no separator)
      {:|>, _,
       [
         {{:., _, [{:__aliases__, _, [:Enum]}, :join]}, _, [list]},
         {{:., _, [{:__aliases__, _, [:String]}, :to_integer]}, _, _}
       ]} ->
        integer_undigits_call_1(list)

      # Pipeline 2-step: Enum.join(list, "") |> String.to_integer() → Integer.undigits(list) (empty separator)
      {:|>, _,
       [
         {{:., _, [{:__aliases__, _, [:Enum]}, :join]}, _, [list, sep]},
         {{:., _, [{:__aliases__, _, [:String]}, :to_integer]}, _, _}
       ]}
      when sep == "" or (is_tuple(sep) and elem(sep, 2) == [""]) ->
        integer_undigits_call_1(list)

      node ->
        node
    end)
  end

  # Matches the lambda body: acc * base + digit (and commutative variants)
  # Returns {:ok, base} or :error
  defp undigits_body?(zero, {:fn, _, [{:->, _, [[{d1, _, _}, {a1, _, _}], body]}]})
       when is_atom(d1) and is_atom(a1) do
    with true <- zero_literal?(zero),
         {:ok, base} <- extract_undigits_expr(body, d1, a1) do
      {:ok, base}
    else
      _ -> :error
    end
  end

  defp undigits_body?(_, _), do: :error

  defp zero_literal?(0), do: true
  defp zero_literal?({:__block__, _, [0]}), do: true
  defp zero_literal?(_), do: false

  # acc * base + digit
  defp extract_undigits_expr({:+, _, [mult, {d, _, _}]}, d, a)
       when is_atom(d) do
    case mult do
      {:*, _, [{a2, _, _}, base]} when is_atom(a2) and a2 == a -> literal_positive_int(base)
      {:*, _, [base, {a2, _, _}]} when is_atom(a2) and a2 == a -> literal_positive_int(base)
      _ -> :error
    end
  end

  # digit + acc * base
  defp extract_undigits_expr({:+, _, [{d, _, _}, mult]}, d, a)
       when is_atom(d) do
    case mult do
      {:*, _, [{a2, _, _}, base]} when is_atom(a2) and a2 == a -> literal_positive_int(base)
      {:*, _, [base, {a2, _, _}]} when is_atom(a2) and a2 == a -> literal_positive_int(base)
      _ -> :error
    end
  end

  defp extract_undigits_expr(_, _, _), do: :error

  defp literal_positive_int(n) when is_integer(n) and n > 1, do: {:ok, n}
  defp literal_positive_int({:__block__, _, [n]}) when is_integer(n) and n > 1, do: {:ok, n}
  defp literal_positive_int(_), do: :error

  defp integer_undigits_call(digits, base) do
    {{:., [], [{:__aliases__, [], [:Integer]}, :undigits]}, [],
     [digits, base]}
  end

  defp integer_undigits_pipe_call(base) do
    {{:., [], [{:__aliases__, [], [:Integer]}, :undigits]}, [], [base]}
  end

  defp integer_undigits_call_1(digits) do
    {{:., [], [{:__aliases__, [], [:Integer]}, :undigits]}, [], [digits]}
  end

  defp integer_undigits_pipe_call_1 do
    {{:., [], [{:__aliases__, [], [:Integer]}, :undigits]}, [], []}
  end

  # join_no_separator?/1 — true when Enum.join args (direct call) have no separator or empty separator
  # Enum.join(list) → [list], Enum.join(list, "") → [list, ""]
  defp join_no_separator?([_list]), do: true
  defp join_no_separator?([_list, {_, _, [""]}]), do: true
  defp join_no_separator?([_list, ""]), do: true
  defp join_no_separator?(_), do: false

  # pipe_join_no_separator?/1 — for pipeline form where list comes from pipe
  # Enum.join() → [], Enum.join("") → [""] or [{:__block__, _, [""]}]
  defp pipe_join_no_separator?([]), do: true
  defp pipe_join_no_separator?([""]), do: true
  defp pipe_join_no_separator?([{_, _, [""]}]), do: true
  defp pipe_join_no_separator?(_), do: false

  defp build_issue(meta) do
    %Issue{
      rule: :no_manual_integer_undigits,
      message:
        "Manual digit-list-to-integer conversion via `Enum.reduce` detected. " <>
          "Prefer `Integer.undigits/2` which is clearer and purpose-built for this.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  defp build_join_issue(meta) do
    %Issue{
      rule: :no_manual_integer_undigits,
      message:
        "Manual digit-list-to-integer conversion via `Enum.join |> String.to_integer` detected. " <>
          "Prefer `Integer.undigits/1` which is clearer and avoids the intermediate string.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
