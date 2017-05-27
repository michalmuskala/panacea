defmodule Panacea.Lexer.Codegen do
  alias Panacea.Lexer.Dfa

  import Panacea.Lexer, only: [meta: 0, meta: 1]

  def compile(name, reas) do
    {dfa, first} = build_dfa(reas)
    [codegen_initial(name, first) | Enum.map(dfa, &codegen_dfa(&1, name))]
  end

  defp codegen_initial(name, first) do
    first_name = :"#{name}_#{first}"
    quote do
      def unquote(name)(input) when is_binary(input) do
        try do
          unquote(first_name)(input, _start = 0, _line = 1, _len = 0, _original = input)
        catch
          {:panacea, error} ->
            {:error, error}
        else
          value ->
            {:ok, value}
        end
      end

      @compile {:inline, panacea_state: 6}
      defp panacea_state(input, start, line, len, original, unquote(name)) do
        unquote(first_name)(input, start, line, len, original)
      end

      defp unquote(first_name)("", _start, _line, _len, _original) do
        []
      end
    end
  end


  defp codegen_dfa(%Dfa{id: id, trans: trans, accept: accept}, name) do
    state_name = :"#{name}_#{id}"
    [Enum.map(trans, &codegen_trans(&1, state_name, name)),
     codegen_accept(accept, state_name, name)]
  end

  defp codegen_accept(nil, state_name, _name) do
    quote do
      defp unquote(state_name)(<<char::utf8, _rest::bitstring>>, start, line, len, original) do
        throw {:panacea, {char, line, start + len}}
      end
      defp unquote(state_name)("", start, line, len, original) do
        throw {:panacea, {:eof, line, start + len}}
      end
    end
  end

  defp codegen_accept({:accept, action}, state_name, name) do
    quote do
      defp unquote(state_name)(<<rest::bitstring>>, start, line, len, original) do
        token = binary_part(original, 0, len)
        new_original = binary_part(original, len, byte_size(original) - len)
        meta = meta(start: start, line: line, len: len, token: token)
        case unquote(action)(meta) do
          {:token, token} ->
            [token | panacea_state(rest, start + len, line, 0, new_original, unquote(name))]
          :skip ->
            panacea_state(rest, start + len, line, 0, new_original, unquote(name))
          {:enter_token, state, token} ->
            [token | panacea_state(rest, start + len, line, 0, new_original, state)]
          {:enter_skip, state} ->
            panacea_state(rest, start + len, line, 0, new_original, state)
          {:error, error} ->
            throw {:panacea, error}
        end
      end
    end
  end

  defp codegen_trans({{low, :maxchar}, next}, state_name, name) do
    next_name = :"#{name}_#{next}"
    quote do
      defp unquote(state_name)(<<char::utf8, rest::bitstring>>, start, line, len, original)
           when char >= unquote(low) do
        unquote(next_name)(rest, start, line, len + 1, original)
      end
    end
  end
  defp codegen_trans({{low, hi}, next}, state_name, name) do
    next_name = :"#{name}_#{next}"
    quote do
      defp unquote(state_name)(<<char::utf8, rest::bitstring>>, start, line, len, original)
           when char >= unquote(low) and char <= unquote(hi) do
        unquote(next_name)(rest, start, line, len + 1, original)
      end
    end
  end
  # newline is always separate
  defp codegen_trans({?\n, next}, state_name, name) do
    next_name = :"#{name}_#{next}"
    quote do
      defp unquote(state_name)(<<?\n::utf8, rest::bitstring>>, start, line, len, original) do
        unquote(next_name)(rest, 0, line + 1, len + 1, original)
      end
    end
  end
  defp codegen_trans({char, next}, state_name, name) do
    next_name = :"#{name}_#{next}"
    quote do
      defp unquote(state_name)(<<char::utf8, rest::bitstring>>, start, line, len, original)
           when char === unquote(char) do
        unquote(next_name)(rest, start, line, len + 1, original)
      end
    end
  end

  defp build_dfa(reas) do
    {nfa, first} = Panacea.Lexer.Nfa.from_regex(reas)
    Panacea.Lexer.Dfa.build(nfa, first)
  end
end
