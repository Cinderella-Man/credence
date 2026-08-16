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

      defmodule ParseCheck do
        def foo(a, b \\\\ :ok) do
          {a, b}
        end

        def foo(a) do
          foo(a, :ok)
        end
      end

  ## Good

      defmodule ParseCheck do
        def foo(a, b \\\\ :ok) do
          {a, b}
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @conflict_pattern ~r/def (\w+)\/(\d+) conflicts with defaults from (\w+)\/(\d+)/

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, "conflicts with defaults from")
  end

  def match?(_), do: false

  @impl true
  def to_issue(%{message: msg, position: position}) do
    {fun, arity} = parse_conflict(msg)

    %Issue{
      rule: :no_conflicting_default_args,
      message: "def #{fun}/#{arity} conflicts with defaults",
      meta: %{line: line(position)}
    }
  end

  @impl true
  def fix(source, %{message: msg, position: position}) do
    with {fun, arity} <- parse_conflict(msg),
         line_no when is_integer(line_no) <- line(position),
         {:ok, ast} <- Sourceror.parse_string(source),
         {:ok, body} <- module_body(ast),
         clauses <- body_clauses(body),
         target when not is_nil(target) <- find_clause(clauses, fun, arity, line_no) do
      remaining = List.delete(clauses, target)

      new_body =
        case remaining do
          [single] -> single
          multiple -> {:__block__, [], multiple}
        end

      new_ast = replace_body(ast, new_body)
      Sourceror.to_string(new_ast)
    else
      _ -> source
    end
  end

  defp parse_conflict(msg) do
    case Regex.run(@conflict_pattern, msg) do
      [_, fun, arity_str, _, _] -> {fun, String.to_integer(arity_str)}
      _ -> nil
    end
  end

  defp module_body({:defmodule, _meta, [_alias, body_kw]}) do
    case body_kw do
      [{{:__block__, _, [:do]}, body}] -> {:ok, body}
      _ -> :error
    end
  end

  defp module_body(_), do: :error

  defp body_clauses({:__block__, _, clauses}), do: clauses
  defp body_clauses(clause), do: [clause]

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

  defp replace_body({:defmodule, meta, [alias, _body_kw]}, new_body) do
    {:defmodule, meta, [alias, [{{:__block__, [], [:do]}, new_body}]]}
  end

  defp line({l, _col}) when is_integer(l), do: l
  defp line(l) when is_integer(l), do: l
  defp line(_), do: nil
end
