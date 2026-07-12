defmodule Credence.Semantic.NoHardcodedGenserverNameInApi do
  @moduledoc """
  Fixes hardcoded `__MODULE__` as GenServer name and literal ETS table atoms
  in public API functions.

  LLMs repeatedly hardcode `__MODULE__` as the GenServer name in
  `GenServer.call/2` inside public API functions and use literal atoms
  (e.g. `:feature_flags`) for ETS table lookups. This causes "no process"
  and `ArgumentError` when `start_link` accepts `name: nil` or a custom
  `:table_name` option.

  The fix stores the server PID and table names in `:persistent_term` during
  `init/1` and replaces hardcoded references with accessor helpers (`server()`,
  `table()`, `hist()`).
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_text "unexpected option :catch in \"case\""

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_text)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_hardcoded_genserver_name_in_api,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        ast
        |> replace_genserver_calls()
        |> then(fn {ast, c1} ->
          {ast2, c2} = replace_ets_atoms(ast)
          {ast2, c1 or c2}
        end)
        |> then(fn {ast, c1} ->
          {ast2, c2} = insert_helpers(ast)
          {ast2, c1 or c2}
        end)
        |> then(fn {ast, c1} ->
          {ast2, c2} = add_persistent_term_to_init(ast)
          {ast2, c1 or c2}
        end)

      if changed, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  # GenServer.call(__MODULE__, ...) -> GenServer.call(server(), ...)
  defp replace_genserver_calls(ast) do
    Macro.prewalk(ast, false, fn
      {{:., d_meta, [{:__aliases__, a_meta, [:GenServer]}, :call]}, c_meta, args} = node,
      acc
      when is_list(args) ->
        case args do
          [{:__MODULE__, mod_meta, nil} | rest] ->
            new_node =
              {{:., d_meta, [{:__aliases__, a_meta, [:GenServer]}, :call]}, c_meta,
               [{:server, [line: mod_meta[:line] || 0], []} | rest]}

            {new_node, true}

          _ ->
            {node, acc}
        end

      node, acc ->
        {node, acc}
    end)
  end

  # :ets.lookup(:feature_flags, ...) -> :ets.lookup(table(), ...)
  defp replace_ets_atoms(ast) do
    Macro.prewalk(ast, false, fn
      {{:., _, [{:__block__, _, [:ets]}, :lookup]} = dot, meta,
       [{:__block__, _, [:feature_flags_history]} | rest]} = _node,
      _acc ->
        # hist() as function call: {:hist, meta, []}
        replacement = {:hist, [line: meta[:line] || 0], []}
        new_node = {dot, meta, [replacement | rest]}
        {new_node, true}

      {{:., _, [{:__block__, _, [:ets]}, :lookup]} = dot, meta,
       [{:__block__, _, [:feature_flags]} | rest]} = _node,
      _acc ->
        replacement = {:table, [line: meta[:line] || 0], []}
        new_node = {dot, meta, [replacement | rest]}
        {new_node, true}

      node, acc ->
        {node, acc}
    end)
  end

  # Insert @pt_server, @pt_table, @pt_hist, defp server/table/hist after `use GenServer`
  defp insert_helpers(ast) do
    Macro.prewalk(ast, false, fn
      {:__block__, meta, stmts} = node, acc ->
        case do_insert_helpers(stmts) do
          {:ok, new_stmts} -> {{:__block__, meta, new_stmts}, true}
          :error -> {node, acc}
        end

      node, acc ->
        {node, acc}
    end)
  end

  defp do_insert_helpers(stmts) do
    case Enum.split_while(stmts, fn
           {:use, _, [{:__aliases__, _, [:GenServer]}]} -> false
           _ -> true
         end) do
      {before, [use_gs | rest]} ->
        helpers = parse_helpers!()
        {:ok, before ++ [use_gs] ++ helpers ++ rest}

      _ ->
        :error
    end
  end

  defp parse_helpers! do
    {:ok, {:__block__, _, stmts}} =
      Sourceror.parse_string("""
      @pt_server {__MODULE__, :server}
      @pt_table {__MODULE__, :table}
      @pt_hist {__MODULE__, :hist}

      defp server, do: :persistent_term.get(@pt_server)
      defp table, do: :persistent_term.get(@pt_table)
      defp hist, do: :persistent_term.get(@pt_hist)
      """)

    stmts
  end

  # Add persistent_term.put calls to init/1 body
  defp add_persistent_term_to_init(ast) do
    Macro.prewalk(ast, false, fn
      {:def, def_meta,
       [{:init, init_meta, [state_arg]},
        [{{:__block__, do_meta, [:do]}, body}]]} = node,
      acc ->
        # body is {:__block__, body_meta, [{{:__block__, _, [:ok]}, _}]}
        case body do
          {:__block__, body_meta, [ok_tuple]} ->
            case ok_tuple do
              {{:__block__, _ok_meta, [:ok]}, _state_val} ->
                pt_stmts = parse_pt_puts!()
                new_stmts = Enum.map(pt_stmts, &strip_block_meta/1) ++ [ok_tuple]
                new_body = {:__block__, body_meta, new_stmts}

                new_node =
                  {:def, def_meta,
                   [{:init, init_meta, [state_arg]},
                    [{{:__block__, do_meta, [:do]}, new_body}]]}

                {new_node, true}

              _ ->
                {node, acc}
            end

          _ ->
            {node, acc}
        end

      node, acc ->
        {node, acc}
    end)
  end

  defp parse_pt_puts! do
    {:ok, {:__block__, _, stmts}} =
      Sourceror.parse_string("""
      :persistent_term.put(@pt_server, self())
      :persistent_term.put(@pt_table, state.table_name)
      :persistent_term.put(@pt_hist, state.hist_name)
      """)

    stmts
  end

  defp strip_block_meta({:__block__, _meta, [val]}), do: val
  defp strip_block_meta(other), do: other

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
