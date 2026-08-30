defmodule Credence.Semantic.NoRescueInWithExpression do
  @moduledoc """
  Fixes the compiler error when `rescue` or `catch` clauses appear inside a
  `with` expression.

  The compiler emits:

      "unexpected option :rescue in \"with\""
      "unexpected option :catch in \"with\""

  LLMs frequently write `rescue`/`catch` inside `with` blocks (confusing them
  with `try`), which is a compile error. The fix wraps the `with` in a `try`
  and moves the `rescue`/`catch` clauses into the `try`, where they mean what
  the author wrote them to mean. An `after` clause on the same `with` — equally
  invalid there, equally valid on `try` — rides along, so the rewrite compiles
  in one pass. An `else` clause stays on the `with`: unlike `cond`/`case`,
  `with` legitimately takes `else`, and its clauses match the *unmatched*
  `<-` value, which is not what `try`'s `else` means.

  Nothing is discarded: `rescue`/`catch` bodies keep running on exceptions and
  throws, and an existing `else` keeps handling unmatched `<-` values.

  ## Bad (compiles with error)

      defmodule NoRescueInWithFixtureNRIWE do
        def run(key) do
          with {:ok, raw} <- fetch(key) do
            {:ok, raw}
          rescue
            e in ArgumentError -> {:error, Exception.message(e)}
          catch
            kind, value -> {:error, {kind, value}}
          end
        end

        defp fetch(key), do: {:ok, key}
      end

  ## Good

      defmodule NoRescueInWithFixtureNRIWE do
        def run(key) do
          try do
            with {:ok, raw} <- fetch(key) do
              {:ok, raw}
            end
          rescue
            e in ArgumentError -> {:error, Exception.message(e)}
          catch
            kind, value -> {:error, {kind, value}}
          end
        end

        defp fetch(key), do: {:ok, key}
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_rescue ~S(unexpected option :rescue in "with")
  @match_catch ~S(unexpected option :catch in "with")

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_rescue) or String.contains?(msg, @match_catch)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_rescue_in_with_expression,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {result, _quote_depth} = Macro.traverse(ast, 0, &rewrite_node/2, &leave_node/2)

      if result == ast do
        source
      else
        Sourceror.to_string(result)
      end
    else
      _ -> source
    end
  end

  defp rewrite_node({:quote, _, _} = node, quote_depth), do: {node, quote_depth + 1}

  defp rewrite_node({:with, meta, args} = node, 0) when is_list(args) do
    {rewrite_with(meta, args, node), 0}
  end

  defp rewrite_node(node, quote_depth), do: {node, quote_depth}

  defp leave_node({:quote, _, _} = node, quote_depth), do: {node, quote_depth - 1}
  defp leave_node(node, quote_depth), do: {node, quote_depth}

  # The block options are the only bare list among a `with`'s arguments — every
  # `<-` clause is a 3-tuple and every literal list is wrapped in a `:__block__`.
  defp rewrite_with(meta, args, node) do
    case Enum.split(args, -1) do
      {clauses, [opts]} when is_list(opts) ->
        {bad, good} = extract_bad_opts(opts)

        if Enum.any?(bad, &trigger_opt?/1) and has_do?(good) do
          new_with = {:with, meta, clauses ++ [good]}

          {:try, meta, [[{{:__block__, [], [:do]}, new_with} | bad]]}
        else
          node
        end

      _ ->
        node
    end
  end

  # `after` is also invalid in `with` but valid in `try`; it rides along so the
  # rewrite compiles. `else` is *valid* in `with` and means something different
  # in `try`, so it stays put. A `with` whose only invalid option is `after` is
  # left alone — this rule only claims the `:rescue`/`:catch` diagnostics.
  defp extract_bad_opts(opts) do
    Enum.split_with(opts, fn
      {{:__block__, _, [key]}, _} when key in [:rescue, :catch, :after] -> true
      _ -> false
    end)
  end

  defp trigger_opt?({{:__block__, _, [key]}, _}) when key in [:rescue, :catch], do: true
  defp trigger_opt?(_), do: false

  defp has_do?(opts) do
    Enum.any?(opts, fn
      {{:__block__, _, [:do]}, _} -> true
      _ -> false
    end)
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
