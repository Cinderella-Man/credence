defmodule Credence.Semantic.FixApplyOnFunctionReference do
  @moduledoc """
  Fixes `apply(receiver, :call, [])` → `receiver.()`.

  LLMs repeatedly write `apply(state.clock, :call, [])` to call a stored
  function reference, thinking `:call` is the function name. This is wrong:
  `Kernel.apply/3` expects a module atom as its first argument, not a function
  reference — it raises `ArgumentError` at runtime.

  The idiomatic Elixir way to invoke a zero-arity function reference is the
  dot-call syntax `receiver.()`.  This rule detects the anti-pattern and
  rewrites it.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_substring "apply(:call, [])"

  @impl true
  def match?(%{severity: sev, message: msg})
      when sev in [:warning, :error] and is_binary(msg) do
    String.contains?(msg, @match_substring)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_apply_on_function_reference,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed?} =
        Macro.prewalk(ast, false, fn
          # apply(receiver, :call, []) → receiver.()
          {:apply, meta, [
            {{:., _, _}, _, _} = target,
            {:__block__, _, [:call]},
            {:__block__, _, [[]]}
          ]}, _acc ->
            {{:., dot_meta, [receiver, fun_name]}, call_meta, _args} = target
            # Build receiver.()
            new_node = {
              {:., [line: meta[:line]], [
                {{:., dot_meta, [receiver, fun_name]}, call_meta, []}
              ]},
              [line: meta[:line], closing: [line: meta[:line]]],
              []
            }
            {new_node, true}

          node, acc ->
            {node, acc}
        end)

      if changed?, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
