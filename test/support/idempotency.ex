defmodule Credence.Idempotency do
  @moduledoc """
  Is `Credence.fix/1` a fixpoint after one pass? (docs/12 C7, docs/22 T2.5)

  Running `fix/1` over its own output should change nothing. Where it does, the
  first pass left work the second pass picked up — sometimes by design, sometimes
  because a rule walks toward its answer one step at a time.

  ## Why the answer is a ledger and not an assertion

  Measured over all 5,188 unique fix-test fixtures: 2,158 are changed by pass 1
  and **29** are not stable. Most of those 29 are cascades working exactly as
  docs/14 E7 intends — 13 are a Pattern fix leaving a variable the Semantic round
  then reports as unused. A flat "fix/1 must be idempotent" assertion would be red
  for correct behaviour, and a gate that is red for correct behaviour gets
  disabled. So today's 29 are frozen and the *delta* is what is gated, in the
  C13/C14 shape.

  The sweep that produced that number is what found T3.12 —
  `UsedUnderscoreVariable` walking `__MODULE` to `_MODULE` to `MODULE`, an alias,
  producing code that compiles clean and raises `MatchError` at runtime. No parse
  check and no compile check can see that, which is the argument for measuring
  fixpoints at all.
  """

  alias Credence.MetaTestSupport, as: Meta

  @dirs ["test/pattern", "test/semantic", "test/syntax"]

  @doc "Every fix-test file, sorted."
  @spec files() :: [String.t()]
  def files do
    @dirs
    |> Enum.flat_map(&Path.wildcard("#{&1}/**/*_fix_test.exs"))
    |> Enum.sort()
  end

  @doc """
  `%{hash => source}` for every string fixture in `path`.

  Keyed by hash because a fixture is identified by its content: the ledger has to
  survive a file being reordered or a neighbouring case being edited, and a line
  number would not.
  """
  @spec fixtures_of(String.t()) :: %{String.t() => String.t()}
  def fixtures_of(path) do
    path
    |> File.read!()
    |> Sourceror.parse_string!()
    |> Meta.fixtures()
    |> Enum.flat_map(&literal_value/1)
    |> Map.new(&{hash(&1), &1})
  end

  @doc "Short content hash of a fixture."
  @spec hash(String.t()) :: String.t()
  def hash(source) do
    :crypto.hash(:sha256, source) |> Base.encode16(case: :lower) |> binary_part(0, 12)
  end

  @doc """
  `true` when a second `fix/1` pass changes what the first produced.

  A raising `fix/1` is **not** a fixpoint violation — it is a different defect,
  and folding the two together would let a crash hide inside this ledger.

  ## The measurement is about the source, so the VM is reset first

  `Credence.fix/1` compiles what it analyses, and a Semantic rule keys on the
  resulting diagnostic. Whether a module is "not available" is a property of the
  **host VM**, not of the source: once an earlier fixture has defined
  `MyApp.Thing`, a later fixture referring to it compiles clean and the rule that
  keys on its absence stops firing.

  That is not hypothetical — it is how this gate first disagreed with the sweep
  that seeded its ledger. Run alone, `fix_plug_dependency_module_order`'s fixture
  is a fixpoint; run after its siblings, it is not. A ledger built on that would
  record the order tests happened to run in.

  So every module the source defines is purged before each pass. The answer then
  depends only on the bytes, which is the only thing a ledger can honestly pin.
  """
  @spec non_idempotent?(String.t()) :: boolean()
  def non_idempotent?(source) do
    purge_defined(source)
    first = Credence.fix(source).code

    purge_defined(source)
    purge_defined(first)
    Credence.fix(first).code != first
  rescue
    _ -> false
  catch
    _, _ -> false
  end

  # Unload every module the source defines, so the next compile sees the same VM
  # a cold one would. `soft_purge` rather than `purge`: the latter kills any
  # process still running the old code, and this runs inside the test VM.
  defp purge_defined(source) do
    source
    |> defined_modules()
    |> Enum.each(fn mod ->
      :code.soft_purge(mod)
      :code.delete(mod)
      :code.soft_purge(mod)
    end)
  end

  @doc "Module atoms the source's `defmodule` headers name."
  @spec defined_modules(String.t()) :: [module()]
  def defined_modules(source) do
    case Code.string_to_quoted(source) do
      {:ok, ast} ->
        {_ast, mods} =
          Macro.prewalk(ast, [], fn
            {:defmodule, _, [{:__aliases__, _, segs} | _]} = node, acc ->
              {node, [Module.concat(segs) | acc]}

            node, acc ->
              {node, acc}
          end)

        mods

      _ ->
        []
    end
  end

  defp literal_value(node) do
    {{value, _}, _diagnostics} =
      Code.with_diagnostics(fn ->
        Code.eval_string(Sourceror.to_string(node), [], file: "nofile")
      end)

    if is_binary(value), do: [value], else: []
  rescue
    _ -> []
  catch
    _, _ -> []
  end
end
