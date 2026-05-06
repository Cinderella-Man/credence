defmodule Credence.Pattern.AvoidGraphemesLengthTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.AvoidGraphemesLength.check(ast, [])
  end

  describe "AvoidGraphemesLength" do
    # --- POSITIVE CASES (should flag) ---

    test "flags simple pipeline" do
      code = """
      defmodule Example do
        def run(str), do: str |> String.graphemes() |> length()
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :avoid_graphemes_length
    end

    test "flags length(String.graphemes(str))" do
      code = """
      defmodule Example do
        def run(str), do: length(String.graphemes(str))
      end
      """

      assert length(check(code)) == 1
    end

    test "flags with longer pipeline before graphemes" do
      code = """
      defmodule Example do
        def run(str), do:
          str
          |> String.trim()
          |> String.upcase()
          |> String.graphemes()
          |> length()
      end
      """

      assert length(check(code)) == 1
    end

    test "flags inside Enum.map" do
      code = """
      Enum.map(list, fn x ->
        String.graphemes(x) |> length()
      end)
      """

      assert length(check(code)) == 1
    end

    test "flags nested pipeline in tuple" do
      code = """
      Enum.map(list, &{&1, &1 |> String.graphemes() |> length()})
      """

      assert length(check(code)) == 1
    end

    # --- NEGATIVE CASES (should NOT flag) ---

    test "does not flag String.length/1" do
      code = """
      defmodule Example do
        def run(str), do: String.length(str)
      end
      """

      assert check(code) == []
    end

    test "does not flag when graphemes result is used" do
      code = """
      defmodule Example do
        def run(str), do: String.graphemes(str) |> Enum.reverse()
      end
      """

      assert check(code) == []
    end

    test "does not flag when there is an intermediate step before length" do
      code = """
      defmodule Example do
        def run(str), do:
          str
          |> String.graphemes()
          |> Enum.map(& &1)
          |> length()
      end
      """

      assert check(code) == []
    end

    test "does not flag when length is applied later after transformations" do
      code = """
      defmodule Example do
        def run(str), do:
          str
          |> String.graphemes()
          |> Enum.filter(&(&1 != " "))
          |> length()
      end
      """

      assert check(code) == []
    end

    test "does not flag unrelated length usage" do
      code = """
      defmodule Example do
        def run(list), do: length(list)
      end
      """

      assert check(code) == []
    end

    test "does not flag graphemes stored then counted later" do
      code = """
      defmodule Example do
        def run(str) do
          g = String.graphemes(str)
          length(g)
        end
      end
      """

      assert check(code) == []
    end
  end
end
