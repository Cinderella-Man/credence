defmodule Credence.Pattern.NoRemForParityCheck do
  @moduledoc """
  Detects manual parity checks via `rem/2` when `Integer.is_even/1` or
  `Integer.is_odd/1` exists (Elixir 1.14+).

  ## Examples

      # Bad
      rem(x, 2) == 0
      rem(x, 2) != 0
      rem(x, 2) == 1
      rem(x, 2) != 1

      # Good
      Integer.is_even(x)
      Integer.is_odd(x)
      Integer.is_odd(x)
      Integer.is_even(x)

  Works in any expression context including guards (since `Integer.is_even/1`
  and `Integer.is_odd/1` are guard-safe since Elixir 1.14).
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        node, acc ->
          case match_parity_check(node) do
            {:ok, _var, replacement} ->
              meta = elem(node, 1) || []
              issue = %Issue{
                rule: :no_rem_for_parity_check,
                message:
                  "Manual parity check via `rem/2`. Prefer `#{replacement}/1`.",
                meta: %{line: Keyword.get(meta, :line)}
              }

              {node, [issue | acc]}

            :error ->
              {node, acc}
          end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    transformed = transform_ast(ast)

    if transformed == ast do
      []
    else
      Credence.RuleHelpers.patches_from_diff(ast, transformed)
    end
  end

  # Walk the AST replacing parity checks everywhere. For defmodule nodes
  # that contain parity patterns, also insert `require Integer` if missing
  # (since Integer.is_even/is_odd are macros).
  #
  # Uses prewalk so that defmodule nodes are visited BEFORE their children.
  # This lets us: (1) detect raw `rem(x, 2)` patterns in the body, (2) replace
  # them AND add `require Integer` in one shot, then (3) return the fully
  # transformed defmodule — the children are skipped.
  defp transform_ast(ast) do
    Macro.prewalk(ast, fn
      {:defmodule, meta, [name, kw]} = node when is_list(kw) ->
        case extract_do_body(kw) do
          {:ok, body} ->
            if has_parity_check?(body) do
              replaced = replace_parity_checks(body)
              statements = block_to_list(replaced)

              new_body =
                if has_integer_require?(statements) do
                  replaced
                else
                  insert_integer_require(statements)
                end

              {:defmodule, meta, [name, replace_do_body(kw, new_body)]}
            else
              node
            end

          :error ->
            node
        end

      node ->
        case match_parity_check(node) do
          {:ok, var_ast, replacement} ->
            {{:., [], [{:__aliases__, [], [:Integer]}, replacement]}, [], [var_ast]}

          :error ->
            node
        end
    end)
  end

  defp has_parity_check?(body) do
    {_, found} =
      Macro.prewalk(body, false, fn
        _node, true ->
          {nil, true}

        node, false ->
          case match_parity_check(node) do
            {:ok, _, _} -> {node, true}
            :error -> {node, false}
          end
      end)

    found
  end

  defp replace_parity_checks(body) do
    Macro.postwalk(body, fn node ->
      case match_parity_check(node) do
        {:ok, var_ast, replacement} ->
          {{:., [], [{:__aliases__, [], [:Integer]}, replacement]}, [], [var_ast]}

        :error ->
          node
      end
    end)
  end

  defp block_to_list({:__block__, _, stmts}), do: stmts
  defp block_to_list(single), do: [single]

  defp has_integer_require?(statements) do
    Enum.any?(statements, fn
      {:require, _, [{:__aliases__, _, [:Integer]} | _]} -> true
      {:import, _, [{:__aliases__, _, [:Integer]} | _]} -> true
      _ -> false
    end)
  end

  defp insert_integer_require(statements) do
    require_ast = Sourceror.parse_string!("require Integer")
    insert_idx = find_directive_end(statements)
    {:__block__, [], List.insert_at(statements, insert_idx, require_ast)}
  end

  @directives [:use, :import, :require, :alias]

  defp find_directive_end(statements) do
    statements
    |> Enum.with_index()
    |> Enum.reduce(0, fn {stmt, idx}, last ->
      if directive_like?(stmt), do: idx + 1, else: last
    end)
  end

  defp directive_like?({tag, _, _}) when tag in @directives, do: true
  defp directive_like?({:@, _, [{:moduledoc, _, _}]}), do: true
  defp directive_like?(_), do: false

  defp extract_do_body([{{:__block__, _, [:do]}, body}]), do: {:ok, body}
  defp extract_do_body(_), do: :error

  defp replace_do_body([{{:__block__, m, [:do]}, _old}], new_body),
    do: [{{:__block__, m, [:do]}, new_body}]

  # Match: rem(x, 2) == 0  →  Integer.is_even(x)
  # Match: 0 == rem(x, 2)  →  Integer.is_even(x)
  # Match: rem(x, 2) != 0  →  Integer.is_odd(x)
  # Match: 0 != rem(x, 2)  →  Integer.is_odd(x)
  # Match: rem(x, 2) == 1  →  Integer.is_odd(x)
  # Match: 1 == rem(x, 2)  →  Integer.is_odd(x)
  # Match: rem(x, 2) != 1  →  Integer.is_even(x)
  # Match: 1 != rem(x, 2)  →  Integer.is_even(x)

  defp match_parity_check({:==, _, [left, right]}), do: match_eq(:eq, left, right)
  defp match_parity_check({:!=, _, [left, right]}), do: match_eq(:neq, left, right)
  defp match_parity_check(_), do: :error

  defp match_eq(op, left, right) do
    with {:ok, var_ast, val} <- extract_rem_and_val(left, right),
         replacement when replacement != nil <- replacement_for(op, val) do
      {:ok, var_ast, replacement}
    else
      _ ->
        with {:ok, var_ast, val} <- extract_rem_and_val(right, left),
             replacement when replacement != nil <- replacement_for(op, val) do
          {:ok, var_ast, replacement}
        else
          _ -> :error
        end
    end
  end

  defp extract_rem_and_val(rem_node, val_node) do
    with {:ok, var_ast} <- extract_rem_var(rem_node),
         {:ok, val} <- extract_int(val_node) do
      {:ok, var_ast, val}
    end
  end

  # rem(x, 2) — auto-imported Kernel.rem
  defp extract_rem_var({:rem, _, [var_ast, divisor]}) do
    case extract_int(divisor) do
      {:ok, 2} -> {:ok, var_ast}
      _ -> :error
    end
  end

  # Kernel.rem(x, 2) — explicit module call
  defp extract_rem_var({{:., _, [{:__aliases__, _, [:Kernel]}, :rem]}, _, [var_ast, divisor]}) do
    case extract_int(divisor) do
      {:ok, 2} -> {:ok, var_ast}
      _ -> :error
    end
  end

  defp extract_rem_var(_), do: :error

  defp extract_int({:__block__, _, [val]}) when is_integer(val), do: {:ok, val}
  defp extract_int(val) when is_integer(val), do: {:ok, val}
  defp extract_int(_), do: :error

  # op == :eq means ==, op == :neq means !=
  # val is 0 or 1
  defp replacement_for(:eq, 0), do: :is_even
  defp replacement_for(:eq, 1), do: :is_odd
  defp replacement_for(:neq, 0), do: :is_odd
  defp replacement_for(:neq, 1), do: :is_even
  defp replacement_for(_, _), do: nil
end
