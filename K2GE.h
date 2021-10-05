// SNK K1GE/K2GE Graphics Engine emulation

#ifndef K2GE_HEADER
#define K2GE_HEADER

#ifdef __cplusplus
extern "C" {
#endif

#define HW_K2GE		(0)
#define HW_K1GE		(1)
#define NGP_COLOR	HW_K2GE
#define NGP_MONO	HW_K1GE

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
	u8 kgeWinXPos;
	u8 kgeWinYPos;
	u8 kgeWinXSize;
	u8 kgeWinYSize;
	u8 kgeBGXScroll[2];
	u8 kgeBGYScroll[2];
	u8 kgeFGXScroll[2];
	u8 kgeFGYScroll[2];

	u8 kgeSprXOfs;
	u8 kgeSprYOfs;
	u8 kgeIrqEnable;
	u8 kgeRef;
	u8 kgeBGCol;
	u8 kgeBGPrio;
	u8 kgeLedEnable;
	u8 kgeLedBlink;
	u8 kgeMode;
	u8 kgeModeChange;

	u8 kgeLedOnOff;			// Bit 0, Led On/Off.
	u8 kgeModel;
//	u8 koPadding1[1];

	u32 ledCounter;
	u32 windowData;

	void *periodicIrqFunc;
	void *frameIrqFunc;

	u8 dirtyTiles[4];
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

void k2GEDoScanline(void);
void k2GEConvertTileMaps(void *destination);
void k2GEConvertSprites(void *destination);
void k2GEConvertTiles(void);

#ifdef __cplusplus
} // extern "C"
#endif

#endif // K2GE_HEADER
