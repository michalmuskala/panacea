defmodule Panacea.Lexer.DfaTest do
  use ExUnit.Case, async: true

  test "does not crash" do
    assert build("a*")
    assert build("a{1,}")
    assert build("(a|b)[a-z]{2}?[0-9a-z]{5,}")
    assert build("((0[1-9])|([12][0-9])|3[01])(-|/)(0[1-9]|1[0-2])(-|/)([1-9][0-9]{3})")
  end

  defp build(str) do
    assert {:ok, reg} = Panacea.Lexer.Regex.parse(str)
    {nfa, first} = Panacea.Lexer.Nfa.from_regex([{reg, []}])
    Panacea.Lexer.Dfa.build(nfa, first)
  end
end
