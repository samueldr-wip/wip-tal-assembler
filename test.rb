#!/usr/bin/env ruby

require_relative "lib/lexer"

lexer = Lexer.new(File.open(ARGV.first))
lexer.parse!
pp lexer.tokens
