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
  use Credence.Rule
  alias Credence.Issue

  @flagged_enum_fns [:all?, :any?, :each, :map, :filter, :reject, :flat_map]
  @keys_returning_fns [:filter, :reject]

  @impl true
  def fixable?, do: true

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

  @impl true
  def fix(source, _opts) do
    source
    |> Sourceror.parse_string!()
    |> Macro.postwalk(fn node ->
      case try_fix_node(node) do
        {:ok, fixed} -> fixed
        _ -> node
      end
    end)
    |> Sourceror.to_string()
  end

  # ================================================================
  # FIX — node matching
  # ================================================================

  # ================================================================
  # FIX — node matching
  # ================================================================

  defp try_fix_node({:|>, _, _} = node) do
    steps = flatten_pipeline(node)

    case try_fix_pipeline_two_step(steps) do
      {:ok, _} = result -> result
      :error -> try_fix_pipeline_three_step(steps)
    end
  end

  # Direct call: Enum.xxx(Map.keys(var), callback)
  defp try_fix_node({{:., _, [mod, fn_name]}, _meta, [first_arg, callback | _rest]})
       when fn_name in @flagged_enum_fns do
    with true <- enum_module?(mod),
         {:ok, var_name, var_expr} <- extract_map_keys_var_with_expr(first_arg) do
      apply_direct_fix(var_expr, var_name, mod, fn_name, callback)
    end
  end

  # Direct call: Enum.xxx(Map.keys(var), callback)
  defp try_fix_node({{:., _, [mod, fn_name]}, _meta, [first_arg, callback | _rest]})
       when fn_name in @flagged_enum_fns do
    with true <- enum_module?(mod),
         {:ok, var_name, var_expr} <- extract_map_keys_var_with_expr(first_arg) do
      apply_direct_fix(var_expr, var_name, mod, fn_name, callback)
    end
  end

  defp try_fix_node(_), do: :error

  # Two-step: Map.keys(var) |> Enum.xxx(callback) [|> rest]
  defp try_fix_pipeline_two_step([map_keys_call, enum_call | rest]) do
    with {:ok, var_name, var_expr} <- extract_map_keys_var_with_expr(map_keys_call),
         {:ok, fn_name, callback} <- extract_piped_enum(enum_call) do
      apply_pipeline_fix(var_expr, var_name, fn_name, callback, rest)
    end
  end

  defp try_fix_pipeline_two_step(_), do: :error

  # Three-step: var |> Map.keys() |> Enum.xxx(callback) [|> rest]
  defp try_fix_pipeline_three_step([var_expr, map_keys_call, enum_call | rest]) do
    with {:ok, var_name} <- extract_simple_var(var_expr),
         true <- map_keys_no_args?(map_keys_call),
         {:ok, fn_name, callback} <- extract_piped_enum(enum_call) do
      apply_three_step_fix(var_expr, var_name, fn_name, callback, rest)
    end
  end

  defp try_fix_pipeline_three_step(_), do: :error

  # ================================================================
  # FIX — application helpers
  # ================================================================

  # Map.keys(var) |> Enum.xxx(callback) [|> rest]
  defp apply_pipeline_fix(var_expr, var_name, fn_name, callback, rest) do
    with {:ok, new_callback} <- transform_callback(callback, var_name) do
      mod = {:__aliases__, [], [:Enum]}
      enum_call = {{:., [], [mod, fn_name]}, [], [var_expr, new_callback]}

      steps =
        if fn_name in @keys_returning_fns do
          [enum_call, build_extract_keys_pipe_step() | rest]
        else
          [enum_call | rest]
        end

      {:ok, rebuild_pipeline(steps)}
    end
  end

  # var |> Map.keys() |> Enum.xxx(callback) [|> rest]
  defp apply_three_step_fix(var_expr, var_name, fn_name, callback, rest) do
    with {:ok, new_callback} <- transform_callback(callback, var_name) do
      mod = {:__aliases__, [], [:Enum]}
      enum_step = {{:., [], [mod, fn_name]}, [], [new_callback]}

      steps =
        if fn_name in @keys_returning_fns do
          [var_expr, enum_step, build_extract_keys_pipe_step() | rest]
        else
          [var_expr, enum_step | rest]
        end

      {:ok, rebuild_pipeline(steps)}
    end
  end

  # Enum.xxx(Map.keys(var), callback)
  defp apply_direct_fix(var_expr, var_name, mod, fn_name, callback) do
    with {:ok, new_callback} <- transform_callback(callback, var_name) do
      enum_call = {{:., [], [mod, fn_name]}, [], [var_expr, new_callback]}

      if fn_name in @keys_returning_fns do
        {:ok, {:|>, [], [enum_call, build_extract_keys_pipe_step()]}}
      else
        {:ok, enum_call}
      end
    end
  end

  # Builds: Enum.map(fn {k, _v} -> k end) — used as a piped step
  defp build_extract_keys_pipe_step do
    mod = {:__aliases__, [], [:Enum]}
    key = {:k, [], nil}
    val = {:_v, [], nil}
    fn_ast = {:fn, [], [{:->, [], [[{key, val}], key]}]}
    {{:., [], [mod, :map]}, [], [fn_ast]}
  end

  defp rebuild_pipeline([single]), do: single

  defp rebuild_pipeline([first, second | rest]) do
    Enum.reduce(rest, {:|>, [], [first, second]}, fn step, acc ->
      {:|>, [], [acc, step]}
    end)
  end

  # ================================================================
  # FIX — callback transformation
  # ================================================================

  defp transform_callback(callback, var_name) do
    case extract_callback_param(callback) do
      {:ok, key_name} ->
        new_callback =
          callback
          |> rewrite_callback_param(key_name)
          |> replace_map_lookups(var_name, key_name)

        {:ok, new_callback}

      :error ->
        :error
    end
  end

  # Extract the key variable name from the callback's parameter.
  # Handles single-clause: fn k -> ... end
  #          with guard:   fn k when guard -> ... end
  defp extract_callback_param({:fn, _, [{:->, _, [params, _]}]}) do
    case params do
      [{name, _, ctx}] when is_atom(name) and is_atom(ctx) ->
        {:ok, name}

      [{:when, _, [{name, _, ctx}, _]}] when is_atom(name) and is_atom(ctx) ->
        {:ok, name}

      _ ->
        :error
    end
  end

  defp extract_callback_param(_), do: :error

  # Rewrite the parameter from `k` to `{k, v}`.
  defp rewrite_callback_param({:fn, fn_meta, [{:->, arrow_meta, [params, body]}]}, key_name) do
    case params do
      [{^key_name, pmeta, pctx}] ->
        new_params = [{{key_name, pmeta, pctx}, {:v, [], pctx}}]
        {:fn, fn_meta, [{:->, arrow_meta, [new_params, body]}]}

      [{:when, when_meta, [{^key_name, pmeta, pctx}, guard]}] ->
        new_params = [{:when, when_meta, [{{key_name, pmeta, pctx}, {:v, [], pctx}}, guard]}]
        {:fn, fn_meta, [{:->, arrow_meta, [new_params, body]}]}

      _ ->
        {:fn, fn_meta, [{:->, arrow_meta, [params, body]}]}
    end
  end

  # Walk the callback body and replace lookups on the source map.
  #
  # Replacement rules (key == callback parameter):
  #   var[key]           →  v
  #   Map.get(var, key)  →  v
  #   Map.get(var, key, default) → v
  #   Map.fetch(var, key)        → {:ok, v}
  #   Map.fetch!(var, key)       → v
  defp replace_map_lookups(callback, map_var_name, key_var_name) do
    Macro.prewalk(callback, fn
      # var[key]
      {{:., _, [Access, :get]}, _, [{name, _, _}, {key, _, _}]}
      when name == map_var_name and key == key_var_name ->
        {:v, [], nil}

      # Map.get(var, key)
      {{:., _, [{:__aliases__, _, [:Map]}, :get]}, _, [{name, _, _}, {key, _, _}]}
      when name == map_var_name and key == key_var_name ->
        {:v, [], nil}

      # Map.get(var, key, _default)
      {{:., _, [{:__aliases__, _, [:Map]}, :get]}, _, [{name, _, _}, {key, _, _}, _]}
      when name == map_var_name and key == key_var_name ->
        {:v, [], nil}

      # Map.fetch(var, key) → {:ok, v}
      {{:., _, [{:__aliases__, _, [:Map]}, :fetch]}, _, [{name, _, _}, {key, _, _}]}
      when name == map_var_name and key == key_var_name ->
        {:ok, {:v, [], nil}}

      # Map.fetch!(var, key) → v
      {{:., _, [{:__aliases__, _, [:Map]}, :fetch!]}, _, [{name, _, _}, {key, _, _}]}
      when name == map_var_name and key == key_var_name ->
        {:v, [], nil}

      node ->
        node
    end)
  end

  # ================================================================
  # CHECK — node matching
  # ================================================================

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

  # ================================================================
  # CHECK — pipeline analysis
  # ================================================================

  defp check_pipeline(steps, meta) do
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

  # ================================================================
  # EXTRACTORS
  # ================================================================

  # Map.keys(var) — full call with one argument (check: returns name only)
  defp extract_map_keys_var({{:., _, [mod, :keys]}, _, [arg]}) do
    if map_module?(mod), do: extract_simple_var(arg), else: :error
  end

  defp extract_map_keys_var(_), do: :error

  # Map.keys(var) — full call with one argument (fix: returns name + expr)
  defp extract_map_keys_var_with_expr({{:., _, [mod, :keys]}, _, [arg]}) do
    if map_module?(mod) do
      case extract_simple_var(arg) do
        {:ok, name} -> {:ok, name, arg}
        :error -> :error
      end
    else
      :error
    end
  end

  defp extract_map_keys_var_with_expr(_), do: :error

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

  # ================================================================
  # CALLBACK BODY INSPECTION (check only)
  # ================================================================

  defp references_map_var?(callback, target_var) do
    {_, found} =
      Macro.prewalk(callback, false, fn
        node, true ->
          {node, true}

        {{:., _, [Access, :get]}, _, [{name, _, ctx}, _]} = node, acc
        when is_atom(name) and is_atom(ctx) ->
          if name == target_var, do: {node, true}, else: {node, acc}

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

  # ================================================================
  # HELPERS
  # ================================================================

  defp flatten_pipeline({:|>, _, [left, right]}) do
    flatten_pipeline(left) ++ [right]
  end

  defp flatten_pipeline(expr), do: [expr]

  defp enum_module?({:__aliases__, _, [:Enum]}), do: true
  defp enum_module?(_), do: false

  defp map_module?({:__aliases__, _, [:Map]}), do: true
  defp map_module?(_), do: false

  # ================================================================
  # MESSAGE GENERATION
  # ================================================================

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
