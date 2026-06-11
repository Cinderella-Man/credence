defmodule Credence.Syntax.NoReservedWordVariable do
  @moduledoc """
  Detects and renames Elixir reserved words used as variable names.

  LLMs frequently use reserved words like `after`, `end`, `else`, etc. as
  variable names in pattern matches, causing syntax errors. This rule detects
  such usage and renames them with a `_val` suffix.

  ## Bad (won't parse)

      {before, after} = Enum.split(list, index)
      before ++ Enum.reverse(after)

  ## Good

      {before, after_val} = Enum.split(list, index)
      before ++ Enum.reverse(after_val)
  """
  use Credence.Syntax.Rule
  alias Credence.Issue

  # Reserved words that can't be used as variable names
  @reserved_words ~w(
    after end fn do catch rescue else
    case cond if unless with
    import require use alias
    def defp defmodule defstruct defprotocol defimpl
    when and or not in
    true false nil
  )

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      case find_reserved_binding(line) do
        nil -> []
        word -> [build_issue(word, line_no)]
      end
    end)
  end

  @impl true
  def fix(source) do
    bindings = find_all_bindings(source)

    if bindings == [] do
      source
    else
      renames = Map.new(bindings, fn word -> {word, "#{word}_val"} end)

      Enum.reduce(renames, source, fn {old_name, new_name}, acc ->
        replace_variable_usage(acc, old_name, new_name)
      end)
    end
  end

  defp find_reserved_binding(line) do
    trimmed = String.trim(line)

    if String.starts_with?(trimmed, "#") do
      nil
    else
      # Find reserved words used as variable bindings
      # Pattern: after { or , in tuple/list, or after ( in function args
      # followed by = (assignment), or followed by , } ] ) | (end of destructuring)
      find_reserved_in_pattern(line)
    end
  end

  defp find_reserved_in_pattern(line) do
    Enum.find_value(@reserved_words, fn word ->
      if reserved_word_in_binding_position?(line, word), do: word
    end)
  end

  defp reserved_word_in_binding_position?(line, word) do
    # Look for the word in binding positions
    # Cases:
    # 1. {before, after} - after comma in tuple
    # 2. {after, before} - after opening brace
    # 3. [first, after] - after comma in list
    # 4. (arg1, after) - after comma in function args

    # Build pattern: word boundary before and after the reserved word
    pattern = Regex.compile!("(?<=^|[\\{\\[\\(,]\\s{0,10})" <> Regex.escape(word) <> "(?=\\s*[=,\\}\\]\\)\\|]|\\s+$)")

    Regex.match?(pattern, line)
  end

  defp find_all_bindings(source) do
    source
    |> String.split("\n")
    |> Enum.flat_map(fn line ->
      case find_reserved_binding(line) do
        nil -> []
        word -> [word]
      end
    end)
    |> Enum.uniq()
  end

  defp replace_variable_usage(source, old_name, new_name) do
    # Only replace when in a binding/variable position:
    # - Preceded by { or , or ( (tuple/list/function arg start)
    # - NOT preceded by : (atom)
    # This avoids replacing:
    # - :end (atom)
    # - end (keyword closing blocks)
    pattern = Regex.compile!("(?<=[\{\(,]\s{0,10})" <> Regex.escape(old_name) <> "(?=\s*[,})\]\|]|\s+$)")
    Regex.replace(pattern, source, new_name)
  end

  defp build_issue(word, line_no) do
    %Issue{
      rule: :no_reserved_word_variable,
      message:
        "`#{word}` is a reserved word in Elixir and cannot be used as a variable name. " <>
          "Use `#{word}_val` instead.",
      meta: %{line: line_no}
    }
  end
end
