defmodule Credence.Semantic.UndefinedFunction do
  @moduledoc """
  Fixes compiler diagnostics about undefined, private, or deprecated functions.

  Handles both module-qualified calls (`Module.function`) from compiler warnings
  and bare local calls (`function`) from compiler errors. Maintains hardcoded
  replacement maps for known patterns, with a FunctionMatcher fallback for
  unknown functions.

  ## Replacement types

  Qualified (module-prefixed):

      {:rename, mod, fun}                   — swap Module.function, keep args
      {:literal, text}                      — replace Module.function() with literal
      {:literal_with_neg, pos, neg}         — literal, negation-aware
      {:rename_add_arg, mod, fun, arg}      — rename + append extra argument
      {:rename_negate_arg, mod, fun, index} — rename + negate argument at index

  Local (bare calls):

      {:literal, text}         — replace name() with text
      {:rename, mod, fun}      — replace name( with mod.fun(
      {:rename_local, new}     — replace name( with new(
      {:wrap_args, mod, fun}   — replace name(a,b,c) with mod.fun([a,b,c])
      :to_range                — replace range(...) with Elixir range literal
  """
  use Credence.Semantic.Rule
  alias Credence.Issue

  # ── Qualified replacements ─────────────────────────────────────

  @qualified_replacements %{
    # Wrong module for real function
    {"Enum", "last", 1} => {:rename, "List", "last"},
    {"Enum", "last", 0} => {:rename, "List", "last"},
    {"List", "reverse", 1} => {:rename, "Enum", "reverse"},

    # Deprecated
    {"Enum", "partition", 2} => {:rename, "Enum", "split_with"},

    # Hallucinated Float infinity
    {"Float", "NegInfinity", 0} => {:literal, ":neg_infinity"},
    {"Float", "PositiveInfinity", 0} => {:literal, ":infinity"},
    {"Float", "NegInf", 0} => {:literal, ":neg_infinity"},
    {"Float", "Infinity", 0} => {:literal, ":infinity"},
    {"Float", "inf", 0} => {:literal_with_neg, ":infinity", ":neg_infinity"},

    # Hallucinated Integer bounds
    {"Integer", "min_value", 0} => {:literal, ":neg_infinity"},
    {"Integer", "max_value", 0} => {:literal, ":infinity"},

    # Hallucinated List operations
    {"List", "pop", 1} => {:rename, "List", "last"},
    {"List", "drop", 2} => {:rename, "Enum", "drop"},

    # Wrong module
    {"Enum", "cycle", 1} => {:rename, "Stream", "cycle"},

    # Hallucinated List.second — no such function, use Enum.at(list, 1)
    {"List", "second", 1} => {:rename_add_arg, "Enum", "at", "1"},

    # Hallucinated Enum.take_last — use Enum.take(list, -n)
    {"Enum", "take_last", 2} => {:rename_negate_arg, "Enum", "take", 1}
  }

  # ── Local replacements ─────────────────────────────────────────

  @local_replacements %{
    # Python float('inf')
    {"infinity", 0} => {:literal, ":math.inf()"},

    # Python max/min — polymorphic
    {"max", 1} => {:rename, "Enum", "max"},
    {"max", 3} => {:wrap_args, "Enum", "max"},
    {"max", 4} => {:wrap_args, "Enum", "max"},
    {"max", 5} => {:wrap_args, "Enum", "max"},
    {"min", 1} => {:rename, "Enum", "min"},
    {"min", 3} => {:wrap_args, "Enum", "min"},
    {"min", 4} => {:wrap_args, "Enum", "min"},
    {"min", 5} => {:wrap_args, "Enum", "min"},

    # Python built-ins
    {"sum", 1} => {:rename, "Enum", "sum"},
    {"sorted", 1} => {:rename, "Enum", "sort"},
    {"len", 1} => {:rename_local, "length"},
    {"reversed", 1} => {:rename, "Enum", "reverse"},

    # Python range()
    {"range", 1} => :to_range,
    {"range", 2} => :to_range,
    {"range", 3} => :to_range
  }

  # ── match? ─────────────────────────────────────────────────────

  @impl true
  def match?(%{severity: :warning, message: msg}) do
    (String.contains?(msg, "is undefined or private") or
       String.contains?(msg, "is deprecated")) and
      parse_qualified_ref(msg) != nil
  end

  def match?(%{severity: :error, message: msg}) do
    String.contains?(msg, "undefined function") and parse_local_ref(msg) != nil
  end

  def match?(_), do: false

  # ── to_issue ───────────────────────────────────────────────────

  @impl true
  def to_issue(%{message: msg, position: position}) do
    %Issue{
      rule: :undefined_function,
      message: msg,
      meta: %{line: extract_line(position)}
    }
  end

  # ── fix ────────────────────────────────────────────────────────

  @impl true
  def fix(source, %{message: msg, position: position}) do
    line_no = extract_line(position)

    case parse_diagnostic(msg) do
      {:qualified, {mod, fun, arity}} ->
        fix_qualified(source, line_no, mod, fun, arity)

      {:local, {name, arity}} ->
        fix_local(source, line_no, name, arity, msg)

      nil ->
        source
    end
  end

  # ── Qualified fix ──────────────────────────────────────────────

  defp fix_qualified(source, line_no, mod, fun, arity) do
    case Map.get(@qualified_replacements, {mod, fun, arity}) do
      {:rename, new_mod, new_fun} ->
        replace_first_on_line(source, line_no, "#{mod}.#{fun}", "#{new_mod}.#{new_fun}")

      {:literal, text} ->
        replace_literal(source, line_no, mod, fun, text)

      {:literal_with_neg, pos_text, neg_text} ->
        replace_literal_with_neg(source, line_no, mod, fun, pos_text, neg_text)

      {:rename_add_arg, new_mod, new_fun, extra_arg} ->
        rename_add_arg_on_line(
          source, line_no, "#{mod}.#{fun}", "#{new_mod}.#{new_fun}", extra_arg
        )

      {:rename_negate_arg, new_mod, new_fun, arg_index} ->
        rename_negate_arg_on_line(
          source, line_no, "#{mod}.#{fun}", "#{new_mod}.#{new_fun}", arg_index
        )

      nil ->
        case Credence.FunctionMatcher.suggest(source, mod, fun, arity,
               visibility: :public_only
             ) do
          {:ok, suggested} ->
            replace_first_on_line(source, line_no, "#{mod}.#{fun}", "#{mod}.#{suggested}")

          :no_candidates ->
            source
        end
    end
  end

  # ── Local fix ──────────────────────────────────────────────────

  defp fix_local(source, line_no, name, arity, msg) do
    case Map.get(@local_replacements, {name, arity}) do
      {:literal, replacement} ->
        replace_all_on_line(source, line_no, "#{name}()", replacement)

      {:rename, mod, fun} ->
        replace_call_on_line(source, line_no, name, "#{mod}.#{fun}")

      {:rename_local, new_name} ->
        replace_call_on_line(source, line_no, name, new_name)

      {:wrap_args, mod, fun} ->
        wrap_args_on_line(source, line_no, name, "#{mod}.#{fun}")

      :to_range ->
        to_range_on_line(source, line_no, arity)

      nil ->
        module_name = parse_expected_module(msg)

        if module_name do
          case Credence.FunctionMatcher.suggest(source, module_name, name, arity) do
            {:ok, suggested} ->
              replace_call_on_line(source, line_no, name, suggested)

            :no_candidates ->
              source
          end
        else
          source
        end
    end
  end

  # ── Diagnostic parsing ────────────────────────────────────────

  defp parse_diagnostic(msg) do
    cond do
      ref = parse_qualified_ref(msg) -> {:qualified, ref}
      ref = parse_local_ref(msg) -> {:local, ref}
      true -> nil
    end
  end

  defp parse_qualified_ref(msg) do
    case Regex.run(~r/(\w+)\.(\w+)\/(\d+) is (undefined or private|deprecated)/, msg) do
      [_, mod, fun, arity, _] -> {mod, fun, String.to_integer(arity)}
      _ -> nil
    end
  end

  defp parse_local_ref(msg) do
    case Regex.run(~r/undefined function (\w+)\/(\d+)/, msg) do
      [_, name, arity] -> {name, String.to_integer(arity)}
      _ -> nil
    end
  end

  defp parse_expected_module(msg) do
    case Regex.run(~r/expected ([\w.]+) to define/, msg) do
      [_, module_name] -> module_name
      _ -> nil
    end
  end

  # ── Common helpers ─────────────────────────────────────────────

  defp extract_line({line, _col}) when is_integer(line), do: line
  defp extract_line(line) when is_integer(line), do: line
  defp extract_line(_), do: nil

  defp replace_first_on_line(source, line_no, old, new) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map(fn
      {line, ^line_no} -> String.replace(line, old, new, global: false)
      {line, _} -> line
    end)
    |> Enum.join("\n")
  end

  defp replace_all_on_line(source, line_no, old, new) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map(fn
      {line, ^line_no} -> String.replace(line, old, new)
      {line, _} -> line
    end)
    |> Enum.join("\n")
  end

  # ── Qualified literal replacement ──────────────────────────────

  defp replace_literal(source, line_no, mod, fun, text) do
    call_with_parens = "#{mod}.#{fun}()"
    call_without_parens = "#{mod}.#{fun}"

    result = replace_first_on_line(source, line_no, call_with_parens, text)

    if result == source do
      replace_first_on_line(source, line_no, call_without_parens, text)
    else
      result
    end
  end

  defp replace_literal_with_neg(source, line_no, mod, fun, pos_text, neg_text) do
    neg_with_parens = "-#{mod}.#{fun}()"
    neg_without_parens = "-#{mod}.#{fun}"
    pos_with_parens = "#{mod}.#{fun}()"
    pos_without_parens = "#{mod}.#{fun}"

    result = replace_first_on_line(source, line_no, neg_with_parens, neg_text)

    result =
      if result == source,
        do: replace_first_on_line(source, line_no, neg_without_parens, neg_text),
        else: result

    result =
      if result == source,
        do: replace_first_on_line(source, line_no, pos_with_parens, pos_text),
        else: result

    if result == source,
      do: replace_first_on_line(source, line_no, pos_without_parens, pos_text),
      else: result
  end

  # ── Rename + add argument ──────────────────────────────────────
  #
  # List.second(list) → Enum.at(list, 1)
  # Finds the call, extracts args via balanced parens, appends the extra arg.

  defp rename_add_arg_on_line(source, line_no, old_call, new_call, extra_arg) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map(fn
      {line, ^line_no} -> do_rename_add_arg(line, old_call, new_call, extra_arg)
      {line, _} -> line
    end)
    |> Enum.join("\n")
  end

  defp do_rename_add_arg(line, old_call, new_call, extra_arg) do
    case :binary.match(line, "#{old_call}(") do
      {match_start, match_len} ->
        paren_pos = match_start + match_len - 1
        after_paren = String.slice(line, (paren_pos + 1)..-1//1)

        case find_matching_close(String.to_charlist(after_paren)) do
          {:ok, inner, rest_after} ->
            before = String.slice(line, 0, match_start)
            trimmed_inner = String.trim(inner)

            args_str =
              if trimmed_inner == "",
                do: extra_arg,
                else: "#{inner}, #{extra_arg}"

            "#{before}#{new_call}(#{args_str})#{rest_after}"

          :unbalanced ->
            line
        end

      :nomatch ->
        line
    end
  end

  # ── Rename + negate argument ───────────────────────────────────
  #
  # Enum.take_last(list, n) → Enum.take(list, -n)
  # Finds the call, extracts + splits args, negates the one at arg_index.

  defp rename_negate_arg_on_line(source, line_no, old_call, new_call, arg_index) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map(fn
      {line, ^line_no} -> do_rename_negate_arg(line, old_call, new_call, arg_index)
      {line, _} -> line
    end)
    |> Enum.join("\n")
  end

  defp do_rename_negate_arg(line, old_call, new_call, arg_index) do
    case :binary.match(line, "#{old_call}(") do
      {match_start, match_len} ->
        paren_pos = match_start + match_len - 1
        after_paren = String.slice(line, (paren_pos + 1)..-1//1)

        case find_matching_close(String.to_charlist(after_paren)) do
          {:ok, inner, rest_after} ->
            before = String.slice(line, 0, match_start)
            args = split_args(inner)

            # In piped form, the first arg is implicit — adjust index
            adjusted_index =
              if arg_index >= length(args), do: length(args) - 1, else: arg_index

            negated_args =
              args
              |> Enum.with_index()
              |> Enum.map(fn
                {arg, ^adjusted_index} -> negate_expr(arg)
                {arg, _} -> arg
              end)

            "#{before}#{new_call}(#{Enum.join(negated_args, ", ")})#{rest_after}"

          :unbalanced ->
            line
        end

      :nomatch ->
        line
    end
  end

  defp negate_expr(expr) do
    trimmed = String.trim(expr)

    if Regex.match?(~r/^\w+$/, trimmed) do
      "-#{trimmed}"
    else
      "-(#{trimmed})"
    end
  end

  # ── Local call rename (with double-replacement protection) ─────

  defp replace_call_on_line(source, line_no, old_name, new_name) do
    pattern = Regex.compile!("(?<![.a-zA-Z0-9_])#{Regex.escape(old_name)}\\(")
    replacement = "#{new_name}("

    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map(fn
      {line, ^line_no} -> Regex.replace(pattern, line, replacement)
      {line, _} -> line
    end)
    |> Enum.join("\n")
  end

  # ── Wrap-args replacement ──────────────────────────────────────

  defp wrap_args_on_line(source, line_no, old_name, new_qualified) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map(fn
      {line, ^line_no} -> do_wrap_args(line, old_name, new_qualified)
      {line, _} -> line
    end)
    |> Enum.join("\n")
  end

  defp do_wrap_args(line, old_name, new_qualified) do
    pattern = Regex.compile!("(?<![.a-zA-Z0-9_])#{Regex.escape(old_name)}\\(")

    case Regex.run(pattern, line, return: :index) do
      [{match_start, match_len}] ->
        paren_pos = match_start + match_len - 1
        after_paren = String.slice(line, (paren_pos + 1)..-1//1)

        case find_matching_close(String.to_charlist(after_paren)) do
          {:ok, inner, rest_after} ->
            before = String.slice(line, 0, match_start)
            rest_wrapped = do_wrap_args(rest_after, old_name, new_qualified)
            "#{before}#{new_qualified}([#{inner}])#{rest_wrapped}"

          :unbalanced ->
            line
        end

      _ ->
        line
    end
  end

  # ── Range replacement ──────────────────────────────────────────

  @range_pattern Regex.compile!("(?<![.a-zA-Z0-9_])range\\(")

  defp to_range_on_line(source, line_no, arity) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map(fn
      {line, ^line_no} -> do_to_range(line, arity)
      {line, _} -> line
    end)
    |> Enum.join("\n")
  end

  defp do_to_range(line, arity) do
    case Regex.run(@range_pattern, line, return: :index) do
      [{match_start, match_len}] ->
        paren_pos = match_start + match_len - 1
        after_paren = String.slice(line, (paren_pos + 1)..-1//1)

        case find_matching_close(String.to_charlist(after_paren)) do
          {:ok, inner, rest_after} ->
            before = String.slice(line, 0, match_start)
            args = split_args(inner)

            case build_range(arity, args) do
              {:ok, range_expr} ->
                rest_fixed = do_to_range(rest_after, arity)
                "#{before}#{range_expr}#{rest_fixed}"

              :error ->
                line
            end

          :unbalanced ->
            line
        end

      _ ->
        line
    end
  end

  defp build_range(1, [n]), do: {:ok, "0..#{n} - 1"}
  defp build_range(2, [a, b]), do: {:ok, "#{a}..#{b} - 1"}
  defp build_range(3, [a, b, c]), do: {:ok, "#{a}..#{b}//#{c}"}
  defp build_range(_, _), do: :error

  # ── Argument splitting (at top-level commas) ───────────────────

  defp split_args(content) do
    content
    |> String.to_charlist()
    |> do_split_args(0, [], [])
    |> Enum.map(&String.trim/1)
  end

  defp do_split_args([], _depth, current, args) do
    arg = current |> Enum.reverse() |> List.to_string()
    Enum.reverse([arg | args])
  end

  defp do_split_args([?, | rest], 0, current, args) do
    arg = current |> Enum.reverse() |> List.to_string()
    do_split_args(rest, 0, [], [arg | args])
  end

  defp do_split_args([?( | rest], depth, current, args),
    do: do_split_args(rest, depth + 1, [?( | current], args)

  defp do_split_args([?) | rest], depth, current, args),
    do: do_split_args(rest, depth - 1, [?) | current], args)

  defp do_split_args([c | rest], depth, current, args),
    do: do_split_args(rest, depth, [c | current], args)

  # ── Balanced-paren matching ────────────────────────────────────

  defp find_matching_close(chars), do: do_find_close(chars, 0, [])

  defp do_find_close([], _depth, _acc), do: :unbalanced

  defp do_find_close([?) | rest], 0, acc) do
    inner = acc |> Enum.reverse() |> List.to_string()
    {:ok, inner, List.to_string(rest)}
  end

  defp do_find_close([?) | rest], depth, acc),
    do: do_find_close(rest, depth - 1, [?) | acc])

  defp do_find_close([?( | rest], depth, acc),
    do: do_find_close(rest, depth + 1, [?( | acc])

  defp do_find_close([c | rest], depth, acc),
    do: do_find_close(rest, depth, [c | acc])
end
