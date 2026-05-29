defmodule Credence.Pattern.InconsistentParamNamesCheckTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Pattern.InconsistentParamNames

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    InconsistentParamNames.check(ast, [])
  end

  describe "flags inconsistent parameter names" do
    test "name drift in do_fibonacci (current vs prev)" do
      code = """
      defmodule Bad do
        defp do_fibonacci(current, _next, 0), do: current

        defp do_fibonacci(prev, current, steps) do
          do_fibonacci(current, prev + current, steps - 1)
        end
      end
      """

      [issue, issue2] = check(code)
      assert issue.rule == :inconsistent_param_names
      assert issue.message =~ "current"
      assert issue.message =~ "prev"
      assert issue.message =~ "position 1"
      assert issue2.rule == :inconsistent_param_names
      assert issue2.message =~ "current"
      assert issue2.message =~ "next"
      assert issue2.message =~ "position 2"
    end

    test "drift in def (not just defp)" do
      code = """
      defmodule Bad do
        def process(input, count), do: {input, count}
        def process(data, n), do: {data, n}
      end
      """

      issues = check(code)
      assert length(issues) == 2

      messages = Enum.map(issues, & &1.message)
      assert Enum.any?(messages, &(&1 =~ "position 1"))
      assert Enum.any?(messages, &(&1 =~ "position 2"))
    end

    test "drift in guarded clauses" do
      code = """
      defmodule Bad do
        defp loop(num, divisor) when rem(num, divisor) == 0 do
          loop(div(num, divisor), divisor)
        end

        defp loop(n, i) when i * i <= n do
          loop(n, i + 1)
        end

        defp loop(n, _i), do: n
      end
      """

      issues = check(code)
      assert length(issues) == 2
      assert hd(issues).message =~ "position 1"
    end

    test "multiple positions with drift" do
      code = """
      defmodule Bad do
        defp helper(alpha, beta, gamma), do: {alpha, beta, gamma}
        defp helper(first, second, third), do: {first, second, third}
      end
      """

      assert length(check(code)) == 3
    end

    test "drift across three clauses" do
      code = """
      defmodule Bad do
        def transform(val, opts), do: {val, opts}
        def transform(value, options), do: {value, options}
        def transform(x, config), do: {x, config}
      end
      """

      issues = check(code)
      assert length(issues) == 2

      pos1 = Enum.find(issues, &(&1.message =~ "position 1"))
      assert pos1.message =~ "val"
      assert pos1.message =~ "value"
      assert pos1.message =~ "x"
    end

    test "drift when one clause is guarded and another is not" do
      code = """
      defmodule Bad do
        defp do_largest_cont_sum(list, current, best) when is_list(list) do
          {list, current, best}
        end

        defp do_largest_cont_sum(nums, curr_sum, max_sum) do
          {nums, curr_sum, max_sum}
        end
      end
      """

      assert length(check(code)) == 3
    end

    test "_number vs banana (base name number vs banana)" do
      code = """
      defmodule Bad do
        def process(_number, opts), do: opts
        def process(banana, opts), do: {banana, opts}
      end
      """

      [%Issue{rule: :inconsistent_param_names, message: msg}] = check(code)
      assert msg =~ "position 1"
    end

    test "data vs input when underscore matches" do
      code = """
      defmodule Bad do
        defp process(data, _opts), do: data
        defp process(input, opts), do: {input, opts}
      end
      """

      [%Issue{message: msg}] = check(code)
      assert msg =~ "position 1"
    end
  end

  describe "does NOT flag" do
    test "consistent names" do
      assert check("""
             defmodule Good do
               defp do_fibonacci(prev, _current, 0), do: prev

               defp do_fibonacci(prev, current, steps) do
                 do_fibonacci(current, prev + current, steps - 1)
               end
             end
             """) == []
    end

    test "_number vs number (same base name)" do
      assert check("""
             defmodule Good do
               def process(_number, opts), do: opts
               def process(number, opts), do: {number, opts}
             end
             """) == []
    end

    test "patterns that differ (legitimate dispatch)" do
      assert check("""
             defmodule Good do
               def handle({:ok, result}), do: result
               def handle({:error, reason}), do: raise(reason)
             end
             """) == []
    end

    test "literals at a position" do
      assert check("""
             defmodule Good do
               def factorial(0, acc), do: acc
               def factorial(n, acc), do: factorial(n - 1, n * acc)
             end
             """) == []
    end

    test "single-clause functions" do
      assert check("""
             defmodule Good do
               defp helper(data, count), do: {data, count}
             end
             """) == []
    end

    test "different functions that share names" do
      assert check("""
             defmodule Good do
               def process(data), do: data
               def transform(input), do: input
             end
             """) == []
    end

    test "functions with different arities" do
      assert check("""
             defmodule Good do
               def foo(alpha), do: alpha
               def foo(first, second), do: {first, second}
             end
             """) == []
    end

    test "list/cons patterns at a position" do
      assert check("""
             defmodule Good do
               def count([], acc), do: acc
               def count([_h | t], acc), do: count(t, acc + 1)
             end
             """) == []
    end

    test "map/struct patterns at a position" do
      assert check("""
             defmodule Good do
               def get(%{key: val}, default), do: val || default
               def get(container, default), do: {container, default}
             end
             """) == []
    end

    test "pinned variables" do
      assert check("""
             defmodule Good do
               def match(^expected, val), do: val
               def match(other, val), do: {other, val}
             end
             """) == []
    end

    test "bare _ (always skips position)" do
      assert check("""
             defmodule Good do
               def process(_, opts), do: opts
               def process(banana, opts), do: {banana, opts}
             end
             """) == []
    end
  end

  # ===========================================================================
  # Pattern-match equality between arguments ("pinning")
  #
  # When the same variable name appears at multiple argument positions within
  # one clause, Elixir requires those arguments to be equal. The name is
  # load-bearing — renaming it to "be consistent" with other clauses either
  # breaks the equality constraint, or invents a new one that wasn't there.
  #
  # Rule: if any clause has a name shared across multiple argument positions
  # (top-level OR nested inside tuples/lists/maps/structs/binaries), every
  # position that participates in that sharing is skipped from analysis
  # across the whole clause group.
  # ===========================================================================

  describe "does NOT flag — argument pattern-match equality" do
    test "two args share the same name in the first clause" do
      assert check("""
             defmodule Good do
               def equal_pair(x, x), do: x
               def equal_pair(a, b), do: {a, b}
             end
             """) == []
    end

    test "two args share the same name in a later clause" do
      assert check("""
             defmodule Good do
               def equal_pair(a, b), do: {a, b}
               def equal_pair(x, x), do: x
             end
             """) == []
    end

    test "three args share the same name" do
      assert check("""
             defmodule Good do
               def triple(x, x, x), do: x
               def triple(a, b, c), do: {a, b, c}
             end
             """) == []
    end

    test "underscored pinning (_x appearing twice in a clause)" do
      assert check("""
             defmodule Good do
               def f(_x, _x), do: :equal
               def f(a, b), do: {a, b}
             end
             """) == []
    end

    test "mixed underscored vs non-underscored sharing the same base" do
      assert check("""
             defmodule Good do
               def f(answer, _answer), do: answer
               def f(a, b), do: {a, b}
             end
             """) == []
    end

    test "original validate_answers_match example" do
      assert check("""
             defmodule Good do
               def validate_answers_match(errors, question, answer, answer)
                   when is_binary(question) and is_binary(answer), do: errors

               def validate_answers_match(errors, question, answer, confirm)
                   when is_binary(question) and is_binary(answer) and is_binary(confirm) do
                 [{"confirm_shared_secret_answer", "mismatch"} | errors]
               end

               def validate_answers_match(errors, _question, _answer, _confirm), do: errors
             end
             """) == []
    end

    test "every clause has pinning at the same positions" do
      assert check("""
             defmodule Good do
               def f(a, a), do: a
               def f(b, b), do: b
             end
             """) == []
    end

    test "clauses have pinning at different positions" do
      assert check("""
             defmodule Good do
               def f(x, x, z), do: {x, z}
               def f(a, b, b), do: {a, b}
             end
             """) == []
    end

    test "pinning at every position" do
      assert check("""
             defmodule Good do
               def f(x, x), do: x
               def f(a, a), do: a
               def f(b, b), do: b
             end
             """) == []
    end

    test "pinning detected in any one of three+ clauses skips that position globally" do
      assert check("""
             defmodule Good do
               def f(a, b), do: {a, b}
               def f(x, x), do: x
               def f(c, d), do: {c, d}
             end
             """) == []
    end

    test "symmetric-pair case across clauses" do
      assert check("""
             defmodule Good do
               def swap(a, b), do: {a, b}
               def swap(x, x), do: x
             end
             """) == []
    end
  end

  describe "does NOT flag — nested pattern equality" do
    test "name shared with a tuple element at another position" do
      assert check("""
             defmodule Good do
               def f(x, {x, _other}), do: x
               def f(alpha, {beta, _other}), do: {alpha, beta}
             end
             """) == []
    end

    test "name shared with a list-head element" do
      assert check("""
             defmodule Good do
               def f(h, [h | _t]), do: h
               def f(first, [_head | _tail]), do: first
             end
             """) == []
    end

    test "name shared with a list-tail variable" do
      assert check("""
             defmodule Good do
               def f(t, [_h | t]), do: t
               def f(tail, [_h | _other]), do: tail
             end
             """) == []
    end

    test "name shared with a map value at another position" do
      assert check("""
             defmodule Good do
               def f(v, %{key: v}), do: v
               def f(value, %{key: _other}), do: value
             end
             """) == []
    end

    test "name shared with a struct field at another position" do
      assert check("""
             defmodule Good do
               def f(id, %User{id: id}), do: id
               def f(uid, %User{id: _other}), do: uid
             end
             """) == []
    end

    test "name shared with a deeply nested element" do
      assert check("""
             defmodule Good do
               def f(x, {:ok, {x, _meta}}), do: x
               def f(alpha, {:ok, {_beta, _meta}}), do: alpha
             end
             """) == []
    end

    test "name shared inside a binary pattern" do
      assert check("""
             defmodule Good do
               def f(n, <<n::8, _rest::binary>>), do: n
               def f(byte, <<_b::8, _rest::binary>>), do: byte
             end
             """) == []
    end

    test "underscored name shared between top-level and nested" do
      assert check("""
             defmodule Good do
               def f(_answer, %{value: _answer}), do: :ok
               def f(answer, %{value: _other}), do: answer
             end
             """) == []
    end

    test "sharing across two non-variable positions (tuple/tuple)" do
      assert check("""
             defmodule Good do
               def f({x, _}, {x, _}), do: x
               def f({a, _}, {b, _}), do: {a, b}
             end
             """) == []
    end
  end

  describe "still flags at non-pinned positions" do
    test "with pinning at positions 1+2, inconsistency at position 3 is flagged" do
      code = """
      defmodule Bad do
        def f(x, x, alpha), do: {x, alpha}
        def f(a, b, beta),  do: {a, b, beta}
      end
      """

      [%Issue{message: msg}] = check(code)
      assert msg =~ "position 3"
      assert msg =~ "alpha"
      assert msg =~ "beta"
    end

    test "with pinning at non-adjacent positions 1+3, inconsistency at position 2 is flagged" do
      code = """
      defmodule Bad do
        def f(x, mid, x), do: {x, mid}
        def f(a, middle, c), do: {a, middle, c}
      end
      """

      [%Issue{message: msg}] = check(code)
      assert msg =~ "position 2"
    end

    test "nested pinning skips affected positions but flags inconsistency elsewhere" do
      code = """
      defmodule Bad do
        def f(x, {x, _meta}, alpha), do: {x, alpha}
        def f(a, {b, _meta}, beta), do: {a, b, beta}
      end
      """

      [%Issue{message: msg}] = check(code)
      assert msg =~ "position 3"
    end

    test "intra-arg duplication leaves unrelated positions analysable" do
      code = """
      defmodule Bad do
        def f({a, a}, b), do: {a, b}
        def f({x, y}, c), do: {x, y, c}
      end
      """

      [%Issue{message: msg}] = check(code)
      assert msg =~ "position 2"
    end
  end

  describe "flags inconsistency across attribute-annotated clauses" do
    test "@impl true between handle_call clauses" do
      code = """
      defmodule Server do
        @impl true
        def handle_call(:get, _from, state), do: {:reply, state, state}

        @impl true
        def handle_call(:reset, _from, server_state), do: {:reply, :ok, server_state}
      end
      """

      [%Issue{message: msg}] = check(code)
      assert msg =~ "position 3"
      assert msg =~ "state"
      assert msg =~ "server_state"
    end

    test "@doc between clauses" do
      code = """
      defmodule Math do
        @doc "positive"
        def sign(n) when n > 0, do: 1

        @doc "negative"
        def sign(num) when num < 0, do: -1
      end
      """

      [%Issue{message: msg}] = check(code)
      assert msg =~ "position 1"
    end

    test "mixed @doc + @spec + @impl annotations" do
      code = """
      defmodule Mixed do
        @doc "first"
        @spec f(integer()) :: integer()
        @impl true
        def f(num), do: num + 1

        @doc "second"
        @impl true
        def f(n) when n > 100, do: n * 2
      end
      """

      [%Issue{message: msg}] = check(code)
      assert msg =~ "position 1"
    end
  end

  describe "does NOT flag with attributes when names are consistent" do
    test "@impl + consistently named state across clauses" do
      assert check("""
             defmodule Server do
               @impl true
               def handle_call(:get, _from, state), do: {:reply, state, state}

               @impl true
               def handle_call(:reset, _from, state), do: {:reply, :ok, state}
             end
             """) == []
    end

    test "@impl-annotated clauses with pattern-match equality (pinning)" do
      assert check("""
             defmodule Pinned do
               @impl true
               def f(x, x), do: x

               @impl true
               def f(a, b), do: {a, b}
             end
             """) == []
    end

    test "separate callback functions (handle_call vs handle_cast) are not grouped" do
      assert check("""
             defmodule Two do
               @impl true
               def handle_call(_msg, _from, state), do: {:reply, :ok, state}

               @impl true
               def handle_cast(_msg, server), do: {:noreply, server}
             end
             """) == []
    end
  end

  describe "does NOT flag — real-world idiomatic patterns" do
    test "Phoenix-style handle_event with string discriminator" do
      assert check("""
             defmodule Live do
               def handle_event("save", %{"user" => params}, socket) do
                 {:noreply, assign(socket, :params, params)}
               end

               def handle_event("cancel", _params, socket) do
                 {:noreply, socket}
               end

               def handle_event("reset", _params, socket) do
                 {:noreply, socket}
               end
             end
             """) == []
    end

    test "GenServer-style handle_call with tag discriminator" do
      assert check("""
             defmodule Server do
               def handle_call({:get, key}, _from, state), do: {:reply, Map.get(state, key), state}
               def handle_call({:put, key, value}, _from, state), do: {:reply, :ok, Map.put(state, key, value)}
               def handle_call(:stop, _from, state), do: {:stop, :normal, :ok, state}
             end
             """) == []
    end

    test "classic recursive list processing with accumulator" do
      assert check("""
             defmodule Lists do
               def reverse([], acc), do: acc
               def reverse([h | t], acc), do: reverse(t, [h | acc])
             end
             """) == []
    end

    test "tagged-tuple result dispatch" do
      assert check("""
             defmodule Result do
               def unwrap({:ok, value}), do: value
               def unwrap({:error, reason}), do: raise(reason)
             end
             """) == []
    end

    test "guarded numeric dispatch" do
      assert check("""
             defmodule Math do
               def sign(n) when n > 0, do: 1
               def sign(n) when n < 0, do: -1
               def sign(n) when n == 0, do: 0
             end
             """) == []
    end

    test "binary-prefix routing" do
      assert check("""
             defmodule Route do
               def handle("/api/" <> rest, conn), do: {:api, rest, conn}
               def handle("/admin/" <> rest, conn), do: {:admin, rest, conn}
               def handle(path, conn), do: {:public, path, conn}
             end
             """) == []
    end
  end
end
