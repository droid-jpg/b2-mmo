/* The mod's code goes in the ARM9 ITCM after the shared block (0x01FFA000..0x01FFA3FF). */
ENTRY(mmo_provider)
SECTIONS
{
    . = 0x01FFA400;
    .text : { *(.text.mmo_provider) *(.text*) *(.rodata*) }
    .data : { *(.data*) }
    .bss : { __bss_start = .; *(.bss*) *(COMMON) __bss_end = .; }
    __image_end = .;
    ASSERT(__image_end <= 0x01FFAF00, "mod code runs into the battle buffers")
    /DISCARD/ : { *(.ARM.*) *(.comment) *(.note*) }
}
