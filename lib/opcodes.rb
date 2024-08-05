OPCODES_BY_BYTE = {
  0x00 => "BRK",
  0x01 => "INC",
  0x02 => "POP",
  0x03 => "NIP",
  0x04 => "SWP",
  0x05 => "ROT",
  0x06 => "DUP",
  0x07 => "OVR",
  0x08 => "EQU",
  0x09 => "NEQ",
  0x0a => "GTH",
  0x0b => "LTH",
  0x0c => "JMP",
  0x0d => "JCN",
  0x0e => "JSR",
  0x0f => "STH",

  0x10 => "LDZ",
  0x11 => "STZ",
  0x12 => "LDR",
  0x13 => "STR",
  0x14 => "LDA",
  0x15 => "STA",
  0x16 => "DEI",
  0x17 => "DEO",
  0x18 => "ADD",
  0x19 => "SUB",
  0x1a => "MUL",
  0x1b => "DIV",
  0x1c => "AND",
  0x1d => "ORA",
  0x1e => "EOR",
  0x1f => "SFT",

  0x20 => "JCI",
  0x40 => "JMI",
  0x60 => "JSI",

  0x80 => "LIT",
  0xa0 => "LIT2",
  0xc0 => "LITr",
  0xe0 => "LIT2r",
}

(0x01..0x1f).each do |num|
  OPCODES_BY_BYTE[ num | 0x20 ] = OPCODES_BY_BYTE[num] + "2"
  OPCODES_BY_BYTE[ num | 0x40 ] = OPCODES_BY_BYTE[num] + "r"
  OPCODES_BY_BYTE[ num | 0x60 ] = OPCODES_BY_BYTE[num] + "2r"
  OPCODES_BY_BYTE[ num | 0x80 ] = OPCODES_BY_BYTE[num] + "k"
  OPCODES_BY_BYTE[ num | 0xa0 ] = OPCODES_BY_BYTE[num] + "2k"
  OPCODES_BY_BYTE[ num | 0xc0 ] = OPCODES_BY_BYTE[num] + "kr"
  OPCODES_BY_BYTE[ num | 0xe0 ] = OPCODES_BY_BYTE[num] + "2kr"
end

OPCODES_BY_MNEMONIC = OPCODES_BY_BYTE.map do |k, v|
  [v, k]
end.sort.to_h

[2, 3].each do |i|
  ["2", "k", "r"].permutation(i) do |list|
    suffix = list.join("")
    OPCODES_BY_BYTE.each do |value, mnemonic|
      OPCODES_BY_MNEMONIC[mnemonic + suffix] = [
        value,
        if list.include?("2") then 0x20 else 0 end,
        if list.include?("r") then 0x40 else 0 end,
        if list.include?("k") then 0x80 else 0 end,
      ].reduce(&:+)
    end
  end
end
