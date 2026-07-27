defmodule Credence.Semantic.FixApplyArityOne do
  @moduledoc """
  Fixes the compile error caused by calling `apply/1`.

  Elixir has only `apply/2` and `apply/3`; `apply/1` does not exist. LLMs
  frequently write `apply(func)` thinking `apply` takes just a function.
  The compiler emits:

      "undefined function apply/1"

  The deterministic fix is `apply(func)` → `apply(func, [])`, which calls
  `func` with zero arguments — the intended semantics.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "undefined function apply/1"

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_apply_arity_one,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          # Match apply/1 — exactly one argument
          {:apply, meta, [single_arg]}, _acc ->
            # Add empty list [] as second argument → apply(arg, [])
            empty_list = {:__block__, [line: meta[:line]], [[]]}
            {{:apply, meta, [single_arg, empty_list]}, true}

          node, acc ->
            {node, acc}
        end)

      if changed, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
