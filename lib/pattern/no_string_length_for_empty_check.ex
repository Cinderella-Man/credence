defmodule Credence.Pattern.NoStringLengthForEmptyCheck do
  @moduledoc """
  Rewrites `String.length(s) == 0` (and `!= 0`, and the flipped operand order)
  to the O(1) empty-string check `s == ""` / `s != ""` — but ONLY when `s` is
  provably a binary.

  `String.length/1` traverses the whole string (O(n)) just to ask "is it empty?".
  `s == ""` answers that in O(1). The two agree for every *string* `s`, but
  `String.length/1` raises on a non-string while `s == ""` returns `false`, so a
  bare variable would diverge on non-string input. The rule therefore fires only
  when the argument is unambiguously a binary:

    * a string literal,
    * a `<>` concatenation,
    * a call to an always-binary `String.*` function (`trim`, `downcase`, …) or
      `to_string/1` / `Integer.to_string/1` etc.

  This is the empty-string analog of `no_enum_count_for_length` (which narrows to
  provably-list arguments).

  ## Bad

      String.length(String.trim(line)) == 0
      0 == String.length(downcased)   # when `downcased = String.downcase(x)`
      String.length(a <> b) != 0

  ## Good

      String.trim(line) == ""
      "" == downcased
      a <> b != ""
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  # String functions that ALWAYS return a binary (never nil, never a list/int).
  @binary_string_funs ~w(
    trim trim_leading trim_trailing downcase upcase capitalize reverse
    replace replace_leading replace_trailing replace_prefix replace_suffix
    pad_leading pad_trailing duplicate normalize slice
  )a

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, acc ->
        case detect(node) do
          {:ok, _expr, _op} -> {node, [build_issue(node) | acc]}
          :no -> {node, acc}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    {_ast, patches} =
      Macro.prewalk(ast, [], fn node, acc ->
        case detect(node) do
          {:ok, expr, op} -> {node, [patch(node, expr, op) | acc]}
          :no -> {node, acc}
        end
      end)

    Enum.reverse(patches)
  end

  # String.length(expr) == 0 / 0 == String.length(expr) / != variants
  defp detect({op, _meta, [left, right]}) when op in [:==, :!=] do
    cond do
      (expr = length_call_arg(left)) && zero?(right) && binary_expr?(expr) -> {:ok, expr, op}
      (expr = length_call_arg(right)) && zero?(left) && binary_expr?(expr) -> {:ok, expr, op}
      true -> :no
    end
  end

  defp detect(_), do: :no

  defp length_call_arg({{:., _, [{:__aliases__, _, [:String]}, :length]}, _, [arg]}), do: arg
  defp length_call_arg(_), do: nil

  defp zero?({:__block__, _, [0]}), do: true
  defp zero?(0), do: true
  defp zero?(_), do: false

  # Provably a binary.
  defp binary_expr?({:__block__, _, [bin]}) when is_binary(bin), do: true
  defp binary_expr?(bin) when is_binary(bin), do: true
  defp binary_expr?({:<>, _, _}), do: true

  defp binary_expr?({{:., _, [{:__aliases__, _, [:String]}, fun]}, _, _})
       when fun in @binary_string_funs,
       do: true

  defp binary_expr?({:to_string, _, [_]}), do: true

  defp binary_expr?({{:., _, [{:__aliases__, _, [mod]}, :to_string]}, _, [_]})
       when mod in [:Integer, :Float, :Atom],
       do: true

  defp binary_expr?(_), do: false

  defp patch(node, expr, op) do
    op_str = if op == :==, do: "==", else: "!="

    %{
      range: Sourceror.get_range(node),
      change: "#{Sourceror.to_string(expr)} #{op_str} \"\""
    }
  end

  defp build_issue({op, meta, _}) do
    target = if op == :==, do: "== \"\"", else: "!= \"\""

    %Issue{
      rule: :no_string_length_for_empty_check,
      message:
        "`String.length(s) #{op} 0` traverses the whole string. Use the O(1) " <>
          "empty check `s #{target}` instead.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
