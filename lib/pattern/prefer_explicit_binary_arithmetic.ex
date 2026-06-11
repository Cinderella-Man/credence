defmodule Credence.Pattern.PreferExplicitBinaryArithmetic do
  @moduledoc """
  Readability rule: flags piping into binary arithmetic functions like `rem/2`
  or `div/2`. Piping obscures which argument is the dividend — prefer an
  explicit call for clarity.

  ## Bad

      String.length(input_string) |> rem(3)
      numerator |> div(denominator)

  ## Good

      rem(String.length(input_string), 3)
      div(numerator, denominator)
  """
  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  # Kernel binary arithmetic functions that are clearer as explicit calls.
  @binary_arithmetic_fns ~w(rem div)a

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:|>, pipe_meta,
         [
           left,
           {fun, fun_meta, [right]}
         ]} = node,
        issues
        when fun in @binary_arithmetic_fns and is_list(fun_meta) and
               is_list(pipe_meta) and right != nil and left != nil ->
          line = Keyword.get(fun_meta, :line) || Keyword.get(pipe_meta, :line)

          {node,
           [
             %Issue{
               rule: :prefer_explicit_binary_arithmetic,
               message:
                 "Piping into `#{fun}/2` obscures which argument is the dividend. " <> 
                   "Use `#{fun}(a, b)` for clarity.",
               meta: %{line: line}
             }
             | issues
           ]}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    RuleHelpers.patches_from_postwalk(ast, fn
      {:|>, _pipe_meta,
       [
         left,
         {fun, _fun_meta, [right]}
       ]}
      when fun in @binary_arithmetic_fns and right != nil and left != nil ->
        {fun, [], [left, right]}

      node ->
        node
    end)
  end
end
