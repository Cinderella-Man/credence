defmodule Credence.Semantic.FixInvalidListTypespecSyntax do
  @moduledoc """
  Fixes invalid multi-element lists inside `list(...)` in typespecs.

  LLMs frequently write `list([integer(), integer()])` in a `@spec` to mean "a
  list of `[x, y]` pairs". A multi-element literal list is not a valid typespec
  form — `[type]` means "a list of `type`", and two or more comma-separated
  element types make the compiler emit:

      unexpected list in typespec: [integer(), integer()]

  Elixir typespecs cannot express fixed-length lists, so the closest valid type
  is a list whose elements are the union of the written element types. The fix
  rewrites the inner list's top-level commas into a union, deduplicating
  textually identical members (`a | a` is `a`):

      list([integer(), integer()])  =>  list([integer()])
      list([integer(), atom()])     =>  list([integer() | atom()])

  A `@spec` has no runtime effect and the flagged line does not compile, so the
  rewrite only ever touches an already-broken spec. Like `NoNonNegatedInteger`,
  the edit is confined to the compiler-flagged line, which is a type-only
  context.

  ## Scope (deliberately narrow)

  Only a standalone `list([...])` call is rewritten — not `my_list(...)` or
  `M.list(...)` — and only when the inner list has two or more top-level
  elements, none of which makes it an already-valid typespec form:

    * `list([type])` — valid (list of lists), left alone;
    * `list([type, ...])` — valid (list of non-empty lists), left alone;
    * `list([key: type])` — valid (list of keyword lists), left alone.

  When the flagged line's invalid list is not wrapped in `list(...)` (e.g. a
  bare `[a, b]` return type), the source is returned unchanged.

  ## Bad

      defmodule SolutionFFILTS do
        @spec f(list([list([integer(), integer()]), atom()])) :: boolean()
        def f(x), do: true
      end

  ## Good

      defmodule SolutionFFILTS do
        @spec f(list([list([integer()]) | atom()])) :: boolean()
        def f(_x), do: true
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, "unexpected list in typespec")
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_invalid_list_typespec_syntax,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, diagnostic) do
    line_no = line(diagnostic)

    if line_no do
      source
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn
        {text, ^line_no} -> rewrite_line(text)
        {text, _} -> text
      end)
    else
      source
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
  defp line(_), do: nil

  # -- line rewriting ---------------------------------------------------------

  defp rewrite_line(line), do: scan(line, 0)

  # Scan left-to-right from `offset` for standalone `list([...])` occurrences.
  # After handling one (rewritten or skipped), continue just past its `list([`
  # opener so nested occurrences are still visited; the offset strictly grows,
  # so the scan terminates.
  defp scan(line, offset) when offset >= byte_size(line), do: line

  defp scan(line, offset) do
    case :binary.match(line, "list([", scope: {offset, byte_size(line) - offset}) do
      :nomatch ->
        line

      {start, _len} ->
        if standalone?(line, start) do
          rewrite_occurrence(line, start)
        else
          scan(line, start + 1)
        end
    end
  end

  defp rewrite_occurrence(line, start) do
    inner_start = start + byte_size("list([")

    with close_pos when is_integer(close_pos) <- find_matching_close(line, inner_start),
         inner = binary_part(line, inner_start, close_pos - inner_start),
         new_inner when is_binary(new_inner) <- rewrite_inner(inner) do
      before = binary_part(line, 0, inner_start)
      rest = binary_part(line, close_pos, byte_size(line) - close_pos)
      scan(before <> new_inner <> rest, inner_start)
    else
      _ -> scan(line, inner_start)
    end
  end

  # `list` must be its own identifier: reject `my_list([`, `M.list([`,
  # `@list([` and identifiers continuing in any multibyte character.
  defp standalone?(_line, 0), do: true

  defp standalone?(line, start) do
    prev = :binary.at(line, start - 1)

    not (prev in ?a..?z or prev in ?A..?Z or prev in ?0..?9 or
           prev in [?_, ?., ?@, ??, ?!] or prev >= 128)
  end

  # Byte offset of the `]` closing the inner list, which must be immediately
  # followed by `)` to complete the `list([...])` shape.
  defp find_matching_close(line, pos), do: do_find_close(line, pos, 0)

  defp do_find_close(line, pos, _depth) when pos >= byte_size(line), do: nil

  defp do_find_close(line, pos, depth) do
    case :binary.at(line, pos) do
      ?[ ->
        do_find_close(line, pos + 1, depth + 1)

      ?] when depth > 0 ->
        do_find_close(line, pos + 1, depth - 1)

      ?] ->
        if pos + 1 < byte_size(line) and :binary.at(line, pos + 1) == ?), do: pos, else: nil

      _ ->
        do_find_close(line, pos + 1, depth)
    end
  end

  # Turn `a, b, c` into `a | b | c` (deduplicated). Returns nil when the inner
  # list is not the invalid multi-element shape this rule targets.
  defp rewrite_inner(inner) do
    parts = inner |> split_top_level() |> Enum.map(&String.trim/1)

    if length(parts) >= 2 and Enum.all?(parts, &invalid_element?/1) do
      parts |> Enum.uniq() |> Enum.join(" | ")
    else
      nil
    end
  end

  # `...` and keyword pairs make the inner list a *valid* typespec form
  # (non-empty list / keyword list) — those must be left untouched.
  defp invalid_element?(""), do: false
  defp invalid_element?("..."), do: false

  defp invalid_element?(element),
    do: not Regex.match?(~r/^([a-zA-Z_][a-zA-Z0-9_?!]*|"[^"]*"):\s/, element)

  # Split on commas at bracket depth 0, tracking (), [], {} and <<>> nesting.
  defp split_top_level(s), do: do_split(s, 0, 0, 0, [])

  defp do_split(s, pos, _depth, start, parts) when pos >= byte_size(s) do
    Enum.reverse([binary_part(s, start, pos - start) | parts])
  end

  defp do_split(s, pos, depth, start, parts) do
    case two_at(s, pos) do
      "<<" ->
        do_split(s, pos + 2, depth + 1, start, parts)

      ">>" ->
        do_split(s, pos + 2, depth - 1, start, parts)

      _ ->
        case :binary.at(s, pos) do
          c when c in [?(, ?[, ?{] ->
            do_split(s, pos + 1, depth + 1, start, parts)

          c when c in [?), ?], ?}] ->
            do_split(s, pos + 1, depth - 1, start, parts)

          ?, when depth == 0 ->
            do_split(s, pos + 1, 0, pos + 1, [binary_part(s, start, pos - start) | parts])

          _ ->
            do_split(s, pos + 1, depth, start, parts)
        end
    end
  end

  defp two_at(s, pos) when pos + 2 > byte_size(s), do: nil
  defp two_at(s, pos), do: binary_part(s, pos, 2)
end
