defmodule Credence.Semantic.FixMultipleDefaultArgs do
  @moduledoc """
  Fixes "defines defaults multiple times" compile errors and missing `@impl`
  annotations on callback implementations with default arguments.

  When multiple `def`/`defp` clauses each declare their own `\\` default
  for the same function, Elixir rejects the code. The fix extracts a single
  header clause that declares the defaults and removes `\\` from every
  pattern-matching clause.

  When a single callback implementation has default arguments but is missing
  `@impl true`, the fix splits the clause into a header (with defaults) and
  a body clause (without defaults, keeping the guard), and adds `@impl true`.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @default_msg_pattern ~r/defp? (\w+)\/(\d+) defines defaults multiple times/
  @impl_callback_pattern ~r/module attribute @impl was not set for function \w+\/\d+ callback/
  @impl_callback_fun_pattern ~r/module attribute @impl was not set for function (\w+)\/(\d+) callback/

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, "defines defaults multiple times")
  end

  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    Regex.match?(@impl_callback_pattern, msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(%{message: msg} = diagnostic) do
    {fun, arity} = parse_fun_arity(msg)

    issue_message =
      cond do
        String.contains?(msg, "defines defaults multiple times") ->
          "def #{fun}/#{arity} defines defaults multiple times"

        Regex.match?(@impl_callback_pattern, msg) ->
          "def #{fun}/#{arity} missing @impl true for callback"
      end

    %Issue{
      rule: :fix_multiple_default_args,
      message: issue_message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{message: msg}) do
    cond do
      String.contains?(msg, "defines defaults multiple times") ->
        fix_multiple_defaults(source, msg)

      Regex.match?(@impl_callback_pattern, msg) ->
        fix_missing_impl_callback(source, msg)

      true ->
        source
    end
  end

  # --- fix for "defines defaults multiple times" (existing behavior) ---

  defp fix_multiple_defaults(source, msg) do
    with {fun, _arity} <- parse_fun_arity(msg),
         {:ok, ast} <- Sourceror.parse_string(source),
         {:defmodule, mod_meta, [alias_ast, [{{:__block__, do_meta, [:do]}, body}]]} <- ast,
         {:__block__, body_meta, defs} <- body,
         func_name <- String.to_atom(fun),
         func_defs when length(func_defs) > 1 <- find_func_defs(defs, func_name),
         true <- multiple_have_defaults?(func_defs) do
      # Find positions where ALL clauses have defaults
      arity = length(get_args(hd(func_defs)))
      pos_defaults = find_default_positions(func_defs, arity)

      # Build header clause args
      header_args = build_header_args(arity, pos_defaults)

      # Determine def/defp kind from the first clause
      kind = func_kind(hd(func_defs))

      # Build header: def greet(arg0, name \\ "world")
      header =
        {kind, [line: 0, end_of_expression: [newlines: 2]],
         [{func_name, [line: 0], header_args}]}

      # Fix each clause: remove \\ from args, replace with just the variable
      fixed_defs =
        Enum.map(func_defs, fn {k, def_meta, [call | rest]} ->
          call_without_defaults = strip_defaults_from_call(call)
          {k, def_meta, [call_without_defaults | rest]}
        end)

      # Combine: header + fixed defs + other defs
      other_defs =
        Enum.reject(defs, fn
          {_, _, [{^func_name, _, _} | _]} -> true
          {_, _, [{:when, _, [{^func_name, _, _} | _]} | _]} -> true
          _ -> false
        end)

      all_defs = [header | fixed_defs] ++ other_defs
      new_body = {:__block__, body_meta, all_defs}

      new_ast =
        {:defmodule, mod_meta, [alias_ast, [{{:__block__, do_meta, [:do]}, new_body}]]}

      new_ast
      |> Sourceror.to_string()
    else
      _ -> source
    end
  end

  # --- fix for missing @impl on callback with defaults ---

  defp fix_missing_impl_callback(source, msg) do
    {fun, _arity} = parse_fun_arity(msg)
    func_name = String.to_atom(fun)

    with {:ok, ast} <- Sourceror.parse_string(source),
         {:defmodule, mod_meta, [alias_ast, [{{:__block__, do_meta, [:do]}, body}]]} <- ast,
         {:__block__, body_meta, defs} <- body,
         [clause] <- find_func_defs(defs, func_name),
         true <- has_defaults?(clause) do
      {kind, def_meta, [call | rest]} = clause

      # Extract call without guard for the header
      {name, _name_meta, args} = extract_call_without_guard(call)

      # Build header args (keep defaults, strip metadata)
      header_args =
        Enum.map(args, fn
          {:\\, _, [var, default]} ->
            {:\\, [line: 0], [strip_node_meta(var), strip_node_meta(default)]}

          arg ->
            strip_node_meta(arg)
        end)

      # Build header clause: def func(arg, arg \\ default)
      header =
        {kind, [line: 0, end_of_expression: [newlines: 2]],
         [{name, [line: 0], header_args}]}

      # Build body clause: strip defaults, keep guard and body
      body_call = strip_defaults_from_call(call)
      body_clause = {kind, def_meta, [body_call | rest]}

      # Build @impl true attribute
      impl_attr =
        {:@, [line: 0, end_of_expression: [newlines: 1]],
         [{:impl, [line: 0], [{:__block__, [line: 0], [true]}]}]}

      # Replace the original clause with impl_attr + header + body_clause
      new_defs =
        Enum.flat_map(defs, fn
          {_, _, [{^func_name, _, _} | _]} ->
            [impl_attr, header, body_clause]

          {_, _, [{:when, _, [{^func_name, _, _} | _]} | _]} ->
            [impl_attr, header, body_clause]

          other ->
            [other]
        end)

      new_body = {:__block__, body_meta, new_defs}

      new_ast =
        {:defmodule, mod_meta, [alias_ast, [{{:__block__, do_meta, [:do]}, new_body}]]}

      Sourceror.to_string(new_ast)
    else
      _ -> source
    end
  end

  # --- helpers ---

  # Parse function name and arity from the diagnostic message
  defp parse_fun_arity(msg) do
    case Regex.run(@default_msg_pattern, msg) do
      [_, fun, arity_str] ->
        {fun, String.to_integer(arity_str)}

      _ ->
        case Regex.run(@impl_callback_fun_pattern, msg) do
          [_, fun, arity_str] -> {fun, String.to_integer(arity_str)}
          _ -> nil
        end
    end
  end

  # Find all def/defp clauses for a given function name
  defp find_func_defs(defs, func_name) do
    Enum.filter(defs, fn
      {:def, _, [{^func_name, _, _} | _]} -> true
      {:def, _, [{:when, _, [{^func_name, _, _} | _]} | _]} -> true
      {:defp, _, [{^func_name, _, _} | _]} -> true
      {:defp, _, [{:when, _, [{^func_name, _, _} | _]} | _]} -> true
      _ -> false
    end)
  end

  # Check if multiple clauses have defaults
  defp multiple_have_defaults?(func_defs) do
    Enum.count(func_defs, fn clause ->
      args = get_args(clause)
      Enum.any?(args || [], &match?({:\\, _, _}, &1))
    end) > 1
  end

  # Check if a single clause has defaults
  defp has_defaults?(clause) do
    args = get_args(clause)
    Enum.any?(args || [], &match?({:\\, _, _}, &1))
  end

  # Extract the call node without the `when` guard
  defp extract_call_without_guard({:when, _, [inner_call, _guard]}), do: inner_call
  defp extract_call_without_guard(call), do: call

  # Get the args list from a def/defp clause, handling when guards
  defp get_args({:def, _, [{:when, _, [{_, _, args} | _]} | _]}) when is_list(args), do: args
  defp get_args({:def, _, [{_, _, args} | _]}) when is_list(args), do: args
  defp get_args({:defp, _, [{:when, _, [{_, _, args} | _]} | _]}) when is_list(args), do: args
  defp get_args({:defp, _, [{_, _, args} | _]}) when is_list(args), do: args
  defp get_args(_), do: nil

  # Get def/defp kind
  defp func_kind({:def, _, _}), do: :def
  defp func_kind({:defp, _, _}), do: :defp

  # Find positions where ALL clauses have defaults
  defp find_default_positions(func_defs, arity) do
    all_args = Enum.map(func_defs, &get_args/1)

    Enum.reduce(0..(arity - 1), %{}, fn pos, acc ->
      args_at_pos = Enum.map(all_args, fn args -> Enum.at(args || [], pos) end)

      if Enum.all?(args_at_pos, &match?({:\\, _, _}, &1)) do
        {:\\, _, [var, default]} = hd(args_at_pos)
        Map.put(acc, pos, {var, default})
      else
        acc
      end
    end)
  end

  # Build header args: defaults use original var + default value, non-defaults get fresh names
  defp build_header_args(arity, pos_defaults) do
    Enum.map(0..(arity - 1), fn pos ->
      case Map.get(pos_defaults, pos) do
        {var, default} ->
          {:\\, [line: 0], [strip_node_meta(var), strip_node_meta(default)]}

        nil ->
          {fresh_name(pos), [line: 0], Elixir}
      end
    end)
  end

  # Strip defaults from a call node, keeping just the variable
  defp strip_defaults_from_call({:when, when_meta, [inner_call, guard]}) do
    {:when, when_meta, [strip_defaults_from_call(inner_call), guard]}
  end

  defp strip_defaults_from_call({name, call_meta, args}) do
    new_args =
      Enum.map(args, fn
        {:\\, _, [var, _default]} -> var
        other -> other
      end)

    {name, call_meta, new_args}
  end

  # Generate a fresh variable name for non-default positions
  defp fresh_name(0), do: :arg0
  defp fresh_name(1), do: :arg1
  defp fresh_name(2), do: :arg2
  defp fresh_name(3), do: :arg3
  defp fresh_name(n), do: :"arg#{n}"

  # Strip Sourceror metadata from a node for clean output
  defp strip_node_meta({name, _meta, ctx}) when is_atom(name), do: {name, [line: 0], ctx}
  defp strip_node_meta({:__block__, _meta, [val]}), do: {:__block__, [line: 0], [val]}
  defp strip_node_meta(other), do: other

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
