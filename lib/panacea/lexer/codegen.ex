defmodule Panacea.Lexer.Codegen do
  alias Panacea.Lexer.Dfa

  import Panacea.Lexer, only: [meta: 0, meta: 1, meta: 2]

  def compile(name, reas) do
    {dfa, first} = build_dfa(reas)
    [codegen_initial(name, first) | Enum.flat_map(dfa, &codegen_dfa(&1, name))]
  end

  defp codegen_initial(name, first) do
    first_name = :"#{name}_#{first}"
    quote do
      def unquote(name)(input) do
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

      @doc false
      def unquote(name)(<<input::binary>>, start, line, len, original) do
        unquote(first_name)(input, start, line, len, original)
      end

      defp unquote(:"#{name}_enter")(<<input::binary>>, state, start, line, len, original) do
        apply(__MODULE__, state, [input, start, line, len, original])
      end
    end
  end

  defp codegen_dfa(%Dfa{id: id, trans: trans, accept: accept}, name) do
    state_name = :"#{name}_#{id}"
    Enum.map(trans, &codegen_trans(&1, state_name, name)) ++
      [codegen_accept(accept, state_name, name)]
  end

  defp codegen_accept(nil, state_name, _name) do
    quote do
      defp unquote(state_name)("", start, line, len, original) do
        throw {:panacea, {:eof, line, start + len}}
      end
      defp unquote(state_name)(<<char::utf8>> <> rest, start, line, len, original) do
        throw {:panacea, {char, line, start + len}}
      end
    end
  end

  defp codegen_accept({:accept, action}, state_name, name) do
    quote do
      defp unquote(state_name)("", start, line, len, original) do
        token = binary_part(original, 0, len)
        meta = meta(start: start, line: line, len: len, token: token)
        case unquote(action)(meta) do
          {:token, token} ->
            [token]
          :skip ->
            []
          {:error, error} ->
            throw {:panacea, error}
        end
      end
      defp unquote(state_name)(<<rest::binary>>, start, line, len, original) do
        token = binary_part(original, 0, len)
        new_original = binary_part(original, len, byte_size(original) - len)
        meta = meta(start: start, line: line, len: len, token: token)
        case unquote(action)(meta) do
          {:token, token} ->
            [token | unquote(name)(rest, start + len, line, 0, new_original)]
          :skip ->
            unquote(name)(rest, start + len, line, 0, new_original)
          {:enter_token, state, token} ->
            [token | unquote(:"#{name}_enter")(rest, state, start + len, line, 0, new_original)]
          {:enter_skip, state} ->
            unquote(:"#{name}_enter")(rest, state, start + len, line, 0, new_original)
          {:error, error} ->
            throw {:panacea, error}
        end
      end
    end
  end

  defp codegen_trans({{low, :maxchar}, next}, state_name, name) do
    next_name = :"#{name}_#{next}"
    quote do
      defp unquote(state_name)(<<char::utf8>> <> rest, start, line, len, original)
           when char >= unquote(low) do
        unquote(next_name)(rest, start, line, len + 1, original)
      end
    end
  end
  defp codegen_trans({{low, hi}, next}, state_name, name) do
    next_name = :"#{name}_#{next}"
    quote do
      defp unquote(state_name)(<<char::utf8>> <> rest, start, line, len, original)
           when char >= unquote(low) and char <= unquote(hi) do
        unquote(next_name)(rest, start, line, len + 1, original)
      end
    end
  end
  # newline is always separate
  defp codegen_trans({?\n, next}, state_name, name) do
    next_name = :"#{name}_#{next}"
    quote do
      defp unquote(state_name)("\n" <> rest, start, line, len, original) do
        unquote(next_name)(rest, 1, line + 1, len + 1, original)
      end
    end
  end
  defp codegen_trans({char, next}, state_name, name) do
    next_name = :"#{name}_#{next}"
    quote do
      defp unquote(state_name)(<<char::utf8>> <> rest, start, line, len, original)
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
