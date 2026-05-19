defmodule Credence.PipelineIntegrationTest do
  @moduledoc """
  Tests the full Credence pipeline: Syntax → Semantic → Pattern.
  Verifies that all three phases cooperate correctly.
  """
  use ExUnit.Case

  describe "Credence.Syntax phase" do
    test "analyze detects infix div in unparseable code" do
      source = """
      defmodule Example do
        def gauss(n) do
          n * (n + 1) div 2
        end
      end
      """

      %{valid: false, issues: issues} = Credence.analyze(source)
      assert Enum.any?(issues, &(&1.rule == :infix_div))
    end

    test "fix repairs infix div so code parses" do
      source = """
      defmodule SyntaxFixDiv do
        def gauss(n) do
          n * (n + 1) div 2
        end
      end
      """

      %{code: fixed} = Credence.fix(source)
      assert fixed =~ "div("
      assert {:ok, _} = Sourceror.parse_string(fixed)
    end

    test "valid code passes through Syntax unchanged" do
      source = """
      defmodule SyntaxPassThru do
        def half(n), do: div(n, 2)
      end
      """

      assert Credence.Syntax.fix(source) == source
    end
  end

  describe "Credence.Semantic phase" do
    test "analyze detects unused variable" do
      source = """
      defmodule SemanticAnalyze1 do
        def run do
          {unused, used} = {1, 2}
          used
        end
      end
      """

      issues = Credence.Semantic.analyze(source)
      assert Enum.any?(issues, &(&1.rule == :unused_variable))
    end

    test "fix prefixes unused variable" do
      source = """
      defmodule SemanticFix1 do
        def run do
          {unused, used} = {1, 2}
          used
        end
      end
      """

      fixed = Credence.Semantic.fix(source)
      assert fixed =~ "_unused"
    end

    test "clean code has no semantic issues" do
      source = """
      defmodule SemanticClean1 do
        def add(a, b), do: a + b
      end
      """

      assert Credence.Semantic.analyze(source) == []
    end

    test "code that won't compile returns no issues" do
      source = "this is not valid elixir {"

      assert Credence.Semantic.analyze(source) == []
    end
  end

  describe "full pipeline" do
    test "syntax fix enables downstream phases" do
      # Code has infix div (Syntax issue) AND would have Pattern issues
      # if it could parse. Syntax fix should repair it, then Pattern can run.
      source = """
      defmodule FullPipeline1 do
        def gauss_sum(n) do
          total = n * (n + 1) div 2
          total
        end
      end
      """

      %{code: fixed, issues: _issues} = Credence.fix(source)
      assert fixed =~ "div("
      assert {:ok, _} = Sourceror.parse_string(fixed)
    end

    test "analyze on valid code runs all phases" do
      source = """
      defmodule FullAnalyze1 do
        def run(list) do
          {unused, result} = {1, Enum.sum(list)}
          result
        end
      end
      """

      %{valid: valid, issues: issues} = Credence.analyze(source)
      refute valid
      # Should have at least the unused variable issue
      assert Enum.any?(issues, &(&1.rule == :unused_variable))
    end

    test "analyze on unparseable code stops at Syntax phase" do
      source = """
      defmodule StopEarly do
        def gauss(n) do
          n * (n + 1) div 2
        end
      end
      """

      %{valid: false, issues: issues} = Credence.analyze(source)
      # Only Syntax issues, no Pattern issues
      assert Enum.all?(issues, &(&1.rule in [:infix_div, :infix_rem]))
    end
  end
end
