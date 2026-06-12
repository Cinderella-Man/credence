defmodule Credence.Pattern.PreferStringCapitalize do
  @moduledoc """
  Detects the verbose manual first-character capitalization pattern and
  replaces it with idiomatic `String.capitalize/1`.

  ## Bad

      defp capitalize_string(""), do: ""
      defp capitalize_string(string) do
        first_char = String.first(string) |> String.upcase()
        rest = String.slice(string, 1, byte_size(string) - String.length(first_char)) |> String.downcase()
        first_char <> rest
      end

  ## Good

      defp capitalize_string(""), do: ""
      defp capitalize_string(string), do: String.capitalize(string)
  """
  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:defp, meta, _args} = node, issues ->
          if capitalize_pattern?(node) do
            {node, [build_issue(meta) | issues]}
          else
            {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    {_ast, patches} =
      Macro.prewalk(ast, [], fn
        {:defp, _meta, _args} = node, acc ->
          case extract_capitalize_var(node) do
            {:ok, _} ->
              case Sourceror.get_range(node) do
                %Sourceror.Range{} = range ->
                  patch = %{range: range, change: "defp capitalize_string(string), do: String.capitalize(string)"}
                  {node, [patch | acc]}

                _ ->
                  {node, acc}
              end

            :error ->
              {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(patches)
  end

  # Check if a defp node matches the capitalize anti-pattern
  defp capitalize_pattern?(node) do
    match?({:ok, _}, extract_capitalize_var(node))
  end

  # Extract the variable name if the defp matches the capitalize pattern
  defp extract_capitalize_var({:defp, _meta, [fn_head, body_kw]}) do
    with {:ok, body} <- extract_do_body(body_kw),
         {:__block__, _, stmts} when is_list(stmts) <- body,
         true <- length(stmts) == 3,
         result when not is_nil(result) <- match_capitalize_stmts(stmts) do
      # Extract the parameter name from fn_head
      case fn_head do
        {:capitalize_string, _, [{param, _, nil}]} when is_atom(param) ->
          {:ok, param}

        _ ->
          {:ok, :unknown}
      end
    else
      _ -> :error
    end
  end

  defp extract_capitalize_var(_), do: :error

  # Match the three statements of the capitalize pattern
  defp match_capitalize_stmts([assign1, assign2, concat]) do
    with {:ok, first_char_var, string_var} <- match_first_char_upcase(assign1),
         {:ok, rest_var, ^first_char_var} <- match_rest_downcase(assign2, string_var),
         true <- match_concat(concat, first_char_var, rest_var) do
      {first_char_var, rest_var, string_var}
    else
      _ -> nil
    end
  end

  defp match_capitalize_stmts(_), do: nil

  # Match: first_char = String.first(string) |> String.upcase()
  defp match_first_char_upcase(
         {:=, _,
          [
            {first_char, _, nil},
            {:|>, _,
             [
               {{:., _, [{:__aliases__, _, [:String]}, :first]}, _, [{var, _, nil}]},
               {{:., _, [{:__aliases__, _, [:String]}, :upcase]}, _, []}
             ]}
          ]}
       )
       when is_atom(first_char) and is_atom(var) do
    {:ok, first_char, var}
  end

  defp match_first_char_upcase(_), do: :error

  # Match: rest = String.slice(var, 1, byte_size(var) - String.length(first_char)) |> String.downcase()
  defp match_rest_downcase(
         {:=, _,
          [
            {rest, _, nil},
            pipe_chain
          ]},
         string_var
       )
       when is_atom(rest) and is_atom(string_var) do
    case pipe_chain do
      {:|>, _,
       [
         {{:., _, [{:__aliases__, _, [:String]}, :slice]}, _,
          [
            {var2, _, nil},
            {:__block__, _, [1]},
            {:-, _,
             [
               {:byte_size, _, [{var3, _, nil}]},
               {{:., _, [{:__aliases__, _, [:String]}, :length]}, _,
                [{first_char2, _, nil}]}
             ]}
          ]},
         {{:., _, [{:__aliases__, _, [:String]}, :downcase]}, _, []}
       ]}
       when is_atom(var2) and is_atom(var3) and is_atom(first_char2) ->
        if var2 == var3 and var2 == string_var do
          {:ok, rest, first_char2}
        else
          :error
        end

      _ ->
        :error
    end
  end

  defp match_rest_downcase(_, _), do: :error

  # Match: first_char <> rest
  defp match_concat(
         {:<>, _, [{first_char, _, nil}, {rest, _, nil}]},
         expected_first_char,
         expected_rest
       )
       when is_atom(first_char) and is_atom(rest) do
    first_char == expected_first_char and rest == expected_rest
  end

  defp match_concat(_, _, _), do: false

  # Extract do body from keyword list
  defp extract_do_body(kw) when is_list(kw) do
    Enum.find_value(kw, :error, fn
      {{:__block__, _, [:do]}, body} -> {:ok, body}
      _ -> nil
    end)
  end

  defp extract_do_body(_), do: :error

  defp build_issue(meta) do
    %Issue{
      rule: :prefer_string_capitalize,
      message:
        "Use `String.capitalize/1` instead of manually capitalizing the first character " <>
          "with `String.first/1 |> String.upcase/0` and slicing the rest.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
