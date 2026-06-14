defmodule Credence.Pattern.PreferReverseForPalindromeCheck do
  @moduledoc """
  Readability & performance rule: Detects index-based recursive palindrome
  checking via a private `palindrome_helper?/3` and replaces it with the
  idiomatic `list == Enum.reverse(list)`.

  ## Bad

      def palindrome_check(list) do
        palindrome_helper?(list, 0, length(list) - 1)
      end

      defp palindrome_helper?(_list, left_index, right_index)
           when left_index >= right_index do
        true
      end

      defp palindrome_helper?(list, left_index, right_index) do
        left_char = Enum.at(list, left_index)
        right_char = Enum.at(list, right_index)
        if left_char == right_char do
          palindrome_helper?(list, left_index + 1, right_index - 1)
        else
          false
        end
      end

  ## Good

      def palindrome_check(list) do
        list == Enum.reverse(list)
      end
  """
  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    case extract_do_body(ast) do
      {:ok, stmts} ->
        if contains_palindrome_helper_pattern?(stmts) do
          {_, meta, _} = find_palindrome_check_def(stmts)
          line = Keyword.get(meta, :line)

          [
            %Issue{
              rule: :prefer_reverse_for_palindrome_check,
              message:
                "Index-based recursive palindrome check detected. " <>
                  "Replace with `list == Enum.reverse(list)` for clarity and performance.",
              meta: %{line: line}
            }
          ]
        else
          []
        end

      :error ->
        []
    end
  end

  @impl true
  def fix_patches(ast, opts) do
    source = Keyword.get(opts, :source) || Sourceror.to_string(ast)

    case extract_do_body(ast) do
      {:ok, stmts} ->
        if contains_palindrome_helper_pattern?(stmts) do
          RuleHelpers.patches_from_ast_transform(ast, source, &rebuild_palindrome_blocks/1)
        else
          []
        end

      :error ->
        []
    end
  end

  defp rebuild_palindrome_blocks(input) do
    Macro.prewalk(input, fn
      {:__block__, meta, stmts} = node when is_list(stmts) ->
        if contains_palindrome_helper_pattern?(stmts) do
          {:__block__, meta, rebuild_body(stmts)}
        else
          node
        end

      node ->
        node
    end)
  end

  defp extract_do_body({:defmodule, _, [_, kw]}) when is_list(kw) do
    case RuleHelpers.extract_do_body(kw) do
      {:ok, {:__block__, _, stmts}} when is_list(stmts) -> {:ok, stmts}
      {:ok, single} -> {:ok, [single]}
      :error -> :error
    end
  end

  defp extract_do_body(_), do: :error

  defp contains_palindrome_helper_pattern?(stmts) do
    has_palindrome_check_def?(stmts) and
      has_base_case_helper?(stmts) and
      has_recursive_case_helper?(stmts)
  end

  defp find_palindrome_check_def(stmts) do
    Enum.find(stmts, fn
      {:def, _, [{:palindrome_check, _, [_arg]}, _]} -> true
      _ -> false
    end)
  end

  defp has_palindrome_check_def?(stmts) do
    Enum.any?(stmts, fn
      {:def, _, [{:palindrome_check, _, [_arg]}, body_kw]} when is_list(body_kw) ->
        case RuleHelpers.extract_do_body(body_kw) do
          {:ok, body} -> palindrome_helper_call?(body)
          _ -> false
        end

      _ ->
        false
    end)
  end

  defp palindrome_helper_call?({:palindrome_helper?, _, [_, zero, length_minus_one]}) do
    literal_zero?(zero) and length_minus_one?(length_minus_one)
  end

  defp palindrome_helper_call?({:__block__, _, [inner]}),
    do: palindrome_helper_call?(inner)

  defp palindrome_helper_call?(_), do: false

  defp literal_zero?({:__block__, _, [0]}), do: true
  defp literal_zero?(0), do: true
  defp literal_zero?(_), do: false

  defp length_minus_one?({:-, _, [length_call, one]}) do
    length_call?(length_call) and literal_one?(one)
  end

  defp length_minus_one?(_), do: false

  defp length_call?({:length, _, [_]}), do: true
  defp length_call?(_), do: false

  defp literal_one?({:__block__, _, [1]}), do: true
  defp literal_one?(1), do: true
  defp literal_one?(_), do: false

  defp has_base_case_helper?(stmts) do
    Enum.any?(stmts, fn
      {:defp, _, [{:when, _, [head, guard]}, body_kw]} when is_list(body_kw) ->
        match?({:palindrome_helper?, _, [_, _, _]}, head) and
          base_case_guard?(guard)

      _ ->
        false
    end)
  end

  defp base_case_guard?({:>=, _, [{left, _, nil}, {right, _, nil}]})
       when is_atom(left) and is_atom(right) do
    true
  end

  defp base_case_guard?(_), do: false

  defp has_recursive_case_helper?(stmts) do
    Enum.any?(stmts, fn
      {:defp, _, [{:palindrome_helper?, _, args}, body_kw]} when is_list(args) ->
        case RuleHelpers.extract_do_body(body_kw) do
          {:ok, body} -> recursive_case_body?(body, args)
          _ -> false
        end

      _ ->
        false
    end)
  end

  defp recursive_case_body?({:__block__, _, stmts}, args) when is_list(stmts) do
    Enum.any?(stmts, fn
      {:if, _, [_comparison, branches]} ->
        recursive_call_in_branch?(branches, args)

      _ ->
        false
    end)
  end

  defp recursive_case_body?(_, _), do: false

  defp recursive_call_in_branch?(branches, _args) when is_list(branches) do
    case RuleHelpers.extract_do_body(branches) do
      {:ok, body} -> recursive_palindrome_call?(body)
      _ -> false
    end
  end

  defp recursive_call_in_branch?(_, _), do: false

  defp recursive_palindrome_call?({:palindrome_helper?, _, [list, incr, decr]}) do
    increment?(incr) and decrement?(decr) and variable?(list)
  end

  defp recursive_palindrome_call?({:__block__, _, [inner]}),
    do: recursive_palindrome_call?(inner)

  defp recursive_palindrome_call?(_), do: false

  defp increment?({:+, _, [_, {:__block__, _, [1]}]}), do: true
  defp increment?({:+, _, [_, 1]}), do: true
  defp increment?(_), do: false

  defp decrement?({:-, _, [_, {:__block__, _, [1]}]}), do: true
  defp decrement?({:-, _, [_, 1]}), do: true
  defp decrement?(_), do: false

  defp variable?({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: true
  defp variable?(_), do: false

  defp rebuild_body(stmts) do
    Enum.flat_map(stmts, fn
      {:def, _, [{:palindrome_check, meta, [arg]}, _body_kw]} ->
        list_var = extract_var(arg)
        new_body = list_reverse_equals(list_var)

        [
          {:def, meta,
           [
             {:palindrome_check, meta, [arg]},
             [{{:__block__, [], [:do]}, new_body}]
           ]}
        ]

      {:defp, _, [{:palindrome_helper?, _, _}, _]} ->
        []

      {:defp, _, [{:when, _, [{:palindrome_helper?, _, _}, _]}, _]} ->
        []

      other ->
        [other]
    end)
  end

  defp extract_var({:_, _, _}), do: {:list, [], nil}
  defp extract_var({name, _, _} = var) when is_atom(name), do: var
  defp extract_var(_), do: {:list, [], nil}

  defp list_reverse_equals(list_var) do
    reverse_call = {{:., [], [{:__aliases__, [], [:Enum]}, :reverse]}, [], [list_var]}
    {:==, [], [list_var, reverse_call]}
  end
end
