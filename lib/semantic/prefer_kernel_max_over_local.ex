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
  def fix(source, diagnostic) do
    case extract_conflicting_func(diagnostic) do
      nil ->
        source

      func_name ->
        case parse(source) do
          {:ok, ast} ->
            transformed =
              ast
              |> remove_defp_name(func_name)
              |> qualify_calls(func_name)

            if transformed == ast do
              source
            else
              Sourceror.to_string(transformed) <> "\n"
            end

          :error ->
            source
        end
    end
  end

  defp parse(source) do
    {:ok, Sourceror.parse_string!(source)}
  rescue
    _ -> :error
  end

  defp extract_conflicting_func(%{message: msg}) when is_binary(msg) do
    case Regex.run(~r/Kernel\.([a-z_][a-z0-9_]*)\//, msg) do
      [_, name] -> String.to_atom(name)
      _ -> nil
    end
  end

  defp extract_conflicting_func(_), do: nil

  defp remove_defp_name(ast, func_name) do
    Macro.prewalk(ast, fn
      {:__block__, meta, stmts} when is_list(stmts) ->
        filtered =
          Enum.reject(stmts, fn stmt -> defp_named?(stmt, func_name) end)

        {:__block__, meta, filtered}

      node ->
        node
    end)
  end

  defp defp_named?({:defp, _, [{name, _, _} | _]}, name), do: true
  defp defp_named?({:defp, _, [{:when, _, [{name, _, _} | _]} | _]}, name), do: true
  defp defp_named?(_, _), do: false

  defp qualify_calls(ast, func_name) do
    Macro.prewalk(ast, fn
      {^func_name, meta, args} when is_list(args) and args != [] ->
        {{:., [], [{:__aliases__, [], [:Kernel]}, func_name]}, meta, args}

      node ->
        node
    end)
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
