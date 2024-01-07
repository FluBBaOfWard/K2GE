//
//  K2GE.h
//  K2GE
//
//  Created by Fredrik Ahlström on 2008-04-02.
//  Copyright © 2008-2024 Fredrik Ahlström. All rights reserved.
//
// SNK K1GE/K2GE Graphics Engine emulation

#ifndef K2GE_HEADER
#define K2GE_HEADER

#ifdef __cplusplus
extern "C" {
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

typedef struct {
	u32 scanline;
	u32 nextLineChange;
	u32 lineState;

//k2GEState:
//k2GERegs:					// 0-4
	u8 winXPos;
	u8 winYPos;
	u8 winXSize;
	u8 winYSize;
	u8 bgXScroll[2];
	u8 bgYScroll[2];
	u8 fgXScroll[2];
	u8 fgYScroll[2];

	u8 sprXOfs;
	u8 sprYOfs;
	u8 irqEnable;
	u8 ref;
	u8 bgCol;
	u8 bgPrio;
	u8 ledEnable;
	u8 ledBlink;
	u8 mode;
	u8 modeChange;

	u8 ledOnOff;			// Bit 0, Led On/Off.
	u8 model;

	u32 ledCounter;
	u32 windowData;

	u8 buffSetting;
	u8 padding1[3];

	void *hblankIrqFunc;
	void *frameIrqFunc;

	void *dirtyPtr;
	void *gfxRAMBuffPtr;
	void *gfxRAM;
	void *sprRAM;
	void *paletteMonoRAM;
	void *paletteRAM;
	void *gfxRAMSwap;
	u32 *scrollBuff;

} K2GE;

void k2GEReset(void *frameIrqFunc(), void *periodicIrqFunc(), void *ram);

/**
 * Saves the state of the chip to the destination.
 * @param  *destination: Where to save the state.
 * @param  *chip: The K1GE/K2GE chip to save.
 * @return The size of the state.
 */
int k2GESaveState(void *destination, const K2GE *chip);

/**
 * Loads the state of the chip from the source.
 * @param  *chip: The K1GE/K2GE chip to load a state into.
 * @param  *source: Where to load the state from.
 * @return The size of the state.
 */
int k2GELoadState(K2GE *chip, const void *source);

/**
 * Gets the state size of a K1GE/K2GE.
 * @return The size of the state.
 */
int k2GEGetStateSize(void);

/**
 * Enables/disables buffered VRAM mode.
 * @param  enable: Enable buffered VRAM mode.
 */
void k2GEEnableBufferMode(bool enable);

void k2GEDoScanline(void);
void k2GEConvertTileMaps(void *destination);
void k2GEConvertSprites(void *destination);
void k2GEConvertTiles(void);

#ifdef __cplusplus
} // extern "C"
#endif

#endif // K2GE_HEADER
