defmodule Credence.Semantic.OutdentedHeredocFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [valid_syntax?: 1]

  alias Credence.Semantic.OutdentedHeredoc

  defp diag(line, col \\ 1) do
    %{
      severity: :warning,
      message: "outdented heredoc line",
      position: {line, col}
    }
  end

  describe "fix/2 — re-indents entire heredoc" do
    test "adds indentation to match closing delimiter" do
      source = ~S'''
      defmodule Example do
        @doc """
      Content at column 0.
        """
        def foo, do: :ok
      end
      '''

      expected = ~S'''
      defmodule Example do
        @doc """
        Content at column 0.
        """
        def foo, do: :ok
      end
      '''

      assert OutdentedHeredoc.fix(source, diag(3)) == expected
    end

    test "fixes all outdented lines in the heredoc in one call" do
      source = ~S'''
      defmodule Example do
        @doc """
      Line one.
       Line two.
      Line three.
        """
        def foo, do: :ok
      end
      '''

      expected = ~S'''
      defmodule Example do
        @doc """
        Line one.
        Line two.
        Line three.
        """
        def foo, do: :ok
      end
      '''

      # Diagnostic points to any one line — all get fixed
      assert OutdentedHeredoc.fix(source, diag(3)) == expected
    end

    test "handles 4-space nested indentation" do
      source = ~S'''
      defmodule Outer do
        defmodule Inner do
          @doc """
      Deep content.
      More content.
          """
          def bar, do: :ok
        end
      end
      '''

      expected = ~S'''
      defmodule Outer do
        defmodule Inner do
          @doc """
          Deep content.
          More content.
          """
          def bar, do: :ok
        end
      end
      '''

      assert OutdentedHeredoc.fix(source, diag(4)) == expected
    end

    test "does not change lines already at or beyond closing indent" do
      source = ~S'''
      defmodule Example do
        @doc """
      Summary.

          iex> Example.foo()
          :ok
        """
        def foo, do: :ok
      end
      '''

      expected = ~S'''
      defmodule Example do
        @doc """
        Summary.

          iex> Example.foo()
          :ok
        """
        def foo, do: :ok
      end
      '''

      # Line 3 (Summary.) gets fixed, iex lines already have enough indent
      assert OutdentedHeredoc.fix(source, diag(3)) == expected
    end

    test "does not change blank lines" do
      source = ~S'''
      defmodule Example do
        @doc """
        Summary.

        Details.
        """
        def foo, do: :ok
      end
      '''

      assert OutdentedHeredoc.fix(source, diag(4)) == source
    end

    test "does not change already properly indented heredoc" do
      source = ~S'''
      defmodule Example do
        @doc """
        Already fine.
        """
        def foo, do: :ok
      end
      '''

      assert OutdentedHeredoc.fix(source, diag(3)) == source
    end

    test "handles @moduledoc heredoc" do
      source = ~S'''
      defmodule Example do
        @moduledoc """
      Module docs here.
      Second line.
        """
        def foo, do: :ok
      end
      '''

      expected = ~S'''
      defmodule Example do
        @moduledoc """
        Module docs here.
        Second line.
        """
        def foo, do: :ok
      end
      '''

      assert OutdentedHeredoc.fix(source, diag(3)) == expected
    end

    test "handles non-doc heredoc (plain string)" do
      source = ~S'''
      defmodule Example do
        def template do
          """
      Hello world.
          """
        end
      end
      '''

      expected = ~S'''
      defmodule Example do
        def template do
          """
          Hello world.
          """
        end
      end
      '''

      assert OutdentedHeredoc.fix(source, diag(4)) == expected
    end

    test "handles bare integer position" do
      source = ~S'''
      defmodule Example do
        @doc """
      Content.
        """
        def foo, do: :ok
      end
      '''

      expected = ~S'''
      defmodule Example do
        @doc """
        Content.
        """
        def foo, do: :ok
      end
      '''

      bare_diag = %{severity: :warning, message: "outdented heredoc line", position: 3}
      assert OutdentedHeredoc.fix(source, bare_diag) == expected
    end
  end

  describe "fix/2 — no-ops" do
    test "returns source unchanged when position is nil" do
      source = """
      some code

      """

      bad_diag = %{severity: :warning, message: "outdented heredoc line", position: nil}
      assert OutdentedHeredoc.fix(source, bad_diag) == source
    end

    test "returns source unchanged when no closing delimiter found" do
      source = """
      not a heredoc at all

      """

      assert OutdentedHeredoc.fix(source, diag(1)) == source
    end

    test "returns source unchanged when no opening delimiter found" do
      source = ~S'''
      just some text
        """
      '''

      assert OutdentedHeredoc.fix(source, diag(1)) == source
    end
  end

  describe "integration through Credence.Semantic" do
    test "fixes all outdented lines end-to-end" do
      source = ~S'''
      defmodule OutdentedFixInteg1 do
        @doc """
      Outdented content.
       Also outdented.
        """
        def foo, do: :ok
      end
      '''

      expected = ~S'''
      defmodule OutdentedFixInteg1 do
        @doc """
        Outdented content.
        Also outdented.
        """
        def foo, do: :ok
      end
      '''

      fixed = Credence.Semantic.fix(source)
      assert fixed == expected
    end

    test "does not modify properly indented heredoc" do
      source = ~S'''
      defmodule OutdentedFixInteg2 do
        @doc """
        Already correct.
        """
        def foo, do: :ok
      end
      '''

      fixed = Credence.Semantic.fix(source)
      assert fixed == source
    end
  end

  describe "fix output is well-formed" do
    test "fixed output parses" do
      source = ~S'''
      defmodule Example do
        @doc """
      Content at column 0.
        """
        def foo, do: :ok
      end
      '''

      assert valid_syntax?(OutdentedHeredoc.fix(source, diag(3)))
    end
  end
end
