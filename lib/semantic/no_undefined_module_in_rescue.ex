defmodule Credence.Semantic.NoUndefinedModuleInRescue do
  @moduledoc """
  Removes undefined modules from rescue clause exception lists.

  LLMs commonly hallucinate undefined Elixir modules as exception types in
  rescue clauses (e.g. `Error`, `NotImplementedError`, `BadStructError`).
  This causes compile warnings/errors under `--warnings-as-errors`.

  The compiler emits:

      struct NotImplementedError is undefined (module NotImplementedError is
      not available or is yet to be defined). Make sure the module name is
      correct and has been specified in full (or that an alias has been defined)

  The fix removes the undefined module from the `in [...]` list.  When the
  list becomes empty the `e in [X]` form is replaced with a catch-all `e`.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_prefix "struct "
  @match_infix "is undefined (module "
  @match_suffix " is not available or is yet to be defined)"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.starts_with?(msg, @match_prefix) and
      String.contains?(msg, @match_infix) and
      String.contains?(msg, @match_suffix)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_undefined_module_in_rescue,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, diagnostic) do
    module_name = extract_module(diagnostic.message)

    if module_name == "" do
      source
    else
      with {:ok, ast} <- Sourceror.parse_string(source) do
        module_parts = module_name |> String.split(".") |> Enum.map(&String.to_atom/1)

        {new_ast, changed} =
          Macro.prewalk(ast, false, fn
            {:in, meta, [var, {:__block__, block_meta, [modules]}]} = node, acc
            when is_list(modules) ->
              filtered =
                Enum.reject(modules, fn
                  {:__aliases__, _, ^module_parts} -> true
                  _ -> false
                end)

              cond do
                filtered == modules ->
                  {node, acc}

                filtered == [] ->
                  {var, true}

                true ->
                  {{:in, meta, [var, {:__block__, block_meta, [filtered]}]}, true}
              end

            node, acc ->
              {node, acc}
          end)

        if changed, do: Sourceror.to_string(new_ast), else: source
      else
        _ -> source
      end
    end
  end

  defp extract_module(msg) do
    case Regex.run(~r/^struct (\S+) is undefined/, msg) do
      [_, mod] -> mod
      _ -> ""
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
