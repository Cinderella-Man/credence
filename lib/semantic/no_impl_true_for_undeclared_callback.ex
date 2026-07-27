defmodule Credence.Semantic.NoImplTrueForUndeclaredCallback do
  @moduledoc """
  Removes `@impl true` from functions that no behaviour in the module declares
  as a callback.

  The Elixir compiler warns when `@impl true` annotates a function that none
  of the module's `@behaviour` declarations define.  For example, a `Supervisor`
  module whose only callback is `init/1` will warn on `@impl true` before
  `handle_call/3` or `handle_info/2`.  In warnings-as-errors projects this
  breaks the build.

  The fix strips the `@impl true` attribute from the offending function while
  leaving correctly-annotated callbacks untouched.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @impl_pattern ~r/got "@impl true" for function (\w+)\/(\d+) but no behaviour specifies such callback/

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, "got \"@impl true\" for function") and
      String.contains?(msg, "but no behaviour specifies such callback")
  end

  def match?(_), do: false

  @impl true
  def to_issue(%{message: msg, position: position}) do
    {fun, arity} = parse_undeclared(msg)

    %Issue{
      rule: :no_impl_true_for_undeclared_callback,
      message: "@impl true for #{fun}/#{arity} but no behaviour specifies such callback",
      meta: %{line: line(position)}
    }
  end

  @impl true
  def fix(source, %{message: msg, position: position}) do
    with {fun, arity} <- parse_undeclared(msg),
         line_no when is_integer(line_no) <- line(position),
         {:ok, ast} <- Sourceror.parse_string(source),
         {:ok, body} <- module_body(ast),
         clauses <- body_clauses(body),
         {:ok, impl_idx} <- find_impl_before(clauses, fun, arity, line_no) do
      remaining = List.delete_at(clauses, impl_idx)

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

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp parse_undeclared(msg) do
    case Regex.run(@impl_pattern, msg) do
      [_, fun, arity_str] -> {fun, String.to_integer(arity_str)}
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

  # Walk the module's top-level clauses looking for `@impl true` immediately
  # preceding the `def` at `line_no` with matching `{fun, arity}`.
  defp find_impl_before(clauses, fun, arity, line_no) do
    def_idx =
      Enum.find_index(clauses, fn clause ->
        clause_fun_arity(clause) == {fun, arity} and clause_line(clause) == line_no
      end)

    case def_idx do
      nil ->
        :error

      idx when idx > 0 ->
        prev = Enum.at(clauses, idx - 1)

        if impl_attribute?(prev) do
          {:ok, idx - 1}
        else
          :error
        end

      _ ->
        :error
    end
  end

  defp impl_attribute?({:@, _, [{:impl, _, [{:__block__, _, [true]}]}]}), do: true
  defp impl_attribute?(_), do: false

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
