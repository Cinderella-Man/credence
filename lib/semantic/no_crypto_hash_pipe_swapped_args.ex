defmodule Credence.Semantic.NoCryptoHashPipeSwappedArgs do
  @moduledoc """
  Fixes the runtime ArgumentError caused by piping data into `:crypto.hash/2`
  with swapped arguments.

  LLMs frequently write:

      path
      |> File.read!()
      |> :crypto.hash(:sha256)
      |> Base.encode16(case: :lower)

  The pipe operator inserts the piped value as the FIRST argument to
  `:crypto.hash/2`, placing the file data in the algorithm position and
  the algorithm atom in the data position. At runtime, this raises
  `ArgumentError` because `:sha256` is an atom, not valid iodata.

  The fix restructures the pipe to a direct call with correct argument order:

      :crypto.hash(:sha256, path |> File.read!())
      |> Base.encode16(case: :lower)
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_substring "not an iodata term"

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_substring)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_crypto_hash_pipe_swapped_args,
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
            {:|>, _pipe_meta, [left, right]} = node, acc ->
              case extract_crypto_hash_single_arg(right) do
                {:ok, algo_node} ->
                  new_call = build_crypto_hash_call(right, algo_node, left)
                  {new_call, true}

                :error ->
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

  # Match `:crypto.hash(algorithm)` with exactly one argument that is an atom literal.
  # AST shape: {{:., _, [{:__block__, _, [:crypto]}, :hash]}, _, [{:__block__, _, [atom]}]}
  defp extract_crypto_hash_single_arg(
         {{:., _dot_meta, [{:__block__, _meta, [:crypto]}, :hash]}, _call_meta,
          [{:__block__, _algo_meta, [algo_atom]} = algo_node]}
       )
       when is_atom(algo_atom) do
    {:ok, algo_node}
  end

  defp extract_crypto_hash_single_arg(_), do: :error

  # Build `:crypto.hash(algorithm, piped_value)` preserving metadata from the original call.
  defp build_crypto_hash_call(
         {{:., dot_meta, [{:__block__, crypto_meta, [:crypto]}, :hash]}, call_meta, [algo_node]},
         _algo_node,
         piped_value
       ) do
    new_dot = {:., dot_meta, [{:__block__, crypto_meta, [:crypto]}, :hash]}
    {new_dot, call_meta, [algo_node, piped_value]}
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
