defmodule Credence.Pattern.Rule do
  @moduledoc """
  Behaviour for pattern-level rules that detect and fix anti-patterns.

  These rules work on parsed ASTs and are the core of Credence's
  80+ anti-pattern detection rules.

  ## Fix interface — migration in progress

  The fix interface is being migrated from `fix(source, opts) :: String.t()`
  (full-AST round-trip, layout-fragile) to `fix_patches(ast, opts) :: [patch]`
  (byte-range patches, layout-safe). See `docs/ast-callback-interface-analysis.md`
  for the design rationale.

  During migration:
  - Rules that have migrated implement `fix_patches/2` and the orchestrator
    routes through `Sourceror.patch_string/2`.
  - Rules that have NOT migrated retain `fix/2` and the orchestrator routes
    through the legacy whole-source path.
  - The orchestrator dispatches per rule via `function_exported?/2`.

  Once every rule has migrated, the legacy `fix/2` callback is removed
  and `fix_patches/2` is renamed to `fix/2`.
  """

  @typedoc """
  A byte-range patch against the source string.

  - `range` carries Sourceror-style start/end positions (`[line: L, column: C]`).
  - `change` is the replacement text. Apply via `Sourceror.patch_string/2`.
  """
  @type patch :: %{
          required(:range) => map(),
          required(:change) => String.t()
        }

  @callback priority() :: integer()

  @doc "Detect issues in the AST. Returns list of issues."
  @callback check(ast :: Macro.t(), opts :: keyword()) :: [Credence.Issue.t()]

  @doc """
  Auto-fix via byte-range patches. Returns a list of patches.

  Optional during migration. Once all rules implement this, it replaces
  the legacy `fix/2` callback.
  """
  @callback fix_patches(ast :: Macro.t(), opts :: keyword()) :: [patch()]

  @doc """
  Legacy auto-fix interface. Returns modified source string.

  Being phased out. New rule implementations should define `fix_patches/2`
  instead. Once all rules have migrated, this callback is removed.
  """
  @callback fix(source :: String.t(), opts :: keyword()) :: String.t()

  @doc "Whether this rule supports auto-fixing."
  @callback fixable?() :: boolean()

  @optional_callbacks fix_patches: 2

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
