//
//  K2GE.s
//  NeoGeo Pocket Video emulation for GBA/NDS.
//
//  Created by Fredrik Ahlström on 2008-04-02.
//  Copyright © 2008-2024 Fredrik Ahlström. All rights reserved.
//
// SNK K2GE Graphics Engine emulation

#ifdef __arm__

#ifdef GBA
	#include "../Shared/gba_asm.h"
#elif NDS
	#include "../Shared/nds_asm.h"
#endif
#include "K2GE.i"
#include "../TLCS900H/TLCS900H.i"	// Used by k2GEHCountR

	.global k2GEInit
	.global k2GEReset
	.global k2GESaveState
	.global k2GELoadState
	.global k2GEGetStateSize
	.global k2GEEnableBufferMode
	.global k2GEDoScanline
	.global copyScrollValues
	.global k2GEConvertTileMaps
	.global k2GEConvertSprites
	.global k2GEConvertTiles
	.global k2GEBufferWindows
	.global k2GE_R
	.global k2GE_R_W
	.global k2GE_W
	.global k2GE_W_W

	.syntax unified
	.arm

#ifdef GBA
	.section .ewram, "ax", %progbits	;@ For the GBA
#else
	.section .text						;@ For anything else
#endif
	.align 2
;@----------------------------------------------------------------------------
k2GEInit:					;@ Only need to be called once
;@----------------------------------------------------------------------------
	ldr r0,=CHR_DECODE			;@ Destination 0x400
	mov r1,#0xffffff00			;@ Build chr decode tbl
chrLutLoop:
	movs r2,r1,lsl#31
	movne r2,#0x1000
	orrcs r2,r2,#0x2000
	tst r1,r1,lsl#29
	orrmi r2,r2,#0x0100
	orrcs r2,r2,#0x0200
	tst r1,r1,lsl#27
	orrmi r2,r2,#0x0010
	orrcs r2,r2,#0x0020
	tst r1,r1,lsl#25
	orrmi r2,r2,#0x0001
	orrcs r2,r2,#0x0002
	strh r2,[r0],#2
	adds r1,r1,#1
	bne chrLutLoop

	bx lr
