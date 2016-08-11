defmodule Panacea.Lexer.Codegen do
  @moduledoc """
  This generates a name_state function

  name_state(char, state, line, column)

  Actions:
  * {:accept, line, column, action}
  * {:accept, line, column, action, state}
  * {:advance, line, column, state}
  * {:condition, line, column, name, state}

  """

  def compile(name, reas) do
    {dfa, first} = build_dfa(reas)
    name = String.to_atom("#{name}_state")
    initial(name, first) ++ Enum.map(dfa, &transition(name, &1))
  end

  defp transition(name, %{id: id, trans: [], accept: {:accept, action}}) do
    quote do
      defp unquote(name)(_, unquote(id)), do: {:accept, unquote(action)}
    end
  end
  defp transition(name, %{id: id, trans: trans, accept: {:accept, action}}) do

    quote do
      defp unquote(name)()
    end
  end

  defp initial(name, state) do
    quote do
      defp unquote(name), do: unquote(state)
    end
  end

  defp build_dfa(reas) do
    {nfa, first} = Panacea.Lexer.Nfa.from_regex(reas)
    Panacea.Lexer.Dfa.build(nfa, first)
  end
end
