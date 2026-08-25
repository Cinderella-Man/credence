defmodule Credence.Semantic.NoConflictingDefaultArgs do
  @moduledoc """
  Removes a redundant lower-arity `def`/`defp` clause that conflicts with
  default arguments already provided by a higher-arity clause.

  The Elixir compiler emits:

      def sequence/1 conflicts with defaults from sequence/2

  when a function defines both a clause with defaults and a lower-arity
  clause that is fully subsumed. The fix drops the lower-arity clause
  because the defaults already cover it.

  ## Bad

      defmodule ParseCheckNCDA do
        def foo(a, b \\\\ :ok) do
          {a, b}
        end

        def foo(a) do
          foo(a, :ok)
        end
      end

  ## Good

      defmodule ParseCheckNCDA do
        def foo(a, b \\\\ :ok) do
          {a, b}
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @conflict_pattern ~r/def ([\p{L}_][\p{L}\p{N}_]*[!?]?)\/(\d+) conflicts with defaults from ([\p{L}_][\p{L}\p{N}_]*[!?]?)\/(\d+)/u

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, "conflicts with defaults from")
  end

  def match?(_), do: false

  @impl true
  def to_issue(%{message: msg, position: position}) do
    {fun, arity, _higher_arity} = parse_conflict(msg)

    %Issue{
      rule: :no_conflicting_default_args,
      message: "def #{fun}/#{arity} conflicts with defaults",
      meta: %{line: line(position)}
    }
  end

  @impl true
  def fix(source, %{message: msg, position: position}) do
    with {fun, arity, higher_arity} <- parse_conflict(msg),
         line_no when is_integer(line_no) <- line(position),
         {:ok, ast} <- Sourceror.parse_string(source),
         {new_ast, true} <- remove_redundant_clause(ast, fun, arity, higher_arity, line_no) do
      Sourceror.to_string(new_ast)
    else
      _ -> source
    end
  end

  defp parse_conflict(msg) do
    case Regex.run(@conflict_pattern, msg) do
      [_, fun, arity_str, _, higher_arity_str] ->
        {fun, String.to_integer(arity_str), String.to_integer(higher_arity_str)}

      _ ->
        nil
    end
  end

  defp body_clauses({:__block__, _, clauses}), do: clauses
  defp body_clauses(clause), do: [clause]

  defp remove_redundant_clause(ast, fun, arity, higher_arity, line_no) do
    Macro.postwalk(ast, false, fn
      {:defmodule, meta, [alias_ast, [{{:__block__, do_meta, [:do]}, body}]]} = module,
      removed? ->
        clauses = body_clauses(body)
        target = find_clause(clauses, fun, arity, line_no)
        higher = Enum.find(clauses, &(clause_fun_arity(&1) == {fun, higher_arity}))

        if (not removed? and target) && higher && equivalent_delegation?(target, higher, fun) do
          remaining = List.delete(clauses, target)

          new_body =
            if length(remaining) == 1, do: hd(remaining), else: {:__block__, [], remaining}

          {{:defmodule, meta, [alias_ast, [{{:__block__, do_meta, [:do]}, new_body}]]}, true}
        else
          {module, removed?}
        end

      node, removed? ->
        {node, removed?}
    end)
  end

  defp equivalent_delegation?(target, higher, fun) do
    with {:ok, target_args} <- clause_args(target),
         {:ok, higher_args} <- clause_args(higher),
         {:ok, body} <- clause_body(target),
         {name, _, call_args} when is_list(call_args) <- body,
         true <- to_string(name) == fun,
         expected_args <- expanded_args(higher_args, length(target_args)) do
      normalize_ast(call_args) == normalize_ast(expected_args)
    else
      _ -> false
    end
  end

  defp clause_args({kind, _, [{:when, _, [head | _]} | _]}) when kind in [:def, :defp],
    do: head_args(head)

  defp clause_args({kind, _, [head | _]}) when kind in [:def, :defp], do: head_args(head)
  defp clause_args(_), do: :error

  defp head_args({_name, _, args}) when is_list(args), do: {:ok, args}
  defp head_args(_), do: :error

  defp clause_body({kind, _, [_head, body_kw]})
       when kind in [:def, :defp] and is_list(body_kw) do
    case Enum.find(body_kw, fn
           {{:__block__, _, [:do]}, _body} -> true
           _ -> false
         end) do
      {{:__block__, _, [:do]}, body} -> {:ok, unwrap_single_block(body)}
      nil -> :error
    end
  end

  defp clause_body(_), do: :error

  defp unwrap_single_block({:__block__, _, [single]}), do: single
  defp unwrap_single_block(ast), do: ast

  defp expanded_args(args, low_arity) do
    args
    |> Enum.with_index()
    |> Enum.map(fn
      {{:\\, _, [arg, _default]}, index} when index < low_arity -> arg
      {{:\\, _, [_arg, default]}, _index} -> default
      {arg, _index} -> arg
    end)
  end

  defp normalize_ast(ast) do
    Macro.prewalk(ast, fn
      {form, meta, args} when is_list(meta) -> {form, [], args}
      node -> node
    end)
  end

  defp find_clause(clauses, fun, arity, line_no) do
    Enum.find(clauses, fn clause ->
      clause_fun_arity(clause) == {fun, arity} and clause_line(clause) == line_no
    end)
  end

  defp clause_fun_arity({:def, _meta, [{:when, _, [{name, _, args} | _]} | _]})
       when is_list(args),
       do: {to_string(name), length(args)}

  defp clause_fun_arity({:defp, _meta, [{:when, _, [{name, _, args} | _]} | _]})
       when is_list(args),
       do: {to_string(name), length(args)}

  defp clause_fun_arity({:def, _meta, [{name, _, args} | _]}) when is_list(args),
    do: {to_string(name), length(args)}

  defp clause_fun_arity({:defp, _meta, [{name, _, args} | _]}) when is_list(args),
    do: {to_string(name), length(args)}

  defp clause_fun_arity(_), do: nil

  defp clause_line({_, meta, _}) when is_list(meta), do: Keyword.get(meta, :line)
  defp clause_line(_), do: nil

  defp line({l, _col}) when is_integer(l), do: l
  defp line(l) when is_integer(l), do: l
  defp line(_), do: nil
end
