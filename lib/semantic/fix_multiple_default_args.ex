defmodule Credence.Semantic.FixMultipleDefaultArgs do
  @moduledoc """
  Fixes "defines defaults multiple times" compile errors.

  When multiple `def`/`defp` clauses each declare their own `\\\\` default
  for the same function, Elixir rejects the code:

      def greet(:hello, name \\\\ "world") do ... end
      def greet(:goodbye, name \\\\ "world") do ... end

  The fix extracts a single header clause that declares the defaults and
  removes `\\\\` from every pattern-matching clause, exactly as the
  compiler's own hint suggests:

      def greet(arg0, name \\\\ "world")
      def greet(:hello, name) do ... end
      def greet(:goodbye, name) do ... end

  ## Safety

  The header is inserted in place of the first clause, so any `import`,
  `alias`, `use`, or module attribute that lexically precedes or follows
  the function keeps its position and scope. The rule only rewrites when
  the intent is unambiguous:

  - only clauses with the reported name AND arity are touched;
  - every one of those clauses declares a default at the same positions
    (a position where one clause has a default and another does not would
    force us to guess which arities the author meant to expose);
  - the default expressions at each position are textually identical
    across clauses (conflicting values like `\\\\ "world"` vs
    `\\\\ "earth"` have no single obvious resolution);
  - all clauses are the same kind (`def` or `defp`).

  Anything else is left byte-identical and unreported via
  `should_report?/2`. Missing-`@impl` callback warnings are deliberately
  not handled here — that is an unrelated diagnostic for a dedicated rule.

  ## Bad

      defmodule CredenceFixMultipleDefaultArgsCheckFixtureFMDA do
        def greet(:hello, name \\\\ "world") do
          "Hello, \#{name}!"
        end

        def greet(:goodbye, name \\\\ "world") do
          "Goodbye, \#{name}!"
        end
      end

  ## Good

      defmodule CredenceFixMultipleDefaultArgsCheckFixtureFMDA do
        def greet(arg0, name \\\\ "world")

        def greet(:hello, name) do
          "Hello, \#{name}!"
        end

        def greet(:goodbye, name) do
          "Goodbye, \#{name}!"
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @default_msg_pattern ~r/(defp?) (\w+)\/(\d+) defines defaults multiple times/

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    Regex.match?(@default_msg_pattern, msg)
  end

  def match?(_), do: false

  @doc """
  Only report diagnostics this rule will actually fix. The matched message
  also fires for shapes the fix deliberately skips (mixed default
  positions, conflicting default values, mixed def/defp), which would
  otherwise be attributed to this rule without being repaired.
  """
  def should_report?(diagnostic, source) do
    fix(source, diagnostic) != source
  end

  @impl true
  def to_issue(%{message: msg} = diagnostic) do
    [_, kind, fun, arity] = Regex.run(@default_msg_pattern, msg)

    %Issue{
      rule: :fix_multiple_default_args,
      message: "#{kind} #{fun}/#{arity} defines defaults multiple times",
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{message: msg}) do
    with [_, _kind, fun, arity_str] <- Regex.run(@default_msg_pattern, msg),
         {:ok, ast} <- Sourceror.parse_string(source),
         {:defmodule, mod_meta, [alias_ast, [{{:__block__, do_meta, [:do]}, body}]]} <- ast,
         {:__block__, body_meta, defs} <- body,
         func_name = String.to_atom(fun),
         arity = String.to_integer(arity_str),
         [_, _ | _] = func_defs <- find_func_defs(defs, func_name, arity),
         [kind] <- func_defs |> Enum.map(&func_kind/1) |> Enum.uniq(),
         {:ok, pos_defaults} <- consistent_defaults(func_defs, arity) do
      header_args = build_header_args(arity, pos_defaults)

      header =
        {kind, [line: 0, end_of_expression: [newlines: 2]], [{func_name, [line: 0], header_args}]}

      first = hd(func_defs)

      new_defs =
        Enum.flat_map(defs, fn d ->
          cond do
            d == first -> [header, strip_clause(d)]
            d in func_defs -> [strip_clause(d)]
            true -> [d]
          end
        end)

      new_body = {:__block__, body_meta, new_defs}

      {:defmodule, mod_meta, [alias_ast, [{{:__block__, do_meta, [:do]}, new_body}]]}
      |> Sourceror.to_string()
    else
      _ -> source
    end
  end

  # --- helpers ---

  # All def/defp clauses for the reported name AND arity (guarded or not).
  defp find_func_defs(defs, func_name, arity) do
    Enum.filter(defs, fn
      {k, _, [{^func_name, _, args} | _]} when k in [:def, :defp] and is_list(args) ->
        length(args) == arity

      {k, _, [{:when, _, [{^func_name, _, args} | _]} | _]}
      when k in [:def, :defp] and is_list(args) ->
        length(args) == arity

      _ ->
        false
    end)
  end

  # {:ok, %{pos => {var, default}}} when every clause declares a default at
  # the same positions with textually identical values; :ambiguous otherwise.
  defp consistent_defaults(func_defs, arity) do
    all_args = Enum.map(func_defs, &get_args/1)

    result =
      Enum.reduce_while(0..(arity - 1), {:ok, %{}}, fn pos, {:ok, acc} ->
        args_at_pos = Enum.map(all_args, &Enum.at(&1 || [], pos))
        defaults = Enum.filter(args_at_pos, &match?({:\\, _, _}, &1))

        cond do
          defaults == [] ->
            {:cont, {:ok, acc}}

          length(defaults) == length(args_at_pos) and uniform_default?(defaults) ->
            {:\\, _, [var, default]} = hd(defaults)
            {:cont, {:ok, Map.put(acc, pos, {var, default})}}

          true ->
            {:halt, :ambiguous}
        end
      end)

    case result do
      {:ok, map} when map_size(map) > 0 -> {:ok, map}
      _ -> :ambiguous
    end
  end

  defp uniform_default?(defaults) do
    defaults
    |> Enum.map(fn {:\\, _, [_var, default]} -> Sourceror.to_string(default) end)
    |> Enum.uniq()
    |> then(&match?([_], &1))
  end

  # Get the args list from a def/defp clause, handling when guards
  defp get_args({_, _, [{:when, _, [{_, _, args} | _]} | _]}) when is_list(args), do: args
  defp get_args({_, _, [{_, _, args} | _]}) when is_list(args), do: args
  defp get_args(_), do: nil

  defp func_kind({:def, _, _}), do: :def
  defp func_kind({:defp, _, _}), do: :defp

  # Header args: defaults keep the first clause's var + value, non-default
  # positions get fresh placeholder names (header arg names carry no meaning).
  defp build_header_args(arity, pos_defaults) do
    Enum.map(0..(arity - 1), fn pos ->
      case Map.get(pos_defaults, pos) do
        {var, default} ->
          {:\\, [line: 0], [strip_node_meta(var), strip_node_meta(default)]}

        nil ->
          {:"arg#{pos}", [line: 0], Elixir}
      end
    end)
  end

  # Remove `\\ default` from a clause's args, keeping just the variable
  defp strip_clause({kind, def_meta, [call | rest]}) do
    {kind, def_meta, [strip_defaults_from_call(call) | rest]}
  end

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

  # Strip Sourceror metadata from a node for clean header output
  defp strip_node_meta({name, _meta, ctx}) when is_atom(name), do: {name, [line: 0], ctx}
  defp strip_node_meta(other), do: other

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
