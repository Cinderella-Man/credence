defmodule Credence.Semantic.NoHallucinatedBaseHexEncode do
  @moduledoc """
  Fixes the compile error caused by calling `Base.hex_encode/1` or `Base.hex_encode/2`.

  LLMs frequently hallucinate `Base.hex_encode/1` as the hex-encoding function;
  the correct function is `Base.encode16/2`. The compiler emits:

      "Base.hex_encode/1 is undefined or private"

  The existing `semantic/undefined_function` rule matches the diagnostic but has
  no replacement entry for `Base.hex_encode`. This targeted rule provides the
  deterministic rewrite:

      Base.hex_encode()           →  Base.encode16(case: :lower)
      Base.hex_encode(arg)        →  Base.encode16(arg, case: :lower)
      Base.hex_encode(arg, opts)  →  Base.encode16(arg, opts)
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "Base.hex_encode/"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg) and String.contains?(msg, "is undefined or private")
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_hallucinated_base_hex_encode,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {{:., dot_meta, [{:__aliases__, _, [:Base]}, :hex_encode]}, call_meta, args}, _acc
          when is_list(args) ->
            new_alias = {:__aliases__, [line: dot_meta[:line]], [:Base]}

            new_args =
              case args do
                [] ->
                  # Base.hex_encode() → Base.encode16(case: :lower)
                  [
                    [
                      {{:__block__,
                        [
                          trailing_comments: [],
                          leading_comments: [],
                          format: :keyword,
                          line: call_meta[:line]
                        ], [:case]},
                       {:__block__,
                        [
                          trailing_comments: [],
                          leading_comments: [],
                          line: call_meta[:line]
                        ], [:lower]}}
                    ]
                  ]

                [single_arg] ->
                  # Base.hex_encode(data) → Base.encode16(data, case: :lower)
                  [
                    single_arg,
                    [
                      {{:__block__,
                        [
                          trailing_comments: [],
                          leading_comments: [],
                          format: :keyword,
                          line: call_meta[:line]
                        ], [:case]},
                       {:__block__,
                        [
                          trailing_comments: [],
                          leading_comments: [],
                          line: call_meta[:line]
                        ], [:lower]}}
                    ]
                  ]

                _ ->
                  # Base.hex_encode(data, opts) → Base.encode16(data, opts)
                  args
              end

            {{{:., dot_meta, [new_alias, :encode16]}, call_meta, new_args}, true}

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
