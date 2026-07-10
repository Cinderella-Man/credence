defmodule Credence.Semantic.FixEtsMatchSpecVariableInComprehension do
  @moduledoc """
  Fixes `undefined variable` errors caused by using Elixir variables inside
  `:ets.match` match specs within `for` comprehensions.

  LLMs frequently write patterns like:

      for {name, _type, value} <- :ets.match(table, {name, :_, :"$1"}) do
        {name, value}
      end

  where `name` is used as if it were a bound variable in the match spec,
  causing `undefined variable "name"` compilation errors. The fix replaces
  the Elixir variables with match spec variables and restructures the
  comprehension as an `Enum.map` pipeline:

      :ets.match(table, {:"$1", :_, :"$2"})
      |> Enum.map(fn [name, value] -> {name, value} end)
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, "undefined variable \"")
  end

  def match?(_), do: false

  @doc false
  def should_report?(_diagnostic, source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} -> has_ets_match_in_for?(ast)
      _ -> false
    end
  end

  @impl true
  def to_issue(%{message: msg} = diagnostic) do
    %Issue{
      rule: :fix_ets_match_spec_variable_in_comprehension,
      message: msg,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{message: msg}) do
    with var_name when is_binary(var_name) <- extract_var_name(msg),
         {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {:for, _, [{:<-, _, [pattern, rhs]}, body_kw]} = node, acc ->
            case try_transform_for(pattern, rhs, body_kw) do
              {:ok, result} -> {result, true}
              :error -> {node, acc}
            end

          node, acc ->
            {node, acc}
        end)

      if changed, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  # --- source inspection ---

  defp has_ets_match_in_for?(ast) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {:for, _, [{:<-, _, [_, rhs]}, _]} = node, acc ->
          if ets_match_call?(rhs), do: {node, true}, else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp ets_match_call?({{:., _, [{:__block__, _, [:ets]}, :match]}, _, _}), do: true
  defp ets_match_call?({{:., _, [{:__aliases__, _, [:ets]}, :match]}, _, _}), do: true
  defp ets_match_call?(_), do: false

  # --- fix helpers ---

  defp extract_var_name(msg) do
    case Regex.run(~r/undefined variable "(\w+)"/, msg) do
      [_, name] -> name
      _ -> nil
    end
  end

  defp try_transform_for(pattern, rhs, body_kw) do
    with {:ok, table, match_spec} <- extract_ets_match(rhs),
         true <- is_tuple_form?(pattern),
         true <- is_tuple_form?(match_spec) do
      pattern_elems = tuple_elements(pattern)
      match_elems = tuple_elements(match_spec)

      if length(pattern_elems) != length(match_elems) do
        :error
      else
        {new_match_elems, captured_vars} =
          process_positions(pattern_elems, match_elems)

        if captured_vars == [] do
          :error
        else
          new_match_spec = rebuild_tuple(match_spec, new_match_elems)
          new_rhs = replace_call_args(rhs, [table, new_match_spec])
          lambda = build_lambda(captured_vars, body_kw)
          enum_map = build_enum_map_call(lambda)
          {:ok, {:|>, [newlines: 1], [new_rhs, enum_map]}}
        end
      end
    else
      _ -> :error
    end
  end

  defp extract_ets_match(
         {{:., _, [{:__block__, _, [:ets]}, :match]}, _, [table, match_spec]}
       ) do
    {:ok, table, match_spec}
  end

  defp extract_ets_match(
         {{:., _, [{:__aliases__, _, [:ets]}, :match]}, _, [table, match_spec]}
       ) do
    {:ok, table, match_spec}
  end

  defp extract_ets_match(_), do: :error

  defp is_tuple_form?({:{}, _, _}), do: true
  defp is_tuple_form?({_, _}), do: true
  defp is_tuple_form?(_), do: false

  defp tuple_elements({:{}, _, elems}), do: elems
  defp tuple_elements({a, b}), do: [a, b]

  defp rebuild_tuple({:{}, meta, _}, elems), do: {:{}, meta, elems}
  defp rebuild_tuple(_, [a, b]), do: {a, b}

  defp replace_call_args({{:., dot_meta, receiver}, call_meta, _}, args) do
    {{:., dot_meta, receiver}, call_meta, args}
  end

  defp process_positions(pattern_elems, match_spec_elems) do
    pairs = Enum.zip(pattern_elems, match_spec_elems)

    {new_ms, captured, _next} =
      Enum.reduce(pairs, {[], [], 1}, fn {pat, ms}, {ms_acc, cap_acc, num} ->
        pat_var = extract_var_atom(pat)
        skip = underscore_prefix?(pat_var)

        case classify_match_spec_elem(ms) do
          :wildcard ->
            {[ms | ms_acc], cap_acc, num}

          {:dollar_var, _} ->
            new_ms = make_dollar_var(num)

            if skip do
              {[new_ms | ms_acc], cap_acc, num + 1}
            else
              {[new_ms | ms_acc], [{num, pat_var} | cap_acc], num + 1}
            end

          {:elixir_var, _} ->
            new_ms = make_dollar_var(num)

            if skip do
              {[new_ms | ms_acc], cap_acc, num + 1}
            else
              {[new_ms | ms_acc], [{num, pat_var} | cap_acc], num + 1}
            end

          :keep_as_is ->
            {[ms | ms_acc], cap_acc, num}
        end
      end)

    {Enum.reverse(new_ms), Enum.reverse(captured)}
  end

  defp classify_match_spec_elem({:__block__, _, [atom]}) when is_atom(atom) do
    atom_str = Atom.to_string(atom)

    cond do
      atom == :_ ->
        :wildcard

      String.starts_with?(atom_str, "$") ->
        case Integer.parse(String.slice(atom_str, 1..-1//1)) do
          {_, ""} -> {:dollar_var, nil}
          _ -> :keep_as_is
        end

      true ->
        :keep_as_is
    end
  end

  defp classify_match_spec_elem({name, _, nil}) when is_atom(name) do
    {:elixir_var, name}
  end

  defp classify_match_spec_elem(_), do: :elixir_var

  defp extract_var_atom({name, _, nil}) when is_atom(name), do: name
  defp extract_var_atom(_), do: nil

  defp underscore_prefix?(nil), do: true

  defp underscore_prefix?(name) do
    String.starts_with?(Atom.to_string(name), "_")
  end

  defp make_dollar_var(n) do
    {:__block__, [delimiter: "\""], [String.to_atom("$#{n}")]}
  end

  defp build_lambda(captured_vars, body_kw) do
    body = extract_do_body_ast(body_kw)
    var_names = Enum.map(captured_vars, fn {_num, name} -> {name, [], nil} end)
    list_pattern = {:__block__, [], [var_names]}
    clause = {:->, [], [[list_pattern], body]}
    {:fn, [], [clause]}
  end

  defp extract_do_body_ast([{{:__block__, _, [:do]}, body}]), do: body
  defp extract_do_body_ast(_), do: {:__block__, [], []}

  defp build_enum_map_call(lambda) do
    enum_alias = {:__aliases__, [], [:Enum]}
    {{:., [], [enum_alias, :map]}, [], [lambda]}
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
