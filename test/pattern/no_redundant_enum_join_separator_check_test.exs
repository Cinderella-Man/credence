defmodule Credence.Pattern.NoRedundantEnumJoinSeparatorCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Issue
  alias Credence.Pattern.NoRedundantEnumJoinSeparator

  describe "flags Enum.join with empty string" do
    test "piped Enum.join(\"\")" do
      assert [%Issue{rule: :no_redundant_enum_join_separator}] =
               check(NoRedundantEnumJoinSeparator, """
               list |> Enum.join("")
               """)
    end

    test "direct Enum.join(list, \"\")" do
      assert [%Issue{rule: :no_redundant_enum_join_separator}] =
               check(NoRedundantEnumJoinSeparator, """
               Enum.join(list, "")
               """)
    end

    test "piped in longer pipeline" do
      assert [%Issue{rule: :no_redundant_enum_join_separator}] =
               check(NoRedundantEnumJoinSeparator, """
               list |> Enum.reverse() |> Enum.join("")
               """)
    end
  end

  describe "flags Enum.map_join with empty string" do
    test "piped Enum.map_join(\"\", mapper)" do
      assert [%Issue{rule: :no_redundant_enum_join_separator}] =
               check(NoRedundantEnumJoinSeparator, """
               list |> Enum.map_join("", &to_string/1)
               """)
    end

    test "direct Enum.map_join(list, \"\", mapper)" do
      assert [%Issue{rule: :no_redundant_enum_join_separator}] =
               check(NoRedundantEnumJoinSeparator, """
               Enum.map_join(list, "", &to_string/1)
               """)
    end
  end

  describe "flags multiple violations" do
    test "four patterns in one module" do
      code = """
      defmodule M do
        def f(a, b) do
          x = Enum.join(a, "")
          y = b |> Enum.join("")
          z = Enum.map_join(a, "", &to_string/1)
          w = b |> Enum.map_join("", &to_string/1)
          {x, y, z, w}
        end
      end
      """

      assert length(check(NoRedundantEnumJoinSeparator, code)) == 4
    end
  end

  describe "does NOT flag" do
    test "Enum.join() with no separator" do
      assert check(NoRedundantEnumJoinSeparator, """
             list |> Enum.join()
             """) == []
    end

    test "Enum.join(list) direct with no separator" do
      assert check(NoRedundantEnumJoinSeparator, """
             Enum.join(list)
             """) == []
    end

    test "Enum.join with non-empty separator" do
      assert check(NoRedundantEnumJoinSeparator, """
             Enum.join(list, ", ")
             """) == []
    end

    test "Enum.map_join with no separator" do
      assert check(NoRedundantEnumJoinSeparator, """
             Enum.map_join(list, &to_string/1)
             """) == []
    end

    test "Enum.map_join with non-empty separator" do
      assert check(NoRedundantEnumJoinSeparator, """
             list |> Enum.map_join(", ", &to_string/1)
             """) ==
               []
    end
  end

  describe "metadata" do
    test "meta.line is set" do
      [issue] =
        check(NoRedundantEnumJoinSeparator, """
        Enum.join(list, "")
        """)

      assert issue.meta.line != nil
    end

    test "message mentions default" do
      [issue] =
        check(NoRedundantEnumJoinSeparator, """
        Enum.join(list, "")
        """)

      assert issue.message =~ "default to an empty string"
    end
  end
end
