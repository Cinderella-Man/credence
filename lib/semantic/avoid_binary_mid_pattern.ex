defmodule Credence.Semantic.AvoidBinaryMidPattern do
  @moduledoc """
  Fixes compiler errors about a binary field without size in the middle of a binary pattern.

  The Elixir compiler rejects patterns like `<<first, rest::binary, last>> = str`
  because a binary field without explicit size is only allowed at the end of a
  binary pattern. The error message is:

      a binary field without size is only allowed at the end of a binary pattern

  The fix rewrites the pattern to use `binary_part/3` for extracting the last byte:

      # Before (compiler error)
      <<first, rest::binary, last>> = str
      first == last

      # After (compiles cleanly)
      <<first, _rest::binary>> = str
      _last = binary_part(str, byte_size(str) - 1, 1)
      first == _last
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, "a binary field without size is only allowed at the end")
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :avoid_binary_mid_pattern,
      message: "Binary field without size in middle of pattern — rewriting with binary_part",
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    case parse(source) do
      {:ok, ast} ->
        transformed = transform(ast)

        if transformed == ast do
          source
        else
          rendered = Sourceror.to_string(transformed)

          case Sourceror.parse_string(rendered) do
            {:ok, re_parsed} ->
              patches = Credence.RuleHelpers.patches_from_diff(ast, re_parsed)

              if patches == [] do
                source
              else
                result = Sourceror.patch_string(source, patches)
                if result == source, do: source, else: result
              end

            {:error, _} ->
              source
          end
        end

      :error ->
        source
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line

  defp parse(source) do
    {:ok, Sourceror.parse_string!(source)}
  rescue
    _ -> :error
  end

  # Walk the AST looking for blocks that contain the binary mid-pattern.
  defp transform(ast) do
    Macro.postwalk(ast, fn
      {:__block__, meta, stmts} when is_list(stmts) ->
        case transform_block(stmts) do
          {:changed, new_stmts} -> {:__block__, meta, new_stmts}
          :unchanged -> {:__block__, meta, stmts}
        end

      node ->
        node
    end)
  end

  # Transform a block of statements: find the binary pattern assignment,
  # rewrite it, and update references to the last variable.
  defp transform_block(stmts) do
    case find_binary_pattern_index(stmts) do
      nil ->
        :unchanged

      idx ->
        {before, [assign | rest]} = Enum.split(stmts, idx)

        case extract_binary_pattern(assign) do
          {:ok, first_var, middle_var, last_var, rhs} ->
            new_assign = build_new_assignment(first_var, middle_var, last_var, rhs)
            new_rest = rewrite_var_references(rest, last_var, :"_#{last_var}")
            {:changed, before ++ [new_assign | new_rest]}

          :no_match ->
            :unchanged
        end
    end
  end

  # Find the index of the first assignment with <<first, rest::binary, last>> = ...
  defp find_binary_pattern_index(stmts) do
    Enum.find_index(stmts, fn
      {:=, _, [{:<<>>, _, [_first, {:"::", _, [_, {:binary, _, nil}]}, _last]}, _rhs]} ->
        true

      _ ->
        false
    end)
  end

  # Extract the components of the binary mid-pattern.
  defp extract_binary_pattern(
         {:=, _,
          [
            {:<<>>, _,
             [{first, _, nil}, {:"::", _, [{middle, _, nil}, {:binary, _, nil}]}, {last, _, nil}]},
            rhs
          ]}
       )
       when is_atom(first) and is_atom(middle) and is_atom(last) do
    {:ok, first, middle, last, rhs}
  end

  defp extract_binary_pattern(_), do: :no_match

  # Build the replacement: <<first, _middle::binary>> = rhs
  #                        _last = binary_part(rhs, byte_size(rhs) - 1, 1)
  defp build_new_assignment(first_var, middle_var, last_var, rhs) do
    new_last_var = :"_#{last_var}"
    new_middle_var = :"_#{middle_var}"

    new_binary_pattern =
      {:<<>>, [],
       [
         {first_var, [], nil},
         {:"::", [], [{new_middle_var, [], nil}, {:binary, [], nil}]}
       ]}

    binary_part_call =
      {:binary_part, [],
       [
         rhs,
         {:-, [],
          [
            {:byte_size, [], [rhs]},
            {:__block__, [token: "1"], [1]}
          ]},
         {:__block__, [token: "1"], [1]}
       ]}

    first_assign = {:=, [], [new_binary_pattern, rhs]}
    second_assign = {:=, [], [{new_last_var, [], nil}, binary_part_call]}

    {:__block__, [], [first_assign, second_assign]}
  end

  # Rename variable references in a list of AST nodes.
  defp rewrite_var_references(nodes, old_name, new_name) do
    Enum.map(nodes, fn node ->
      Macro.prewalk(node, fn
        {^old_name, meta, nil} -> {new_name, meta, nil}
        other -> other
      end)
    end)
  end
end
