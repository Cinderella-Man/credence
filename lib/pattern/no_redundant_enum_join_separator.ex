defmodule Credence.Pattern.NoRedundantEnumJoinSeparator do
  @moduledoc """
  Readability rule: Detects `Enum.join("")` and `Enum.map_join("", mapper)`
  where the empty-string separator is passed explicitly.

  `Enum.join/1` and `Enum.map_join/2` already default to `""`, so the argument
  adds visual noise without changing behaviour.

  ## Bad

      graphemes |> Enum.join("")
      Enum.join(list, "")
      items |> Enum.map_join("", &to_string/1)
      Enum.map_join(items, "", &to_string/1)

  ## Good

      graphemes |> Enum.join()
      Enum.join(list)
      items |> Enum.map_join(&to_string/1)
      Enum.map_join(items, &to_string/1)
  """
  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Direct call: Enum.join(list, "")
        {{:., _, [{:__aliases__, _, [:Enum]}, :join]}, meta, [_list, ""]} = node, issues ->
          {node, [build_issue(meta) | issues]}

        # In a pipe the separator is the only explicit arg: ... |> Enum.join("")
        # The piped value becomes the first arg, so the AST call has [""]
        {{:., _, [{:__aliases__, _, [:Enum]}, :join]}, meta, [""]} = node, issues ->
          {node, [build_issue(meta) | issues]}

        # Direct call: Enum.map_join(list, "", mapper)
        {{:., _, [{:__aliases__, _, [:Enum]}, :map_join]}, meta, [_list, "", _mapper]} = node,
        issues ->
          {node, [build_issue(meta) | issues]}

        # In a pipe the separator is the first explicit arg: ... |> Enum.map_join("", mapper)
        # The piped value becomes the first arg, so the AST call has ["", mapper]
        {{:., _, [{:__aliases__, _, [:Enum]}, :map_join]}, meta, ["", _mapper]} = node, issues ->
          {node, [build_issue(meta) | issues]}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix(source, _opts) do
    source
    |> Sourceror.parse_string!()
    |> Macro.postwalk(fn
      # Direct call: Enum.join(list, "") → Enum.join(list)
      {{:., dot_m, [{:__aliases__, al_m, [:Enum]}, :join]}, call_m, [list_arg, sep]} = node ->
        if empty_string?(sep),
          do: {{:., dot_m, [{:__aliases__, al_m, [:Enum]}, :join]}, call_m, [list_arg]},
          else: node

      # Piped call: ... |> Enum.join("") → ... |> Enum.join()
      {{:., dot_m, [{:__aliases__, al_m, [:Enum]}, :join]}, call_m, [sep]} = node ->
        if empty_string?(sep),
          do: {{:., dot_m, [{:__aliases__, al_m, [:Enum]}, :join]}, call_m, []},
          else: node

      # Direct call: Enum.map_join(list, "", mapper) → Enum.map_join(list, mapper)
      {{:., dot_m, [{:__aliases__, al_m, [:Enum]}, :map_join]}, call_m, [list_arg, sep, mapper]} =
          node ->
        if empty_string?(sep),
          do:
            {{:., dot_m, [{:__aliases__, al_m, [:Enum]}, :map_join]}, call_m, [list_arg, mapper]},
          else: node

      # Piped call: ... |> Enum.map_join("", mapper) → ... |> Enum.map_join(mapper)
      {{:., dot_m, [{:__aliases__, al_m, [:Enum]}, :map_join]}, call_m, [sep, mapper]} = node ->
        if empty_string?(sep),
          do: {{:., dot_m, [{:__aliases__, al_m, [:Enum]}, :map_join]}, call_m, [mapper]},
          else: node

      # Collapse single-step pipe: x |> Enum.join() → Enum.join(x)
      # (fires after the "" removal above, since postwalk is bottom-up)
      {:|>, _, [lhs, {{:., dot_m, [{:__aliases__, al_m, [:Enum]}, :join]}, call_m, []}]} = node ->
        case lhs do
          {:|>, _, _} -> node
          _ -> {{:., dot_m, [{:__aliases__, al_m, [:Enum]}, :join]}, call_m, [lhs]}
        end

      # Collapse single-step pipe: x |> Enum.map_join(mapper) → Enum.map_join(x, mapper)
      {:|>, _, [lhs, {{:., dot_m, [{:__aliases__, al_m, [:Enum]}, :map_join]}, call_m, [mapper]}]} =
          node ->
        case lhs do
          {:|>, _, _} -> node
          _ -> {{:., dot_m, [{:__aliases__, al_m, [:Enum]}, :map_join]}, call_m, [lhs, mapper]}
        end

      node ->
        node
    end)
    |> Sourceror.to_string()
  end

  # Sourceror wraps string literals with metadata: {:__block__, meta, [""]}
  # Match both the wrapped and bare forms.
  defp empty_string?(""), do: true
  defp empty_string?({:__block__, _, [""]}), do: true
  defp empty_string?(_), do: false

  defp build_issue(meta) do
    %Issue{
      rule: :no_redundant_enum_join_separator,
      message:
        "`Enum.join/1` and `Enum.map_join/2` already default to an empty string separator. " <>
          "Remove the redundant `\"\"` argument.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
