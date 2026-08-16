defmodule Credence.Semantic.FixInvalidCaptureWithArguments do
  @moduledoc """
  Fixes `&Mod.fun(args)/0` capture syntax.

  Elixir's `&` capture does not accept call arguments — only `&Mod.fun/arity`
  or `&Mod.fun(&1, ...)`. When an LLM writes `&Mod.fun(args)/0`, the parser
  reads it as a capture of the division `Mod.fun(args) / 0`; the body contains
  no `&1`-style capture argument, so the compiler rejects it with
  `invalid args for &, expected one of: ...`.

  The fix rewrites the declared-zero-arity form to the thunk the author meant:

      clock = &System.monotonic_time(:millisecond)/0
      # becomes
      clock = fn -> System.monotonic_time(:millisecond) end

  The resulting anonymous function has exactly the arity the `/0` suffix
  declared, so call sites (`clock.()`) work unchanged.

  ## Matching vs fixing

  `match?/1` sees only the diagnostic, so it claims every
  `invalid args for &` error; `fix/2` then verifies the source has the shape
  above and no-ops otherwise, and the `should_report?/2` phase hook keeps
  `analyze` honest by reporting an issue only when the fix would rewrite the
  source.

  ## Deliberately skipped (no fix)

    * `&fun(args)/N` with `N > 0` — `fn -> fun(args) end` would have arity 0
      where the call site expects arity N, and which argument the author
      meant to become `&1` is unknowable;
    * any capture whose body contains a nested `&` (`&(&1 / 2)`,
      `&div(&1, 2)/2`) — those are *valid* captures of a division and must
      not be touched;
    * operator and special-form "calls" (`&(x * 2 / 0)`) and zero-argument
      calls (`&Mod.fun()/0`) — not the hallucinated shape this rule targets.

  ## Bad

      defmodule Example do
        def start do
          clock = &System.monotonic_time(:millisecond)/0
          clock.()
        end
      end

  ## Good

      defmodule Example do
        def start do
          clock = fn -> System.monotonic_time(:millisecond) end
          clock.()
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_substring "invalid args for &"

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_substring)
  end

  def match?(_), do: false

  @doc """
  Phase hook (`Credence.Semantic.match_rules/2`): report an issue only when
  `fix/2` would actually rewrite the source. `match?/1` sees just the
  diagnostic, so without this gate every `invalid args for &` error —
  including shapes this rule deliberately skips — would be attributed to
  this rule.
  """
  def should_report?(diagnostic, source) do
    fix(source, diagnostic) != source
  end

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_invalid_capture_with_arguments,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        {new_ast, changed?} =
          Macro.prewalk(ast, false, fn
            {:&, meta, [{:/, _, [call, arity]}]} = node, acc ->
              if literal_zero?(arity) and fixable_call?(call) do
                {{:fn, meta, [{:->, [], [[], call]}]}, true}
              else
                {node, acc}
              end

            node, acc ->
              {node, acc}
          end)

        if changed?, do: Sourceror.to_string(new_ast), else: source

      _ ->
        source
    end
  end

  # Sourceror wraps literals in a `__block__`; accept the raw form too.
  defp literal_zero?({:__block__, _, [0]}), do: true
  defp literal_zero?(0), do: true
  defp literal_zero?(_), do: false

  # A real call with at least one argument and no nested `&` — the only
  # shape whose `fn -> call end` rewrite is safe. Operator and special-form
  # atoms (`:/`, `:*`, `:&`, `:fn`, ...) also parse as `{name, meta, args}`,
  # so a valid capture like `&(&1 / 2)` reaches here and must be refused.
  defp fixable_call?({{:., _, _}, _, args}) when is_list(args) and args != [] do
    not contains_capture_ref?(args)
  end

  defp fixable_call?({name, _, args})
       when is_atom(name) and is_list(args) and args != [] do
    not Macro.operator?(name, length(args)) and
      not Macro.special_form?(name, length(args)) and
      not contains_capture_ref?(args)
  end

  defp fixable_call?(_), do: false

  defp contains_capture_ref?(ast) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        {:&, _, _} = node, _acc -> {node, true}
        node, acc -> {node, acc}
      end)

    found
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
