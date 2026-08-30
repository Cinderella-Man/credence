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

  ## Bad

      defmodule MisusedImplNITFUC do
        use Supervisor

        @impl true
        def init(opts), do: {:ok, opts}

        @impl true
        def handle_call(:ping, _from, state), do: {:reply, :pong, state}
      end

  ## Good

      defmodule MisusedImplNITFUC do
        use Supervisor

        @impl true
        def init(opts), do: {:ok, opts}

        def handle_call(:ping, _from, state), do: {:reply, :pong, state}
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @impl_pattern ~r/got "@impl true" for function (\w+[!?]?)\/(\d+) but no behaviour specifies such callback/

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    Regex.match?(@impl_pattern, msg)
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
         {:ok, impl} <- find_impl_before(ast, fun, arity, line_no),
         impl_line when is_integer(impl_line) <- clause_line(impl) do
      source
      |> String.split("\n", trim: false)
      |> List.delete_at(impl_line - 1)
      |> Enum.join("\n")
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

  defp find_impl_before(ast, fun, arity, line_no) do
    {_ast, impl} =
      Macro.prewalk(ast, nil, fn
        {:__block__, _, clauses} = node, nil when is_list(clauses) ->
          {node, impl_before_def(clauses, fun, arity, line_no)}

        node, found ->
          {node, found}
      end)

    if impl, do: {:ok, impl}, else: :error
  end

  defp impl_before_def(clauses, fun, arity, line_no) do
    with idx when is_integer(idx) <-
           Enum.find_index(clauses, fn clause ->
             clause_fun_arity(clause) == {fun, arity} and clause_line(clause) == line_no
           end) do
      clauses
      |> Enum.take(idx)
      |> Enum.reverse()
      |> Enum.take_while(&module_attribute?/1)
      |> Enum.find(&impl_attribute?/1)
    end
  end

  defp module_attribute?({:@, _, _}), do: true
  defp module_attribute?(_), do: false

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

  defp clause_fun_arity({kind, _meta, [{name, _, nil} | _]}) when kind in [:def, :defp],
    do: {to_string(name), 0}

  defp clause_fun_arity(_), do: nil

  defp clause_line({_, meta, _}) when is_list(meta), do: Keyword.get(meta, :line)
  defp clause_line(_), do: nil

  defp line({l, _col}) when is_integer(l), do: l
  defp line(l) when is_integer(l), do: l
  defp line(_), do: nil
end
