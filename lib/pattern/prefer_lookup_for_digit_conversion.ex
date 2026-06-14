defmodule Credence.Pattern.PreferLookupForDigitConversion do
  @moduledoc """
  Detects the anti-pattern of mapping each hex digit (0–15) to its character
  representation via 16 separate function clauses, and rewrites it to a single
  clause using `String.at/2` on the lookup string `"0123456789ABCDEF"`.

  ## Bad

      defp hex_digit(0), do: "0"
      defp hex_digit(1), do: "1"
      defp hex_digit(2), do: "2"
      defp hex_digit(3), do: "3"
      defp hex_digit(4), do: "4"
      defp hex_digit(5), do: "5"
      defp hex_digit(6), do: "6"
      defp hex_digit(7), do: "7"
      defp hex_digit(8), do: "8"
      defp hex_digit(9), do: "9"
      defp hex_digit(10), do: "A"
      defp hex_digit(11), do: "B"
      defp hex_digit(12), do: "C"
      defp hex_digit(13), do: "D"
      defp hex_digit(14), do: "E"
      defp hex_digit(15), do: "F"

  ## Good

      defp hex_digit(remainder) do
        "0123456789ABCDEF"
        |> String.at(remainder)
      end

  The 16-clause form is verbose and hard to maintain. A single string-lookup
  clause is more concise, idiomatic, and equally efficient.
  """
  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @hex_chars "0123456789ABCDEF"
  @expected_values for(i <- 0..15, do: {i, String.at(@hex_chars, i)}) |> Map.new()

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:__block__, _, stmts} = node, acc when is_list(stmts) ->
          issues = detect_hex_digit_clauses(stmts) ++ acc
          {node, issues}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, opts) do
    source = Keyword.fetch!(opts, :source)

    RuleHelpers.patches_from_ast_transform(ast, source, fn input ->
      Macro.postwalk(input, fn
        {:__block__, meta, stmts} when is_list(stmts) ->
          case replace_hex_digit_clauses(stmts) do
            {:ok, new_stmts} -> {:__block__, meta, new_stmts}
            :no_change -> {:__block__, meta, stmts}
          end

        node ->
          node
      end)
    end)
  end

  # ── Detection ─────────────────────────────────────────────────────────

  defp detect_hex_digit_clauses(stmts) do
    stmts
    |> collect_defp_by_name()
    |> Enum.flat_map(fn {_name_arity, clauses} ->
      case extract_hex_mapping(clauses) do
        {:ok, mapping} ->
          if complete_hex_mapping?(mapping) do
            meta = elem(hd(clauses), 1)
            [build_issue(meta)]
          else
            []
          end

        :error ->
          []
      end
    end)
  end

  # ── Fix ───────────────────────────────────────────────────────────────

  defp replace_hex_digit_clauses(stmts) do
    case find_hex_digit_group(stmts) do
      {:ok, name, clause_indices} ->
        replacement = build_replacement(name)
        indices_set = MapSet.new(clause_indices)

        new_stmts =
          stmts
          |> Enum.with_index()
          |> Enum.flat_map(fn {stmt, idx} ->
            cond do
              idx == hd(clause_indices) ->
                [replacement]

              MapSet.member?(indices_set, idx) ->
                []

              true ->
                [stmt]
            end
          end)

        {:ok, new_stmts}

      :error ->
        :no_change
    end
  end

  defp find_hex_digit_group(stmts) do
    stmts
    |> collect_defp_by_name()
    |> Enum.find_value(:error, fn {_name_arity, clauses} ->
      case extract_hex_mapping(clauses) do
        {:ok, mapping} ->
          if complete_hex_mapping?(mapping) do
            indices =
              Enum.map(clauses, fn {_, _, _} = clause ->
                Enum.find_index(stmts, &(&1 == clause))
              end)

            name = get_function_name(hd(clauses))
            {:ok, name, indices}
          end

        :error ->
          nil
      end
    end)
  end

  defp get_function_name({:defp, _, [{name, _, _} | _]}), do: name

  defp build_replacement(name) do
    # Build: defp name(remainder) do "0123456789ABCDEF" |> String.at(remainder) end
    param = {:remainder, [], Elixir}
    lookup_string = {:__block__, [delimiter: "\""], [@hex_chars]}

    string_at_call =
      {{:., [], [{:__aliases__, [], [:String]}, :at]}, [], [param]}

    pipe = {:|>, [newlines: 1], [lookup_string, string_at_call]}

    body = [{{:__block__, [], [:do]}, pipe}]

    {:defp, [],
     [
       {name, [], [param]},
       body
     ]}
  end

  # ── Helpers ───────────────────────────────────────────────────────────

  defp collect_defp_by_name(stmts) do
    stmts
    |> Enum.reduce(%{}, fn
      {:defp, _, [{name, _, args} | _]} = clause, acc
      when is_list(args) and length(args) == 1 ->
        key = {name, 1}
        Map.update(acc, key, [clause], &(&1 ++ [clause]))

      _, acc ->
        acc
    end)
  end

  defp extract_hex_mapping(clauses) do
    mappings =
      Enum.map(clauses, fn {:defp, _, [{_name, _, [arg]}, body_kw]} ->
        with {:ok, int} <- extract_integer(arg),
             {:ok, str} <- extract_string(body_kw) do
          {int, str}
        else
          _ -> :error
        end
      end)

    if Enum.any?(mappings, &(&1 == :error)) do
      :error
    else
      {:ok, Map.new(mappings)}
    end
  end

  defp extract_integer({:__block__, _meta, [val]})
       when is_integer(val) and val >= 0 and val <= 15,
       do: {:ok, val}

  defp extract_integer({:__block__, meta, _val}) do
    case Keyword.get(meta, :token) do
      nil -> :error
      token -> parse_token_integer(token)
    end
  end

  defp extract_integer(_), do: :error

  defp parse_token_integer(token) do
    case Integer.parse(token) do
      {n, ""} when n >= 0 and n <= 15 -> {:ok, n}
      _ -> :error
    end
  end

  defp extract_string([{{:__block__, _, [:do]}, {:__block__, _, [str]}}])
       when is_binary(str) and byte_size(str) == 1,
       do: {:ok, str}

  defp extract_string(_), do: :error

  defp complete_hex_mapping?(mapping) do
    map_size(mapping) == 16 and mapping == @expected_values
  end

  defp build_issue(meta) do
    %Issue{
      rule: :prefer_lookup_for_digit_conversion,
      message:
        "16 separate function clauses for hex digit conversion. " <>
          "Use a single clause with string lookup instead:\n" <>
          "  \"0123456789ABCDEF\" |> String.at(remainder)",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
