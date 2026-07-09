defmodule Credence.Semantic.NoRescueInWithExpressionFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoRescueInWithExpression

  @rescue_diag %{severity: :error, message: "unexpected option :rescue in \"with\"", position: {1, 1}}
  @catch_diag %{severity: :error, message: "unexpected option :catch in \"with\"", position: {1, 1}}

  defp fix(source, diag \\ @rescue_diag) do
    NoRescueInWithExpression.fix(source, diag)
  end

  test "removes rescue and catch, moves catch to else" do
    input = ~S"""
    with {:ok, dt} <- DateTime.from_iso8601(timestamp) do
      {:ok, dt}
    rescue
      _ -> {:ok, DateTime.from_iso8601!(String.replace(timestamp, "Z", "+00:00"))}
    catch
      _ -> {:error, :invalid_timestamp}
    end
    """

    expected = ~S"""
    with {:ok, dt} <- DateTime.from_iso8601(timestamp) do
      {:ok, dt}
    else
      _ -> {:error, :invalid_timestamp}
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "removes rescue and catch, replaces existing else with catch" do
    input = ~S"""
    with {:ok, dt} <- DateTime.from_iso8601(timestamp) do
      {:ok, dt}
    rescue
      _ -> {:ok, DateTime.from_iso8601!(String.replace(timestamp, "Z", "+00:00"))}
    else
      dt when is_map(dt) -> {:ok, dt}
    catch
      _ -> {:error, :invalid_timestamp}
    end
    """

    expected = ~S"""
    with {:ok, dt} <- DateTime.from_iso8601(timestamp) do
      {:ok, dt}
    else
      _ -> {:error, :invalid_timestamp}
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "removes rescue only, moves rescue to else" do
    input = ~S"""
    with {:ok, dt} <- DateTime.from_iso8601(timestamp) do
      {:ok, dt}
    rescue
      _ -> {:ok, DateTime.from_iso8601!(String.replace(timestamp, "Z", "+00:00"))}
    end
    """

    expected = ~S"""
    with {:ok, dt} <- DateTime.from_iso8601(timestamp) do
      {:ok, dt}
    else
      _ -> {:ok, DateTime.from_iso8601!(String.replace(timestamp, "Z", "+00:00"))}
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "removes catch only, moves catch to else" do
    input = ~S"""
    with {:ok, dt} <- DateTime.from_iso8601(timestamp) do
      {:ok, dt}
    catch
      _ -> {:error, :invalid_timestamp}
    end
    """

    expected = ~S"""
    with {:ok, dt} <- DateTime.from_iso8601(timestamp) do
      {:ok, dt}
    else
      _ -> {:error, :invalid_timestamp}
    end
    """

    confirm_fix(fix(input, @catch_diag), expected)
  end

  test "leaves with expression unchanged when no rescue/catch" do
    input = ~S"""
    with {:ok, dt} <- DateTime.from_iso8601(timestamp) do
      {:ok, dt}
    end
    """

    confirm_fix(fix(input), input)
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    with {:ok, dt} <- DateTime.from_iso8601(timestamp) do
      {:ok, dt}
    rescue
      _ -> {:ok, DateTime.from_iso8601!(String.replace(timestamp, "Z", "+00:00"))}
    catch
      _ -> {:error, :invalid_timestamp}
    end
    """

    assert valid_syntax?(fix(input))
  end
end