;@----------------------------------------------------------------------------
k2GEReset:		;@ r0=frameIrqFunc, r1=hIrqFunc, r2=ram+LUTs, r3=model, r12=geptr
;@----------------------------------------------------------------------------
	stmfd sp!,{r0-r3,lr}

	mov r0,geptr
	ldr r1,=k2GESize/4
	bl memclr_					;@ Clear K2GE state

	ldr r2,=lineStateTable
	ldr r1,[r2],#4
	mov r0,#0
	stmia geptr,{r0-r2}			;@ Reset scanline, nextChange & lineState

	ldmfd sp!,{r0-r3}
	cmp r0,#0
	adreq r0,dummyIrqFunc
	cmp r1,#0
	adreq r1,dummyIrqFunc
	str r0,[geptr,#frameIrqFunc]
	str r1,[geptr,#hblankIrqFunc]

	str r2,[geptr,#gfxRAM]
	add r2,r2,#0x3000
	str r2,[geptr,#sprRAM]
	add r2,r2,#0x140
	str r2,[geptr,#paletteMonoRAM]
	add r2,r2,#0x20
	str r2,[geptr,#paletteRAM]
	add r2,r2,#0x200
	str r2,[geptr,#gfxRAMSwap]
	ldr r0,=SCROLL_BUFF
	str r0,[geptr,#scrollBuff]

	strb r3,[geptr,#kgeModel]
	cmp r3,#SOC_K1GE
	movne r0,#0x00				;@ Use Color mode.
	moveq r0,#0x80				;@ Use B&W mode.
	strb r0,[geptr,#kgeMode]
	ldrne r0,=k2GEPaletteW
	ldreq r0,=k2GEBadW
	ldr r1,=k2GEPalPtr
	str r0,[r1],#4
	str r0,[r1],#4
	ldrne r0,=k2GEExtraW
	ldreq r0,=k1GEExtraW
	ldr r1,=k2GEExtraPtr
	str r0,[r1],#4

	mov r0,#1
	bl k2GEEnableBufferMode
	ldmfd sp!,{lr}
	b k2GERegistersReset

dummyIrqFunc:
	bx lr

;@----------------------------------------------------------------------------
k2GERegistersReset:
;@----------------------------------------------------------------------------
	mov r0,#0xC0
	strb r0,[geptr,#kgeIrqEnable]	;@ Both interrupts allowed
	mov r0,#0xC6
	strb r0,[geptr,#kgeRef]			;@ Refresh Rate value
	mov r0,#0
	strb r0,[geptr,#kgeBGCol]
	strh r0,[geptr,#kgeSprXOfs]
	strb r0,[geptr,#kgeBGPrio]
	str r0,[geptr,#kgeFGXScroll]
	str r0,[geptr,#kgeBGXScroll]
	strh r0,[geptr,#kgeWinXPos]		;@ Window pos
	mov r0,#0xFFFFFFFF
	strh r0,[geptr,#kgeWinXSize]	;@ Window size
	mov r0,#0x80
	strb r0,[geptr,#kgeLedBlink]	;@ Flash cycle = 1.3s
	ldr r1,[geptr,#paletteMonoRAM]
	strb r0,[r1,#0x18]				;@ BGC on!
	ldr r0,=0x0FFF
	ldr r1,[geptr,#paletteRAM]
	add r1,r1,#0x100
	strh r0,[r1,#0xE0]			;@ 0x83E0. Default background colour
	strh r0,[r1,#0xF0]			;@ 0x83F0. Default window colour

	bx lr
;@----------------------------------------------------------------------------
k2GEEnableBufferMode:		;@ In r0 = disable=0 / enable!=0. geptr initialized.
;@----------------------------------------------------------------------------
	strb r0,[geptr,#kgeBuffSetting]
	cmp r0,#0
	ldreq r0,[geptr,#gfxRAM]
	ldrne r0,[geptr,#gfxRAMSwap]
	ldreq r1,=DIRTYTILES
	ldrne r1,=DIRTYTILES2
	str r0,[geptr,#gfxRAMBuffPtr]	;@ Direct or buffered gfxRAM
	str r1,[geptr,#dirtyPtr]		;@ Direct or buffered dirtyTiles
	bx lr
;@----------------------------------------------------------------------------
k2GESaveState:				;@ In r0=destination, r1=geptr. Out r0=state size.
	.type   k2GESaveState STT_FUNC
;@----------------------------------------------------------------------------
	stmfd sp!,{r4,r5,lr}
	mov r4,r0					;@ Store destination
	mov r5,r1					;@ Store geptr (r1)

	ldr r1,[r5,#gfxRAM]
	ldr r2,=0x3360
	bl memcpy

	ldr r2,=0x3360
	add r0,r4,r2
	add r1,r5,#k2GEState
	mov r2,#(k2GEStateSize-k2GEState)
	bl memcpy

	ldmfd sp!,{r4,r5,lr}
	ldr r0,=0x3360+(k2GEStateSize-k2GEState)
	bx lr
;@----------------------------------------------------------------------------
k2GELoadState:				;@ In r0=geptr, r1=source. Out r0=state size.
	.type   k2GELoadState STT_FUNC
;@----------------------------------------------------------------------------
	stmfd sp!,{r4,r5,lr}
	mov r5,r0					;@ Store geptr (r0)
	mov r4,r1					;@ Store source

	ldr r0,[r5,#gfxRAM]
	ldr r2,=0x3360
	bl memcpy

	ldr r2,=0x3360
	add r0,r5,#k2GEState
	add r1,r4,r2
	mov r2,#(k2GEStateSize-k2GEState)
	bl memcpy

	ldr r0,=DIRTYTILES
	mov r1,#0
	mov r2,#0x600
	bl memset

	mov geptr,r5
	bl endFrame
	ldmfd sp!,{r4,r5,lr}
;@----------------------------------------------------------------------------
k2GEGetStateSize:	;@ Out r0=state size.
	.type   k2GEGetStateSize STT_FUNC
;@----------------------------------------------------------------------------
	ldr r0,=0x3360+(k2GEStateSize-k2GEState)
	bx lr

;@----------------------------------------------------------------------------
#ifdef GBA
	.section .ewram,"ax"
#endif
;@----------------------------------------------------------------------------
k2GEBufferWindows:
;@----------------------------------------------------------------------------
	ldr r0,[geptr,#kgeWinXPos]	;@ Win pos/size
	and r1,r0,#0x000000FF		;@ H start
	and r2,r0,#0x00FF0000		;@ H size
	cmp r1,#GAME_WIDTH
	movpl r1,#GAME_WIDTH
	add r1,r1,#(SCREEN_WIDTH-GAME_WIDTH)/2
	add r2,r2,r1,lsl#16
	cmp r2,#((SCREEN_WIDTH+GAME_WIDTH)/2)<<16
	movpl r2,#((SCREEN_WIDTH+GAME_WIDTH)/2)<<16
	orr r1,r1,r2,lsl#8
	mov r1,r1,ror#24
	strh r1,[geptr,#windowData]

	and r1,r0,#0x0000FF00		;@ V start
	mov r2,r0,lsr#24			;@ V size
	cmp r1,#GAME_HEIGHT<<8
	movpl r1,#GAME_HEIGHT<<8
	add r1,r1,#((SCREEN_HEIGHT-GAME_HEIGHT)/2)<<8
	add r2,r2,r1,lsr#8
	cmp r2,#(SCREEN_HEIGHT+GAME_HEIGHT)/2
	movpl r2,#(SCREEN_HEIGHT+GAME_HEIGHT)/2
	orr r1,r1,r2
	strh r1,[geptr,#windowData+2]

	bx lr

;@----------------------------------------------------------------------------
k2GE_R_W:					;@ I/O read word (0x8000-0x8FFF)
;@----------------------------------------------------------------------------
	stmfd sp!,{r4,lr}
	mov r3,r0
	bl k2GE_R
	mov r4,r0
	add r0,r3,#1
	bl k2GE_R
	orr r0,r4,r0,lsl#8
	ldmfd sp!,{r4,lr}
	bx lr
;@----------------------------------------------------------------------------
k2GE_R:						;@ I/O read byte (0x8000-0x8FFF)
;@----------------------------------------------------------------------------
	ands r2,r0,#0x0F00
	ldrne pc,[pc,r2,lsr#6]
	b k2GERegistersR
	.long k2GERegistersR		;@ 0x80XX
	.long k2GEPaletteMonoR		;@ 0x81XX
	.long k2GEPaletteR			;@ 0x82XX
	.long k2GEPaletteR			;@ 0x83XX
	.long k2GELedR				;@ 0x84XX
	.long k2GEBadR				;@ 0x85XX
	.long k2GEBadR				;@ 0x86XX
	.long k2GEExtraR			;@ 0x87XX
	.long k2GESpriteR			;@ 0x88XX
	.long k2GEBadR				;@ 0x89XX
	.long k2GEBadR				;@ 0x8AXX
	.long k2GEBadR				;@ 0x8BXX
	.long k2GESpriteR			;@ 0x8CXX
	.long k2GEBadR				;@ 0x8DXX
	.long k2GEBadR				;@ 0x8EXX
	.long k2GEBadR				;@ 0x8FXX

k2GERegistersR:
	and r2,r0,#0xFF
	cmp r2,#0x36
	ldrmi pc,[pc,r2,lsl#2]
	b k2GEBadR
	.long k2GEIrqEnableR		;@ 0x8000
	.long k2GEBadR				;@ 0x8001
	.long k2GEWinHStartR		;@ 0x8002
	.long k2GEWinVStartR		;@ 0x8003
	.long k2GEWinHSizeR			;@ 0x8004
	.long k2GEWinVSizeR			;@ 0x8005
	.long k2GERefreshR			;@ 0x8006
	.long k2GEBadR				;@ 0x8007
	.long k2GEHCountR			;@ 0x8008
	.long k2GEVCountR			;@ 0x8009
	.long k2GEBadR				;@ 0x800A
	.long k2GEBadR				;@ 0x800B
	.long k2GEBadR				;@ 0x800C
	.long k2GEBadR				;@ 0x800D
	.long k2GEBadR				;@ 0x800E
	.long k2GEBadR				;@ 0x800F
	.long k2GEStatusR			;@ 0x8010
	.long k2GEBadR				;@ 0x8011
	.long k2GEBgColR			;@ 0x8012
	.long k2GEBadR				;@ 0x8013
	.long k2GEBadR				;@ 0x8014
	.long k2GEBadR				;@ 0x8015
	.long k2GEBadR				;@ 0x8016
	.long k2GEBadR				;@ 0x8017
	.long k2GEBadR				;@ 0x8018
	.long k2GEBadR				;@ 0x8019
	.long k2GEBadR				;@ 0x801A
	.long k2GEBadR				;@ 0x801B
	.long k2GEBadR				;@ 0x801C
	.long k2GEBadR				;@ 0x801D
	.long k2GEBadR				;@ 0x801E
	.long k2GEBadR				;@ 0x801F
	.long k2GESprOfsXR			;@ 0x8020
	.long k2GESprOfsYR			;@ 0x8021
	.long k2GEBadR				;@ 0x8022
	.long k2GEBadR				;@ 0x8023
	.long k2GEBadR				;@ 0x8024
	.long k2GEBadR				;@ 0x8025
	.long k2GEBadR				;@ 0x8026
	.long k2GEBadR				;@ 0x8027
	.long k2GEBadR				;@ 0x8028
	.long k2GEBadR				;@ 0x8029
	.long k2GEBadR				;@ 0x802A
	.long k2GEBadR				;@ 0x802B
	.long k2GEBadR				;@ 0x802C
	.long k2GEBadR				;@ 0x802D
	.long k2GEBadR				;@ 0x802E
	.long k2GEBadR				;@ 0x802F
	.long k2GEBgPrioR			;@ 0x8030
	.long k2GEBadR				;@ 0x8031
	.long k2GEFgScrXR			;@ 0x8032
	.long k2GEFgScrYR			;@ 0x8033
	.long k2GEBgScrXR			;@ 0x8034
	.long k2GEBgScrYR			;@ 0x8035
k2GEBadR:
	mov r11,r11					;@ No$GBA breakpoint
	ldr r1,=0x826EBAD0
	stmfd sp!,{lr}
	bl debugIOUnimplR
	ldmfd sp!,{lr}
	mov r0,#0
	bx lr
;@----------------------------------------------------------------------------
k2GEIrqEnableR:				;@ 0x8000
;@----------------------------------------------------------------------------
	ldrb r0,[geptr,#kgeIrqEnable]
	bx lr
;@----------------------------------------------------------------------------
k2GEWinHStartR:				;@ 0x8002
;@----------------------------------------------------------------------------
	ldrb r0,[geptr,#kgeWinXPos]
	bx lr
;@----------------------------------------------------------------------------
k2GEWinVStartR:				;@ 0x8003
;@----------------------------------------------------------------------------
	ldrb r0,[geptr,#kgeWinYPos]
	bx lr
;@----------------------------------------------------------------------------
k2GEWinHSizeR:				;@ 0x8004
;@----------------------------------------------------------------------------
	ldrb r0,[geptr,#kgeWinXSize]
	bx lr
;@----------------------------------------------------------------------------
k2GEWinVSizeR:				;@ 0x8005
;@----------------------------------------------------------------------------
	ldrb r0,[geptr,#kgeWinYSize]
	bx lr
;@----------------------------------------------------------------------------
k2GERefreshR:				;@ 0x8006
;@----------------------------------------------------------------------------
	ldrb r0,[geptr,#kgeRef]
	bx lr
;@----------------------------------------------------------------------------
k2GEHCountR:				;@ 0x8008
;@----------------------------------------------------------------------------
	ldrb r1,[t9ptr,#tlcsCycShift]
	mov r0,t9cycles,lsr r1		;@ The value decreases along the scanline
	mov r0,r0,lsr#2				;@
	bx lr
;@----------------------------------------------------------------------------
k2GEVCountR:				;@ 0x8009
;@----------------------------------------------------------------------------
	ldrb r0,[geptr,#scanline]
	bx lr
;@----------------------------------------------------------------------------
k2GEStatusR:				;@ 0x8010
;@----------------------------------------------------------------------------
	ldr r0,[geptr,#scanline]
	cmp r0,#152					;@ Should this be WIN_VStart + WIN_VSize?
	movpl r0,#0x40				;@ bit 6 = in VBlank, bit 7 = character over
	movmi r0,#0
	bx lr
;@----------------------------------------------------------------------------
k2GEBgColR:					;@ 0x8012
;@----------------------------------------------------------------------------
	ldrb r0,[geptr,#kgeBGCol]
	bx lr
;@----------------------------------------------------------------------------
k2GESprOfsXR:				;@ 0x8020
;@----------------------------------------------------------------------------
	ldrb r0,[geptr,#kgeSprXOfs]
	bx lr
;@----------------------------------------------------------------------------
k2GESprOfsYR:				;@ 0x8021
;@----------------------------------------------------------------------------
	ldrb r0,[geptr,#kgeSprYOfs]
	bx lr
;@----------------------------------------------------------------------------
k2GEBgPrioR:				;@ 0x8030
;@----------------------------------------------------------------------------
	ldrb r0,[geptr,#kgeBGPrio]	;@ Bit 7=1 BG is top
	bx lr
;@----------------------------------------------------------------------------
k2GEFgScrXR:				;@ 0x8032, Foreground Horizontal Scroll register
;@----------------------------------------------------------------------------
	ldrb r0,[geptr,#kgeFGXScroll]
	bx lr
;@----------------------------------------------------------------------------
k2GEFgScrYR:				;@ 0x8033, Foreground Vertical Scroll register
;@----------------------------------------------------------------------------
	ldrb r0,[geptr,#kgeFGYScroll]
	bx lr
;@----------------------------------------------------------------------------
k2GEBgScrXR:				;@ 0x8034, Background Horizontal Scroll register
;@----------------------------------------------------------------------------
	ldrb r0,[geptr,#kgeBGXScroll]
	bx lr
;@----------------------------------------------------------------------------
k2GEBgScrYR:				;@ 0x8035, Background Vertical Scroll register
;@----------------------------------------------------------------------------
	ldrb r0,[geptr,#kgeBGYScroll]
	bx lr
;@----------------------------------------------------------------------------
k2GEPaletteMonoR:			;@ 0x8100-0x8118
;@----------------------------------------------------------------------------
	and r0,r0,#0xFF
	cmp r0,#0x19
	ldrmi r2,[geptr,#paletteMonoRAM]
	ldrbmi r0,[r2,r0]
	bx lr
;@----------------------------------------------------------------------------
k2GEPaletteR:				;@ 0x8200-0x83FF
;@----------------------------------------------------------------------------
	ldr r2,[geptr,#paletteRAM]
	mov r0,r0,lsl#23
	ldrb r0,[r2,r0,lsr#23]
	bx lr
;@----------------------------------------------------------------------------
k2GELedR:					;@ 0x84XX
;@----------------------------------------------------------------------------
	ands r1,r0,#0xFF
	beq k2GELedEnableR
	cmp r1,#0x02
	beq k2GELedBlinkR
	b k2GEBadR
;@----------------------------------------------------------------------------
k2GELedEnableR:				;@ 0x8400
;@----------------------------------------------------------------------------
	ldrb r0,[geptr,#kgeLedEnable]
	bx lr
;@----------------------------------------------------------------------------
k2GELedBlinkR:				;@ 0x8402
;@----------------------------------------------------------------------------
	ldrb r0,[geptr,#kgeLedBlink]
	bx lr
;@----------------------------------------------------------------------------
k2GEExtraR:					;@ 0x87XX
;@----------------------------------------------------------------------------
	ands r1,r0,#0xFF
	cmp r1,#0xE0
	beq k2GEResetR
	cmp r1,#0xE2
	beq k2GEModeR
	cmp r1,#0xF0
	beq k2GEModeChangeR
	cmp r1,#0xFE
	beq k2GEInputPortR
	b k2GEBadR
;@----------------------------------------------------------------------------
k2GEResetR:					;@ 0x87E0
;@----------------------------------------------------------------------------
	mov r11,r11
	mov r0,#0					;@ should return 1? !!!
	bx lr
;@----------------------------------------------------------------------------
k2GEModeR:					;@ 0x87E2
;@----------------------------------------------------------------------------
	ldrb r0,[geptr,#kgeMode]
	bx lr
;@----------------------------------------------------------------------------
k2GEModeChangeR:			;@ 0x87F0
;@----------------------------------------------------------------------------
	mov r11,r11
	ldrb r0,[geptr,#kgeModeChange]
	bx lr
;@----------------------------------------------------------------------------
k2GEInputPortR:				;@ 0x87FE (Reserved)
;@----------------------------------------------------------------------------
	mov r11,r11
	mov r0,#0x3F
//	orrne r0,r0,#0x40			;@ INP0
	bx lr
;@----------------------------------------------------------------------------
k2GESpriteR:				;@ 0x8800-0x88FF, 0x8C00-0x8C3F
;@----------------------------------------------------------------------------
	tst r0,#0x0700
	ldr r2,[geptr,#sprRAM]
	mov r1,r0,lsl#24
	addne r2,r2,#0x100
	tstne r1,#0xC0000000
	ldrbeq r0,[r2,r1,lsr#24]
	bx lr

;@----------------------------------------------------------------------------
k2GE_W_W:					;@ I/O write word (0x8000-0x8FFF)
;@----------------------------------------------------------------------------
	stmfd sp!,{r0,r1,lr}
	bl k2GE_W
	ldmfd sp!,{r0,r1,lr}
	mov r0,r0,lsr#8
	add r1,r1,#1
;@----------------------------------------------------------------------------
k2GE_W:						;@ I/O write byte (0x8000-0x8FFF)
;@----------------------------------------------------------------------------
	ands r2,r1,#0x0F00
	ldrne pc,[pc,r2,lsr#6]
	b k2GERegistersW
	.long k2GERegistersW		;@ 0x80XX
	.long k2GEPaletteMonoW		;@ 0x81XX
k2GEPalPtr:
	.long k2GEPaletteW			;@ 0x82XX
	.long k2GEPaletteW			;@ 0x83XX
	.long k2GELedW				;@ 0x84XX
	.long k2GEBadW				;@ 0x85XX
	.long k2GEBadW				;@ 0x86XX
k2GEExtraPtr:
	.long k2GEExtraW			;@ 0x87XX
	.long k2GESpriteW			;@ 0x88XX
	.long k2GEBadW				;@ 0x89XX
	.long k2GEBadW				;@ 0x8AXX
	.long k2GEBadW				;@ 0x8BXX
	.long k2GESpriteW			;@ 0x8CXX
	.long k2GEBadW				;@ 0x8DXX
	.long k2GEBadW				;@ 0x8EXX
	.long k2GEBadW				;@ 0x8FXX

k2GERegistersW:
	and r2,r1,#0xFF
	cmp r2,#0x36
	ldrmi pc,[pc,r2,lsl#2]
	b k2GEBadW
	.long k2GEIrqEnableW		;@ 0x8000
	.long k2GEBadW				;@ 0x8001
	.long k2GEWinHStartW		;@ 0x8002
	.long k2GEWinVStartW		;@ 0x8003
	.long k2GEWinHSizeW			;@ 0x8004
	.long k2GEWinVSizeW			;@ 0x8005
	.long k2GERefW				;@ 0x8006
	.long k2GEBadW				;@ 0x8007
	.long k2GEBadW				;@ 0x8008
	.long k2GEBadW				;@ 0x8009
	.long k2GEBadW				;@ 0x800A
	.long k2GEBadW				;@ 0x800B
	.long k2GEBadW				;@ 0x800C
	.long k2GEBadW				;@ 0x800D
	.long k2GEBadW				;@ 0x800E
	.long k2GEBadW				;@ 0x800F
	.long k2GEBadW				;@ 0x8010
	.long k2GEBadW				;@ 0x8011
	.long k2GEBgColW			;@ 0x8012
	.long k2GEBadW				;@ 0x8013
	.long k2GEBadW				;@ 0x8014
	.long k2GEBadW				;@ 0x8015
	.long k2GEBadW				;@ 0x8016
	.long k2GEBadW				;@ 0x8017
	.long k2GEBadW				;@ 0x8018
	.long k2GEBadW				;@ 0x8019
	.long k2GEBadW				;@ 0x801A
	.long k2GEBadW				;@ 0x801B
	.long k2GEBadW				;@ 0x801C
	.long k2GEBadW				;@ 0x801D
	.long k2GEBadW				;@ 0x801E
	.long k2GEBadW				;@ 0x801F
	.long k2GESprOfsXW			;@ 0x8020
	.long k2GESprOfsYW			;@ 0x8021
	.long k2GEBadW				;@ 0x8022
	.long k2GEBadW				;@ 0x8023
	.long k2GEBadW				;@ 0x8024
	.long k2GEBadW				;@ 0x8025
	.long k2GEBadW				;@ 0x8026
	.long k2GEBadW				;@ 0x8027
	.long k2GEBadW				;@ 0x8028
	.long k2GEBadW				;@ 0x8029
	.long k2GEBadW				;@ 0x802A
	.long k2GEBadW				;@ 0x802B
	.long k2GEBadW				;@ 0x802C
	.long k2GEBadW				;@ 0x802D
	.long k2GEBadW				;@ 0x802E
	.long k2GEBadW				;@ 0x802F
	.long k2GEBgPrioW			;@ 0x8030
	.long k2GEBadW				;@ 0x8031
	.long k2GEFgScrXW			;@ 0x8032
	.long k2GEFgScrYW			;@ 0x8033
	.long k2GEBgScrXW			;@ 0x8034
	.long k2GEBgScrYW			;@ 0x8035
k2GEBadW:
								;@ Cool Boarders writes 0x80 to 0x8011 and lots of values to 8036.
	mov r11,r11					;@ No$GBA breakpoint
	ldr r2,=0x826EBAD1
	b debugIOUnimplW
;@----------------------------------------------------------------------------
k2GEIrqEnableW:				;@ 0x8000
;@----------------------------------------------------------------------------
	strb r0,[geptr,#kgeIrqEnable]
	bx lr
;@----------------------------------------------------------------------------
k2GEWinHStartW:				;@ 0x8002
;@----------------------------------------------------------------------------
	strb r0,[geptr,#kgeWinXPos]
	bx lr
;@----------------------------------------------------------------------------
k2GEWinVStartW:				;@ 0x8003
;@----------------------------------------------------------------------------
	strb r0,[geptr,#kgeWinYPos]
	bx lr
;@----------------------------------------------------------------------------
k2GEWinHSizeW:				;@ 0x8004
;@----------------------------------------------------------------------------
	strb r0,[geptr,#kgeWinXSize]
	bx lr
;@----------------------------------------------------------------------------
k2GEWinVSizeW:				;@ 0x8005
;@----------------------------------------------------------------------------
	strb r0,[geptr,#kgeWinYSize]
	bx lr
;@----------------------------------------------------------------------------
k2GERefW:					;@ 0x8006, Total number of scanlines
;@----------------------------------------------------------------------------
	strb r0,[geptr,#kgeRef]
	bx lr
;@----------------------------------------------------------------------------
k2GEBgColW:					;@ 0x8012
;@----------------------------------------------------------------------------
	strb r0,[geptr,#kgeBGCol]
	bx lr
;@----------------------------------------------------------------------------
k2GESprOfsXW:				;@ 0x8020
;@----------------------------------------------------------------------------
	strb r0,[geptr,#kgeSprXOfs]
	bx lr
;@----------------------------------------------------------------------------
k2GESprOfsYW:				;@ 0x8021
;@----------------------------------------------------------------------------
	strb r0,[geptr,#kgeSprYOfs]
	bx lr
;@----------------------------------------------------------------------------
k2GEBgPrioW:				;@ 0x8030
;@----------------------------------------------------------------------------
	strb r0,[geptr,#kgeBGPrio]	;@ Bit 7=1 BG is top
#ifdef NDS
	ldrd r2,r3,[geptr,#kgeFGXScroll]
#else
	ldr r2,[geptr,#kgeFGXScroll]
	ldr r3,[geptr,#kgeBGXScroll]
#endif
	and r0,r0,#0x80
	strb r0,[geptr,#kgeFGYScroll+1]
	b scrollCnt
;@----------------------------------------------------------------------------
k2GEFgScrXW:				;@ 0x8032, Foreground Horizontal Scroll register
;@----------------------------------------------------------------------------
;@----------------------------------------------------------------------------
k2GEFgScrYW:				;@ 0x8033, Foreground Vertical Scroll register
;@----------------------------------------------------------------------------
;@----------------------------------------------------------------------------
k2GEBgScrXW:				;@ 0x8034, Background Horizontal Scroll register
;@----------------------------------------------------------------------------
;@----------------------------------------------------------------------------
k2GEBgScrYW:				;@ 0x8035, Background Vertical Scroll register
;@----------------------------------------------------------------------------
	add r1,r2,#(kgeFGXScroll/2) - 0x32
#ifdef NDS
	ldrd r2,r3,[geptr,#kgeFGXScroll]
#else
	ldr r2,[geptr,#kgeFGXScroll]
	ldr r3,[geptr,#kgeBGXScroll]
#endif
	strb r0,[geptr,r1,lsl#1]
scrollCnt:

	ldr r1,[geptr,#scanline]	;@ r1=scanline
	cmp r1,#159
	movhi r1,#159
	ldr r0,[geptr,#scrollLine]
	subs r0,r1,r0
	strhi r1,[geptr,#scrollLine]

	stmfd sp!,{r3}
	ldr r3,[geptr,#scrollBuff]
	add r1,r3,r1,lsl#3
	ldmfd sp!,{r3}
sy2:
	stmdbpl r1!,{r2,r3}			;@ Fill backwards from scanline to lastline
	subs r0,r0,#1
	bpl sy2
	bx lr

;@----------------------------------------------------------------------------
k2GEPaletteMonoW:			;@ 0x8100-0x8118
;@----------------------------------------------------------------------------
	and r1,r1,#0xFF
	cmp r1,#0x18
	andmi r0,r0,#0x7
	ldrle r2,[geptr,#paletteMonoRAM]
	strble r0,[r2,r1]
	bx lr
;@----------------------------------------------------------------------------
k2GEPaletteW:				;@ 0x8200-0x83FF
;@----------------------------------------------------------------------------
	ldr r2,[geptr,#paletteRAM]
	mov r1,r1,lsl#23
	strb r0,[r2,r1,lsr#23]
	bx lr
;@----------------------------------------------------------------------------
k2GELedW:					;@ 0x84XX
;@----------------------------------------------------------------------------
	ands r2,r1,#0xFF
	beq k2GELedEnableW
	cmp r2,#0x02
	beq k2GELedBlinkW
	b k2GEBadW
;@----------------------------------------------------------------------------
k2GELedEnableW:				;@ 0x8400
;@----------------------------------------------------------------------------
	strb r0,[geptr,#kgeLedEnable]
	bx lr
;@----------------------------------------------------------------------------
k2GELedBlinkW:				;@ 0x8402
;@----------------------------------------------------------------------------
	strb r0,[geptr,#kgeLedBlink]
	mov r1,r0,lsl#16
	str r1,[geptr,#ledCounter]
	bx lr
;@----------------------------------------------------------------------------
k1GEExtraW:					;@ 0x87XX
;@----------------------------------------------------------------------------
	ands r2,r1,#0xFF
	cmp r2,#0xE0
	beq k2GEResetW
	b k2GEBadW
;@----------------------------------------------------------------------------
k2GEExtraW:					;@ 0x87XX
;@----------------------------------------------------------------------------
	ands r2,r1,#0xFF
	cmp r2,#0xE0
	beq k2GEResetW
	cmp r2,#0xE2
	beq k2GEModeW
	cmp r2,#0xF0
	beq k2GEModeChangeW
	b k2GEBadW
;@----------------------------------------------------------------------------
k2GEResetW:					;@ 0x87E0
;@----------------------------------------------------------------------------
	cmp r0,#0x52
	beq k2GERegistersReset
	bx lr
;@----------------------------------------------------------------------------
k2GEModeW:					;@ 0x87E2
;@----------------------------------------------------------------------------
	ldrb r1,[geptr,#kgeModeChange]
	tst r1,#1
	and r0,r0,#0x80
	strbeq r0,[geptr,#kgeMode]
	bx lr
;@----------------------------------------------------------------------------
k2GEModeChangeW:			;@ 0x87F0
;@----------------------------------------------------------------------------
	cmp r0,#0x55
	cmpne r0,#0xAA
	and r0,r0,#1
	strbeq r0,[geptr,#kgeModeChange]
	bx lr
;@----------------------------------------------------------------------------
//k2GE_???_W				;@ 0x87F2
;@----------------------------------------------------------------------------
;@----------------------------------------------------------------------------
//k2GE_???_W				;@ 0x87F4
;@----------------------------------------------------------------------------
;@----------------------------------------------------------------------------
//k2GEInputPortW			;@ 0x87FE (Reserved)
;@----------------------------------------------------------------------------

;@----------------------------------------------------------------------------
k2GESpriteW:				;@ 0x8800-0x88FF, 0x8C00-0x8C3F
;@----------------------------------------------------------------------------
	tst r1,#0x0700
	ldr r2,[geptr,#sprRAM]
	mov r1,r1,lsl#24
	addne r2,r2,#0x100
	tstne r1,#0xC0000000
	strbeq r0,[r2,r1,lsr#24]
	bx lr

;@----------------------------------------------------------------------------
k2GEConvertTileMaps:		;@ r0 = destination
;@----------------------------------------------------------------------------
	stmfd sp!,{r4-r11,lr}


	ldr r1,[geptr,#gfxRAMBuffPtr]	;@ Source
	ldr r6,=0xFE00FE00
	ldr r7,=0xC000C000
	mov r9,#0					;@ Extra bit for bg tiles
	ldr r10,=0x44444444
	ldr r11,[geptr,#dirtyPtr]	;@ DirtyTiles
	mov r2,#64					;@ Row count

	adr lr,bgRet0
	ldrb r3,[geptr,#kgeMode]	;@ Color mode
	tst r3,#0x80
	ldreq r8,=0x1E001E00
	ldrne r8,=0x20002000
	beq bgColor
	bne bgMono
bgRet0:
	ldmfd sp!,{r4-r11,pc}

;@----------------------------------------------------------------------------
midFrame:
;@----------------------------------------------------------------------------
	stmfd sp!,{lr}
	ldrb r0,[geptr,#kgeBuffSetting]
	cmp r0,#0
	blne k2GETransferVRAM
	ldr r0,=tmpOamBuffer		;@ Destination
	ldr r0,[r0]
	bl k2GEConvertSprites
	bl k2GEBufferWindows

	ldmfd sp!,{pc}
;@----------------------------------------------------------------------------
endFrame:
;@----------------------------------------------------------------------------
	bx lr
;@----------------------------------------------------------------------------
checkFrameIRQ:
;@----------------------------------------------------------------------------
	stmfd sp!,{geptr}
	mov r2,#0x32				;@ Register 0x8032
	ldrb r0,[geptr,#kgeFGXScroll]
	bl k2GEFgScrXW
	bl endFrameGfx

	ldrb r0,[geptr,#kgeIrqEnable]
	tst r0,#0x80				;@ VBlank IRQ
	movne lr,pc
	ldrne pc,[geptr,#frameIrqFunc]
	mov r0,#0					;@ Must return 0 to end frame.
	ldmfd sp!,{geptr,pc}
;@----------------------------------------------------------------------------
frameEndHook:
	ldrb r0,[geptr,#kgeLedOnOff]
	ldrb r1,[geptr,#kgeLedEnable]
	cmp r1,#0xff
	cmpne r1,#0x00
	andeq r0,r1,#1
	beq noLedBlink
	ldr r1,[geptr,#ledCounter]
	ldr r2,=515*198				;@ Total cycles per frame
	subs r1,r1,r2
	eormi r0,r0,#1
	ldrbmi r2,[geptr,#kgeLedBlink]
	addsmi r1,r1,r2,lsl#16
	addmi r1,r1,r2,lsl#16		;@ Lowest value is less than tcpf.
	str r1,[geptr,#ledCounter]
noLedBlink:
	strb r0,[geptr,#kgeLedOnOff]

	mov r0,#0
	str r0,[geptr,#scrollLine]

	ldr r2,=lineStateTable
	ldr r1,[r2],#4
	mov r0,#0
	stmia geptr,{r0-r2}			;@ Reset scanline, nextChange & lineState

	mov r0,#1
	ldmfd sp!,{pc}

;@----------------------------------------------------------------------------
newFrame:					;@ Called before line 0
;@----------------------------------------------------------------------------
	bx lr

;@----------------------------------------------------------------------------
lineStateTable:
	.long 0, newFrame			;@ zeroLine
	.long 75, midFrame			;@ Middle of screen
	.long 151, endFrame			;@ Last visible scanline
	.long 152, checkFrameIRQ	;@ frameIRQ
	.long 199, frameEndHook		;@ totalScanlines (from 0x8006)
;@----------------------------------------------------------------------------
#ifdef GBA
	.section .iwram, "ax", %progbits	;@ For the GBA
	.align 2
#endif
;@----------------------------------------------------------------------------
redoScanline:
;@----------------------------------------------------------------------------
	ldr r2,[geptr,#lineState]
	ldmia r2!,{r0,r1}
	stmib geptr,{r1,r2}			;@ Write nextLineChange & lineState
	stmfd sp!,{lr}
	mov lr,pc
	bx r0
	ldmfd sp!,{lr}
;@----------------------------------------------------------------------------
k2GEDoScanline:
;@----------------------------------------------------------------------------
	ldmia geptr,{r0,r1}			;@ Read scanLine & nextLineChange
	cmp r0,r1
	bpl redoScanline
	add r0,r0,#1
	str r0,[geptr,#scanline]
;@----------------------------------------------------------------------------
checkScanlineIRQ:
;@----------------------------------------------------------------------------
	cmp r0,#152
	movhi r0,#1
	bxhi lr

	ldrb r1,[geptr,#kgeIrqEnable]
	ands r1,r1,#0x40			;@ HIRQ enabled?
	stmfd sp!,{lr}
	movne lr,pc
	ldrne pc,[geptr,#hblankIrqFunc]

	mov r0,#1
	ldmfd sp!,{pc}

;@----------------------------------------------------------------------------
cData:
	.long CHR_DECODE
	.long BG_GFX+0x08000		;@ BGR tiles
	.long BG_GFX+0x0C000		;@ BGR tiles2
	.long SPRITE_GFX			;@ SPR tiles
	.long 0x44444444			;@ Tile2 mask
;@----------------------------------------------------------------------------
k2GETransferVRAM:
;@----------------------------------------------------------------------------
	stmfd sp!,{r4-r11,lr}
	ldr r5,=DIRTYTILES
	ldr r0,[geptr,#gfxRAMSwap]
	ldr r1,[geptr,#gfxRAM]
	add r6,r5,#0x300
	mov r2,#0
	ldr r7,=0x44444444

tileLoop16_2p:
	ldr r4,[r5]
	str r7,[r5],#4
	ldr r3,[r6]
	and r3,r3,r4
	str r3,[r6],#4
	tst r4,#0x000000FF
	bleq tileLoop16_3p
	add r2,r2,#0x10
	tst r4,#0x0000FF00
	bleq tileLoop16_3p
	add r2,r2,#0x10
	tst r4,#0x00FF0000
	bleq tileLoop16_3p
	add r2,r2,#0x10
	tst r4,#0xFF000000
	bleq tileLoop16_3p
	add r2,r2,#0x10
	cmp r2,#0x3000
	bne tileLoop16_2p

	ldmfd sp!,{r4-r11,pc}

tileLoop16_3p:
	add r3,r1,r2
	ldmia r3,{r8-r11}
	add r3,r0,r2
	stmia r3,{r8-r11}
	bx lr

;@----------------------------------------------------------------------------
k2GEConvertTiles:
;@----------------------------------------------------------------------------
	stmfd sp!,{r4-r11,lr}
	adr r0,cData
	ldmia r0,{r6-r10}
	ldr r4,[geptr,#gfxRAMBuffPtr]
	add r4,r4,#0x1000			;@ Skip tilemap
	ldr r5,[geptr,#dirtyPtr]
	add r5,r5,#0x100			;@ Skip tilemap
	mov r1,#0
	mov r2,#0xFF
	mov r2,r2,lsl#1

tileLoop16_0p:
	ldr r11,[r5]
	str r10,[r5],#4
	tst r11,#0x000000FF
	addne r1,r1,#0x10
	bleq tileLoop16_1p
	tst r11,#0x0000FF00
	addne r1,r1,#0x10
	bleq tileLoop16_1p
	tst r11,#0x00FF0000
	addne r1,r1,#0x10
	bleq tileLoop16_1p
	tst r11,#0xFF000000
	addne r1,r1,#0x10
	bleq tileLoop16_1p
	cmp r1,#0x2000
	bne tileLoop16_0p

	ldmfd sp!,{r4-r11,pc}

tileLoop16_1p:
	ldrh r0,[r4,r1]
	and r3,r2,r0,lsr#7
	ldrh r3,[r6,r3]
	and r0,r2,r0,lsl#1
	ldrh r0,[r6,r0]
	orr r0,r3,r0,lsl#16

	str r0,[r9,r1,lsl#1]
	str r0,[r7,r1,lsl#1]
	orr r3,r0,r0,lsr#1
	and r3,r10,r3,lsl#2
	orr r0,r0,r3
	str r0,[r8,r1,lsl#1]
	add r1,r1,#2
	tst r1,#0x0E
	bne tileLoop16_1p

	bx lr

;@----------------------------------------------------------------------------
;@bgChrFinish				;@ r0=destination, r1=source, r2=rowCount
;@----------------------------------------------------------------------------
;@	r6=0xFE00FE00
;@	r7=0xC000C000
;@	r8=0x1E001E00
;@  r9=0x0						;@ Extra bit for bg tiles
;@ r10=0x44444444
;@ r11=DIRTYTILES
;@ MSB          LSB
;@ hv_CCCCnnnnnnnnn
bgColor:
	cmp r2,#0x20				;@ Are we on BG?
	ldreq r9,=0x02000200		;@ Extra bit for bg tiles
	ldr r3,[r11],#4				;@ Dirtytiles
	teq r3,r10
	bne bgColorRow
	add r1,r1,#0x40
	add r0,r0,#0x40
	subs r2,r2,#1
	bne bgColor
	bx lr
bgColorRow:
	str r10,[r11,#-4]			;@ Dirtytiles
bgColorLoop:
	ldr r4,[r1],#4				;@ Read from NeoGeo Pocket Tilemap RAM
	bic r3,r4,r6
	and r5,r4,r8
	orr r3,r3,r5,lsl#3			;@ Color
	and r4,r4,r7				;@ Mask NGP flip bits
	orr r4,r4,r4,lsr#2
	and r4,r7,r4,lsl#1
	orr r3,r3,r4,lsr#4			;@ XY flip
	cmp r2,#0x20				;@ Are we on BG?
	orrle r3,r3,r9

	str r3,[r0],#4				;@ Write to GBA/NDS Tilemap RAM
	tst r0,#0x3C				;@ 32 tiles wide
	bne bgColorLoop
	subs r2,r2,#1
	bne bgColor

	bx lr
;@----------------------------------------------------------------------------
;@bgChrFinish				;@ r0=destination, r1=source, r2=rowCount
;@----------------------------------------------------------------------------
;@	r6=0xFE00FE00
;@	r7=0xC000C000
;@	r8=0x20002000
;@  r9=0x0						;@ Extra bit for bg tiles
;@ r10=0x44444444
;@ r11=DIRTYTILES
;@ MSB          LSB
;@ hvC____nnnnnnnnn
bgMono:
	cmp r2,#0x20				;@ Are we on BG?
	ldreq r9,=0x02000200		;@ Extra bit for bg tiles
	ldr r3,[r11],#4				;@ Dirtytiles
	teq r3,r10
	bne bgMonoRow
	add r1,r1,#0x40
	add r0,r0,#0x40
	subs r2,r2,#1
	bne bgMono
	bx lr
bgMonoRow:
	str r10,[r11,#-4]			;@ Dirtytiles
bgMonoLoop:
	ldr r4,[r1],#4				;@ Read from NeoGeo Pocket Tilemap RAM
	bic r3,r4,r6
	and r5,r4,r8
	orr r3,r3,r5,lsr#1			;@ Color
	and r4,r4,r7				;@ Mask NGP flip bits
	orr r4,r4,r4,lsr#2
	and r4,r7,r4,lsl#1
	orr r3,r3,r4,lsr#4			;@ XY flip
	orr r3,r3,r9

	str r3,[r0],#4				;@ Write to GBA/NDS Tilemap RAM
	tst r0,#0x3C				;@ 32 tiles wide
	bne bgMonoLoop
	subs r2,r2,#1
	bne bgMono

	bx lr

;@----------------------------------------------------------------------------
copyScrollValues:			;@ r0 = destination
;@----------------------------------------------------------------------------
	stmfd sp!,{r4-r7}
	ldr r1,[geptr,#scrollBuff]

	mov r6,#((SCREEN_HEIGHT-GAME_HEIGHT)/2)<<23
	add r0,r0,r6,lsr#20			;@ 8 bytes per row
	mov r4,#(0x100-(SCREEN_WIDTH-GAME_WIDTH)/2)<<7
	sub r4,r4,r6
	mov r5,#GAME_HEIGHT
setScrlLoop:
	ldmia r1!,{r2,r3}
	add r2,r2,r4,lsr#7
	add r3,r3,r4,lsr#7
	cmn r6,r2,lsl#7
	eormi r2,r2,#0x1000000
	cmn r6,r3,lsl#7
	eorpl r3,r3,#0x1000000
	movs r7,r2					;@ Also checks BG priority.
	stmiapl r0!,{r2,r3}
	stmiami r0!,{r3,r7}
	add r6,r6,#1<<23
	subs r5,r5,#1
	bne setScrlLoop

	ldmfd sp!,{r4-r7}
	bx lr

;@----------------------------------------------------------------------------
	.equ PRIORITY,	0x400		;@ 0x400=AGB OBJ priority 1
;@----------------------------------------------------------------------------
k2GEConvertSprites:			;@ in r0 = destination.
;@----------------------------------------------------------------------------
	stmfd sp!,{r4-r11,lr}

	mov r11,r0					;@ Destination

	ldr r10,[geptr,#sprRAM]
	add r9,r10,#0x100			;@ Spr palette

	ldrb r7,[geptr,#kgeMode]	;@ Color mode
	ldrb r0,[geptr,#kgeSprXOfs]	;@ Sprite offset X
	ldrb r5,[geptr,#kgeSprYOfs]	;@ Sprite offset Y
	add r0,r0,#(SCREEN_WIDTH-GAME_WIDTH)/2		;@ GBA/NDS X offset
	add r5,r5,#(SCREEN_HEIGHT-GAME_HEIGHT)/2	;@ GBA/NDS Y offset
	orr r5,r5,r0,lsl#24
	mov r4,r5

	mov r8,#64					;@ Number of sprites
dm5:
	ldr r0,[r10],#4				;@ NGP OBJ, r4=Tile,Attrib,Xpos,Ypos.
	movs r2,r0,lsl#22			;@ 0x400=X-Chain, 0x200=Y-Chain
	addcs r1,r0,r4,lsr#8		;@ X-Chain
	addcc r1,r0,r5,lsr#8		;@ X-Offset
	addmi r3,r4,r0,lsr#24		;@ Y-Chain
	addpl r3,r5,r0,lsr#24		;@ Y-Offset
	and r1,r1,#0xFF0000
	and r4,r3,#0xFF				;@ Save Y-pos
	orr r3,r4,r1				;@ Xpos
	orr r4,r4,r1,lsl#8			;@ Save X-pos
	ands r6,r0,#0x1800			;@ Prio
	beq skipSprite
	movs r2,r0,lsl#17			;@ Test H- & V-flip
	orrcs r3,r3,#0x10000000		;@ H-flip
	orrmi r3,r3,#0x20000000		;@ V-flip

	str r3,[r11],#4				;@ Store OBJ Atr 0,1. Xpos, ypos, flip, scale/rot, size, shape.

	mov r0,r0,ror#9
	mov r3,r0,lsr#23			;@ Tilenumber
	and r0,r0,#0x10
	mov r0,r0,lsr#4
	tst r7,#0x80
	ldrbeq r0,[r9],#1			;@ Color palette
	orr r3,r3,r0,lsl#12
#ifdef NDS
	rsb r6,r6,#0x1800			;@ Convert prio NDS
#elif GBA
	rsb r6,r6,#0x2000			;@ Convert prio GBA
#endif
	orr r3,r3,r6,lsr#1

	strh r3,[r11],#4			;@ Store OBJ Atr 2. Pattern, palette.
dm4:
	subs r8,r8,#1
	bne dm5
	ldmfd sp!,{r4-r11,pc}
skipSprite:
	mov r0,#0x200+SCREEN_HEIGHT	;@ Double, y=SCREEN_HEIGHT
	str r0,[r11],#8
	add r9,r9,#1
	b dm4

;@----------------------------------------------------------------------------
#ifdef GBA
	.section .sbss				;@ For the GBA
#else
	.section .bss
#endif
CHR_DECODE:
	.space 0x200
	.space 8
SCROLL_BUFF:
	.space 160*8

#endif // #ifdef __arm__
