defmodule Credence.Semantic.UndefinedLocalFunction do
  @moduledoc """
  Fixes compiler errors about undefined local functions with known replacements.

  LLMs sometimes hallucinate local functions that don't exist in Elixir,
  often translating idioms from other languages. This rule maintains a
  mapping of known corrections.

  ## Literal example (arity-0 call → replacement text)

      # Error: undefined function infinity/0
      Enum.reduce(nums, {-infinity(), -infinity()}, fn ...)

      # Fixed:
      Enum.reduce(nums, {-:math.inf(), -:math.inf()}, fn ...)

  ## Rename example (bare call → qualified call)

      # Error: undefined function max/1
      max([option1, option2])

      # Fixed:
      Enum.max([option1, option2])

  ## Wrap-args example (multi-arg call → single list arg)

      # Error: undefined function max/3
      max(a, b, c)

      # Fixed:
      Enum.max([a, b, c])

  ## Rename-local example (bare call → different bare call)

      # Error: undefined function len/1
      len(items)

      # Fixed:
      length(items)

  ## Range example (Python range → Elixir range literal)

      # Error: undefined function range/3
      range(max_num, min_num - 1, -1)

      # Fixed:
      max_num..min_num - 1//-1
  """
  use Credence.Semantic.Rule
  alias Credence.Issue

  # ── Replacement table ──────────────────────────────────────────
  #
  #   {:literal, text}         — replace name() with text (arity-0 only)
  #   {:rename, mod, fun}      — replace name( with mod.fun(
  #   {:rename_local, new}     — replace name( with new( (no module prefix)
  #   {:wrap_args, mod, fun}   — replace name(a, b, c) with mod.fun([a, b, c])
  #   :to_range                — replace range(...) with Elixir range literal

  @replacements %{
    # Python float('inf') → bare infinity() call
    {"infinity", 0} => {:literal, ":math.inf()"},

    # Python max() — polymorphic: max(list) or max(a, b, c, ...)
    {"max", 1} => {:rename, "Enum", "max"},
    {"max", 3} => {:wrap_args, "Enum", "max"},
    {"max", 4} => {:wrap_args, "Enum", "max"},
    {"max", 5} => {:wrap_args, "Enum", "max"},

    # Python min() — polymorphic: min(list) or min(a, b, c, ...)
    {"min", 1} => {:rename, "Enum", "min"},
    {"min", 3} => {:wrap_args, "Enum", "min"},
    {"min", 4} => {:wrap_args, "Enum", "min"},
    {"min", 5} => {:wrap_args, "Enum", "min"},

    # Python sum(iterable)
    {"sum", 1} => {:rename, "Enum", "sum"},

    # Python sorted(iterable) — note: different function name in Elixir
    {"sorted", 1} => {:rename, "Enum", "sort"},

    # Python len(sequence) — maps to Kernel.length/1 (no module prefix needed)
    {"len", 1} => {:rename_local, "length"},

    # Python reversed(iterable) — note: different function name in Elixir
    {"reversed", 1} => {:rename, "Enum", "reverse"},

    # Python range() — three arities, each with different translation:
    #   range(n)       → 0..n - 1          (implicit start=0, step=1)
    #   range(a, b)    → a..b - 1          (implicit step=1)
    #   range(a, b, c) → a..b//c           (naive — LLM already baked in Python's stop adjustment)
    {"range", 1} => :to_range,
    {"range", 2} => :to_range,
    {"range", 3} => :to_range
  }

  @impl true
  def match?(%{severity: :error, message: msg}) do
    String.contains?(msg, "undefined function") and parse_local_ref(msg) != nil
  end

  def match?(_), do: false

  @impl true
  def to_issue(%{message: msg, position: position}) do
    %Issue{
      rule: :undefined_local_function,
      message: msg,
      meta: %{line: extract_line(position)}
    }
  end

  @impl true
  def fix(source, %{message: msg, position: position}) do
    line_no = extract_line(position)

    case parse_local_ref(msg) do
      {name, arity} = key ->
        case Map.get(@replacements, key) do
          nil ->
            # Fallback: use FunctionMatcher to find a close match in the module
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

          {:literal, replacement} ->
            replace_on_line(source, line_no, "#{name}()", replacement)

          {:rename, mod, fun} ->
            replace_call_on_line(source, line_no, name, "#{mod}.#{fun}")

          {:rename_local, new_name} ->
            replace_call_on_line(source, line_no, name, new_name)

          {:wrap_args, mod, fun} ->
            wrap_args_on_line(source, line_no, name, "#{mod}.#{fun}")

          :to_range ->
            to_range_on_line(source, line_no, arity)
        end

      _ ->
        source
    end
  end

  # ── Helpers ────────────────────────────────────────────────────

  defp extract_line({line, _col}) when is_integer(line), do: line
  defp extract_line(line) when is_integer(line), do: line
  defp extract_line(_), do: nil

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

  # ── Literal replacement (arity-0) ─────────────────────────────

  defp replace_on_line(source, line_no, old, new) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map(fn
      {line, ^line_no} -> String.replace(line, old, new)
      {line, _} -> line
    end)
    |> Enum.join("\n")
  end

  # ── Call rename (with double-replacement protection) ──────────
  #
  # Uses a negative lookbehind so `Enum.max(` is not re-matched as `max(`.
  # This makes the fix idempotent — applying it twice is harmless.

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

  # ── Wrap-args replacement ─────────────────────────────────────
  #
  # Converts name(a, b, c) → mod.fun([a, b, c]) using balanced-paren
  # matching to find the closing `)`. Handles nested calls correctly:
  # max(foo(x), bar(y), z) → Enum.max([foo(x), bar(y), z])

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

  # ── Range replacement ─────────────────────────────────────────
  #
  # Converts Python range() to Elixir range literals:
  #   range(n)       → 0..n - 1
  #   range(a, b)    → a..b - 1
  #   range(a, b, c) → a..b//c

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

  # ── Argument splitting (at top-level commas) ──────────────────
  #
  # Splits "foo(1, 2), bar(3), z" into ["foo(1, 2)", "bar(3)", "z"],
  # respecting paren nesting so commas inside nested calls are skipped.

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

  # Scans a charlist for the matching `)` at depth 0.
  # Returns {:ok, inner_content, rest_after_close} or :unbalanced.
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
