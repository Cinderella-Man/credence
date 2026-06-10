defmodule Credence.Pattern.PreferPatternMatchOverIfEmptyList do
  @moduledoc """
  Detects `if var == []` inside a function body and rewrites it to a
  pattern-matched clause on `[]`.

  ## Bad

      def process(list) do
        if list == [] do
          0
        else
          Enum.sum(list)
        end
      end

  ## Good

      def process([]), do: 0

      def process(list) do
        Enum.sum(list)
      end

  ## Auto-fix

  Replaces the `if var == []` guard with a dedicated `def name([]), do: do_body`
  clause and keeps the else body as the original clause body.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, acc ->
        case detect_anti_pattern(node) do
          {:ok, info} -> {node, [build_issue(info) | acc]}
          :no -> {node, acc}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    {_ast, patches} =
      Macro.prewalk(ast, [], fn node, acc ->
        case detect_anti_pattern(node) do
          {:ok, info} -> {node, [build_patch(node, info) | acc]}
          :no -> {node, acc}
        end
      end)

    Enum.reverse(patches)
  end

  defp detect_anti_pattern({kind, meta, [{name, _, [param]}, body_kw]})
       when kind in [:def, :defp] and is_atom(name) and is_list(body_kw) do
    with true <- bare_variable?(param),
         {:ok, if_body} <- extract_do_body(body_kw),
         {:ok, _if_meta, left, right, do_body, else_body} <- extract_if_eq_empty(if_body),
         true <- var_matches_param?(left, right, param) do
      {:ok,
       %{
         line: Keyword.get(meta, :line),
         name: name,
         param_name: elem(param, 0),
         do_body: do_body,
         else_body: else_body,
         kind: kind
       }}
    else
      _ -> :no
    end
  end

  defp detect_anti_pattern(_), do: :no

  defp bare_variable?({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: true
  defp bare_variable?(_), do: false

  defp extract_do_body(kw) when is_list(kw) do
    case kw do
      [{{:__block__, _, [:do]}, body}] -> {:ok, body}
      [{:do, body}] -> {:ok, body}
      _ -> :error
    end
  end

  defp extract_do_body(_), do: :error

  defp extract_if_eq_empty({:if, if_meta, [condition, branches]}) when is_list(branches) do
    case condition do
      {:==, _, [left, {:__block__, _, [[]]}]} ->
        {:ok, if_meta, left, nil, extract_branch(branches, :do), extract_branch(branches, :else)}

      {:==, _, [{:__block__, _, [[]]}, right]} ->
        {:ok, if_meta, nil, right, extract_branch(branches, :do), extract_branch(branches, :else)}

      _ ->
        :error
    end
  end

  defp extract_if_eq_empty(_), do: :error

  defp extract_branch(branches, key) do
    Enum.find_value(branches, fn
      {{:__block__, _, [^key]}, body} -> body
      _ -> nil
    end)
  end

  defp var_matches_param?(left, nil, {param_name, _, _}) do
    match?({^param_name, _, ctx} when is_atom(ctx), left)
  end

  defp var_matches_param?(nil, right, {param_name, _, _}) do
    match?({^param_name, _, ctx} when is_atom(ctx), right)
  end

  defp var_matches_param?(_, _, _), do: false

  defp build_issue(%{line: line}) do
    %Issue{
      rule: :prefer_pattern_match_over_if_empty_list,
      message:
        "Use pattern matching on `[]` instead of `if var == []`. " <>
          "Rewrite as `def name([]), do: do_body` and `def name(var) do else_body end`.",
      meta: %{line: line}
    }
  end

  defp build_patch(node, %{kind: kind, name: name, param_name: param_name,
                            do_body: do_body, else_body: else_body}) do
    range = Sourceror.get_range(node)

    do_str = Sourceror.to_string(do_body)
    else_str = Sourceror.to_string(else_body)

    kw = if kind == :defp, do: "defp", else: "def"
    empty_clause = "#{kw} #{name}([]), do: #{do_str}"
    fallthrough = "#{kw} #{name}(#{param_name}) do\n  #{else_str}\nend"
    raw_change = empty_clause <> "\n\n" <> fallthrough

    # Parse and re-render to normalize indentation
    change =
      case Sourceror.parse_string(raw_change) do
        {:ok, parsed} -> Sourceror.to_string(parsed)
        {:error, _} -> raw_change
      end

    %{range: range, change: change}
  end
end
