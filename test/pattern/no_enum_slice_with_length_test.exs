defmodule Credence.Pattern.NoEnumSliceWithLengthTest do
  use ExUnit.Case

  alias Credence.Pattern.NoEnumSliceWithLength

  describe "check/2" do
    test "flags Enum.slice(x, 0, length(x) - 1)" do
      source = """
      defmodule M do
        def drop_last(list) do
          Enum.slice(list, 0, length(list) - 1)
        end
      end
      """

      ast = Sourceror.parse_string!(source)
      issues = NoEnumSliceWithLength.check(ast, [])
      assert length(issues) == 1
      assert hd(issues).rule == :no_enum_slice_with_length
      assert hd(issues).message =~ "Enum.slice"
      assert hd(issues).message =~ "0..-2//1"
    end

    test "flags Enum.slice(x, 0, length(x) - 2)" do
      source = """
      defmodule M do
        def drop_two(list) do
          Enum.slice(list, 0, length(list) - 2)
        end
      end
      """

      ast = Sourceror.parse_string!(source)
      issues = NoEnumSliceWithLength.check(ast, [])
      assert length(issues) == 1
      assert hd(issues).message =~ "0..-3//1"
    end

    test "does not flag Enum.slice with a literal count" do
      source = """
      defmodule M do
        def take(list) do
          Enum.slice(list, 0, 5)
        end
      end
      """

      ast = Sourceror.parse_string!(source)
      issues = NoEnumSliceWithLength.check(ast, [])
      assert issues == []
    end

    test "does not flag Enum.slice with a non-zero start" do
      source = """
      defmodule M do
        def middle(list) do
          Enum.slice(list, 1, length(list) - 1)
        end
      end
      """

      ast = Sourceror.parse_string!(source)
      issues = NoEnumSliceWithLength.check(ast, [])
      assert issues == []
    end

    test "does not flag Enum.slice with a different variable's length" do
      source = """
      defmodule M do
        def pick(list, other) do
          Enum.slice(list, 0, length(other) - 1)
        end
      end
      """

      ast = Sourceror.parse_string!(source)
      issues = NoEnumSliceWithLength.check(ast, [])
      assert issues == []
    end

    test "does not flag Enum.slice without length" do
      source = """
      defmodule M do
        def take(list, n) do
          Enum.slice(list, 0, n)
        end
      end
      """

      ast = Sourceror.parse_string!(source)
      issues = NoEnumSliceWithLength.check(ast, [])
      assert issues == []
    end

    test "flags the pattern from the row log" do
      source = """
      defmodule Solution do
        defp palindrome_helper(chars) do
          case chars do
            [first | rest] ->
              last = List.last(rest)
              middle = Enum.slice(rest, 0, length(rest) - 1)

              if first == last do
                palindrome_helper(middle)
              else
                false
              end
          end
        end
      end
      """

      ast = Sourceror.parse_string!(source)
      issues = NoEnumSliceWithLength.check(ast, [])
      assert length(issues) == 1
      assert hd(issues).rule == :no_enum_slice_with_length
    end
  end

  describe "fix_patches/2" do
    test "rewrites Enum.slice(x, 0, length(x) - 1) to Enum.slice(x, 0..-2//1)" do
      source = """
      defmodule M do
        def drop_last(list) do
          Enum.slice(list, 0, length(list) - 1)
        end
      end
      """

      ast = Sourceror.parse_string!(source)
      patches = NoEnumSliceWithLength.fix_patches(ast, source: source)
      assert length(patches) == 1

      fixed = Sourceror.patch_string(source, patches)
      assert fixed =~ "Enum.slice(list, 0..-2//1)"
      refute fixed =~ "length(list)"
    end

    test "rewrites Enum.slice(x, 0, length(x) - 2) to Enum.slice(x, 0..-3//1)" do
      source = """
      defmodule M do
        def drop_two(list) do
          Enum.slice(list, 0, length(list) - 2)
        end
      end
      """

      ast = Sourceror.parse_string!(source)
      patches = NoEnumSliceWithLength.fix_patches(ast, source: source)
      assert length(patches) == 1

      fixed = Sourceror.patch_string(source, patches)
      assert fixed =~ "Enum.slice(list, 0..-3//1)"
    end

    test "returns no patches for non-matching patterns" do
      source = """
      defmodule M do
        def take(list, n) do
          Enum.slice(list, 0, n)
        end
      end
      """

      ast = Sourceror.parse_string!(source)
      patches = NoEnumSliceWithLength.fix_patches(ast, source: source)
      assert patches == []
    end
  end

  # ── Integration through Credence.Pattern ──────────────────────────

  describe "integration" do
    test "detected through pattern pipeline" do
      source = """
      defmodule IntegSliceLen do
        def drop_last(list) do
          Enum.slice(list, 0, length(list) - 1)
        end
      end
      """

      issues = Credence.Pattern.analyze(source)
      found = Enum.filter(issues, &(&1.rule == :no_enum_slice_with_length))
      assert length(found) == 1
    end

    test "not flagged for literal count" do
      source = """
      defmodule IntegSliceLenOk do
        def take_five(list) do
          Enum.slice(list, 0, 5)
        end
      end
      """

      issues = Credence.Pattern.analyze(source)
      found = Enum.filter(issues, &(&1.rule == :no_enum_slice_with_length))
      assert found == []
    end
  end
end
