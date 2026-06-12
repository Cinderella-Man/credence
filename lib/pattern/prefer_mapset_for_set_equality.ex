defmodule Credence.Pattern.PreferMapsetForSetEquality do
  @moduledoc """
  Detects `Enum.uniq() |> Enum.sort()` used to build two sorted unique
  lists that are then compared with `==` for set-equality checking, and
  rewrites them to use `MapSet.new/1` directly.

  ## Why this matters

  The pattern `Enum.uniq() |> Enum.sort()` creates an unnecessary
  intermediate list and sort when the only goal is to compare two
  collections for equal-element membership (set equality). `MapSet.new/1`
  is semantically explicit and avoids the unnecessary sort overhead.

  Both `Enum.uniq/1` and `MapSet.new/1` deduplicate using exact (`===`)
  equality — `1` and `1.0` stay distinct under both — so the set-membership
  semantics are preserved.

  ## Bad

      first_set = String.codepoints(first) |> Enum.uniq() |> Enum.sort()
      second_set = String.codepoints(second) |> Enum.uniq() |> Enum.sort()
      first_set == second_set

  ## Good

      MapSet.new(String.codepoints(first)) == MapSet.new(String.codepoints(second))
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, acc ->
        case check_block(node) do
          {:ok, issues} -> {node, issues ++ acc}
          :no -> {node, acc}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      {:__block__, _, stmts} = node when is_list(stmts) ->
        case check_block({:__block__, [], stmts}) do
          {:ok, _issues} ->
            {eq_var1, eq_var2} = find_equality_vars(stmts)

            with {:ok, arg1} <- find_sorted_uniq_assignment(stmts, eq_var1),
                 {:ok, arg2} <- find_sorted_uniq_assignment(stmts, eq_var2) do
              make_mapset_eq(arg1, arg2)
            else
              _ -> node
            end

          :no ->
            node
        end

      node ->
        node
    end)
  end

  # Check if a block node matches the pattern
  defp check_block({:__block__, meta, stmts}) when is_list(stmts) do
    {assigns, rest} = Enum.split_with(stmts, &match?({:=, _, _}, &1))

    sorted_uniq_assigns =
      Enum.filter(assigns, fn {:=, _, [_, rhs]} ->
        sorted_uniq_pipeline?(rhs)
      end)

    case sorted_uniq_assigns do
      [_, _] ->
        # Two sorted-uniq assignments: check if `rest` has an `==` comparing them
        var_names =
          MapSet.new(sorted_uniq_assigns, fn {:=, _, [{name, _, _}, _]} -> name end)

        equality? =
          Enum.any?(rest, fn
            {:==, _, [{n1, _, _}, {n2, _, _}]} ->
              MapSet.size(var_names) == 2 and MapSet.member?(var_names, n1) and
                MapSet.member?(var_names, n2)

            _ ->
              false
          end)

        if equality? do
          line = Keyword.get(meta, :line) || find_line(stmts)

          issue = %Issue{
            rule: :prefer_mapset_for_set_equality,
            message:
              "Using `Enum.uniq() |> Enum.sort()` for set equality is non-idiomatic. " <>
                "Use `MapSet.new/1` directly — it is semantically explicit and avoids " <>
                "unnecessary sort overhead.",
            meta: %{line: line}
          }

          {:ok, [issue]}
        else
          :no
        end

      _ ->
        :no
    end
  end

  defp check_block(_), do: :no

  # Check if an AST node is: expr |> Enum.uniq() |> Enum.sort()
  defp sorted_uniq_pipeline?(
         {:|>, _,
          [
            {:|>, _, [_, {{:., _, [{:__aliases__, _, [:Enum]}, :uniq]}, _, []}]},
            {{:., _, [{:__aliases__, _, [:Enum]}, :sort]}, _, []}
          ]}
       ),
       do: true

  defp sorted_uniq_pipeline?(_), do: false

  # Find the equality comparison in statements and return {var1_name, var2_name}
  defp find_equality_vars(stmts) do
    Enum.find_value(stmts, fn
      {:==, _, [{n1, _, _}, {n2, _, _}]} when is_atom(n1) and is_atom(n2) -> {n1, n2}
      _ -> nil
    end)
  end

  # Find the assignment `var_name = expr |> Enum.uniq() |> Enum.sort()`
  # and return the inner expression (before Enum.uniq)
  defp find_sorted_uniq_assignment(stmts, var_name) do
    Enum.find_value(stmts, fn
      {:=, _, [{name, _, _}, rhs]} when name == var_name ->
        extract_codepoints_arg(rhs)

      _ ->
        nil
    end)
  end

  # Extract the inner expression from: expr |> Enum.uniq() |> Enum.sort()
  defp extract_codepoints_arg(
         {:|>, _,
          [
            {:|>, _, [inner, {{:., _, [{:__aliases__, _, [:Enum]}, :uniq]}, _, []}]},
            {{:., _, [{:__aliases__, _, [:Enum]}, :sort]}, _, []}
          ]}
       ) do
    case inner do
      {{:., _, [_, _]}, _, _} -> {:ok, inner}
      _ -> nil
    end
  end

  defp extract_codepoints_arg(_), do: nil

  # Build: MapSet.new(arg1) == MapSet.new(arg2)
  defp make_mapset_eq(arg1, arg2) do
    {:==, [],
     [
       {{:., [], [{:__aliases__, [], [:MapSet]}, :new]}, [], [arg1]},
       {{:., [], [{:__aliases__, [], [:MapSet]}, :new]}, [], [arg2]}
     ]}
  end

  defp find_line(stmts) do
    Enum.find_value(stmts, 1, fn
      {_, meta, _} when is_list(meta) -> Keyword.get(meta, :line)
      _ -> nil
    end)
  end
end
