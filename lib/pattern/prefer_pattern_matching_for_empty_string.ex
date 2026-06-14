defmodule Credence.Pattern.PreferPatternMatchingForEmptyString do
  @moduledoc """
  Detects `if String.trim(var) == "" do [] else ... end` inside a function body
  and rewrites it to pattern-match `""` in a separate function clause.

  Non-idiomatic empty-string checks using `String.trim/1` compared against `""`
  can be replaced with pattern matching for clearer, more idiomatic Elixir.

  ## Bad

      def comma_separated_to_list(input_string) do
        if String.trim(input_string) == "" do
          []
        else
          String.split(input_string, ",")
          |> Enum.map(&String.to_integer/1)
        end
      end

  ## Good

      def comma_separated_to_list(""), do: []
      def comma_separated_to_list(input_string) do
        String.split(input_string, ",")
        |> Enum.map(&String.to_integer/1)
      end

  ## What is flagged

  Any `def`/`defp` clause with exactly one bare-variable parameter whose body
  is an `if` expression checking `String.trim(param) == ""` (or `"" ==
  String.trim(param)`), with the do-branch returning `[]` and an else-branch
  containing the actual logic.

  Not flagged:
  - Multi-parameter functions
  - `if` conditions that are not `String.trim(var) == ""`
  - `if` conditions where the comparison is not against `""`
  - Do-branches that don't return `[]`
  - Functions with guards

  ## Auto-fix

  Creates a new `def` clause with `""` pattern matching that returns `[]`,
  and rewrites the original clause to use the else-body directly.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def assumptions, do: [:single_codepoint_graphemes]

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, acc ->
        case detect(node) do
          {:ok, info} -> {node, [build_issue(info) | acc]}
          :skip -> {node, acc}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, opts) do
    {_ast, patches} =
      Macro.prewalk(ast, [], fn node, acc ->
        case detect(node) do
          {:ok, _info} ->
            case build_patch(node, opts) do
              nil -> {node, acc}
              patch -> {node, [patch | acc]}
            end

          :skip ->
            {node, acc}
        end
      end)

    Enum.reverse(patches)
  end

  # ── detection ─────────────────────────────────────────────────────

  # def/defp with exactly one bare-variable param, body is if String.trim(var) == "" do [] else ... end
  defp detect({kind, meta, [{name, _, params}, body_kw]})
       when kind in [:def, :defp] and is_atom(name) and is_list(params) do
    with [param] <- params,
         {:var, var_name} <- bare_var(param),
         {:ok, body} <- do_only_body(body_kw),
         {:ok, ^var_name, _else_body} <- unwrap_if_trim_empty(body, var_name) do
      {:ok, %{kind: kind, meta: meta, name: name, var: var_name}}
    else
      _ -> :skip
    end
  end

  defp detect(_), do: :skip

  # Returns {:var, name} for a bare variable node, else :error.
  defp bare_var({:__block__, _, [inner]}), do: bare_var(inner)
  defp bare_var({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: {:var, name}
  defp bare_var(_), do: :error

  # The body keyword list must be EXACTLY a `do:` body
  defp do_only_body([{{:__block__, _, [:do]}, body}]), do: {:ok, body}
  defp do_only_body([{:do, body}]), do: {:ok, body}
  defp do_only_body(_), do: :error

  # Unwrap `if String.trim(var) == "" do [] else ... end`
  defp unwrap_if_trim_empty({:if, _, [condition, branches]}, expected_var) do
    with {:ok, ^expected_var} <- match_trim_empty_condition(condition, expected_var),
         true <- match_empty_list_do_body(branches),
         {:ok, else_body} <- extract_else_body(branches) do
      {:ok, expected_var, else_body}
    else
      _ -> :error
    end
  end

  defp unwrap_if_trim_empty(_, _), do: :error

  # Match `String.trim(var) == ""` or `"" == String.trim(var)`
  defp match_trim_empty_condition({:==, _, [left, right]}, expected_var) do
    case {left, right} do
      {{{:., _, [{:__aliases__, _, [:String]}, :trim]}, _, [{^expected_var, _, ctx}]},
       {:__block__, _, [""]}}
      when is_atom(ctx) ->
        {:ok, expected_var}

      {{:__block__, _, [""]},
       {{:., _, [{:__aliases__, _, [:String]}, :trim]}, _, [{^expected_var, _, ctx}]}}
      when is_atom(ctx) ->
        {:ok, expected_var}

      _ ->
        :error
    end
  end

  defp match_trim_empty_condition(_, _), do: :error

  # Check if do-body returns `[]`
  defp match_empty_list_do_body(branches) when is_list(branches) do
    case find_branch(branches, :do) do
      {:ok, {:__block__, _, [[]]}} -> true
      {:ok, []} -> true
      _ -> false
    end
  end

  defp match_empty_list_do_body(_), do: false

  # Extract the else body
  defp extract_else_body(branches) when is_list(branches) do
    case find_branch(branches, :else) do
      {:ok, body} -> {:ok, body}
      _ -> :error
    end
  end

  defp extract_else_body(_), do: :error

  defp find_branch(branches, kind) when is_list(branches) do
    Enum.find_value(branches, :error, fn
      {{:__block__, _, [^kind]}, body} -> {:ok, body}
      _ -> nil
    end)
  end

  # ── rewrite ───────────────────────────────────────────────────────

  defp build_patch(node, _opts) do
    case detect(node) do
      {:ok, %{kind: kind, name: name, var: var_name}} ->
        {_def_kind, _meta, [_fn_head, body_kw]} = node
        {:ok, body} = do_only_body(body_kw)
        {:ok, ^var_name, else_body} = unwrap_if_trim_empty(body, var_name)

        range = Sourceror.get_range(node)

        # Build the pattern-matching clause: def func(""), do: []
        empty_string_param = {:__block__, [delimiter: "\""], [""]}

        empty_clause =
          {kind, [],
           [
             {name, [], [empty_string_param]},
             [{{:__block__, [], [:do]}, {:__block__, [], [[]]}}]
           ]}

        # Build the else-body clause: def func(var) do <else_body> end
        var_param = {var_name, [line: 0, column: 0], nil}

        else_clause =
          {kind, [],
           [
             {name, [], [var_param]},
             [{{:__block__, [], [:do]}, else_body}]
           ]}

        # Render both clauses
        change =
          RuleHelpers.render_replacement(empty_clause, range) <>
            "\n" <>
            RuleHelpers.render_replacement(else_clause, range)

        %{range: range, change: change}

      :skip ->
        nil
    end
  end

  # ── issue ─────────────────────────────────────────────────────────

  defp build_issue(%{meta: meta}) do
    %Issue{
      rule: :prefer_pattern_matching_for_empty_string,
      message:
        ~s[Use pattern matching `""` instead of `if String.trim(var) == ""` ] <>
          "to check for empty strings.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
