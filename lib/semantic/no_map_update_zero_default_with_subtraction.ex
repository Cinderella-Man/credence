defmodule Credence.Semantic.NoMapUpdateZeroDefaultWithSubtraction do
  @moduledoc """
  Fixes `Map.update` calls that use a bare `0` default with a callback
  containing sign-based branching (credit/debit via subtraction).

  LLMs frequently write:

      Map.update(balance_by_account, "acct_1", 0, fn existing ->
        case type do
          "credit" -> existing + amount
          "debit" -> existing - amount
        end
      end)

  When the key is absent, the first debit evaluates `0 - amount = -amount`,
  then later additions double-count the sign. The fix computes a signed
  default so the callback is always additive:

      signed_amount = if type == "credit", do: amount, else: -amount

      Map.update(balance_by_account, "acct_1", signed_amount, fn existing ->
        existing + amount
      end)
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "Map.update with zero default and subtraction in callback"

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    msg == @match_msg
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_map_update_zero_default_with_subtraction,
      message:
        "Map.update uses 0 default with sign-based callback; use a signed default instead",
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      case find_map_update_pattern(ast) do
        {:ok, range, type_var, map_var, key_str, amount_var} ->
          apply_fix(source, range, type_var, map_var, key_str, amount_var)

        :error ->
          source
      end
    else
      _ -> source
    end
  end

  defp find_map_update_pattern(ast) do
    Macro.prewalk(ast, :error, fn
      {{:., _, [{:__aliases__, _, [:Map]}, :update]}, _, args} = node, :error
      when is_list(args) and length(args) == 4 ->
        [map_var, key, default, callback] = args

        with true <- literal_zero?(default),
             {:fn, _, [{:->, _, [[_param], body]}]} <- callback,
             {:case, _, [case_subject, case_body_kw]} <- body,
             {:ok, type_var} <- extract_type_var(case_subject),
             {:ok, branches} <- extract_case_branches(case_body_kw),
             {:ok, amount_node} <- classify_branches(branches),
             {map_atom, _, nil} when is_atom(map_atom) <- map_var,
             {:__block__, _, [key_str]} when is_binary(key_str) <- key,
             {amount_atom, _, nil} when is_atom(amount_atom) <- amount_node,
             %Sourceror.Range{} = range <- Sourceror.get_range(node) do
          {node,
           {:ok, range, type_var, Atom.to_string(map_atom), key_str,
            Atom.to_string(amount_atom)}}
        else
          _ -> {node, :error}
        end

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
  end

  defp apply_fix(source, range, type_var, map_var, key_str, amount_var) do
    source_lines = String.split(source, "\n")
    start_line = range.start[:line]
    end_line = range.end[:line]

    indent =
      source_lines
      |> Enum.at(start_line - 1, "")
      |> extract_indent()

    # Build the replacement lines
    assignment_line =
      "#{indent}signed_amount = if #{type_var} == \"credit\", do: #{amount_var}, else: -#{amount_var}"

    blank_line = ""

    map_line =
      "#{indent}Map.update(#{map_var}, \"#{key_str}\", signed_amount, fn existing ->"

    callback_line = "#{indent}  existing + #{amount_var}"
    close_line = "#{indent}end)"

    new_lines = [assignment_line, blank_line, map_line, callback_line, close_line]

    # Replace the range in the source
    before = Enum.take(source_lines, start_line - 1)
    after_lines = Enum.drop(source_lines, end_line)

    Enum.join(before ++ new_lines ++ after_lines, "\n")
  end

  defp extract_indent(line) do
    case Regex.run(~r/^(\s*)/, line) do
      [_, indent] -> indent
      _ -> ""
    end
  end

  defp literal_zero?({:__block__, _, [0]}), do: true
  defp literal_zero?(_), do: false

  defp extract_type_var({var, _, nil}) when is_atom(var), do: {:ok, var}
  defp extract_type_var(_), do: :error

  defp extract_case_branches([{{:__block__, _, [:do]}, branches}]) when is_list(branches) do
    {:ok, branches}
  end

  defp extract_case_branches(_), do: :error

  defp classify_branches(branches) do
    case branches do
      [
        {:->, _, [[{:__block__, _, ["credit"]}], credit_body]},
        {:->, _, [[{:__block__, _, ["debit"]}], debit_body]}
      ] ->
        match_add_sub(credit_body, debit_body)

      [
        {:->, _, [[{:__block__, _, ["debit"]}], debit_body]},
        {:->, _, [[{:__block__, _, ["credit"]}], credit_body]}
      ] ->
        match_add_sub(credit_body, debit_body)

      _ ->
        :error
    end
  end

  defp match_add_sub({:+, _, [c_existing, c_amount]}, {:-, _, [d_existing, d_amount]}) do
    if strip_meta(c_existing) == strip_meta(d_existing) and
         strip_meta(c_amount) == strip_meta(d_amount) do
      {:ok, c_amount}
    else
      :error
    end
  end

  defp match_add_sub(_, _), do: :error

  defp strip_meta(node) do
    Macro.prewalk(node, fn
      {form, _meta, args} when is_list(args) -> {form, [], args}
      {form, _meta, ctx} when is_atom(ctx) -> {form, [], ctx}
      other -> other
    end)
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
