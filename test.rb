#!/usr/bin/env ruby

require_relative "lib/lexer"
require_relative "lib/parser"

lexer = Lexer.from_file(ARGV.first)
lexer.parse!
lexer.preprocess!

parser = Parser.new(lexer.tokens)
parser.parse!
