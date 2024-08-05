require "json"
require "stringio"
require_relative "error"

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
  attr_reader :labels

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
    @labels = {}
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

  def ungetc(char)
    @src.ungetc(char)
    if char == "\n"
      @line -= 1
      raise "TODO: implement ungetc column tracking for newlines..."
    else
      @column -= 1
    end
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
          result, self_restart = token.preprocess!()
          need_restart ||= self_restart
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
      break if peek.nil? || peek.match(SPACES_REGEX)
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

    def initialize(lexer)
      @str = nil
      @lexer = lexer # Used to improve error messages
      @position = lexer.position
      @position[:column] += 1
      parse!
    end

    def path()
      @lexer.path
    end

    def parse!()
      raise "#parse! needs to be implemented for #{self.class.name.inspect}!"
    end

    def warn(str)
      $stderr.puts [
        "Warning: #{str} in #{path}@#{position}",
        if @lexer.nil? then nil else "(#{@lexer.position})" end,
      ].compact.join(" ")
    end

    def error(str)
      $stderr.puts [
        "Error: #{str} in #{path}@#{position}",
        if @lexer.nil? then nil else "(#{@lexer.position})" end,
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
      return self, false
    end

    def ==(other)
      [
        other.str == self.str,
        other.position == self.position,
      ].all?
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
      str << @lexer.getc()
      count = 1
      char = @lexer.getc()
      str << char
      warn "Comments should start with a whitespace. Found #{char.inspect}" unless char.match(SPACES_REGEX)
      loop do
        char = @lexer.getc()
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
      @str = @lexer.getc()
    end
  end

  class Token < BasicToken
    def initialize(str, lexer)
      @lexer = lexer
      @str = str
      @position = lexer.position
      @position[:column] -= str.length
      parse!
    end

    def parse!()
    end
  end

  class ByteOrShort < Token
    def value()
      {
        length: (str.length) / 2,
        value: str.to_i(base=16),
      }
    end
  end
  class Opcode < Token
  end

  # Runes
  class Literal < Token
    def value()
      {
        length: (str.length - 1) / 2,
        value: str.sub("#", "").to_i(base=16),
      }
    end
    # FIXME: desugar down to Opcode + ByteOrShort in preprocess?
    #        it probably should be...
  end
  class RawAscii < Token
    def value()
      str.sub(/^"/, "")
    end
  end
  class PaddingAbsolute < Token
    def value()
      str.sub("|", "").to_i(base=16)
    end
  end
  class PaddingRelative < Token
    def value()
      str.sub("$", "").to_i(base=16)
    end
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

      unless @lexer.labels[@str].nil?
        original = @lexer.labels[@str]
        error "Label #{@str.inspect} already defined (original at #{original.position})..."
      end
      @lexer.labels[@str] = self
    end

    def label()
      str
    end
  end

  class LabelRef < Token
    attr_reader :label

    def parse!()
      @parent = nil
      super()
      @original_str ||= @str
      if @str.match(%r{^/})
        @parent = Label.current_label()
        @str = [@parent.str[1..-1], @str[1..-1]].join("/")
      end

      if @str.match(/^&/)
        current_label = Label.current_label
        @str = [current_label.str, @str[1..-1]].join("/")
      end
    end

    def ref_type()
      :relative_16
    end

    def instruction()
      "JSI"
    end

    def label()
      str
    end
  end

  class ReferenceToken < LabelRef
    def parse!()
      @original_str = @str
      @str = @str[1..-1]
      if @str == "{"
        @lexer.ungetc("{")
        @bracket = @lexer.read_bracket()
      end
      super()
    end

    def instruction() nil end
    def ref_type()
      raise "Unexpected call to #ref_type on generic ReferenceToken"
    end

    def preprocess!()
      if @str == "{"
        @str = @bracket.label()
      end
      super()
    end
  end
  class JCIReference < ReferenceToken
    def ref_type() :relative_16 end
    def instruction() "JCI" end
  end
  class JMIReference < ReferenceToken
    def ref_type() :relative_16 end
    def instruction() "JMI" end
  end

  class LiteralAddressRelative < ReferenceToken
    def ref_type() :relative_8 end
    def instruction() "LIT" end
  end
  class LiteralAddressZeroPage < ReferenceToken
    def ref_type() :zeropage end
    def instruction() "LIT" end
  end
  class LiteralAddressAbsolute < ReferenceToken
    def ref_type() :absolute end
    def instruction() "LIT2" end
  end

  class RawAddressRelative < ReferenceToken
    def ref_type() :relative_8 end
  end
  class RawAddressZeroPage < ReferenceToken
    def ref_type() :zeropage end
  end
  class RawAddressAbsolute < ReferenceToken
    def ref_type() :absolute end
  end

  class Include < Token
    def preprocess!()
      # Replaces self!
      path = str.sub(/^~/, "")
      lexer = Lexer.from_file(path)
      lexer.parse!
      lexer.preprocess!
      return lexer.tokens, true
    end
  end
  class Macro < Token
    def preprocess!()
      raise "TODO: implement Macro#preprocess!"
    end
  end

  # Paired symbols
  module PairedSymbol
    attr_accessor :associate

    def initialize(lexer)
      @str = nil
      @lexer = lexer # Used to improve error messages
      @position = lexer.position
      @position[:column] += 1
      parse!
    end

    def parse!()
      @str = @lexer.getc()
    end

    def type()
      raise "#type needs to be implemented for #{self.class.name}"
    end
  end
  module PairedOpeningSymbol
    include PairedSymbol
  end
  module PairedClosingSymbol
    include PairedSymbol
  end

  class SquareBracketOpen < TransparentToken
    include PairedOpeningSymbol
    def type() :square end
    def transparent?() true end
  end
  class SquareBracketClose < TransparentToken
    include PairedClosingSymbol
    def type() :square end
    def transparent?() true end
  end

  # NOTE: overloaded for macro usage too.
  class LambdaBracketOpen < LabelRef
    include PairedOpeningSymbol
    def type() :lambda end
    def label()
      associate.label()
    end
  end
  class LambdaBracketClose < Label
    include PairedClosingSymbol
    def type() :lambda end
    def label()
      "{PRG/byte/#{position}}"
    end
  end

  PAIRED_SYMBOLS = {
    %q'{' => LambdaBracketOpen,
    %q'}' => LambdaBracketClose,
    %q'[' => SquareBracketOpen,
    %q']' => SquareBracketClose,
  }

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
    %q{?} => JCIReference,
    %q{!} => JMIReference,

    # Literal Hex Rune
    %q{#} => Literal,
    # Ascii Rune
    %q{"} => RawAscii,
    # Pre-processor Runes
    %q{~} => Include,
    %q{%} => Macro,
  }
end
