defmodule Panacea.Lexer do
  import Record

  defrecord :meta, [:token, :line, :start, :len]

  def deflexer(name, [do: block]) do
    quote do
      Module.register_attribute(__MODULE__, :panacea_lexer_rules, accumulate: true)

      try do
        import Panacea.Lexer, except: [deflexer: 2]
        unquote(block)
      after
        :ok
      end

      reas = Module.get_attribute(__MODULE__, :panacea_lexer_rules)
      Module.delete_attribute(__MODULE__, :panacea_lexer_rules)
      ast = Panacea.Lexer.Codegen.compile(unquote(name), Enum.reverse(reas))
      Module.eval_quoted(__ENV__, ast)
    end
  end

  defmacro defrule(regex, meta \\ quote(do: _), [do: block]) do
    id = next_id(__CALLER__.module)
    action = :"panacea_action_#{id}"
    quote do
      rule = {Panacea.Lexer.Regex.parse!(unquote(regex)), unquote(action)}
      Module.put_attribute(__MODULE__, :panacea_lexer_rules, rule)
      unquote(action(action, meta, block))
    end
  end

  defp action(name, meta, block) do
    quote do
      @compile {:inline, {unquote(name), 1}}
      defp unquote(name)(unquote(meta)), do: unquote(block)
    end
  end

  defp next_id(module) do
    id = Module.get_attribute(module, :panacea_lexer_id) || 0
    Module.put_attribute(module, :panacea_lexer_id, id + 1)
    id
  end
end
