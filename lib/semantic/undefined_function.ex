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

  ## Ordering — this rule runs last, deliberately

  This is the catch-all for `undefined function …` / `… is undefined or
  private`, so its `match?/1` overlaps with every rule that owns one specific
  spelling of that diagnostic — `NoBareReturnInUnless` (`return/1`),
  `NoModuleLevelInit` (`init/0`), `FixTaskRefFieldAccess` (`Task.ref/1`) and a
  dozen more. Semantic dispatch is `Enum.find`: first match wins, no
  fall-through, so whichever rule sorts first is the *only* one that runs.

  At the default 500 that order came from `Enum.sort_by(&{&1.priority(), &1})`
  falling back to the module atom — every one of those rules won only because
  its name sorts before `UndefinedFunction`. Correct outcome, chosen by nobody,
  and a rename would have silently handed the slot to this rule and replaced a
  structural repair with a renamed call.

  Declaring **501** states the real relationship once, in the one place it is
  true of: the general rule yields to the specific one. That is docs/20 §4's
  "runs after the default population, for a stated reason", and it is why the
  specific rules need no priority of their own. Enforced by
  `test/dispatch_contention_test.exs` (docs/22 T1.2).
  """
  use Credence.Semantic.Rule
  alias Credence.Issue
  alias Credence.SourceMask

  # The catch-all yields to every rule owning a specific spelling of the
  # diagnostic — see "## Ordering" above.
  @impl true
  def priority, do: 501

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

    # Hallucinated List.* that should be Enum.*
    {"List", "max", 1} => {:rename, "Enum", "max"},
    {"List", "min", 1} => {:rename, "Enum", "min"},
    {"List", "sum", 1} => {:rename, "Enum", "sum"},
    {"List", "product", 1} => {:rename, "Enum", "product"},

    # List.at/2 does not exist; the idiomatic equivalent is Enum.at/2
    {"List", "at", 2} => {:rename, "Enum", "at"},

    # Wrong module
    {"Enum", "cycle", 1} => {:rename, "Stream", "cycle"},

    # Enum.sum/2 does not exist (LLMs call sum with a mapper fn); the modern
    # equivalent is Enum.sum_by/2 (same arg order, sums the mapper over each
    # element). Repair — `Enum.sum/2` never compiles.
    {"Enum", "sum", 2} => {:rename, "Enum", "sum_by"},

    # Hallucinated List.second — no such function, use Enum.at(list, 1)
    {"List", "second", 1} => {:rename_add_arg, "Enum", "at", "1"},

    # Hallucinated Enum.take_last — use Enum.take(list, -n)
    {"Enum", "take_last", 2} => {:rename_negate_arg, "Enum", "take", 1},

    # Enum.length/1 does not exist; use Kernel.length/1 (bare local call)
    {"Enum", "length", 1} => {:drop_module, "length"},

    # String.join/2 does not exist; the idiomatic call is Enum.join/2 (same args)
    {"String", "join", 2} => {:rename, "Enum", "join"},

    # List.slice/3 does not exist; Enum.slice/3 has the same (enum, start, count)
    {"List", "slice", 3} => {:rename, "Enum", "slice"},

    # Map.size/1 is deprecated in favour of the Kernel guard-safe map_size/1
    {"Map", "size", 1} => {:drop_module, "map_size"},

    # Enum.tail/1 does not exist; the head/tail equivalent is Kernel.tl/1
    {"Enum", "tail", 1} => {:drop_module, "tl"},

    # Erlang modules. These keys carry the leading colon because that is what
    # the compiler emits (`:math.round/1 is undefined or private`) and what
    # `parse_qualified_ref/1` now captures.
    #
    # :crypto has no hex encoder at all — Base.encode16/1 is the real one.
    # Note it returns UPPERCASE hex, where a digest is conventionally lower;
    # add `case: :lower` if that matters to the caller.
    {":crypto", "hex", 1} => {:rename, "Base", "encode16"},
    # :erlang.warn/1 does not exist; the Elixir equivalent is IO.warn/1.
    {":erlang", "warn", 1} => {:rename, "IO", "warn"},
    # :queue.empty/0 does not exist — :queue.new/0 builds the empty queue.
    # (:queue.is_empty/1 is the predicate, a different function.)
    {":queue", "empty", 0} => {:rename, ":queue", "new"},
    # :math has no min/max — those are Kernel guards.
    {":math", "min", 2} => {:rename, "Kernel", "min"},
    {":math", "max", 2} => {:rename, "Kernel", "max"},
    # :math has no round either; Kernel.round/1 is auto-imported.
    {":math", "round", 1} => {:drop_module, "round"},

    # `Base.hex_encode` is invented; the hex encoder is `Base.encode16`, which
    # defaults to UPPERCASE. An LLM reaching for `hex_encode` is translating
    # Python's `bytes.hex()`, which is lowercase, so the one-argument form
    # carries `case: :lower` and the two-argument form leaves the caller's own
    # options alone.
    #
    # These rows were blocked on call-boundary anchoring, not on themselves
    # (docs/16 4.6d): `hex_encode` is a prefix of the REAL `hex_encode32`, which
    # the compiler lists in this diagnostic's own did-you-mean block, so before
    # the anchoring one broken call became two.
    {"Base", "hex_encode", 1} => {:rename_add_arg, "Base", "encode16", "case: :lower"},
    {"Base", "hex_encode", 2} => {:rename, "Base", "encode16"},

    # `hex_encode64` is invented too — base64 has no hex variant at all, and the
    # compiler suggests `encode64/1` itself (escalation ledger row 119).
    {"Base", "hex_encode64", 1} => {:rename, "Base", "encode64"},
    {"Base", "hex_encode64", 2} => {:rename, "Base", "encode64"},

    # `List.keystore/4` confused with `List.keyfind/3`: the POSITION argument is
    # the one left out, and it belongs second. Appending would compile and mean
    # something else, which is why this needs its own verb (docs/16 4.6d).
    {"List", "keystore", 3} => {:insert_arg, "List", "keystore", 1, "0"}
  }

  @local_replacements %{
    # Python float('inf')
    {"infinity", 0} => {:literal, ":math.inf()"},

    # `exit(pid, reason)` from the Python `os._exit`/`sys.exit` idiom.
    # `Kernel.exit/1` is real and `exit/2` is not, so the row MUST be
    # arity-checked at the call site as well as in this key — the two spellings
    # co-occur in the same file and often on the same line (docs/16 4.6d).
    {"exit", 2} => {:rename, "Process", "exit"},

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

  @impl true
  def to_issue(%{message: msg, position: position}) do
    %Issue{
      rule: :undefined_function,
      message: msg,
      meta: %{line: extract_line(position)}
    }
  end

  @doc """
  Report only what this rule can actually repair (docs/22 T3.6, ledger row 296).

  `match?/1` accepts every `undefined function …` message, but the repair is a
  lookup in the replacement tables — so a call this rule has never heard of,
  like a `Plug` import missing from the file (`undefined function send_resp/2`),
  matched and then returned the source byte-identical. The row was reported
  against `UndefinedFunction`, which had done nothing, and the diagnostic was
  consumed.

  The guard IS the fix, deliberately. A guard that approximates the fix is a
  second implementation of the same decision and drifts from it; this one cannot
  disagree with what `fix/2` will do, because it asks `fix/2`.
  """
  @spec should_report?(map(), String.t()) :: boolean()
  def should_report?(diagnostic, source) do
    fix(source, diagnostic) != source
  end

  @impl true
  def fix(source, %{message: msg, position: position}) do
    line_no = extract_line(position)

    case parse_diagnostic(msg) do
      {:qualified, {mod, fun, arity}} ->
        fix_qualified(source, line_no, mod, fun, arity)

      {:local, {name, arity}} ->
        fix_local(source, line_no, name, arity)

      nil ->
        source
    end
  end

  defp fix_qualified(source, line_no, mod, fun, arity) do
    if anchored_call?(source, line_no, mod, fun) do
      apply_qualified_replacement(source, line_no, mod, fun, arity)
    else
      source
    end
  end

  # A diagnostic names only the LAST segment of an alias, so
  # `MyApp.Input.List.reverse/1` and `List.reverse/1` arrive identical. Without
  # a boundary check the first gets rewritten as if it were the second, turning
  # a user's own nested module into one that does not exist:
  #
  #     Input.List.reverse(l)  ->  Input.Enum.reverse(l)
  #
  # (verified against the live rule). A replacement therefore only applies when
  # the call actually starts at a module boundary on the flagged line.
  defp anchored_call?(_source, nil, _mod, _fun), do: false

  defp anchored_call?(source, line_no, mod, fun) do
    case Enum.at(String.split(source, "\n"), line_no - 1) do
      nil ->
        false

      line ->
        Regex.match?(
          ~r/(?<![.\w])#{Regex.escape(mod)}\.#{Regex.escape(fun)}\b/,
          line
        )
    end
  end

  defp apply_qualified_replacement(source, line_no, mod, fun, arity) do
    case Map.get(@qualified_replacements, {mod, fun, arity}) do
      {:rename, new_mod, new_fun} ->
        replace_first_on_line(source, line_no, "#{mod}.#{fun}", "#{new_mod}.#{new_fun}")

      {:literal, text} ->
        replace_literal(source, line_no, mod, fun, text)

      {:literal_with_neg, pos_text, neg_text} ->
        replace_literal_with_neg(source, line_no, mod, fun, pos_text, neg_text)

      {:insert_arg, new_mod, new_fun, index, inserted} ->
        insert_arg_on_line(
          source,
          line_no,
          "#{mod}.#{fun}",
          "#{new_mod}.#{new_fun}",
          index,
          inserted,
          arity
        )

      {:rename_add_arg, new_mod, new_fun, extra_arg} ->
        rename_add_arg_on_line(
          source,
          line_no,
          "#{mod}.#{fun}",
          "#{new_mod}.#{new_fun}",
          extra_arg
        )

      {:rename_negate_arg, new_mod, new_fun, arg_index} ->
        rename_negate_arg_on_line(
          source,
          line_no,
          "#{mod}.#{fun}",
          "#{new_mod}.#{new_fun}",
          arg_index
        )

      {:drop_module, new_fun} ->
        # Replace Module.fun(...) with new_fun(...) — strips the module prefix
        replace_drop_module(source, line_no, mod, fun, new_fun)

      nil ->
        case Credence.FunctionMatcher.suggest(source, mod, fun, arity, visibility: :public_only) do
          {:ok, suggested} ->
            replace_first_on_line(source, line_no, "#{mod}.#{fun}", "#{mod}.#{suggested}")

          :no_candidates ->
            source
        end
    end
  end

  defp fix_local(source, line_no, name, arity) do
    case Map.get(@local_replacements, {name, arity}) do
      {:literal, replacement} ->
        replace_all_on_line(source, line_no, "#{name}()", replacement)

      {:rename, mod, fun} ->
        replace_call_with_arity(source, line_no, name, "#{mod}.#{fun}", arity)

      {:rename_local, new_name} ->
        replace_call_with_arity(source, line_no, name, new_name, arity)

      {:wrap_args, mod, fun} ->
        wrap_args_on_line(source, line_no, name, "#{mod}.#{fun}")

      :to_range ->
        to_range_on_line(source, line_no, arity)

      nil ->
        # No FunctionMatcher fallback for local (bare) undefined function calls.
        # Fuzzy-matching bare calls is too dangerous — the matcher can suggest
        # the enclosing function itself (e.g. list_to_tuple → findmaxinrotatedlist),
        # creating infinite recursion. Only known patterns from @local_replacements
        # are fixed; everything else is left for the user.
        source
    end
  end

  defp parse_diagnostic(msg) do
    cond do
      ref = parse_qualified_ref(msg) -> {:qualified, ref}
      ref = parse_local_ref(msg) -> {:local, ref}
      true -> nil
    end
  end

  # The module capture allows a leading `:` so Erlang module atoms survive.
  # `\w` cannot match `:`, so the old pattern started at the letter and silently
  # dropped it — `:math.round/1` came back as `{"math", "round", 1}`, and a
  # `{:drop_module, "round"}` keyed on that emitted `:round(x)`, which does not
  # parse. Verified safe for all 27 pre-existing rows: none of their keys begins
  # with `:`, and the optional colon cannot latch onto the one in
  # `warning: Enum.last/1 …` because a space follows it.
  defp parse_qualified_ref(msg) do
    case Regex.run(~r/(:?\w+)\.(\w+)\/(\d+) is (undefined or private|deprecated)/, msg) do
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

  defp extract_line({line, _col}) when is_integer(line), do: line
  defp extract_line(line) when is_integer(line), do: line
  defp extract_line(_), do: nil

  # Every per-line edit in this module goes through `edit_line/3`, which hands
  # the transform the line AND its `Credence.SourceMask` shadow. Matching on the
  # shadow is what keeps a rewrite off a same-named call sitting in a string
  # literal or a trailing comment on the same line — measured, not assumed:
  # before this, `len(l)` beside `"the helper len(x) is not real"` rewrote both.
  # Mask the whole FILE, never a line alone: heredoc state crosses lines
  # (the T3.7 `FixDivRem` finding).
  defp edit_line(source, line_no, fun) do
    source
    |> SourceMask.lines()
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn
      {{line, shadow}, ^line_no} -> fun.(line, shadow)
      {{line, _shadow}, _} -> line
    end)
  end

  defp replace_first_on_line(source, line_no, old, new) do
    edit_line(
      source,
      line_no,
      &SourceMask.replace_code(&1, &2, call_boundary(old), new, global: false)
    )
  end

  defp replace_all_on_line(source, line_no, old, new) do
    edit_line(source, line_no, &SourceMask.replace_code(&1, &2, call_boundary(old), new))
  end

  # CALL-BOUNDARY ANCHORING (docs/16 4.6d).
  #
  # These replacements used to be plain substring searches, and a function name
  # is a prefix of longer real names. `Base.hex_encode` is a prefix of
  # `Base.hex_encode32` — which the compiler lists in that very diagnostic's
  # did-you-mean block — so repairing one broken call produced two. The same
  # trap waits for `Agent`, `NaiveDateTime`, `List.keystore` and `exit`, which
  # is why docs/16 deferred those rows on this anchoring rather than on the
  # rows themselves.
  #
  # The anchor is one-sided on purpose: the leading side is already bounded by
  # the module prefix or by `replace_call_on_line/4`'s own lookbehind, and what
  # is missing is the TRAILING side — the match must not be followed by another
  # name character. `Foo.bar(` and `Foo.bar()` both qualify; `Foo.barbaz` does
  # not.
  defp call_boundary(old), do: Regex.compile!(Regex.escape(old) <> "(?![A-Za-z0-9_])")

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

  defp replace_drop_module(source, line_no, mod, fun, new_fun) do
    # Replace Module.fun with new_fun — preserves args, strips module prefix
    # Match both Module.fun(...) and Module.fun forms
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn
      {line, ^line_no} ->
        line
        |> String.replace("#{mod}.#{fun}(", "#{new_fun}(", global: false)
        |> then(fn result ->
          if result == line do
            # Try without parens (e.g. piped Enum.length())
            String.replace(line, "#{mod}.#{fun}", new_fun, global: false)
          else
            result
          end
        end)

      {line, _} ->
        line
    end)
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

  #
  # List.second(list) → Enum.at(list, 1)
  # Finds the call, extracts args via balanced parens, appends the extra arg.

  # Insert an argument at a POSITION rather than appending one. Every other
  # table verb renames or appends; `List.keystore/3` needs neither — the missing
  # argument is the position index and it belongs second
  # (`List.keystore(l, k, t)` -> `List.keystore(l, 0, k, t)`), so appending
  # would produce a call that compiles and means something else.
  #
  # Arguments are split on top-level commas of the SHADOW, so a comma inside a
  # string or a nested bracket is not a separator; the pieces are then taken
  # from the real line, which is what keeps the caller's own bytes intact.
  defp insert_arg_on_line(source, line_no, old_call, new_call, index, inserted, arity) do
    edit_line(source, line_no, fn line, shadow ->
      with {start, len} <- :binary.match(shadow, "#{old_call}("),
           open <- start + len - 1,
           # The diagnostic is about the WRONG-arity call. A correct
           # `List.keystore/4` on the same line is not what it is complaining
           # about, and inserting into it would corrupt a working call —
           # measured, before this guard existed.
           ^arity <- call_arity(shadow, open + 1),
           {:ok, close} <- matching_close(shadow, open) do
        inner_start = open + 1
        inner_len = close - inner_start
        inner = binary_part(line, inner_start, inner_len)
        shadow_inner = binary_part(shadow, inner_start, inner_len)

        args = split_top_level(inner, shadow_inner)

        if index <= length(args) do
          new_args = List.insert_at(args, index, inserted) |> Enum.join(", ")

          binary_part(line, 0, start) <>
            new_call <>
            "(" <>
            new_args <>
            ")" <>
            binary_part(line, close + 1, byte_size(line) - close - 1)
        else
          line
        end
      else
        _ -> line
      end
    end)
  end

  defp matching_close(shadow, open), do: matching_close(shadow, open + 1, 1)

  defp matching_close(shadow, i, _depth) when i >= byte_size(shadow), do: :unbalanced

  defp matching_close(shadow, i, depth) do
    case :binary.at(shadow, i) do
      c when c in [?(, ?[, ?{] -> matching_close(shadow, i + 1, depth + 1)
      ?) when depth == 1 -> {:ok, i}
      c when c in [?), ?], ?}] -> matching_close(shadow, i + 1, depth - 1)
      _ -> matching_close(shadow, i + 1, depth)
    end
  end

  # Split on the shadow's top-level commas; slice the pieces from the real line.
  defp split_top_level(inner, shadow_inner) do
    cuts =
      shadow_inner
      |> :binary.bin_to_list()
      |> Enum.with_index()
      |> Enum.reduce({[], 0}, fn {c, i}, {acc, depth} ->
        cond do
          c in [?(, ?[, ?{] -> {acc, depth + 1}
          c in [?), ?], ?}] -> {acc, depth - 1}
          c == ?, and depth == 0 -> {[i | acc], depth}
          true -> {acc, depth}
        end
      end)
      |> elem(0)
      |> Enum.reverse()

    {pieces, last} =
      Enum.reduce(cuts, {[], 0}, fn cut, {acc, from} ->
        {[binary_part(inner, from, cut - from) | acc], cut + 1}
      end)

    [binary_part(inner, last, byte_size(inner) - last) | pieces]
    |> Enum.reverse()
    |> Enum.map(&String.trim/1)
  end

  defp rename_add_arg_on_line(source, line_no, old_call, new_call, extra_arg) do
    edit_line(source, line_no, fn line, shadow ->
      # The shadow decides only WHETHER this line has a code-position call;
      # `do_rename_add_arg/4` rebuilds from the real bytes.
      if :binary.match(shadow, "#{old_call}(") == :nomatch,
        do: line,
        else: do_rename_add_arg(line, old_call, new_call, extra_arg)
    end)
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

  #
  # Enum.take_last(list, n) → Enum.take(list, -n)
  # Finds the call, extracts + splits args, negates the one at arg_index.

  defp rename_negate_arg_on_line(source, line_no, old_call, new_call, arg_index) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn
      {line, ^line_no} -> do_rename_negate_arg(line, old_call, new_call, arg_index)
      {line, _} -> line
    end)
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

  # Arity-aware call replacement (docs/16 4.6d's remaining gap).
  #
  # `@local_replacements` is keyed `{name, arity}`, so the LOOKUP already knows
  # the arity — but the replacement above matches the name whatever the call's
  # shape, so an `exit/2` row rewrote a bare `exit(reason)` sitting on the same
  # line. That is not academic for exactly this row: `Kernel.exit/1` is real and
  # common, and `exit/2` is the invention, so the two genuinely co-occur.
  #
  # Counting arity from text needs only the argument list's top-level commas,
  # which is why this is a scan rather than a parse: the line may not parse (the
  # file has a compile error by construction) and the argument expressions can
  # contain commas inside their own brackets and strings.
  defp replace_call_with_arity(source, line_no, old_name, new_name, arity) do
    pattern = Regex.compile!("(?<![.a-zA-Z0-9_])#{Regex.escape(old_name)}\\(")

    edit_line(source, line_no, fn line, shadow ->
      # EVERY match is considered, not just the first: a line can hold both
      # `exit(:normal)` and `exit(p, :kill)`, and stopping at the first match
      # would decline the whole line because the wrong one came first.
      # EVERY match whose arity fits is replaced — the previous helper replaced
      # every match unconditionally, and a line may hold two calls of the same
      # arity (`max([a, b]) + max([c, d])`). Right-to-left, so an earlier
      # splice cannot invalidate a later offset.
      pattern
      |> Regex.scan(shadow, return: :index)
      |> Enum.map(&hd/1)
      |> Enum.filter(fn {start, len} -> call_arity(shadow, start + len) == arity end)
      |> Enum.reverse()
      |> Enum.reduce(line, fn {start, len}, acc ->
        head = binary_part(acc, 0, start)
        tail = binary_part(acc, start + len, byte_size(acc) - start - len)
        head <> new_name <> "(" <> tail
      end)
    end)
  end

  # Top-level argument count of the call whose `(` has just been consumed at
  # `from`. Counts commas at bracket depth 0; the shadow has string and comment
  # bytes blanked already, so a comma inside a literal cannot be seen here.
  defp call_arity(shadow, from), do: call_arity(shadow, from, 0, 1, false)

  defp call_arity(shadow, i, _commas, _depth, _seen) when i >= byte_size(shadow), do: nil

  defp call_arity(shadow, i, commas, depth, seen) do
    case :binary.at(shadow, i) do
      c when c in [?(, ?[, ?{] -> call_arity(shadow, i + 1, commas, depth + 1, true)
      ?) when depth == 1 -> if seen, do: commas + 1, else: 0
      c when c in [?), ?], ?}] -> call_arity(shadow, i + 1, commas, depth - 1, seen)
      ?, when depth == 1 -> call_arity(shadow, i + 1, commas + 1, depth, true)
      c when c in [?\s, ?\t] -> call_arity(shadow, i + 1, commas, depth, seen)
      _ -> call_arity(shadow, i + 1, commas, depth, true)
    end
  end

  defp wrap_args_on_line(source, line_no, old_name, new_qualified) do
    edit_line(source, line_no, fn line, shadow ->
      # `do_wrap_args/3` scans for the call and rebuilds the argument list, so it
      # needs the real bytes; the shadow decides only WHETHER this line has a
      # code-position call to act on.
      if SourceMask.replace_code(shadow, shadow, old_name <> "(", "", global: false) == shadow,
        do: line,
        else: do_wrap_args(line, old_name, new_qualified)
    end)
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

  @range_pattern Regex.compile!("(?<![.a-zA-Z0-9_])range\\(")

  defp to_range_on_line(source, line_no, arity) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn
      {line, ^line_no} -> do_to_range(line, arity)
      {line, _} -> line
    end)
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
