defmodule Credence.PhantomRedefinitionTest do
  use ExUnit.Case, async: false

  alias Credence.RuleHelpers

  # `Code.compile_string/2` warns "redefining module M" whenever M is already
  # loaded in the calling VM. That is a fact about the HOST PROCESS, not about
  # the source being analysed — the same source yields `{:ok, []}` cold and a
  # warning warm.
  #
  # Found in Phase 5, from the harness logs. The evolution harness runs credence
  # via `mix run --no-compile` inside a persistent, already-compiled workspace,
  # so this fired on essentially every row, was handed to every Semantic rule's
  # `match?/1`, and at least one generated rule keyed on it — a rule invented to
  # repair a defect that exists only inside the harness. It also produced
  # findings on clean files, which is how `credence check` came to exit 1 with
  # nothing actually wrong.

  test "a module already loaded in this VM does not produce a diagnostic" do
    source = """
    defmodule PhantomRedefFixture do
      def go, do: :ok
    end
    """

    # Cold: nothing to report.
    assert {:ok, []} = RuleHelpers.compile_and_capture(source)

    # Now guarantee the module is loaded — the harness's normal condition.
    Code.with_diagnostics(fn -> Code.compile_string(source, "preload.ex") end)

    assert {:ok, []} = RuleHelpers.compile_and_capture(source),
           "a warm VM leaked a `redefining module` diagnostic into the analysis"
  end

  # The filter must not swallow the real thing. Source that defines the same
  # module twice has earned the warning, and a Semantic rule should see it.
  test "a module genuinely defined twice in the source still reports" do
    source = """
    defmodule PhantomRedefGenuine do
      def a, do: 1
    end

    defmodule PhantomRedefGenuine do
      def b, do: 2
    end
    """

    assert {:ok, diagnostics} = RuleHelpers.compile_and_capture(source)

    assert Enum.any?(diagnostics, &(&1.message =~ "redefining module PhantomRedefGenuine")),
           "the genuine in-source redefinition was filtered out with the phantoms"
  end

  test "unrelated diagnostics are untouched" do
    source = """
    defmodule PhantomRedefUnrelated do
      def go do
        unused = 1
        :ok
      end
    end
    """

    assert {:ok, diagnostics} = RuleHelpers.compile_and_capture(source)
    assert Enum.any?(diagnostics, &(&1.message =~ "unused"))
  end

  # Conservative by construction: if the source cannot be parsed there is no way
  # to count definitions, so nothing is dropped.
  test "unparseable source keeps every diagnostic" do
    assert {:error, diagnostics} = RuleHelpers.compile_and_capture("defmodule Broken do\n")
    assert diagnostics != []
  end
end
