defmodule Credence.Semantic.NoPlugUploadSizeFieldFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoPlugUploadSizeField

  defp fix(source, message, line \\ 1) do
    NoPlugUploadSizeField.fix(source, %{severity: :error, message: message, position: {line, 1}})
  end

  test "removes size from Plug.Upload pattern and function calls" do
    input =
      ~S'''
      defmodule FileUpload.Validator do
        @moduledoc """
        Validates uploaded files according to type-specific rules.
        """

        @doc """
        Validates an upload struct according to type-specific rules.

        Returns `:ok` on success, or `{:error, reason}` on failure.
        """
        @spec validate(%Plug.Upload{}) :: :ok | {:error, String.t()}
        def validate(%Plug.Upload{path: path, filename: filename, size: size}) do
          case Path.extname(filename) |> String.downcase() do
            ".csv" -> validate_csv(path, size)
            ".json" -> validate_json(path)
            _ -> {:error, "File type not allowed. Only .csv and .json files are accepted"}
          end
        end

        defp validate_csv(path, size) do
          with {:ok, content} <- File.read(path) do
            lines = String.split(content, "\n")

            lines =
              if List.last(lines) == "" do
                Enum.drop(lines, -1)
              else
                lines
              end

            case lines do
              [] ->
                {:error, "Invalid CSV: file must contain a header row with multiple columns"}

              [_] = single_line ->
                if String.contains?(hd(single_line), ",") do
                  :ok
                else
                  {:error, "Invalid CSV: file must contain a header row with multiple columns"}
                end

              _ ->
                :ok
            end
          else
            _ -> {:error, "Failed to read file content"}
          end
        end

        defp validate_json(path) do
          with {:ok, content} <- File.read(path) do
            case Jason.decode(content) do
              {:ok, _} -> :ok
              {:error, error} -> {:error, "Invalid JSON: #{inspect(error)}"}
            end
          else
            _ -> {:error, "Failed to read file content"}
          end
        end
      end
      '''

    expected =
      ~S'''
      defmodule FileUpload.Validator do
        @moduledoc """
        Validates uploaded files according to type-specific rules.
        """

        @doc """
        Validates an upload struct according to type-specific rules.

        Returns `:ok` on success, or `{:error, reason}` on failure.
        """
        @spec validate(%Plug.Upload{}) :: :ok | {:error, String.t()}
        def validate(%Plug.Upload{path: path, filename: filename}) do
          case Path.extname(filename) |> String.downcase() do
            ".csv" -> validate_csv(path)
            ".json" -> validate_json(path)
            _ -> {:error, "File type not allowed. Only .csv and .json files are accepted"}
          end
        end

        defp validate_csv(path) do
          with {:ok, content} <- File.read(path) do
            lines = String.split(content, "\n")

            lines =
              if List.last(lines) == "" do
                Enum.drop(lines, -1)
              else
                lines
              end

            case lines do
              [] ->
                {:error, "Invalid CSV: file must contain a header row with multiple columns"}

              [_] = single_line ->
                if String.contains?(hd(single_line), ",") do
                  :ok
                else
                  {:error, "Invalid CSV: file must contain a header row with multiple columns"}
                end

              _ ->
                :ok
            end
          else
            _ -> {:error, "Failed to read file content"}
          end
        end

        defp validate_json(path) do
          with {:ok, content} <- File.read(path) do
            case Jason.decode(content) do
              {:ok, _} -> :ok
              {:error, error} -> {:error, "Invalid JSON: #{inspect(error)}"}
            end
          else
            _ -> {:error, "Failed to read file content"}
          end
        end
      end
      '''

    confirm_fix(fix(input, "unknown key :size for struct Plug.Upload"), expected)
  end

  test "fixed output is well-formed (parses)" do
    input =
      """
      defmodule FileUpload.Validator do
        def validate(%Plug.Upload{path: path, filename: filename, size: size}) do
          validate_csv(path, size)
        end

        defp validate_csv(path, size) do
          :ok
        end
      end
      """

    assert valid_syntax?(fix(input, "unknown key :size for struct Plug.Upload"))
  end
end
