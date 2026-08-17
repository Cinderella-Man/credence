defmodule Credence.Semantic.FixStructTestInGuard do
  @moduledoc """
  Moves a struct test out of a guard and into the pattern, which is the only sound
  repair on record for a remote function in a guard.

      def f(v) when Map.get(v, :__struct__) == Regex, do: {:regex, v}
      def f(%Regex{} = v), do: {:regex, v}

  Only guard-whitelisted BIFs and macros are legal in guard position, so a remote call
  there is a hard `CompileError` and the module never compiles:

      cannot invoke remote function Map.get/2 inside a guard

  ## Why this is not `no_remote_function_in_guard`

  docs/23 tracks that name, and it cannot be built as specified. Its own disposition
  asks for a **report-only** rule, which this project deletes, and docs/17 §787 records
  **three independent corruption paths** in the body-hoist repair it proposed:

    * **Wrong semantics.** A guard swallows exceptions and a body does not, so hoisting
      converts a fall-through into a `BadMapError`.
    * **Clause deletion.** When the whole guard has to move, the same-name/arity
      fallback clause gets folded into the `if`'s `else` and deleted, leaving every
      argument the surviving head no longer matches unhandled.
    * **Unparseable output.** The hand-assembled `if` node renders `=>` pairs outside a
      map, a hard `syntax error before: '=>'` that takes the whole file out. Three rows
      of the 2026-07-06 harness run hit it.

  docs/17 names the sole exception in as many words: "the repair must move the test into
  the *pattern* … the only sound repair in the set". That is this rule and nothing more.
  It is named for the shape it repairs rather than for the diagnostic family, because a
  rule whose name promises a general repair its matcher never attempts is how
  `FixLocalFunctionInGuard` ended up with three escalation-ledger rows.

  The remaining shapes of the family — `System.monotonic_time(:millisecond) - a >= b`,
  `Map.has_key?(m, pid)`, `String.length(name) > 0` — stay banked in docs/17. Each needs
  the body, and the body is what the three paths above make unsafe.

  ## The parameter must be a bare variable, and that is the whole safety condition

  Moving `%Regex{}` onto a parameter that is already a pattern does not intersect the
  two — it replaces one with the other, and the guard is gone, so the clause matches
  everything the loosened pattern accepts. Executed, on the exact shape docs/18 records
  as the hole its proposed containment check does not close:

      def go(x, %{} = regex) when Map.get(regex, :__struct__) == Regex, do: {:regex_matched, x}
      # naively repaired to: def go(x, %{} = regex), do: {:regex_matched, x}
      go("x", %{a: 1})   #=> {:regex_matched, "x"}   and it must be {:plain, "x"}

  So the target parameter must appear in the head as a plain variable. `%{} = regex`,
  `[_ | _] = regex` and `_` all decline. With a bare variable the dispatch is exactly
  what the author meant, executed:

      def f(%Regex{} = v), do: {:regex, v}
      def f(v), do: {:plain, v}
      f(~r/x/)    #=> {:regex, ~r/x/}
      f(%{a: 1})  #=> {:plain, %{a: 1}}
      f("x")      #=> {:plain, "x"}

  ## `or` declines too

  A conjunct may only be lifted out of an `and` chain. Removing one side of an `or`
  changes which values reach the clause, and an `or` guard is precisely where docs/17's
  path (b) deleted a clause. Any `or` anywhere in the guard and this declines.

  ## Bad (does not compile)

      defmodule StructTestInGuardFSTIG do
        def f(v) when Map.get(v, :__struct__) == Regex, do: {:regex, v}
        def f(v), do: {:plain, v}
      end

  ## Good

      defmodule StructTestInGuardFSTIG do
        def f(%Regex{} = v), do: {:regex, v}
        def f(v), do: {:plain, v}
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  # Nothing else claims this family — measured for docs/18, 0 of 90 live semantic rules
  # match the diagnostic — so the default 500 is right and no ordering note is needed.
  @impl true
  def priority, do: 500

  # `?` and `!` belong in the function-name class: `MapSet.member?/2` is one of the
  # recorded members of this family and was not matching without them.
  @match_re ~r/cannot invoke remote function [A-Za-z_.:]+[?!]?\/\d+ inside a guard/

  @impl true
  def match?(%{severity: :error, message: message}) when is_binary(message) do
    Regex.match?(@match_re, message)
  end

  def match?(_diagnostic), do: false

  @doc """
  Report only when `fix/2` would really rewrite.

  Semantic dispatch is first-match-wins, and `match?/1` claims the whole diagnostic
  family while this rule repairs one shape of it, so without this the other shapes would
  be reported and left unfixed — which is what `test/fix_or_drop_test.exs` exists to
  prevent.
  """
  @spec should_report?(map(), String.t()) :: boolean()
  def should_report?(diagnostic, source), do: fix(source, diagnostic) != source

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_struct_test_in_guard,
      message:
        "a struct test in a guard uses a remote call, which is not legal in guard " <>
          "position, so the module does not compile. Move the test into the pattern " <>
          "as `%Struct{} = var`.",
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        {new_ast, changed} =
          Macro.prewalk(ast, false, fn node, changed ->
            case rewrite_clause(node) do
              {:ok, rewritten} -> {rewritten, true}
              :decline -> {node, changed}
            end
          end)

        if changed, do: Sourceror.to_string(new_ast), else: source

      _error ->
        source
    end
  end

  @kinds [:def, :defp, :defmacro, :defmacrop]

  # A clause whose guard holds exactly one liftable struct test, over a parameter that
  # is a plain variable. Everything else declines, and each decline is a recorded
  # corruption path rather than a missing feature.
  defp rewrite_clause({kind, kind_meta, [{:when, when_meta, [call, guard]} | rest]})
       when kind in @kinds do
    with false <- contains_or?(guard),
         conjuncts = split_and(guard),
         {:ok, alias_node, var} <- single_struct_test(conjuncts),
         {:ok, new_call} <- bind_struct_pattern(call, alias_node, var) do
      remaining = Enum.reject(conjuncts, &struct_test(&1))

      {:ok, rebuild(kind, kind_meta, when_meta, new_call, remaining, rest)}
    else
      _ -> :decline
    end
  end

  defp rewrite_clause(_node), do: :decline

  defp rebuild(kind, kind_meta, _when_meta, call, [], rest), do: {kind, kind_meta, [call | rest]}

  defp rebuild(kind, kind_meta, when_meta, call, remaining, rest) do
    {kind, kind_meta, [{:when, when_meta, [call, join_and(remaining)]} | rest]}
  end

  # `Map.get(var, :__struct__) == Alias`, either way round. `{alias_node, var_name}`.
  defp struct_test({:==, _meta, [left, right]}) do
    cond do
      match?({:ok, _}, struct_get(left)) and alias?(right) ->
        {:ok, var} = struct_get(left)
        {right, var}

      match?({:ok, _}, struct_get(right)) and alias?(left) ->
        {:ok, var} = struct_get(right)
        {left, var}

      true ->
        nil
    end
  end

  defp struct_test(_node), do: nil

  defp struct_get({{:., _, [{:__aliases__, _, [:Map]}, :get]}, _, [{var, _, ctx}, key]})
       when is_atom(var) and is_atom(ctx) do
    if literal(key) == :__struct__, do: {:ok, var}, else: :error
  end

  defp struct_get(_node), do: :error

  # Sourceror wraps every literal leaf in `{:__block__, meta, [value]}`, so a bare
  # `:__struct__` in a pattern never matches parsed source — this rule matched nothing at
  # all until the key went through here. Several modules in this repo carry their own
  # one-line unwrapper (`dsl_guard.ex:400`, `prefer_guard_over_if.ex:402`); there is no
  # shared one, and `RuleHelpers.unwrap_list/1` is list-specific.
  defp literal({:__block__, _meta, [value]}), do: value
  defp literal(value), do: value

  defp alias?({:__aliases__, _meta, segments}) when is_list(segments), do: true
  defp alias?(_node), do: false

  defp single_struct_test(conjuncts) do
    case Enum.flat_map(conjuncts, fn c -> List.wrap(struct_test(c)) end) do
      [{alias_node, var}] -> {:ok, alias_node, var}
      _many_or_none -> :decline
    end
  end

  # The safety condition. `var` must be a plain variable in the head, so the struct
  # pattern INTERSECTS with what was there rather than replacing a pattern and taking
  # the guard's filtering with it.
  defp bind_struct_pattern({name, meta, args}, alias_node, var) when is_list(args) do
    {new_args, found} =
      Enum.map_reduce(args, false, fn
        {^var, var_meta, ctx}, _found when is_atom(ctx) ->
          {{:=, [], [struct_pattern(alias_node), {var, var_meta, ctx}]}, true}

        arg, found ->
          {arg, found}
      end)

    if found, do: {:ok, {name, meta, new_args}}, else: :decline
  end

  defp bind_struct_pattern(_call, _alias_node, _var), do: :decline

  defp struct_pattern(alias_node), do: {:%, [], [alias_node, {:%{}, [], []}]}

  defp split_and({:and, _meta, [left, right]}), do: split_and(left) ++ split_and(right)
  defp split_and(node), do: [node]

  defp join_and([single]), do: single
  defp join_and([head | tail]), do: {:and, [], [head, join_and(tail)]}

  defp contains_or?(guard) do
    {_ast, found} =
      Macro.prewalk(guard, false, fn
        {:or, _, [_, _]} = node, _found -> {node, true}
        node, found -> {node, found}
      end)

    found
  end

  defp line(%{position: {line, _column}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
  defp line(_diagnostic), do: 1
end
