defmodule Credence.Semantic.NoHallucinatedSelfBang do
  @moduledoc """
  Fixes the compile error caused by hallucinated `self!/1`.

  LLMs frequently hallucinate `self!/1` (undefined in Elixir) meaning
  "send to self". The compiler emits:

      "undefined function self!/1 (expected Module to define such a function
       or for it to be imported, but none are available)"

  The deterministic fix is `send(self(), arg)` since `self!` never exists and
  the only reasonable interpretation is self-messaging.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  # Anchor the arity so `self!/12`, `self!/13`, … (whose "self!/1" is a
  # substring) don't match — `fix/2` only rewrites the single-arg call, so a
  # bare String.contains? would flag arities the fix refuses to touch.
  @match_re ~r{undefined function self!/1\b}

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    Regex.match?(@match_re, msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_hallucinated_self_bang,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {:self!, meta, [_arg] = args}, _acc ->
            # Only single-argument `self!(arg)` has a deterministic same-answer
            # fix, `send(self(), arg)`. The diagnostic we claim is `self!/1`;
            # rewriting `self!/0` (`send(self())` → send/1) or `self!/2`
            # (`send(self(), a, b)` → send/3) would just swap one compile error
            # for another, so leave those untouched for a narrower rule/user.
            #
            # Strip self!-specific closing metadata so Sourceror formats
            # the replacement send(self(), ...) on a single line.
            send_meta = Keyword.drop(meta, [:closing])
            self_meta = [line: meta[:line], column: (meta[:column] || 0) + 5]
            send_call = {:send, send_meta, [{:self, self_meta, []} | args]}

            {send_call, true}

          node, acc ->
            {node, acc}
        end)

      if changed, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
