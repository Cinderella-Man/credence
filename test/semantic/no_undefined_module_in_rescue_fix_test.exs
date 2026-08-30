defmodule Credence.Semantic.NoUndefinedModuleInRescueFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoUndefinedModuleInRescue

  @not_implemented_msg "struct NotImplementedError is undefined (module NotImplementedError is not available or is yet to be defined)"

  defp fix(source, message \\ @not_implemented_msg, line \\ 1) do
    NoUndefinedModuleInRescue.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  describe "rewrites it repairs" do
    test "quotes the undefined module in a two-module rescue list" do
      input = """
      defmodule M do
        def run do
          try do
            {:ok, 1}
          rescue
            e in [NotImplementedError, RuntimeError] ->
              {:error, :exception}
          end
        end
      end
      """

      expected = """
      defmodule M do
        def run do
          try do
            {:ok, 1}
          rescue
            e in [:"Elixir.NotImplementedError", RuntimeError] ->
              {:error, :exception}
          end
        end
      end
      """

      confirm_fix(fix(input), expected)
      assert valid_syntax?(fix(input))
    end

    test "keeps the other modules of a three-module list in order" do
      input = """
      defmodule M do
        def run do
          try do
            :ok
          rescue
            e in [ArgumentError, NotImplementedError, RuntimeError] -> e
          end
        end
      end
      """

      expected = """
      defmodule M do
        def run do
          try do
            :ok
          rescue
            e in [ArgumentError, :"Elixir.NotImplementedError", RuntimeError] -> e
          end
        end
      end
      """

      confirm_fix(fix(input), expected)
    end

    test "repairs a def-level rescue and leaves sibling clauses alone" do
      input = """
      defmodule M do
        def run do
          do_work()
        rescue
          e in [NotImplementedError, RuntimeError] ->
            {:error, e}

          e in [NotImplementedError] ->
            {:other, e}
        end
      end
      """

      expected = """
      defmodule M do
        def run do
          do_work()
        rescue
          e in [:"Elixir.NotImplementedError", RuntimeError] ->
            {:error, e}

          e in [NotImplementedError] ->
            {:other, e}
        end
      end
      """

      confirm_fix(fix(input), expected)
    end

    test "leaves later clauses and the after block untouched" do
      input = """
      defmodule M do
        def run do
          try do
            :ok
          rescue
            e in [NotImplementedError, RuntimeError] -> {:a, e}
            e in [ArgumentError] -> {:b, e}
            e -> {:c, e}
          after
            :cleanup
          end
        end
      end
      """

      expected = """
      defmodule M do
        def run do
          try do
            :ok
          rescue
            e in [:"Elixir.NotImplementedError", RuntimeError] -> {:a, e}
            e in [ArgumentError] -> {:b, e}
            e -> {:c, e}
          after
            :cleanup
          end
        end
      end
      """

      confirm_fix(fix(input), expected)
    end

    test "matches a fully-qualified spelling of the flagged module" do
      input = """
      defmodule M do
        def run do
          try do
            :ok
          rescue
            e in [Elixir.NotImplementedError, RuntimeError] -> e
          end
        end
      end
      """

      expected = """
      defmodule M do
        def run do
          try do
            :ok
          rescue
            e in [:"Elixir.NotImplementedError", RuntimeError] -> e
          end
        end
      end
      """

      confirm_fix(fix(input), expected)
    end

    test "handles a different undefined module" do
      msg =
        "struct BadStructError is undefined (module BadStructError is not available or is yet to be defined)"

      input = """
      defmodule M do
        def run do
          try do
            {:ok, 1}
          rescue
            e in [BadStructError, ArgumentError] ->
              {:error, :exception}
          end
        end
      end
      """

      expected = """
      defmodule M do
        def run do
          try do
            {:ok, 1}
          rescue
            e in [:"Elixir.BadStructError", ArgumentError] ->
              {:error, :exception}
          end
        end
      end
      """

      confirm_fix(fix(input, msg), expected)
    end

    test "keeps a comment written on the quoted module" do
      input = """
      defmodule M do
        def run do
          try do
            :ok
          rescue
            e in [
              # not a real module
              NotImplementedError,
              RuntimeError
            ] ->
              e
          end
        end
      end
      """

      expected = """
      defmodule M do
        def run do
          try do
            :ok
          rescue
            e in [
              # not a real module
              :"Elixir.NotImplementedError",
              RuntimeError
            ] ->
              e
          end
        end
      end
      """

      confirm_fix(fix(input), expected)
    end

    test "keeps catching the exception when its module is defined after compilation" do
      input = """
      defmodule NoUndefinedRescueLateLoadFixture do
        def run do
          try do
            raise NoUndefinedRescueLateError, message: "late"
          rescue
            e in [NoUndefinedRescueLateError, RuntimeError] -> {:caught, e.__struct__}
          end
        end
      end
      """

      {:ok, diagnostics} = Credence.RuleHelpers.compile_and_capture(input)

      diagnostic =
        Enum.find(diagnostics, &NoUndefinedModuleInRescue.match?/1)

      emitted = NoUndefinedModuleInRescue.fix(input, diagnostic)

      runtime_witness = """

      Module.create(
        String.to_atom("Elixir.NoUndefinedRescueLateError"),
        quote do
          defexception [:message]
        end,
        Macro.Env.location(__ENV__)
      )

      unless NoUndefinedRescueLateLoadFixture.run() ==
               {:caught, NoUndefinedRescueLateError} do
        raise "late-defined exception was not caught"
      end
      """

      assert {:ok, _} = Credence.RuleHelpers.compile_and_capture(input <> runtime_witness)
      assert {:ok, _} = Credence.RuleHelpers.compile_and_capture(emitted <> runtime_witness)
    end

    test "repairs a real compiler diagnostic through the semantic pipeline" do
      input = """
      defmodule NoUndefinedRescuePipelineFixture do
        def run do
          try do
            :ok
          rescue
            e in [NoUndefinedRescuePipelineError, RuntimeError] -> e
          end
        end
      end
      """

      expected = """
      defmodule NoUndefinedRescuePipelineFixture do
        def run do
          try do
            :ok
          rescue
            e in [:"Elixir.NoUndefinedRescuePipelineError", RuntimeError] -> e
          end
        end
      end
      """

      assert {:ok, diagnostics} = Credence.RuleHelpers.compile_and_capture(input)
      assert Enum.any?(diagnostics, &NoUndefinedModuleInRescue.match?/1)

      emitted = Credence.Semantic.fix(input)

      confirm_fix(emitted, expected)

      assert Credence.RuleHelpers.compile_and_capture(emitted) ==
               Credence.RuleHelpers.compile_and_capture(expected)
    end
  end

  describe "shapes it deliberately refuses" do
    # Rewriting this to `rescue e ->` would turn a clause that catches nothing
    # (the struct cannot exist) into one that swallows every exception.
    test "leaves a one-module rescue list alone" do
      input = """
      defmodule M do
        def run do
          try do
            {:ok, 1}
          rescue
            e in [NotImplementedError] ->
              {:error, :exception}
          end
        end
      end
      """

      confirm_fix(fix(input), input)
    end

    test "leaves a non-list rescue head alone" do
      input = """
      defmodule M do
        def run do
          try do
            :ok
          rescue
            e in NotImplementedError -> e
          end
        end
      end
      """

      confirm_fix(fix(input), input)
    end

    # `in` here is `Enum.member?/2`; trimming the list would change the answer,
    # and emptying it would leave a bare truthiness test on `x`.
    test "leaves a membership test outside a rescue clause alone" do
      input = """
      defmodule M do
        def f(x) do
          if x in [NotImplementedError] do
            :yes
          else
            :no
          end
        end
      end
      """

      confirm_fix(fix(input), input)
    end

    test "leaves a membership test that names the module beside another alone" do
      input = """
      defmodule M do
        def f(x), do: x in [NotImplementedError, RuntimeError]
      end
      """

      confirm_fix(fix(input), input)
    end

    # A block-scoped alias can make the same spelling resolve to a real struct
    # elsewhere in the file, so an aliasing file is left entirely alone.
    test "leaves a file that aliases the flagged name alone" do
      input = """
      defmodule M do
        alias MyApp.NotImplementedError

        def run do
          try do
            :ok
          rescue
            e in [NotImplementedError, RuntimeError] -> e
          end
        end
      end
      """

      confirm_fix(fix(input), input)
    end

    test "leaves a guarded rescue head alone" do
      input = """
      defmodule M do
        def run do
          try do
            :ok
          rescue
            e in [NotImplementedError, RuntimeError] when is_map(e) -> e
          end
        end
      end
      """

      confirm_fix(fix(input), input)
    end

    test "returns source unchanged when the module is not in the rescue list" do
      input = """
      defmodule M do
        def run do
          try do
            {:ok, 1}
          rescue
            e in [RuntimeError] ->
              {:error, :exception}
          end
        end
      end
      """

      confirm_fix(fix(input), input)
    end

    test "returns source unchanged when the source does not parse" do
      input = """
      defmodule M do
        def run do
      """

      confirm_fix(fix(input), input)
    end

    test "returns source unchanged when the message names no module" do
      msg = "struct is undefined (module is not available or is yet to be defined)"

      input = """
      defmodule M do
        def run do
          try do
            :ok
          rescue
            e in [NotImplementedError, RuntimeError] -> e
          end
        end
      end
      """

      confirm_fix(fix(input, msg), input)
    end
  end
end
