defmodule Credence.Semantic.NoHallucinatedFetchPartFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoHallucinatedFetchPart

  @message "function init/1 required by behaviour Plug was implemented as \"defp\" but should have been \"def\" (in module FileUpload.Router)"

  defp fix(source, message, line \\ 1) do
    NoHallucinatedFetchPart.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "replaces Plug.Conn.fetch_part with conn.params access" do
    input = ~S"""
    defmodule FetchPartExample do
      def handle_upload(conn) do
        case Plug.Conn.fetch_part(conn, "file") do
          {:ok, %{file: %Plug.Upload{} = upload}, _} ->
            {:ok, upload}

          _ ->
            {:error, :no_file}
        end
      end
    end
    """

    expected = ~S"""
    defmodule FetchPartExample do
      def handle_upload(conn) do
        case conn.params["file"] do
          %Plug.Upload{} = upload ->
            {:ok, upload}

          _ ->
            {:error, :no_file}
        end
      end
    end
    """

    confirm_fix(fix(input, @message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    defmodule FetchPartExample do
      def handle_upload(conn) do
        case Plug.Conn.fetch_part(conn, "file") do
          {:ok, %{file: %Plug.Upload{} = upload}, _} ->
            {:ok, upload}

          _ ->
            {:error, :no_file}
        end
      end
    end
    """

    assert valid_syntax?(fix(input, @message))
  end

  test "returns source unchanged when no Plug.Conn.fetch_part call" do
    input = ~S"""
    defmodule CleanExample do
      def handle_upload(conn) do
        case conn.params["file"] do
          %Plug.Upload{} = upload ->
            {:ok, upload}

          _ ->
            {:error, :no_file}
        end
      end
    end
    """

    confirm_fix(fix(input, @message), input)
  end
end
