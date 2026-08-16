defmodule Credence.Semantic.NoDeprecatedNotInFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Semantic.NoDeprecatedNotIn

  @message ~s("not expr1 in expr2" is deprecated, use "expr1 not in expr2" instead)

  defp diag(line), do: %{severity: :warning, message: @message, position: {line, 1}}

  describe "fix/2" do
    test "rewrites the simple form" do
      confirm_fix(
        NoDeprecatedNotIn.fix(
          "defmodule NiFixA do\n  def f(x, l), do: not x in l\nend\n",
          diag(2)
        ),
        """
        defmodule NiFixA do
          def f(x, l), do: x not in l
        end
        """
      )
    end

    # The left operand is re-rendered from the AST rather than reconstructed by
    # hand, so a call, a literal list and a pipeline all survive intact.
    test "keeps a complex left operand" do
      fixed =
        NoDeprecatedNotIn.fix(
          "defmodule NiFixB do\n  def f(m, l), do: not Map.get(m, :k) in l\nend\n",
          diag(2)
        )

      assert fixed =~ "Map.get(m, :k) not in l"
      assert valid_syntax?(fixed)
    end

    test "works inside a guard" do
      fixed =
        NoDeprecatedNotIn.fix(
          "defmodule NiFixC do\n  def f(x) when not x in [1, 2], do: :ok\n  def f(_), do: :no\nend\n",
          diag(2)
        )

      assert fixed =~ "when x not in [1, 2]"
      assert valid_syntax?(fixed)
    end

    test "works inside an if" do
      fixed =
        NoDeprecatedNotIn.fix(
          "defmodule NiFixD do\n  def f(x, l) do\n    if not x in l, do: :missing, else: :present\n  end\nend\n",
          diag(3)
        )

      assert fixed =~ "if x not in l"
      assert valid_syntax?(fixed)
    end
  end

  # The meta gate wants `valid_syntax?(fix(...))` with the call nested directly,
  # not a bound variable — so the assertion cannot drift away from the fix it is
  # about.
  test "the fix output is well-formed" do
    assert valid_syntax?(
             NoDeprecatedNotIn.fix(
               "defmodule NiWellFormed do\n  def f(x, l), do: not x in l\nend\n",
               diag(2)
             )
           )
  end

  describe "declines" do
    # The two forms have the SAME AST — only the `not` column differs — so a
    # rule that did not compare positions would rewrite the modern spelling into
    # itself forever, reporting `:no_op` on every pass. This is the test that
    # proves the column comparison is load-bearing.
    test "leaves the modern spelling alone" do
      source = """
      defmodule NiFixE do
        def f(x, l), do: x not in l
      end
      """

      confirm_fix(NoDeprecatedNotIn.fix(source, diag(2)), source)
    end

    test "leaves a plain `in` alone" do
      source = """
      defmodule NiFixF do
        def f(x, l), do: x in l
      end
      """

      confirm_fix(NoDeprecatedNotIn.fix(source, diag(2)), source)
    end

    # A `not` over something that is not an `in` at all.
    test "leaves an unrelated negation alone" do
      source = """
      defmodule NiFixG do
        def f(x), do: not is_nil(x)
      end
      """

      confirm_fix(NoDeprecatedNotIn.fix(source, diag(2)), source)
    end

    test "declines when the diagnostic has no usable position" do
      source = """
      defmodule NiFixH do
        def f(x, l), do: not x in l
      end
      """

      confirm_fix(
        NoDeprecatedNotIn.fix(source, %{severity: :warning, message: @message, position: nil}),
        source
      )
    end

    # The line is what selects the node, so a diagnostic pointing elsewhere must
    # not rewrite a match on some other line.
    test "declines when the diagnostic points at a different line" do
      source = """
      defmodule NiFixI do
        def f(x, l), do: not x in l
      end
      """

      confirm_fix(NoDeprecatedNotIn.fix(source, diag(3)), source)
    end
  end

  describe "the repaired code means the same thing" do
    # `expr1 not in expr2` is DEFINED as `not (expr1 in expr2)`, so equivalence
    # is exact — but the rewrite moves source bytes across an operator boundary,
    # which is exactly where an off-by-one splice would show up. Executed on
    # both sides rather than argued.
    test "same answers on membership, absence and an empty list" do
      before_src = """
      defmodule NiEquiv do
        def check(x, list), do: not x in list
      end
      """

      after_src = NoDeprecatedNotIn.fix(before_src, diag(2))

      assert after_src != before_src

      for {x, list} <- [{1, [1, 2]}, {3, [1, 2]}, {1, []}, {nil, [nil]}, {:a, [:a, :b]}] do
        assert call_fixed(before_src, NiEquiv, :check, [x, list]) ==
                 call_fixed(after_src, NiEquiv, :check, [x, list]),
               "diverged on #{inspect(x)} in #{inspect(list)}"
      end
    end

    test "the repaired source compiles without the deprecation" do
      before_src = """
      defmodule NiNoWarn do
        def check(x, list), do: not x in list
      end
      """

      fixed = NoDeprecatedNotIn.fix(before_src, diag(2))
      {:ok, diagnostics} = Credence.RuleHelpers.compile_and_capture(fixed)

      refute Enum.any?(diagnostics, &NoDeprecatedNotIn.match?/1),
             "the repair left the deprecation in place"
    end
  end

  describe "integration through Credence.Semantic" do
    test "fixes end-to-end" do
      source = """
      defmodule NiInteg do
        def missing?(x, list), do: not x in list
      end
      """

      assert Credence.Semantic.fix(source) =~ "x not in list"
    end
  end
end
