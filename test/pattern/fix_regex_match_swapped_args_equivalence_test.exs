defmodule Credence.Pattern.RegexMatchSwappedArgsAttributeProvider do
  defmacro __using__(_opts) do
    quote do
      @re "x"
    end
  end
end

defmodule Credence.Pattern.FixRegexMatchSwappedArgsEquivalenceTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.FixRegexMatchSwappedArgs
  alias Credence.RuleHelpers

  test "does not swap a binary attribute set by an external use macro" do
    input = """
    defmodule Credence.Pattern.RegexMatchSwappedArgsUseFixture do
      use Credence.Pattern.RegexMatchSwappedArgsAttributeProvider
      def substring?(string), do: @re =~ string
      @re ~r/x/
    end

    unless Credence.Pattern.RegexMatchSwappedArgsUseFixture.substring?("xylophone") ==
             ("x" =~ "xylophone"),
      do: raise("substring direction changed")
    """

    emitted = fix(FixRegexMatchSwappedArgs, input)

    confirm_fix(emitted, input)
    assert {:ok, _diagnostics} = RuleHelpers.compile_and_capture(emitted)
  end

  test "fix is a repair (before crashes on every input)" do
    # The rule fires only when the left side of `=~` is provably never a
    # binary: a ~r sigil literal, or a module attribute whose every `@attr`
    # assignment in the file is a ~r literal (with no
    # Module.put_attribute/register_attribute or use anywhere, and never
    # inside a quote block). Every clause of `Kernel.=~/2` requires `is_binary(left)`,
    # so the "before" raises FunctionClauseError on every input — the swap is
    # a repair, not a behaviour-preserving rewrite.
    mark_equivalence_repair(
      "left side is provably a regex (or nil/list from a regex-only attribute), " <>
        "never a binary — Kernel.=~/2 requires is_binary(left), so the before " <>
        "raises FunctionClauseError on every input"
    )
  end
end
