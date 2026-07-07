defmodule Credence.Semantic.FixStructUpdateOnDynamicVariable do
  @moduledoc """
  Fixes the compiler warning where a tuple return containing a struct is
  destructured without a struct pattern, leaving the variable as `dynamic()`
  and causing "a struct for X is expected on struct update" warnings (fatal
  under --warnings-as-errors).

  The compiler emits a message like:

      a struct for AutocompleteTrie is expected on struct update:
          %AutocompleteTrie{node | weight: weight}
      but got type: dynamic()
      when defining the variable "node", you must also pattern match on "%AutocompleteTrie{}".

  The fix adds `%__MODULE__{} =` to the pattern match on the destructured
  variable. For example:

      {result, flag} = do_insert(trie, word)

  becomes:

      {%__MODULE__{} = result, flag} = do_insert(trie, word)
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "you must also pattern match on"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_struct_update_on_dynamic_variable,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{message: msg}) do
    var_name = extract_var_name(msg)

    with true <- is_binary(var_name) and var_name != "",
         {:ok, ast} <- Sourceror.parse_string(source) do
      var_atom = String.to_atom(var_name)

      result =
        Macro.prewalk(ast, fn
          # Assignment with tuple destructuring: {a, b} = expr
          {:=, assign_meta, [{:__block__, block_meta, [tuple]}, rhs]} = node ->
            if is_tuple(tuple) do
              case wrap_var_in_tuple(tuple, var_atom) do
                {:ok, new_tuple} ->
                  {:=, assign_meta, [{:__block__, block_meta, [new_tuple]}, rhs]}

                :error ->
                  node
              end
            else
              node
            end

          # Simple assignment: var = expr (not already a pattern match)
          {:=, meta, [{var, var_meta, nil} = _lhs, rhs]} = node ->
            if var == var_atom and not match?({:=, _, _}, rhs) do
              # Build: %__MODULE__{} = var = rhs
              struct_pattern = {:%, [], [{:__MODULE__, [], nil}, {:%{}, [], []}]}

              {:=, meta,
               [
                 {:=, [], [struct_pattern, {var, var_meta, nil}]},
                 rhs
               ]}
            else
              node
            end

          node ->
            node
        end)

      Sourceror.to_string(result)
    else
      _ -> source
    end
  end

  defp wrap_var_in_tuple(tuple, var_atom) do
    list = Tuple.to_list(tuple)

    case Enum.find_index(list, fn
           {^var_atom, _, nil} -> true
           _ -> false
         end) do
      nil ->
        :error

      idx ->
        new_list =
          List.update_at(list, idx, fn {var, meta, nil} ->
            struct_pattern = {:%, [], [{:__MODULE__, [], nil}, {:%{}, [], []}]}
            {:=, [], [struct_pattern, {var, meta, nil}]}
          end)

        {:ok, List.to_tuple(new_list)}
    end
  end

  defp extract_var_name(msg) do
    case Regex.run(~r/when defining the variable "(\w+)"/, msg) do
      [_, name] -> name
      _ -> nil
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
