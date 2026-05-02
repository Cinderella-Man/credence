defmodule Credence.Rule.NoMapKeysEnumLookup do
  @moduledoc """
  Detects `Map.keys(var)` piped into an `Enum` function whose callback
  also looks up values from the same map variable.

  ## Why this matters

  LLMs frequently port the Python idiom `for key in dict: ... dict[key]`
  into Elixir as `Map.keys(map) |> Enum.xxx(fn k -> ... map[k] ... end)`.
  This creates an unnecessary intermediate list and performs redundant
  lookups.  In Elixir, maps are directly enumerable as `{key, value}`
  pairs:

      # Flagged — extra allocation + redundant lookups
      Map.keys(freqs)
      |> Enum.all?(fn char -> Map.get(other, char, 0) >= freqs[char] end)

      # Idiomatic — single traversal, values already in hand
      Enum.all?(freqs, fn {char, count} ->
        Map.get(other, char, 0) >= count
      end)

  ## Detection scope (strict)

  Only flagged when **all three** conditions hold:

  1. `Map.keys(var)` is called on a simple variable,
  2. The result is passed to one of: `Enum.all?`, `Enum.any?`,
     `Enum.each`, `Enum.map`, `Enum.filter`, `Enum.reject`,
     `Enum.flat_map`, and
  3. The callback body references `var` via `var[key]`,
     `Map.get(var, ...)`, `Map.fetch(var, ...)`, or
     `Map.fetch!(var, ...)`.

  Patterns where only keys are needed (no value lookup in the callback)
  are **not** flagged.
  """

  @behaviour Credence.Rule
  alias Credence.Issue

  @flagged_enum_fns [:all?, :any?, :each, :map, :filter, :reject, :flat_map]

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        case check_node(node) do
          {:ok, issue} -> {node, [issue | issues]}
          :error -> {node, issues}
        end
      end)

    Enum.reverse(issues)
  end

  # ------------------------------------------------------------
  # NODE MATCHING
  # ------------------------------------------------------------

  # Pipeline form: Map.keys(var) |> Enum.xxx(fn ...)
  #            or: var |> Map.keys() |> Enum.xxx(fn ...)
  defp check_node({:|>, meta, _} = node) do
    pipeline = flatten_pipeline(node)
    check_pipeline(pipeline, meta)
  end

  # Direct call form: Enum.xxx(Map.keys(var), fn ...)
  defp check_node({{:., _, [mod, fn_name]}, meta, [first_arg, callback | _]})
       when fn_name in @flagged_enum_fns do
    with true <- enum_module?(mod),
         {:ok, var_name} <- extract_map_keys_var(first_arg),
         true <- references_map_var?(callback, var_name) do
      {:ok, build_issue(fn_name, var_name, meta)}
    else
      _ -> :error
    end
  end

  defp check_node(_), do: :error

  # ------------------------------------------------------------
  # PIPELINE ANALYSIS
  # ------------------------------------------------------------

  defp check_pipeline(steps, meta) do
    # Try two-step first: [Map.keys(var), Enum.xxx(callback)]
    case check_two_step(steps, meta) do
      {:ok, _} = result -> result
      :error -> check_three_step(steps, meta)
    end
  end

  # Pattern A: Map.keys(var) |> Enum.xxx(callback)
  defp check_two_step([map_keys_call, enum_call | _], meta) do
    with {:ok, var_name} <- extract_map_keys_var(map_keys_call),
         {:ok, fn_name, callback} <- extract_piped_enum(enum_call),
         true <- references_map_var?(callback, var_name) do
      {:ok, build_issue(fn_name, var_name, meta)}
    else
      _ -> :error
    end
  end

  defp check_two_step(_, _), do: :error

  # Pattern B: var |> Map.keys() |> Enum.xxx(callback)
  defp check_three_step([var_expr, map_keys_call, enum_call | _], meta) do
    with {:ok, var_name} <- extract_simple_var(var_expr),
         true <- map_keys_no_args?(map_keys_call),
         {:ok, fn_name, callback} <- extract_piped_enum(enum_call),
         true <- references_map_var?(callback, var_name) do
      {:ok, build_issue(fn_name, var_name, meta)}
    else
      _ -> :error
    end
  end

  defp check_three_step(_, _), do: :error

  # ------------------------------------------------------------
  # EXTRACTORS
  # ------------------------------------------------------------

  # Map.keys(var) — full call with one argument
  defp extract_map_keys_var({{:., _, [mod, :keys]}, _, [arg]}) do
    if map_module?(mod) do
      extract_simple_var(arg)
    else
      :error
    end
  end

  defp extract_map_keys_var(_), do: :error

  # Map.keys() — pipeline form with no explicit args
  defp map_keys_no_args?({{:., _, [mod, :keys]}, _, []}) do
    map_module?(mod)
  end

  defp map_keys_no_args?(_), do: false

  # Enum.xxx(callback) — pipeline form, one explicit arg
  defp extract_piped_enum({{:., _, [mod, fn_name]}, _, [callback]})
       when fn_name in @flagged_enum_fns do
    if enum_module?(mod), do: {:ok, fn_name, callback}, else: :error
  end

  defp extract_piped_enum(_), do: :error

  # Simple variable: {name, _, context}
  defp extract_simple_var({name, _, ctx}) when is_atom(name) and is_atom(ctx) do
    {:ok, name}
  end

  defp extract_simple_var(_), do: :error

  # ------------------------------------------------------------
  # CALLBACK BODY INSPECTION
  #
  # Walk the callback AST looking for lookups on the source map
  # variable via Access syntax or Map.get/fetch/fetch!.
  # ------------------------------------------------------------

  defp references_map_var?(callback, target_var) do
    {_, found} =
      Macro.prewalk(callback, false, fn
        # Short-circuit once found
        node, true ->
          {node, true}

        # Access syntax: var[key]
        {{:., _, [Access, :get]}, _, [{name, _, ctx}, _]} = node, acc
        when is_atom(name) and is_atom(ctx) ->
          if name == target_var, do: {node, true}, else: {node, acc}

        # Map.get / Map.fetch / Map.fetch!
        {{:., _, [mod, fn_name]}, _, [{name, _, ctx} | _]} = node, acc
        when is_atom(name) and is_atom(ctx) and fn_name in [:get, :fetch, :fetch!] ->
          if map_module?(mod) and name == target_var,
            do: {node, true},
            else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    found
  end

  # ------------------------------------------------------------
  # HELPERS
  # ------------------------------------------------------------

  defp flatten_pipeline({:|>, _, [left, right]}) do
    flatten_pipeline(left) ++ [right]
  end

  defp flatten_pipeline(expr), do: [expr]

  defp enum_module?({:__aliases__, _, [:Enum]}), do: true
  defp enum_module?(_), do: false

  defp map_module?({:__aliases__, _, [:Map]}), do: true
  defp map_module?(_), do: false

  # ------------------------------------------------------------
  # MESSAGE GENERATION
  # ------------------------------------------------------------

  defp build_issue(fn_name, var_name, meta) do
    %Issue{
      rule: :no_map_keys_enum_lookup,
      message: build_message(fn_name, var_name),
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  defp build_message(fn_name, var_name) do
    """
    `Map.keys(#{var_name})` piped into `Enum.#{fn_name}/2` while also \
    looking up values from `#{var_name}` inside the callback.

    Iterate the map directly to get both keys and values in one pass:

        Enum.#{fn_name}(#{var_name}, fn {key, value} -> ... end)
    """
  end
end
