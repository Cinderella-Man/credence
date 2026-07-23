defmodule Credence.Semantic.NoUnusedTypeDeclarationCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoUnusedTypeDeclaration

  # Real diagnostic shape from `Code.with_diagnostics/1` compiling the flagship
  # input below: the position is a bare integer line (the compiler reports no
  # column for this warning) and the message has no trailing context.
  @diag %{severity: :warning, message: "type step/0 is unused", position: 2}

  @flagship """
  defmodule CredenceUnusedTypepFlagship do
    @typep step :: %{name: atom()}

    def hi, do: :ok
  end
  """

  # Compiler diagnostics through the same capture the semantic phase itself uses.
  defp diagnostics(source) do
    {_status, diagnostics} = Credence.RuleHelpers.compile_and_capture(source)
    Enum.map(diagnostics, &{&1.severity, &1.message, &1.position})
  end

  test "premise: the compiler emits exactly this diagnostic for an unused @typep" do
    assert diagnostics(@flagship) == [{:warning, "type step/0 is unused", 2}]
  end

  test "premise: @type and @opaque never raise this warning, so only @typep is in scope" do
    source = """
    defmodule CredenceUnusedTypepExported do
      @type pub :: atom()
      @opaque op :: atom()

      def hi, do: :ok
    end
    """

    assert diagnostics(source) == []
  end

  test "matches the unused-type diagnostic" do
    assert NoUnusedTypeDeclaration.match?(@diag)
  end

  test "matches a parameterized type and a tuple position" do
    assert NoUnusedTypeDeclaration.match?(%{
             severity: :warning,
             message: "type my_type/1 is unused",
             position: {5, 3}
           })
  end

  test "ignores unrelated diagnostics" do
    refute NoUnusedTypeDeclaration.match?(%{
             severity: :warning,
             message: "variable \"x\" is unused",
             position: {1, 1}
           })
  end

  test "ignores a message that only embeds the sentence" do
    refute NoUnusedTypeDeclaration.match?(%{
             severity: :warning,
             message: "type step/0 is unused in CredenceFoo",
             position: 2
           })
  end

  test "ignores non-warning diagnostics" do
    refute NoUnusedTypeDeclaration.match?(%{
             severity: :error,
             message: "type step/0 is unused",
             position: {3, 3}
           })
  end

  test "ignores anything that is not a diagnostic map" do
    refute NoUnusedTypeDeclaration.match?(%{severity: :warning, message: nil, position: 1})
    refute NoUnusedTypeDeclaration.match?(:nope)
  end

  test "the semantic phase dispatches this rule for the diagnostic" do
    winner =
      Credence.Semantic.Rule
      |> Credence.RuleHelpers.discover_rules()
      |> Enum.find(& &1.match?(@diag))

    assert winner == NoUnusedTypeDeclaration
  end

  test "the phase reports the flagship end to end" do
    assert [issue] = Credence.Semantic.analyze(@flagship)
    assert issue.rule == :no_unused_type_declaration
    assert issue.meta.line == 2
  end

  test "attributes the issue to this rule and carries the compiler message" do
    issue = NoUnusedTypeDeclaration.to_issue(@diag)

    assert issue.rule == :no_unused_type_declaration
    assert issue.message == "type step/0 is unused"
  end

  test "sets the line in issue meta from an integer position" do
    assert NoUnusedTypeDeclaration.to_issue(@diag).meta.line == 2
  end

  test "sets the line in issue meta from a tuple position" do
    diag = %{severity: :warning, message: "type step/0 is unused", position: {7, 5}}
    assert NoUnusedTypeDeclaration.to_issue(diag).meta.line == 7
  end

  describe "should_report?/2 — reports only what the fix deletes" do
    test "a declaration among siblings in a module body" do
      assert NoUnusedTypeDeclaration.should_report?(@diag, @flagship)
    end

    test "a parameterized declaration" do
      source = """
      defmodule M do
        @typep pair(a) :: {a, a}

        def hi, do: :ok
      end
      """

      diag = %{severity: :warning, message: "type pair/1 is unused", position: 2}
      assert NoUnusedTypeDeclaration.should_report?(diag, source)
    end

    test "no issue: the declaration sits inside a quote" do
      source = """
      defmodule M do
        defmacro define do
          quote do
            @typep step :: atom()
          end
        end
      end
      """

      diag = %{severity: :warning, message: "type step/0 is unused", position: 4}
      refute NoUnusedTypeDeclaration.should_report?(diag, source)
    end

    test "no issue: the declaration is the module's whole body" do
      source = """
      defmodule M do
        @typep step :: atom()
      end
      """

      diag = %{severity: :warning, message: "type step/0 is unused", position: 2}
      refute NoUnusedTypeDeclaration.should_report?(diag, source)
    end

    test "no issue: the flagged line holds no matching declaration" do
      source = """
      defmodule M do
        @typep step :: atom()
        def hi, do: :ok
      end
      """

      diag = %{severity: :warning, message: "type step/0 is unused", position: 3}
      refute NoUnusedTypeDeclaration.should_report?(diag, source)
    end

    test "no issue: the arity in the message matches no declaration on that line" do
      source = """
      defmodule M do
        @typep step :: atom()
        def hi, do: :ok
      end
      """

      diag = %{severity: :warning, message: "type step/1 is unused", position: 2}
      refute NoUnusedTypeDeclaration.should_report?(diag, source)
    end

    test "no issue: the source does not parse" do
      diag = %{severity: :warning, message: "type step/0 is unused", position: 2}
      refute NoUnusedTypeDeclaration.should_report?(diag, "defmodule M do\n  @typep step ::\n")
    end
  end
end
