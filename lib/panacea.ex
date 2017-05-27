defmodule Panacea do
  defmacro deflexer(name, block) do
    Panacea.Lexer.deflexer(name, block)
  end
end
