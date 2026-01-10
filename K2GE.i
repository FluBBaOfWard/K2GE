//
//  K2GE.i
//  K2GE
//
//  Created by Fredrik Ahlström on 2008-04-02.
//  Copyright © 2008-2026 Fredrik Ahlström. All rights reserved.
//
// ASM header for the SNK K1GE/K2GE Graphics Engine emulator
//
#if !__ASSEMBLER__
	#error This header file is only for use in assembly files!
#endif

#define HW_AUTO       (0)
#define HW_NGPMONO    (1)
#define HW_NGPCOLOR   (2)
#define HW_SELECT_END (3)

#define SOC_K1GE	(0)
#define SOC_K2GE	(1)

/** Game screen width in pixels */
#define GAME_WIDTH  (160)
/** Game screen height in pixels */
#define GAME_HEIGHT (152)

	geptr		.req r12
						;@ K2GE.s
	.struct 0
scanline:		.long 0		;@ These 3 must be first in state.
nextLineChange:	.long 0
lineState:		.long 0
kgePadding0:	.skip 4

k2GEState:					;@
k2GERegs:
kgeWinXPos:		.byte 0		;@ Window X-Position
kgeWinYPos:		.byte 0		;@ Window Y-Position
kgeWinXSize:	.byte 0		;@ Window X-Size
kgeWinYSize:	.byte 0		;@ Window Y-Size
kgeFGXScroll:	.byte 0,0	;@ Foreground X-Scroll
kgeFGYScroll:	.byte 0,0	;@ Foreground Y-Scroll
kgeBGXScroll:	.byte 0,0	;@ Background X-Scroll
kgeBGYScroll:	.byte 0,0	;@ Background Y-Scroll

kgeSprXOfs:		.byte 0
kgeSprYOfs:		.byte 0
kgeIrqEnable:	.byte 0
kgeRef:			.byte 0
kgeBGCol:		.byte 0
kgeBGPrio:		.byte 0
kgeLedEnable:	.byte 0
kgeLedBlink:	.byte 0
kgeMode:		.byte 0
kgeModeChange:	.byte 0

kgeLedOnOff:	.byte 0		;@ Bit 0, Led On/Off.
kgePadding1:	.skip 1

scrollLine: 	.long 0 	;@ Last write to scroll registers was when?

ledCounter:		.long 0
windowData:		.long 0
k2GEStateSize:

kgeModel:		.byte 0		;@ SOC_K1GE / SOC_K2GE.
kgeBuffSetting:	.byte 0
kgePadding2:	.skip 2

frameIrqFunc:	.long 0		;@ V-Blank Irq func ptr
hblankIrqFunc:	.long 0		;@ H-Blank Irq func ptr

dirtyPtr:		.long 0
gfxRAMBuffPtr:	.long 0
gfxRAM:			.long 0		;@ 0x3000
sprRAM:			.long 0		;@ 0x0140
paletteMonoRAM:	.long 0		;@ 0x0020
paletteRAM:		.long 0		;@ 0x0200
gfxRAMSwap:		.long 0		;@ 0x3000
scrollBuff:		.long 0

k2GESize:

;@----------------------------------------------------------------------------

