defmodule Credence.Semantic.NoHallucinatedCryptoHex do
  @moduledoc """
  Fixes the compile error caused by calling `:crypto.hex/1`.

  LLMs frequently hallucinate `:crypto.hex/1` as the hex-encoding function;
  it does not exist in OTP. The correct function is `Base.encode16/1`. The
  compiler emits:

      ":crypto.hex/1 is undefined or private"

  The deterministic fix replaces the call:

      :crypto.hex(data)  →  Base.encode16(data)
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg ":crypto.hex/"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg) and String.contains?(msg, "is undefined or private")
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_hallucinated_crypto_hex,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {{:., dot_meta, [{:__block__, block_meta, [:crypto]}, :hex]}, call_meta, args},
          _acc
          when is_list(args) ->
            new_dot =
              {{:., dot_meta,
                [{:__aliases__, block_meta, [:Base]}, :encode16]}, call_meta, args}

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
