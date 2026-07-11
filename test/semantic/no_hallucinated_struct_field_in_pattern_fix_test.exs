defmodule Credence.Semantic.NoHallucinatedStructFieldInPatternFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoHallucinatedStructFieldInPattern

  defp fix(source, message, line \\ 1) do
    NoHallucinatedStructFieldInPattern.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "removes hallucinated field and inserts File.stat! when variable is used" do
    input =
      """
      defmodule HallucinatedFieldDemo do
        def extract_size(%Plug.Upload{path: path, filename: filename, size: size}) do
          {:ok, size, path, filename}
        end
      end
      """

    expected =
      """
      defmodule HallucinatedFieldDemo do
        def extract_size(%Plug.Upload{path: path, filename: filename}) do
          size = File.stat!(path).size
          {:ok, size, path, filename}
        end
      end
      """

    confirm_fix(fix(input, "key :size not found"), expected)
  end

  test "removes hallucinated field without File.stat! when variable is unused" do
    input =
      """
      defmodule HallucinatedFieldDemo do
        def extract_size(%Plug.Upload{path: path, filename: filename, size: size}) do
          {:ok, path, filename}
        end
      end
      """

    expected =
      """
      defmodule HallucinatedFieldDemo do
        def extract_size(%Plug.Upload{path: path, filename: filename}) do
          {:ok, path, filename}
        end
      end
      """

    confirm_fix(fix(input, "key :size not found"), expected)
  end

  test "fixed output is well-formed (parses)" do
    message = "key :size not found"

    input =
      """
      defmodule HallucinatedFieldDemo do
        def extract_size(%Plug.Upload{path: path, filename: filename, size: size}) do
          {:ok, size, path, filename}
        end
      end
      """

    assert valid_syntax?(fix(input, message))
  end
end
