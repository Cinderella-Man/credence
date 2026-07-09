defmodule Credence.Semantic.NoPrivateFnInTimerMfa do
  @moduledoc """
  Fixes compiler warnings about private functions referenced via MFA tuples
  in `:timer.apply_after/4` or `:timer.apply_interval/4`.

  LLMs frequently call `:timer.apply_after` or `:timer.apply_interval` with
  an MFA tuple pointing to a `defp` function:

      {:ok, _ref} = :timer.apply_after(ms, __MODULE__, :do_cleanup, [pid])

  The compiler cannot see the MFA reference as a function call and emits:

      function do_cleanup/1 is unused

  Under `--warnings-as-errors` this blocks compilation.  The fix promotes
  the `defp` clause to `def` because the MFA tuple proves the function is
  reachable at runtime.
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
      rule: :no_private_fn_in_timer_mfa,
      message: msg,
      meta: %{line: line(position)}
    }
  end

  @impl true
  def fix(source, %{message: msg}) do
    case Regex.run(@unused_pattern, msg) do
      [_, fun_name, _arity_str] ->
        if referenced_via_timer_mfa?(source, fun_name) do
          lines = String.split(source, "\n")
          defp_indices = find_defp_lines(lines, fun_name)

          cond do
            defp_indices == [] ->
              source

            true ->
              updated_lines =
                Enum.reduce(defp_indices, lines, fn idx, acc ->
                  line_text = Enum.at(acc, idx)
                  new_text = String.replace(line_text, ~r/\bdefp\b/, "def", global: false)
                  List.replace_at(acc, idx, new_text)
                end)

              Enum.join(updated_lines, "\n")
          end
        else
          source
        end

      _ ->
        source
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp referenced_via_timer_mfa?(source, fun_name) do
    fun_atom = String.to_atom(fun_name)

    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        {_ast, found} =
          Macro.prewalk(ast, false, fn
            {{:., _, [{:__block__, _, [:timer]}, timer_fun]}, _, args} = node, acc
            when timer_fun in [:apply_after, :apply_interval] ->
              found = mfa_references_fun?(args, fun_atom)
              {node, acc or found}

            node, acc ->
              {node, acc}
          end)

        found

      _ ->
        false
    end
  end

  defp mfa_references_fun?(args, fun_atom) do
    # The MFA tuple is: timer_fun(ms, module, function_atom, [args])
    # function_atom is the 3rd argument (index 2)
    case Enum.at(args, 2) do
      {:__block__, _, [^fun_atom]} -> true
      ^fun_atom -> true
      _ -> false
    end
  end

  defp find_defp_lines(lines, fun_name) do
    pattern = Regex.compile!("^\\s*defp\\s+#{Regex.escape(fun_name)}\\b")

    lines
    |> Enum.with_index()
    |> Enum.filter(fn {line_text, _} -> String.match?(line_text, pattern) end)
    |> Enum.map(fn {_, idx} -> idx end)
  end

  defp line({l, _col}) when is_integer(l), do: l
  defp line(l) when is_integer(l), do: l
end
