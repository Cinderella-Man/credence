defmodule Credence.Semantic.PreferKernelMaxOverLocal do
  @moduledoc """
  Removes a local `defp max/2` that merely re-implements `Kernel.max/2`.

  LLMs frequently define a private `max/2` with two guard clauses
  (`when a >= b` / `when b > a`) even though `Kernel.max/2` is
  auto-imported and already provides this exact behaviour. The
  compiler emits an error because the local definition shadows the
  imported `Kernel.max/2`:

      imported Kernel.max/2 conflicts with local function

  This rule removes the local `defp max` clauses, letting callers
  use the built-in `Kernel.max/2`.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, "imported") and
      String.contains?(msg, "conflicts with local function")
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :prefer_kernel_max_over_local,
      message: "Local max/2 shadows Kernel.max/2 — removing it",
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    case parse(source) do
      {:ok, ast} ->
        transformed = remove_defp_max(ast)

        if transformed == ast do
          source
        else
          Sourceror.to_string(transformed) <> "\n"
        end

      :error ->
        source
    end
  end

  defp parse(source) do
    {:ok, Sourceror.parse_string!(source)}
  rescue
    _ -> :error
  end

  defp remove_defp_max(ast) do
    Macro.prewalk(ast, fn
      {:__block__, meta, stmts} when is_list(stmts) ->
        filtered =
          Enum.reject(stmts, fn
            {:defp, _, _} -> true
            _ -> false
          end)

        {:__block__, meta, filtered}

      node ->
        node
    end)
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
