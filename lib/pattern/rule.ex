defmodule Credence.Pattern.Rule do
  @moduledoc """
  Behaviour for pattern-level rules that detect and fix anti-patterns.

  These rules work on parsed ASTs and are the core of Credence's
  80+ anti-pattern detection rules.
  """

  @callback priority() :: integer()

  @doc "Detect issues in the AST. Returns list of issues."
  @callback check(ast :: Macro.t(), opts :: keyword()) :: [Credence.Issue.t()]

  @doc "Auto-fix the source code. Returns modified source string."
  @callback fix(source :: String.t(), opts :: keyword()) :: String.t()

  @doc "Whether this rule supports auto-fixing."
  @callback fixable?() :: boolean()

  defmacro __using__(_opts) do
    quote do
      @behaviour Credence.Pattern.Rule
      alias Credence.Issue

      @impl true
      def fixable?, do: false

      @impl true
      def priority, do: 500

      @impl true
      def fix(source, _opts), do: source

      defoverridable fixable?: 0, priority: 0, fix: 2
    end
  end
end
