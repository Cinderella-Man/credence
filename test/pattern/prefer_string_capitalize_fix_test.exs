defmodule Credence.Pattern.PreferStringCapitalizeFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferStringCapitalize

  test "rewrites the anti-pattern" do
    input = """
    defmodule PatternExample do
      defp capitalize_string(""), do: ""

      defp capitalize_string(string) do
        first_char = String.first(string) |> String.upcase()
        rest = String.slice(string, 1, byte_size(string) - String.length(first_char)) |> String.downcase()
        first_char <> rest
      end
    end
    """

    expected = """
    defmodule PatternExample do
      defp capitalize_string(""), do: ""

      defp capitalize_string(string), do: String.capitalize(string)
    end
    """

    assert fix(PreferStringCapitalize, input) == expected
  end

  test "does not modify code already using String.capitalize" do
    code = """
    defmodule Example do
      defp capitalize_string(""), do: ""
      defp capitalize_string(string), do: String.capitalize(string)
    end
    """

    assert fix(PreferStringCapitalize, code) == code
  end

  test "preserves other functions in the module" do
    input = """
    defmodule Example do
      defp capitalize_string(""), do: ""

      defp capitalize_string(string) do
        first_char = String.first(string) |> String.upcase()
        rest = String.slice(string, 1, byte_size(string) - String.length(first_char)) |> String.downcase()
        first_char <> rest
      end

      defp other_func(x), do: x
    end
    """

    expected = """
    defmodule Example do
      defp capitalize_string(""), do: ""

      defp capitalize_string(string), do: String.capitalize(string)

      defp other_func(x), do: x
    end
    """

    assert fix(PreferStringCapitalize, input) == expected
  end
end
