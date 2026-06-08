defmodule Credence.RuleName do
  @moduledoc """
  The one place that turns a rule's name into every derived form — snake, Pascal,
  rule atom, rule module, and the conventional paths/modules of its test files.

  The naming convention (rule `Credence.Pattern.NoFoo` lives at
  `lib/pattern/no_foo.ex`; its check test is `test/pattern/no_foo_check_test.exs`
  defining `Credence.Pattern.NoFooCheckTest`) used to be re-typed in several places
  — `MetaTestSupport.test_path/2`, `RuleTestCompletenessTest`, and (soon) the
  generator and its pin. Re-typing means the copies can drift. Here it is derived
  once, and everyone — the generator that *writes* the files, the gates that
  *check* them, and the pin that proves the generator matches the gates — calls
  the same code. There is nothing to drift from.
  """

  @types %{pattern: "Pattern", syntax: "Syntax", semantic: "Semantic"}

  @type rule_type :: :pattern | :syntax | :semantic
  @type derived :: %{
          type: rule_type(),
          snake: String.t(),
          pascal: String.t(),
          atom: atom(),
          rule_module: module(),
          rule_path: String.t(),
          test_dir: String.t()
        }

  @doc """
  Derive every name form from a rule `name` (`"NoFooBar"` or `"no_foo_bar"`) and
  its `type`.
  """
  @spec derive(String.t(), rule_type()) :: derived()
  def derive(name, type) when is_binary(name) and is_map_key(@types, type) do
    snake = Macro.underscore(name)
    pascal = Macro.camelize(snake)

    %{
      type: type,
      snake: snake,
      pascal: pascal,
      atom: String.to_atom(snake),
      rule_module: Module.concat([Credence, @types[type], pascal]),
      rule_path: "lib/#{type}/#{snake}.ex",
      test_dir: "test/#{type}"
    }
  end

  @doc """
  Derive from an existing rule module, inferring the type from its namespace.
  Used by the gates, which iterate over discovered rule modules.
  """
  @spec from_module(module()) :: derived()
  def from_module(module) do
    case Module.split(module) do
      ["Credence", "Pattern", short] -> derive(short, :pattern)
      ["Credence", "Syntax", short] -> derive(short, :syntax)
      ["Credence", "Semantic", short] -> derive(short, :semantic)
    end
  end

  @doc ~S"""
  The conventional path of a rule's `kind` test file
  (`"test/<type>/<snake>_<kind>_test.exs"`). `kind` is `"check"`, `"fix"`,
  `"equivalence"`, `"analyze"`, …
  """
  @spec test_path(derived(), String.t()) :: String.t()
  def test_path(%{test_dir: dir, snake: snake}, kind), do: "#{dir}/#{snake}_#{kind}_test.exs"

  @doc ~S"""
  The conventionally-named test module for a rule's `kind` file, e.g.
  `Credence.Pattern.NoFooCheckTest` for `kind` `"check"`.
  """
  @spec test_module(derived(), String.t()) :: module()
  def test_module(%{type: type, pascal: pascal}, kind) do
    Module.concat([Credence, @types[type], :"#{pascal}#{Macro.camelize(kind)}Test"])
  end
end
