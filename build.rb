#!/usr/bin/env ruby

require_relative "lib/lexer"
require_relative "lib/parser"

if ARGV.length != 2
  $stderr.puts "Usage: <input.tal> <output.rom>"
  exit 2
end

puts ":: Lexing!"
lexer = Lexer.from_file(ARGV[0])
lexer.parse!
lexer.preprocess!

puts ":: Parsing!"
parser = Parser.new(lexer.tokens)
parser.parse!
puts ":: Emitting!"
file = File.new(ARGV[1], File::CREAT|File::TRUNC|File::RDWR)
parser.emit!(file)
