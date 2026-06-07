defmodule Credence.Semantic.OutdentedHeredocCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.OutdentedHeredoc

  describe "match?/1" do
    test "matches outdented heredoc warning" do
      diag = %{
        severity: :warning,
        message:
          ~s(outdented heredoc line. The contents inside the heredoc should be indented at the same level as the closing """.),
        position: {3, 8}
      }

      assert OutdentedHeredoc.match?(diag)
    end

    test "matches shorter outdented heredoc message" do
      diag = %{
        severity: :warning,
        message: "outdented heredoc line",
        position: {5, 1}
      }

      assert OutdentedHeredoc.match?(diag)
    end

    test "does not match error severity" do
      diag = %{
        severity: :error,
        message: "outdented heredoc line",
        position: {3, 8}
      }

      refute OutdentedHeredoc.match?(diag)
    end

    test "does not match unused variable warning" do
      diag = %{
        severity: :warning,
        message: """
        variable "x" is unused
        """,
        position: {5, 6}
      }

      refute OutdentedHeredoc.match?(diag)
    end

    test "does not match unrelated warning" do
      diag = %{
        severity: :warning,
        message: "function helper/1 is unused",
        position: {5, 6}
      }

      refute OutdentedHeredoc.match?(diag)
    end
  end

  describe "to_issue/1" do
    test "builds issue with correct rule and line from tuple position" do
      diag = %{
        severity: :warning,
        message: "outdented heredoc line",
        position: {3, 8}
      }

      issue = OutdentedHeredoc.to_issue(diag)
      assert issue.rule == :outdented_heredoc
      assert issue.meta.line == 3
      assert issue.message =~ "outdented"
    end

    test "builds issue with bare integer position" do
      diag = %{
        severity: :warning,
        message: "outdented heredoc line",
        position: 7
      }

      issue = OutdentedHeredoc.to_issue(diag)
      assert issue.meta.line == 7
    end
  end

  describe "integration through Credence.Semantic" do
    test "detects outdented heredoc in module doc" do
      source = ~S'''
      defmodule OutdentedInteg1 do
        @doc """
      Outdented content.
        """
        def foo, do: :ok
      end
      '''

      issues = Credence.Semantic.analyze(source)
      outdented = Enum.filter(issues, &(&1.rule == :outdented_heredoc))
      refute Enum.empty?(outdented)
    end

    test "no issues when heredoc is properly indented" do
      source = ~S'''
      defmodule OutdentedInteg2 do
        @doc """
        Properly indented content.
        """
        def foo, do: :ok
      end
      '''

      issues = Credence.Semantic.analyze(source)
      outdented = Enum.filter(issues, &(&1.rule == :outdented_heredoc))
      assert outdented == []
    end
  end
end
