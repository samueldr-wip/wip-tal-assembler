This Tal assembler has some minor differences compared to the reference implementation.

### `0x00` bytes output at the end

Bytes with the `0x00` value at the end *will be written out*.

```
 $ cat tmp.tal 
BRK a5a5 BRK
 $ xxd this_assembler.rom
00000000: 00a5 a500                                ....
 $ xxd reference_assembler.rom
00000000: 00a5 a5                                  ...
```

This difference can also be observed in some demos like the `amiga` demo.

This assembler will output the last few zeroes of the `@bg` data.

In practice, since memory is zeroed-out at boot, it will not matter:

> During boot, the stacks, device and addressable memories are zeroed, if it is a soft-reboot, the content of the zero-page is preserved.

— https://wiki.xxiivv.com/site/uxntal.html

... except if the ROM is loaded and `JMP`'d into by a uxn routine, without restarting.

The data may refer to previously used memory.

A *feature quirk* may be added down the line to drop last emitted bytes when zeroes.

> NOTE: This means a Tal file with only `BRK` should error out with `Output empty: tmp.rom` according to the reference implementation.


### Symbols listing

There is no symbols listing output at this time.

If there will be, it will likely be in a different format.


### Warnings

Warnings may be emitted during lexing, parsing or emission.

These are not part of the reference implementation.
