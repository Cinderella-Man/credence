defmodule Credence.Semantic.NoHallucinatedCryptoCompare do
  @moduledoc """
  Fixes the compile error caused by calling `:crypto.compare/2`.

  LLMs frequently hallucinate `:crypto.compare/2` as the constant-time
  comparison function; it does not exist in OTP. The correct function is
  `:crypto.hash_equals/2` (available since OTP 22). The compiler emits:

      ":crypto.compare/2 is undefined or private"

  The existing `UndefinedFunction` rule matches the diagnostic but has no
  replacement entry for `:crypto.compare`. This targeted rule provides the
  deterministic 1:1 rewrite:

      :crypto.compare(a, b)  →  :crypto.hash_equals(a, b)
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg ":crypto.compare/"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg) and String.contains?(msg, "is undefined or private")
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_hallucinated_crypto_compare,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {{:., dot_meta, [{:__block__, block_meta, [:crypto]}, :compare]}, call_meta, args},
          _acc
          when is_list(args) ->
            new_dot =
              {{:., dot_meta,
                [{:__block__, block_meta, [:crypto]}, :hash_equals]}, call_meta, args}

            {new_dot, true}

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
