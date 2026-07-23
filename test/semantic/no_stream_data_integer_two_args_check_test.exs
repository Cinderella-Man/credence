defmodule Credence.Semantic.NoStreamDataIntegerTwoArgsCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.NoStreamDataIntegerTwoArgs

  # Real diagnostic shape from `Code.with_diagnostics/1` compiling the flagship
  # input of the fix test — the column points at the `integer` token.
  @message "undefined function integer/2 (expected CredenceIntegerTwoArgsFlagship to define such a function or for it to be imported, but none are available)"
  @diag %{severity: :error, message: @message, position: {5, 10}}

  @flagship """
  defmodule CredenceIntegerTwoArgsFlagship do
    import StreamData

    def account_program do
      bind(integer(0, 10), fn n ->
        deposit = {:deposit, integer(1, 1000)}
        {:withdraw, integer(1, n)}
        constant(deposit)
      end)
    end
  end
  """

  test "matches the undefined integer/2 diagnostic" do
    assert NoStreamDataIntegerTwoArgs.match?(@diag)
  end

  test "the semantic phase dispatches this rule for the diagnostic" do
    winner =
      Credence.Semantic.Rule
      |> Credence.RuleHelpers.discover_rules()
      |> Enum.find(& &1.match?(@diag))

    assert winner == NoStreamDataIntegerTwoArgs
  end

  test "premise: StreamData has integer/0 and integer/1 but no integer/2" do
    # Calling `integer/1` loads the module, so `function_exported?/3` is
    # accurate for the assertions that pin this rule's premise.
    assert %StreamData{} = StreamData.integer(0..10)
    assert function_exported?(StreamData, :integer, 1)
    refute function_exported?(StreamData, :integer, 2)
  end

  test "matches the bare message with no parenthetical" do
    assert NoStreamDataIntegerTwoArgs.match?(%{
             severity: :error,
             message: "undefined function integer/2",
             position: {5, 10}
           })
  end

  test "ignores unrelated diagnostics" do
    refute NoStreamDataIntegerTwoArgs.match?(%{
             severity: :error,
             message: "unrelated",
             position: {1, 1}
           })
  end

  test "ignores other arities" do
    refute NoStreamDataIntegerTwoArgs.match?(%{
             severity: :error,
             message: "undefined function integer/3 (expected M to define such a function)",
             position: {1, 1}
           })
  end

  test "ignores an arity whose digits merely start with 2" do
    refute NoStreamDataIntegerTwoArgs.match?(%{
             severity: :error,
             message: "undefined function integer/21 (expected M to define such a function)",
             position: {1, 1}
           })
  end

  test "ignores another function whose name merely ends in integer" do
    refute NoStreamDataIntegerTwoArgs.match?(%{
             severity: :error,
             message: "undefined function my_integer/2 (expected M to define such a function)",
             position: {1, 1}
           })
  end

  test "ignores the qualified StreamData.integer/2 spelling (a warning, out of scope)" do
    refute NoStreamDataIntegerTwoArgs.match?(%{
             severity: :warning,
             message:
               "StreamData.integer/2 is undefined or private. Did you mean:\n\n    * integer/0\n    * integer/1\n",
             position: {2, 27}
           })
  end

  test "ignores the generic compile error wrapper" do
    refute NoStreamDataIntegerTwoArgs.match?(%{
             severity: :error,
             message: "credence_check.ex: cannot compile module Foo (errors have been logged)",
             position: 0
           })
  end

  test "attributes the issue to this rule" do
    assert NoStreamDataIntegerTwoArgs.to_issue(@diag).rule == :no_stream_data_integer_two_args
  end

  test "preserves the line in the issue" do
    assert NoStreamDataIntegerTwoArgs.to_issue(@diag).meta.line == 5

    bare = %{severity: :error, message: @message, position: 42}
    assert NoStreamDataIntegerTwoArgs.to_issue(bare).meta.line == 42
  end

  test "reports the flagged call" do
    assert NoStreamDataIntegerTwoArgs.should_report?(@diag, @flagship)
  end

  test "the phase reports one issue per flagged call" do
    issues = Credence.Semantic.analyze(@flagship)

    assert Enum.map(issues, & &1.rule) == [
             :no_stream_data_integer_two_args,
             :no_stream_data_integer_two_args,
             :no_stream_data_integer_two_args
           ]

    assert Enum.map(issues, & &1.meta.line) == [5, 6, 7]
  end

  #
  # No issue — the cases the fix deliberately declines to rewrite. Reporting
  # them would promise a repair that never arrives.

  test "no issue when the file does not import StreamData" do
    source = """
    defmodule CredenceIntegerTwoArgsNoImportCheck do
      def gen, do: integer(0, 10)
    end
    """

    diag = %{severity: :error, message: @message, position: {2, 16}}
    refute NoStreamDataIntegerTwoArgs.should_report?(diag, source)
    assert Credence.Semantic.analyze(source) == []
  end

  test "no issue when an argument could re-associate under .." do
    source = """
    defmodule CredenceIntegerTwoArgsPipeCheck do
      import StreamData

      def gen(x, y), do: integer(x |> abs(), y)
    end
    """

    diag = %{severity: :error, message: @message, position: {4, 22}}
    refute NoStreamDataIntegerTwoArgs.should_report?(diag, source)
  end

  test "no issue when a comment sits between the arguments" do
    source =
      """
      defmodule CredenceIntegerTwoArgsCommentCheck do
        import StreamData

        def gen do
          integer(0,
            # upper bound
            10)
        end
      end
      """

    diag = %{severity: :error, message: @message, position: {5, 5}}
    refute NoStreamDataIntegerTwoArgs.should_report?(diag, source)
  end

  test "no issue when the flagged position holds no two-argument integer call" do
    diag = %{severity: :error, message: @message, position: {8, 3}}
    refute NoStreamDataIntegerTwoArgs.should_report?(diag, @flagship)
  end
end
