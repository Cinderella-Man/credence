defmodule Credence.Semantic.NoPrivateFnCalledFromMacroQuote do
  @moduledoc """
  Fixes compiler warnings about private functions called only from macro
  `quote` blocks.

  When a `defp` helper is called exclusively from within a `quote` block
  inside a `defmacro`, the compiler cannot see the call as a usage and emits:

      function X/N is unused

  Under `--warnings-as-errors` this blocks compilation.  Even if the warning
  were suppressed, the generated code would fail at runtime because a private
  function cannot be called from the caller module's context.

  The fix promotes every `defp` clause for the function to `def` and adds
  `@doc false` before the first clause so the function stays invisible to
  documentation while becoming callable from the macro-expanded code.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @unused_pattern ~r/^function (\w+)\/(\d+) is unused$/

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.match?(msg, @unused_pattern)
  end

  def match?(_), do: false

  @impl true
  def to_issue(%{message: msg, position: position}) do
    %Issue{
      rule: :no_private_fn_called_from_macro_quote,
      message: msg,
      meta: %{line: line(position)}
    }
  end

  @impl true
  def fix(source, %{message: msg}) do
    case Regex.run(@unused_pattern, msg) do
      [_, fun_name, _arity_str] ->
        lines = String.split(source, "\n")
        defp_indices = find_defp_lines(lines, fun_name)

        cond do
          defp_indices == [] ->
            source

          not called_from_quote?(source, fun_name) ->
            source

          true ->
            updated_lines =
              Enum.reduce(defp_indices, lines, fn idx, acc ->
                line_text = Enum.at(acc, idx)
                new_text = String.replace(line_text, ~r/\bdefp\b/, "def", global: false)
                List.replace_at(acc, idx, new_text)
              end)

            first_idx = List.first(defp_indices)
            indent = get_indent(Enum.at(updated_lines, first_idx))

            if already_has_doc_false?(lines, first_idx) do
              Enum.join(updated_lines, "\n")
            else
              {before, rest} = Enum.split(updated_lines, first_idx)
              Enum.join(before ++ ["#{indent}@doc false"] ++ rest, "\n")
            end
        end

      _ ->
        source
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp called_from_quote?(source, fun_name) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        fun_atom = String.to_atom(fun_name)

        {_ast, found} =
          Macro.prewalk(ast, false, fn
            {:quote, _, body} = node, acc ->
              found_in_quote = calls_fun?(body, fun_atom)
              {node, acc or found_in_quote}

            node, acc ->
              {node, acc}
          end)

        found

      _ ->
        false
    end
  end

  defp calls_fun?(node, fun_atom) do
    {_node, found} =
      Macro.prewalk(node, false, fn
        {^fun_atom, _, args} = n, _ when is_list(args) -> {n, true}
        n, a -> {n, a}
      end)

    found
  end

  defp find_defp_lines(lines, fun_name) do
    pattern = Regex.compile!("^\\s*defp\\s+#{Regex.escape(fun_name)}\\b")

    lines
    |> Enum.with_index()
    |> Enum.filter(fn {line_text, _} -> String.match?(line_text, pattern) end)
    |> Enum.map(fn {_, idx} -> idx end)
  end

  defp get_indent(line_text) do
    case Regex.run(~r/^(\s*)/, line_text) do
      [_, indent] -> indent
      _ -> ""
    end
  end

  defp already_has_doc_false?(lines, defp_idx) do
    (defp_idx - 1)..0//-1
    |> Enum.reduce_while(false, fn idx, _acc ->
      line_text = Enum.at(lines, idx, "") |> String.trim()

      cond do
        line_text == "" ->
          {:cont, false}

        String.match?(line_text, ~r/^@doc\s+false\s*$/) ->
          {:halt, true}

        String.match?(line_text, ~r/^@\w/) ->
          {:halt, false}

        String.match?(line_text, ~r/^#/) ->
          {:cont, false}

        true ->
          {:halt, false}
      end
    end)
  end

  defp line({l, _col}) when is_integer(l), do: l
  defp line(l) when is_integer(l), do: l
end
