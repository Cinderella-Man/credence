defmodule Credence.Rule.NoStringConcatInLoop do
  @moduledoc """
  Performance rule: Detects string concatenation with `<>` inside
  `Enum.reduce` calls with an empty string initial accumulator that can
  be automatically fixed.

  Each `<>` concatenation copies the entire accumulated binary, making
  character-by-character string building O(n²). This is the string equivalent
  of `list ++ [element]`.

  The following patterns are automatically fixed:

    * `Enum.reduce(list, "", fn elem, acc -> acc <> elem end)` → `Enum.join(list)`
    * `Enum.reduce(list, "", fn elem, acc -> acc <> expr end)` where `expr`
      doesn't reference `acc` → `Enum.map_join(list, fn elem -> expr end)`

  ## Bad

      Enum.reduce(graphemes, "", fn char, acc ->
        acc <> char
      end)

      Enum.reduce(graphemes, "", fn char, acc ->
        acc <> String.upcase(char)
      end)

  ## Good

      Enum.join(graphemes)

      Enum.map_join(graphemes, fn char -> String.upcase(char) end)
  """

  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Direct call: Enum.reduce(list, "", fn elem, acc -> acc <> expr end)
        {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, meta, [_list, "", lambda]} = node, issues ->
          case extract_simple_concat(lambda) do
            {:ok, _, _} -> {node, [build_issue(meta) | issues]}
            :error -> {node, issues}
          end

        # Pipeline: ... |> Enum.reduce("", fn elem, acc -> acc <> expr end)
        {:|>, _,
         [
           _,
           {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, meta, ["", lambda]}
         ]} = node,
        issues ->
          case extract_simple_concat(lambda) do
            {:ok, _, _} -> {node, [build_issue(meta) | issues]}
            :error -> {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix(source, _opts) do
    ast = Sourceror.parse_string!(source)

    {_ast, patches} =
      Macro.postwalk(ast, [], fn
        {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, [_list, init, lambda]} = node, acc ->
          if empty_string_literal?(init) do
            case extract_simple_concat(lambda) do
              {:ok, elem_var, expr} ->
                {node, [{:direct, elem_var, expr} | acc]}

              :error ->
                {node, acc}
            end
          else
            {node, acc}
          end

        {:|>, _,
         [
           _prev,
           {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, [init, lambda]}
         ]} = node,
        acc ->
          if empty_string_literal?(init) do
            case extract_simple_concat(lambda) do
              {:ok, elem_var, expr} ->
                {node, [{:pipe, elem_var, expr} | acc]}

              :error ->
                {node, acc}
            end
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    patches = Enum.reverse(patches)
    apply_patches(source, patches)
  end

  defp empty_string_literal?(""), do: true
  defp empty_string_literal?({:__block__, _, [""]}), do: true
  defp empty_string_literal?(_), do: false

  # ── Patch application (reverse order so byte ranges stay valid) ─────

  defp apply_patches(source, patches) do
    patches
    |> Enum.reverse()
    |> Enum.reduce(source, fn patch, src ->
      case find_real_reduce(src) do
        {:ok, byte_pos} ->
          case find_reduce_range(src, byte_pos) do
            {:ok, range_start, range_end} ->
              matched = binary_part(src, range_start, range_end - range_start)
              replacement = build_replacement(patch, matched)
              binary_splice(src, range_start, range_end, replacement)

            :error ->
              src
          end

        :error ->
          src
      end
    end)
  end

  # ── Find "Enum.reduce" skipping string literals ────────────────────

  defp find_real_reduce(source), do: find_real_reduce_loop(source, 0)

  defp find_real_reduce_loop(source, from) do
    if from >= byte_size(source) do
      :error
    else
      remaining = binary_part(source, from, byte_size(source) - from)

      case :binary.match(remaining, "Enum.reduce") do
        {pos, _len} ->
          abs_pos = from + pos

          if inside_string_literal?(source, abs_pos) do
            end_pos = advance_past_string(source, abs_pos)
            find_real_reduce_loop(source, end_pos)
          else
            {:ok, abs_pos}
          end

        :nomatch ->
          :error
      end
    end
  end

  defp inside_string_literal?(source, pos), do: inside_string_loop(source, 0, pos, false)

  defp inside_string_loop(source, current, target, in_string) do
    cond do
      current >= target ->
        in_string

      current >= byte_size(source) ->
        false

      true ->
        <<_::binary-size(current), char::utf8, _::binary>> = source

        cond do
          in_string and char == ?\\ -> inside_string_loop(source, current + 2, target, true)
          in_string and char == ?" -> inside_string_loop(source, current + 1, target, false)
          not in_string and char == ?" -> inside_string_loop(source, current + 1, target, true)
          true -> inside_string_loop(source, current + 1, target, in_string)
        end
    end
  end

  defp advance_past_string(source, pos), do: advance_past_string_loop(source, pos + 1)

  defp advance_past_string_loop(source, pos) do
    if pos >= byte_size(source) do
      pos
    else
      <<_::binary-size(pos), char::utf8, _::binary>> = source

      cond do
        char == ?\\ -> advance_past_string_loop(source, pos + 2)
        char == ?" -> pos + 1
        true -> advance_past_string_loop(source, pos + 1)
      end
    end
  end

  # ── Find byte range of Enum.reduce(...) ────────────────────────────

  defp find_reduce_range(source, byte_pos) do
    rest = binary_part(source, byte_pos, byte_size(source) - byte_pos)

    case :binary.match(rest, "(") do
      {paren_offset, _} ->
        abs_open = byte_pos + paren_offset
        find_matching_paren(source, abs_open + 1, 1, byte_pos)

      :nomatch ->
        :error
    end
  end

  defp find_matching_paren(source, pos, depth, start) do
    cond do
      depth == 0 ->
        {:ok, start, pos}

      pos >= byte_size(source) ->
        :error

      true ->
        <<_::binary-size(pos), char::utf8, _::binary>> = source

        case char do
          ?( -> find_matching_paren(source, pos + 1, depth + 1, start)
          ?) -> find_matching_paren(source, pos + 1, depth - 1, start)
          ?" -> find_matching_paren(source, advance_past_string(source, pos), depth, start)
          _ -> find_matching_paren(source, pos + 1, depth, start)
        end
    end
  end

  # ── Build replacement text ─────────────────────────────────────────

  defp build_replacement({:direct, elem_var, expr}, matched) do
    list_text = extract_first_arg(matched)

    if simple_identity?(expr, elem_var, matched) do
      "Enum.join(#{list_text})"
    else
      lambda_text = extract_lambda_body(matched, elem_var)
      "Enum.map_join(#{list_text}, fn #{elem_name(elem_var)} -> #{lambda_text} end)"
    end
  end

  defp build_replacement({:pipe, elem_var, expr}, matched) do
    if simple_identity?(expr, elem_var, matched) do
      "Enum.join()"
    else
      lambda_text = extract_lambda_body(matched, elem_var)
      "Enum.map_join(fn #{elem_name(elem_var)} -> #{lambda_text} end)"
    end
  end

  defp simple_identity?(_expr, elem_var, matched) do
    body_text = extract_lambda_body(matched, elem_var)
    body_text == elem_name(elem_var)
  end

  defp elem_name({name, _, _}), do: Atom.to_string(name)

  # Extract the first argument text from "Enum.reduce(<HERE>, ...)"
  defp extract_first_arg(matched) do
    case :binary.match(matched, "(") do
      {open_pos, _} -> extract_first_arg_loop(matched, open_pos + 1, open_pos + 1, 0)
      :nomatch -> "list"
    end
  end

  defp extract_first_arg_loop(text, pos, start, depth) do
    if pos >= byte_size(text) do
      binary_part(text, start, pos - start) |> String.trim()
    else
      <<_::binary-size(pos), char::utf8, _::binary>> = text

      cond do
        char == ?( -> extract_first_arg_loop(text, pos + 1, start, depth + 1)
        char == ?) and depth > 0 -> extract_first_arg_loop(text, pos + 1, start, depth - 1)
        char == ?, and depth == 0 -> binary_part(text, start, pos - start) |> String.trim()
        char == ?" -> extract_first_arg_loop(text, advance_past_string(text, pos), start, depth)
        true -> extract_first_arg_loop(text, pos + 1, start, depth)
      end
    end
  end

  # Extract the lambda body text after "->" within fn ... end
  defp extract_lambda_body(matched, elem_var) do
    fn_pos = find_fn_keyword(matched)
    end_pos = find_end_keyword(matched, fn_pos)
    lambda_text = binary_part(matched, fn_pos, end_pos - fn_pos)

    case :binary.match(lambda_text, "->") do
      {arrow_pos, _} ->
        body_start = arrow_pos + 2

        body =
          binary_part(lambda_text, body_start, byte_size(lambda_text) - body_start)
          |> String.trim()

        body =
          case :binary.match(body, " end") do
            {end_kw, _} -> binary_part(body, 0, end_kw) |> String.trim()
            :nomatch -> body
          end

        # Strip "acc <> " to get just the RHS expression
        case :binary.match(body, "<>") do
          {concat_pos, len} ->
            binary_part(body, concat_pos + len, byte_size(body) - concat_pos - len)
            |> String.trim()

          :nomatch ->
            body
        end

      :nomatch ->
        Macro.to_string(elem_var)
    end
  end

  defp find_fn_keyword(text), do: find_fn_loop(text, 0)

  defp find_fn_loop(text, pos) do
    if pos + 2 >= byte_size(text) do
      0
    else
      case binary_part(text, pos, 2) do
        "fn" ->
          after_fn = pos + 2

          if after_fn >= byte_size(text) do
            pos
          else
            <<_::binary-size(after_fn), next::utf8, _::binary>> = text

            if next == ?\s or next == ?\n or next == ?\t do
              pos
            else
              find_fn_loop(text, pos + 1)
            end
          end

        _ ->
          find_fn_loop(text, pos + 1)
      end
    end
  end

  defp find_end_keyword(text, start), do: find_end_loop(text, start, 0)

  defp find_end_loop(text, pos, depth) do
    if pos + 3 > byte_size(text) do
      byte_size(text)
    else
      <<_::binary-size(pos), char::utf8, _::binary>> = text

      cond do
        char == ?( ->
          find_end_loop(text, pos + 1, depth + 1)

        char == ?) and depth > 0 ->
          find_end_loop(text, pos + 1, depth - 1)

        char == ?" ->
          find_end_loop(text, advance_past_string(text, pos), depth)

        depth == 0 and binary_part(text, pos, 3) == "end" ->
          after_end = pos + 3

          if after_end >= byte_size(text) do
            pos
          else
            <<_::binary-size(after_end), next::utf8, _::binary>> = text

            if next == ?\) or next == ?\s or next == ?\n or next == ?\t or next == ?\0 do
              pos
            else
              find_end_loop(text, pos + 1, depth)
            end
          end

        true ->
          find_end_loop(text, pos + 1, depth)
      end
    end
  end

  defp binary_splice(source, from, to, replacement) do
    before = binary_part(source, 0, from)
    after_ = binary_part(source, to, byte_size(source) - to)
    before <> replacement <> after_
  end

  # ── AST helpers (used by check/2) ──────────────────────────────────

  defp extract_simple_concat(
         {:fn, _,
          [
            {:->, _,
             [
               [{_elem_ctx, _, _} = elem_var, {acc_name, _, _}],
               {:<>, _, [left, right]}
             ]}
          ]}
       ) do
    case left do
      {^acc_name, _, _} ->
        if references_var?(right, acc_name) do
          :error
        else
          {:ok, elem_var, right}
        end

      _ ->
        :error
    end
  end

  defp extract_simple_concat(_), do: :error

  defp references_var?(ast, name) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        {^name, _, _} = node, _acc -> {node, true}
        node, acc -> {node, acc}
      end)

    found
  end

  defp build_issue(meta) do
    %Issue{
      rule: :no_string_concat_in_loop,
      message:
        "Avoid `<>` string concatenation inside `Enum.reduce` with an empty " <>
          "string accumulator — each concatenation copies the entire accumulated " <>
          "binary (O(n²)). Use `Enum.join/1` or `Enum.map_join/2` instead.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
