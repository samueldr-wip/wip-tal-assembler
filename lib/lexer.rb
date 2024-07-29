require "json"
require "stringio"

class Lexer
  SPACES = [ " ", "\t", "\n" ]
  SPACES_REGEX        = /[ \t\n]/
  COMMENT_START_REGEX = /\(/
  COMMENT_END_REGEX   = /\)/

  attr_reader :src
  attr_reader :tokens
  attr_reader :line
  attr_reader :column
  attr_reader :path

  def self.from_file(path)
    new(File.open(path)).tap do |inst|
      inst.instance_exec do
        @path = path
      end
    end
  end

  def self.from_source(str)
    new(StringIO.new(str))
  end

  private

  def initialize(src)
    @path = "<memory>"
    @src = src
    @tokens = []
    @line = 1
    @column = 0
    @brackets_stack = []
  end

  public

  def getc()
    char = @src.getc()
    return nil if char.nil?
    if char == "\n"
      @line += 1
      @column = 0
    else
      @column += 1
    end
    char
  end

  def peek()
     char = @src.getc()
     return nil if char.nil?
     @src.ungetc(char)
     char
  end

  def position()
    {
      line:   line,
      column: column,
    }
  end

  def parse!()
    loop do
      break if peek == nil
      case peek
      when COMMENT_START_REGEX
        tokens << Comment.new(self)
      when SPACES_REGEX
        tokens << Space.new(self)
      when "!"
        tokens << JMIRune.new(self)
      when "?"
        tokens << JCIRune.new(self)
      when /[\[\]{}]/
        tokens << read_bracket()
      else
        # At this point we should have either syntax errors, or free-standing tokens (no spaces, no comments).
        tokens << read_token()
      end
    end
  end

  def preprocess!()
    raise "Parsing needed, or empty source file at pre-processing." unless tokens.length > 0

    loop do
      need_restart = false

      @tokens =
        tokens.map do |token|
          original_token = token
          token = token.dup
          result = token.preprocess!()
          need_restart ||= result != token
          result
        end.flatten
      break unless need_restart

    end
  end

  def read_bracket()
    token = PAIRED_SYMBOLS[peek].new(self)
    if token.is_a?(PairedOpeningSymbol)
      @brackets_stack << token
    else
      pair = @brackets_stack.pop
      if pair.type != token.type
        token.error("Unmatched bracket type")
      end
      pair.associate = token
      token.associate = pair
    end
    token
  end

  def read_token()
    str = []
    loop do
      str << getc()
      break if peek.match(SPACES_REGEX)
    end
    str = str.join("")
    rune = RUNES[str[0]]

    unless rune.nil?
        (RUNES[str[0]]).new(str, self)
    else
      case str
      when /^[A-Z]{3}2?k?r?/
        Opcode.new(str, self)
      when /^[a-f0-9]+$/
        ByteOrShort.new(str, self)
      else
        LabelRef.new(str, self)
      end
    end
  end

  def inspect()
    {
      tokens: tokens,
      line: line,
      column: column,
    }.to_json
  end

  class BasicToken
    attr_reader :position
    attr_reader :str
    attr_reader :path

    def initialize(lex)
      @str = nil
      @lex = lex # Used to improve error messages
      @position = lex.position
      @position[:column] += 1
      parse!
    end

    def path()
      @lex.path
    end

    def parse!()
      raise "#parse! needs to be implemented for #{self.class.name.inspect}!"
    end

    def warn(str)
      $stderr.puts [
        "Warning: #{str} in #{path}@#{position}",
        if @lex.nil? then nil else "(#{@lex.position})" end,
      ].compact.join(" ")
    end

    def error(str)
      $stderr.puts [
        "Error: #{str} in #{path}@#{position}",
        if @lex.nil? then nil else "(#{@lex.position})" end,
      ].compact.join(" ")
      exit 2
    end

    def inspect()
      "#{self.class.name}<#{@str.inspect}>"
    end

    def transparent?()
      false
    end

    # By default, a no-op.
    def preprocess!()
      self
    end
  end

  class TransparentToken < BasicToken
    def transparent?()
      true
    end
  end

  # Kept to allow source-to-source manipulations
  class Comment < TransparentToken
    def parse!()
      str = []
      # Weird logic here to check leading spaces
      str << @lex.getc()
      count = 1
      char = @lex.getc()
      str << char
      warn "Comments should start with a whitespace. Found #{char.inspect}" unless char.match(SPACES_REGEX)
      loop do
        char = @lex.getc()
        if char == "("
          count += 1
          if count > 1 then
            warn("Nested comments in Tal is wonky. Avoid them at all costs.")
          end
        end
        if char == ")"
          count -= 1
        end
        str << char
        break if count == 0
      end
      penultimate = str[-2]
      warn "Comments should end with a whitespace. Found #{penultimate.inspect} before #{")".inspect} " unless penultimate.match(SPACES_REGEX)
      @str = str.join("")
    end
  end

  # Kept to allow source-to-source manipulations
  class Space < TransparentToken
    def parse!()
      @str = @lex.getc()
    end
  end

  class JMIRune < BasicToken
    def parse!()
      @str = @lex.getc()
    end
  end

  class JCIRune < BasicToken
    def parse!()
      @str = @lex.getc()
    end
  end

  class Token < BasicToken
    def initialize(str, lex)
      @lex = lex
      @str = str
      @position = lex.position
      @position[:column] -= str.length
      parse!
    end

    def parse!()
    end
  end

  class ByteOrShort < Token
  end
  class Opcode < Token
  end
  class LabelRef < Token
    def parse!()
      @parent = nil
      super()
      @original_str = @str
      if @str.match(%r{^/})
        @parent = Label.current_label()
        @str = [@parent.str[1..-1], @str[1..-1]].join("/")
      end
    end
  end

  # Paired symbols
  class PairedSymbol < BasicToken
    attr_accessor :associate

    def parse!()
      @str = @lex.getc()
    end

    def type()
    end
  end
  class PairedOpeningSymbol < PairedSymbol
  end
  class PairedClosingSymbol < PairedSymbol
  end

  class SquareBracketOpen < PairedOpeningSymbol
    def type() :square end
    def transparent?() true end
  end
  class SquareBracketClose < PairedClosingSymbol
    def type() :square end
    def transparent?() true end
  end

  class LambdaBracketOpen < PairedOpeningSymbol
    def type() :lambda end
  end
  class LambdaBracketClose < PairedClosingSymbol
    def type() :lambda end
  end

  PAIRED_SYMBOLS = {
    %q'{' => LambdaBracketOpen,
    %q'}' => LambdaBracketClose,
    %q'[' => SquareBracketOpen,
    %q']' => SquareBracketClose,
  }

  # Runes
  class Literal < Token
  end
  class RawAscii < Token
  end
  class PaddingAbsolute < Token
  end
  class PaddingRelative < Token
  end

  class Label < Token
    @@current_label = nil

    def self.current_label()
      @@current_label
    end

    def parse!()
      @parent = nil
      super()
      @original_str = @str
      if @str.match(/^@/)
        @@current_label = self
      else
        error("Child label Rune used before a parent is defined.") if @@current_label.nil?
        @parent = @@current_label
        @str = [@@current_label.str, @str[1..-1]].join("/")
      end
      # Fully qualified label to be matched
      @str = @str.sub(/^@/, "")
    end
  end

  class ReferenceToken < Token
    # TODO: associate with its label in the next pass...
    def parse!()
      super()
      @original_str = @str
      @str = @str[1..-1]
    end
  end
  class LiteralAddressRelative < ReferenceToken
  end
  class LiteralAddressZeroPage < ReferenceToken
  end
  class LiteralAddressAbsolute < ReferenceToken
  end
  class RawAddressRelative < ReferenceToken
  end
  class RawAddressZeroPage < ReferenceToken
  end
  class RawAddressAbsolute < ReferenceToken
  end

  class Include < Token
    def preprocess!()
      # Replaces self!
      path = str.sub(/^~/, "")
      lex = Lexer.from_file(path)
      lex.parse!
      lex.preprocess!
      lex.tokens
      # TODO: determine if we add transparent tokens noting included origin to the tokens list.
    end
  end
  class Macro < Token
    def preprocess!()
      raise "TODO: implement Macro#preprocess!"
    end
  end

  RUNES = {
    # Padding Runes
    %q{|} => PaddingAbsolute,
    %q{$} => PaddingRelative,
    # Label Runes
    %q{@} => Label,
    %q{&} => Label,
    # Addressing Runes
    %q{,} => LiteralAddressRelative,
    %q{.} => LiteralAddressZeroPage,
    %q{;} => LiteralAddressAbsolute,
    %q{_} => RawAddressRelative,
    %q{-} => RawAddressZeroPage,
    %q{=} => RawAddressAbsolute,
    %q{:} => RawAddressAbsolute, # Legacy?
    # Immediate Runes
    # ? handled in previous pass
    # ! handled in previous pass

    # Literal Hex Rune
    %q{#} => Literal,
    # Ascii Rune
    %q{"} => RawAscii,
    # Pre-processor Runes
    %q{~} => Include,
    %q{%} => Macro,
  }
end
