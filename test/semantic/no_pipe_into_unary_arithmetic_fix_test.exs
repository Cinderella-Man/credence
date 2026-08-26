defmodule Credence.Semantic.NoPipeIntoUnaryArithmeticFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Semantic.NoPipeIntoUnaryArithmetic

  @diag %{severity: :error, message: "piping into a unary operator is not supported", position: 0}

  describe "fix/2" do
    test "rewrites a piped unary plus" do
      confirm_fix(
        NoPipeIntoUnaryArithmetic.fix(
          "defmodule NpuA do\n  def f(x), do: x |> + 1\nend\n",
          @diag
        ),
        """
        defmodule NpuA do
          def f(x), do: x |> Kernel.+(1)
        end
        """
      )
    end

    test "rewrites a piped unary minus" do
      confirm_fix(
        NoPipeIntoUnaryArithmetic.fix(
          "defmodule NpuB do\n  def f(x), do: x |> - 3\nend\n",
          @diag
        ),
        """
        defmodule NpuB do
          def f(x), do: x |> Kernel.-(3)
        end
        """
      )
    end

    test "works at the end of a longer pipe" do
      fixed =
        NoPipeIntoUnaryArithmetic.fix(
          "defmodule NpuC do\n  def f(l), do: l |> Enum.sum() |> + 10\nend\n",
          @diag
        )

      assert fixed =~ "l |> Enum.sum() |> Kernel.+(10)"
      assert valid_syntax?(fixed)
    end

    # The rule ignores the diagnostic's line because there is none, so it repairs
    # every occurrence in one pass rather than relying on the round's three
    # passes to catch up.
    test "repairs every occurrence in one pass" do
      fixed =
        NoPipeIntoUnaryArithmetic.fix(
          """
          defmodule NpuD do
            def a(x), do: x |> + 1
            def b(x), do: x |> - 2
            def c(x), do: x |> + 3
          end
          """,
          @diag
        )

      assert fixed =~ "Kernel.+(1)"
      assert fixed =~ "Kernel.-(2)"
      assert fixed =~ "Kernel.+(3)"
      refute fixed =~ "|> + "
      refute fixed =~ "|> - "
    end

    test "the fix output is well-formed" do
      assert valid_syntax?(
               NoPipeIntoUnaryArithmetic.fix(
                 "defmodule NpuE do\n  def f(x), do: x |> + 1\nend\n",
                 @diag
               )
             )
    end

    test "repairs nested piped unary operators in one pass" do
      source = """
      defmodule NpuNested do
        def f(x, y), do: x |> +(y |> +1)
      end
      """

      fixed = NoPipeIntoUnaryArithmetic.fix(source, @diag)

      confirm_fix(fixed, """
      defmodule NpuNested do
        def f(x, y), do: x |> Kernel.+(y |> Kernel.+(1))
      end
      """)

      assert {:ok, []} = Credence.RuleHelpers.compile_and_capture(fixed)
      confirm_fix(NoPipeIntoUnaryArithmetic.fix(fixed, @diag), fixed)
    end
  end

  describe "declines" do
    # Arity is the whole distinction: `{:+, _, [a, b]}` is ordinary addition and
    # a perfectly legal pipe target. Getting this wrong would rewrite working
    # code.
    test "leaves a binary + on the right of a pipe alone" do
      source = """
      defmodule NpuF do
        def f(x), do: x |> Kernel.+(1)
      end
      """

      confirm_fix(NoPipeIntoUnaryArithmetic.fix(source, @diag), source)
    end

    test "leaves ordinary arithmetic alone" do
      source = """
      defmodule NpuG do
        def f(x), do: x + 1
      end
      """

      confirm_fix(NoPipeIntoUnaryArithmetic.fix(source, @diag), source)
    end

    test "leaves a unary minus that is not a pipe target alone" do
      source = """
      defmodule NpuH do
        def f(x), do: -x
      end
      """

      confirm_fix(NoPipeIntoUnaryArithmetic.fix(source, @diag), source)
    end

    test "declines on source that does not parse" do
      source = """
      defmodule NpuI do
        def f(, do: :ok
      end
      """

      confirm_fix(NoPipeIntoUnaryArithmetic.fix(source, @diag), source)
    end
  end

  describe "the repaired code does what the author wrote" do
    # The input never compiled, so there is no prior behaviour to preserve —
    # what has to hold is that the output means `x + 1`. Executed.
    test "the repair computes ordinary arithmetic" do
      before_src = """
      defmodule NpuEquiv do
        def bump(x), do: x |> + 1
        def drop(x), do: x |> - 2
      end
      """

      fixed = NoPipeIntoUnaryArithmetic.fix(before_src, @diag)

      refute Credence.RuleHelpers.compiles?(before_src),
             "precondition: the input must NOT compile"

      assert Credence.RuleHelpers.compiles?(fixed)

      for n <- [0, 1, 7, -3] do
        assert call_fixed(fixed, NpuEquiv, :bump, [n]) == n + 1
        assert call_fixed(fixed, NpuEquiv, :drop, [n]) == n - 2
      end
    end
  end

  describe "integration through Credence.Semantic" do
    test "fixes end-to-end" do
      assert Credence.Semantic.fix("defmodule NpuInteg do\n  def f(x), do: x |> + 1\nend\n") =~
               "Kernel.+(1)"
    end
  end
end
