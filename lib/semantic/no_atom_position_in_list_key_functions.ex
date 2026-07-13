defmodule Credence.Semantic.NoAtomPositionInListKeyFunctions do
  @moduledoc """
  Fixes `List.keytake/3`, `List.keyfind/3`, and `List.keydelete/3` calls
  where an atom is passed as the position argument.

  LLMs frequently pass an atom key name (e.g., `:ref`) as the position
  argument to these functions, but they require an integer index. The
  compiler may emit a module-redefinition warning when the LLM-generated
  code redefines an existing module containing this misuse. The
  deterministic fix replaces:

      case List.keytake(list, key, :field) do
        {_, remaining} -> {:ok, remaining}
        nil -> {:error, list}
      end

  with:

      if Enum.any?(list, fn elem -> elem.field == key end) do
        {:ok, Enum.reject(list, fn elem -> elem.field == key end)}
      else
        {:error, list}
      end

  and standalone `List.keyfind/3` → `Enum.find/2` and
  `List.keydelete/3` → `Enum.reject/2`.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "redefining module"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_atom_position_in_list_key_functions,
      message:
        "Atom passed as position to List.keytake/keyfind/keydelete. " <>
          "These functions require an integer position. " <>
          "Use Enum.any?/Enum.reject or Enum.find instead.",
      meta: %{line: line(diagnostic)}
    }
  end

  @doc false
  def should_report?(_diagnostic, source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} -> has_atom_position_list_key_call?(ast)
      _ -> false
    end
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          # case List.keytake(list, key, :atom) do ... end
          {:case, _,
           [
             {{:., _, [{:__aliases__, _, [:List]}, :keytake]}, _,
              [list, key, {:__block__, _, [atom]}]},
             [{{:__block__, _, [:do]}, clauses}]
           ]} = node,
          acc
          when is_atom(atom) and not is_nil(atom) ->
            case transform_keytake_case(list, key, atom, clauses) do
              {:ok, new_node} -> {new_node, true}
              :error -> {node, acc}
            end

          # List.keyfind(list, key, :atom) standalone
          {{:., _, [{:__aliases__, _, [:List]}, :keyfind]}, _,
           [list, key, {:__block__, _, [atom]}]},
          _acc
          when is_atom(atom) and not is_nil(atom) ->
            var = derive_lambda_var(list)
            {build_enum_call(:find, list, var, atom, key), true}

          # List.keydelete(list, key, :atom) standalone
          {{:., _, [{:__aliases__, _, [:List]}, :keydelete]}, _,
           [list, key, {:__block__, _, [atom]}]},
          _acc
          when is_atom(atom) and not is_nil(atom) ->
            var = derive_lambda_var(list)
            {build_enum_call(:reject, list, var, atom, key), true}

          node, acc ->
            {node, acc}
        end)

      if changed, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  # Transform case List.keytake(list, key, :atom) into if/else.
  defp transform_keytake_case(list, key, atom, clauses) do
    with [{:->, _, [[{:__block__, _, [tuple_pat]}], success_body]},
          {:->, _, [[{:__block__, _, [nil]}], failure_body]}] <- clauses,
         true <- is_tuple(tuple_pat) and tuple_size(tuple_pat) == 2,
         {first, {remaining_var, _, nil}} <- tuple_pat,
         true <- is_atom(remaining_var) and remaining_var != :_,
         true <- underscore_var?(first) do
      var = derive_lambda_var(list)
      any_cond = build_enum_call(:any?, list, var, atom, key)
      reject_call = build_enum_call(:reject, list, var, atom, key)
      new_success = replace_var(success_body, remaining_var, reject_call)

      new_node =
        {:if, [do: [line: 0, column: 0], end: [line: 0, column: 0]],
         [
           any_cond,
           [
             {{:__block__, [], [:do]}, new_success},
             {{:__block__, [], [:else]}, failure_body}
           ]
         ]}

      {:ok, new_node}
    else
      _ -> :error
    end
  end

  # Build Enum.func(list, fn var -> var.atom == key end)
  defp build_enum_call(func, list, var, atom, key) do
    fn_expr =
      {:fn, [],
       [
         {:->, [],
          [
            [{var, [], nil}],
            {:==, [],
             [{{:., [], [{var, [], nil}, atom]}, [no_parens: true], []}, key]}
          ]}
       ]}

    {{:., [], [{:__aliases__, [], [:Enum]}, func]}, [], [list, fn_expr]}
  end

  # Replace all occurrences of var_name in ast with replacement.
  defp replace_var(ast, var_name, replacement) do
    Macro.prewalk(ast, fn
      {^var_name, _, ctx} when is_atom(ctx) -> replacement
      node -> node
    end)
  end

  # Derive a lambda variable name from the list variable.
  # timers -> t, users -> u, data -> d, otherwise -> elem
  defp derive_lambda_var({var_name, _, nil}) when is_atom(var_name) do
    first = var_name |> Atom.to_string() |> String.first()

    case first do
      <<c>> when c in ?a..?z -> String.to_atom(first)
      _ -> :elem
    end
  end

  defp derive_lambda_var(_), do: :elem

  # True for underscore-prefixed variables: _, _removed, etc.
  defp underscore_var?({:_, _, _}), do: true

  defp underscore_var?({name, _, nil}) when is_atom(name) do
    name |> Atom.to_string() |> String.starts_with?("_")
  end

  defp underscore_var?(_), do: false

  # Walk AST and check for List.keytake/keyfind/keydelete with atom position.
  defp has_atom_position_list_key_call?(ast) do
    {_, found} =
      Macro.prewalk(ast, false, fn node, acc ->
        {node, acc || is_atom_position_list_key_call?(node)}
      end)

    found
  end

  defp is_atom_position_list_key_call?(
         {{:., _, [{:__aliases__, _, [:List]}, func]}, _,
          [_, _, {:__block__, _, [atom]}]}
       )
       when func in [:keytake, :keyfind, :keydelete] and is_atom(atom) and not is_nil(atom),
       do: true

  defp is_atom_position_list_key_call?(_), do: false

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
