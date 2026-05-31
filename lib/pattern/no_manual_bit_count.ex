defmodule Credence.Pattern.NoManualBitCount do
  @moduledoc """
  Check-only rule: flags hand-rolled bit-counting loops that use
  `Bitwise.bsr/2` and `Bitwise.band/2` (or `>>>` and `&&&` operators)
  to count set bits in a non-negative integer.

  Prefer `Integer.digits(number, 2) |> Enum.sum()` for counting set bits.

  ## Bad

      defp count_bits(0, acc), do: acc
      defp count_bits(number, acc) do
        count_bits(Bitwise.bsr(number, 1), acc + Bitwise.band(number, 1))
      end

  ## Good

      number
      |> Integer.digits(2)
      |> Enum.sum()

  ## Check-only

  The fix replaces an entire recursive helper with a two-function pipeline —
  too invasive for auto-fix.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {kind, _meta, [head, body_kw]} = node, acc
        when kind in [:def, :defp] and is_list(body_kw) ->
          func_name = extract_func_name(head)
          body = extract_do_body(body_kw)

          if func_name != nil and body != nil and bit_count_pattern?(body, func_name) do
            meta = extract_meta(head)
            {node, [build_issue(meta) | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

  # Detects a recursive function that uses Bitwise.bsr(_, 1) and Bitwise.band(_, 1)
  # in its recursive calls — the bit-counting loop pattern.
  defp bit_count_pattern?(body, func_name) do
    recursive_calls = find_recursive_calls(body, func_name)

    Enum.any?(recursive_calls, fn args ->
      has_bsr_shift_1?(args) and has_band_mask_1?(args)
    end)
  end

  defp find_recursive_calls(body, func_name) do
    {_, calls} =
      Macro.prewalk(body, [], fn
        {^func_name, _, args} = node, acc when is_list(args) ->
          {node, [args | acc]}

        node, acc ->
          {node, acc}
      end)

    calls
  end

  # Checks if any argument is Bitwise.bsr(_, 1) or _ >>> 1
  # Sourceror wraps integer literals in {:__block__, meta, [1]}.
  defp has_bsr_shift_1?(args) do
    Enum.any?(args, fn
      {{:., _, [{:__aliases__, _, [:Bitwise]}, :bsr]}, _, [_, one]} -> literal_one?(one)
      {:>>>, _, [_, one]} -> literal_one?(one)
      _ -> false
    end)
  end

  # Checks if any argument contains Bitwise.band(_, 1) or _ &&& 1
  defp has_band_mask_1?(args) do
    Enum.any?(args, fn arg ->
      {_, found} =
        Macro.prewalk(arg, false, fn
          {{:., _, [{:__aliases__, _, [:Bitwise]}, :band]}, _, [a, b]} = node, acc ->
            {node, acc or literal_one?(a) or literal_one?(b)}

          {:&&&, _, [a, b]} = node, acc ->
            {node, acc or literal_one?(a) or literal_one?(b)}

          node, acc ->
            {node, acc}
        end)

      found
    end)
  end

  # Matches both raw 1 and Sourceror-wrapped {:__block__, _, [1]}.
  defp literal_one?(1), do: true
  defp literal_one?({:__block__, _, [1]}), do: true
  defp literal_one?(_), do: false

  defp extract_func_name({:when, _, [{name, _, _} | _]}) when is_atom(name), do: name
  defp extract_func_name({name, _, _}) when is_atom(name), do: name
  defp extract_func_name(_), do: nil

  defp extract_do_body(body_kw) when is_list(body_kw) do
    Enum.find_value(body_kw, fn
      {{:__block__, _, [:do]}, body} -> body
      _ -> nil
    end)
  end

  defp extract_meta({:when, meta, _}), do: meta
  defp extract_meta({_, meta, _}), do: meta

  defp build_issue(meta) do
    %Issue{
      rule: :no_manual_bit_count,
      message:
        "Hand-rolled bit-counting loop detected. " <>
          "Use `Integer.digits(number, 2) |> Enum.sum()` instead.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
