defmodule Credence.Pattern.NoCodepointStringReverseFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoCodepointStringReverse
  alias Credence.RuleHelpers

  describe "fix — codepoints → String.reverse" do
    test "fixes codepoints |> reverse |> IO.iodata_to_binary" do
      input =
        "def r(str), do: str |> String.codepoints() |> Enum.reverse() |> IO.iodata_to_binary()"

      expected = "def r(str), do: String.reverse(str)"

      confirm_fix(fix(NoCodepointStringReverse, input), expected)
    end

    test "fixes codepoints |> reverse |> Enum.join" do
      input = "def r(str), do: str |> String.codepoints() |> Enum.reverse() |> Enum.join()"

      expected = "def r(str), do: String.reverse(str)"

      confirm_fix(fix(NoCodepointStringReverse, input), expected)
    end

    test "fixes nested IO.iodata_to_binary(Enum.reverse(String.codepoints(...)))" do
      input = "def r(str), do: IO.iodata_to_binary(Enum.reverse(String.codepoints(str)))"

      expected = "def r(str), do: String.reverse(str)"

      confirm_fix(fix(NoCodepointStringReverse, input), expected)
    end

    test "keeps upstream pipeline, replaces last steps" do
      input =
        "def r(str), do: str |> String.trim() |> String.codepoints() |> Enum.reverse() |> Enum.join()"

      expected = "def r(str), do: str |> String.trim() |> String.reverse()"

      confirm_fix(fix(NoCodepointStringReverse, input), expected)
    end

    test "does not touch graphemes decompose" do
      code = "def r(str), do: str |> String.graphemes() |> Enum.reverse() |> Enum.join()"

      confirm_fix(fix(NoCodepointStringReverse, code), code)
    end

    test "does not touch Enum.join with separator" do
      code = ~S'def r(str), do: str |> String.codepoints() |> Enum.reverse() |> Enum.join("-")'

      confirm_fix(fix(NoCodepointStringReverse, code), code)
    end

    test "does not combine the module and function halves of different reassemblers" do
      for {module_name, module_alias, function} <- [
            {"CrossProductIOJoin", "IO", "join"},
            {"CrossProductEnumIodata", "Enum", "iodata_to_binary"}
          ] do
        input = """
        defmodule #{module_name} do
          defmodule ApplicationModule do
            def #{function}(_codepoints), do: :application_answer
            def reverse(items), do: :lists.reverse(items)
          end

          alias ApplicationModule, as: #{module_alias}

          def run(string) do
            #{module_alias}.#{function}(Enum.reverse(String.codepoints(string)))
          end
        end

        :application_answer = #{module_name}.run("abc")
        """

        emitted = fix(NoCodepointStringReverse, input)

        confirm_fix(emitted, input)
        assert {:ok, []} = RuleHelpers.compile_and_capture(input)
        assert RuleHelpers.compile_and_capture(emitted) == RuleHelpers.compile_and_capture(input)
      end
    end
  end
end
