;;--------------------------------------------------------------------
;; rasterbar.asm - Metallic raster bar (copperbar) for the ZX Spectrum Next
;;
;; The bar is a rigid horizontal metallic band drawn by the hardware Copper
;; coprocessor: for every scanline inside the band the Copper writes a
;; different shade to Layer 2 palette entry 0.  Because the Copper is scanline
;; synchronised hardware, this effect is stable on HDMI output (CPU-timed
;; multicolour such as Nirvana/Bifrost is not - see the SpecNext FAQ).
;;
;; The whole Layer 2 screen is filled with pixel value 0, so every scanline
;; displays palette entry 0.  The Copper repaints entry 0 to dark background
;; everywhere except the band, where it paints the metallic shades.
;;
;; The bar is translated by re-writing the Y byte of each band WAIT instruction.
;; The Copper runs in mode %11 (restart from index 0 on every raster 0/0), so a
;; new position is picked up at the top of the next frame and there is no
;; tearing.  No interrupts are needed - the main loop paces the updates.
;;--------------------------------------------------------------------

	DEVICE ZXSPECTRUMNEXT
	SLDOPT COMMENT WPMEM, LOGPOINT, ASSERTION
	CSPECTMAP "build/rasterbar.map"

;;--------------------------------------------------------------------
;; constants
;;--------------------------------------------------------------------

L2_START_16K_BANK = 9
L2_START_8K_BANK  = L2_START_16K_BANK * 2
L2_END_8K_BANK    = L2_START_8K_BANK + 6

BAR_TOP0     = 90      ; initial bar top scanline
BAR_STEPS    = 3       ; vertical speed in scanlines per frame
BAR_BOUND_LO = 64      ; bar top may not go above this
BAR_BOUND_HI = 176     ; bar top may not go below this

	ORG $8000
Start:
	DI
	CALL InitLayer2
	CALL InitPalette
	CALL UploadCopper

	; Main animation loop.  We wait for the start of a new frame (the active
	; video line counter wrapping to a low value), then move the bar and re-write
	; the copper WAIT targets.  The Copper restarts from raster 0/0 each frame, so
	; the new position is applied at the next frame top - no tearing, and no
	; interrupts are required.
.loop:
	CALL WaitForFrame
	CALL AdvanceBar
	CALL WriteBarTargets
	JP .loop

	RET

;;--------------------------------------------------------------------
;; Fill the whole visible Layer 2 screen (6 x 8K banks) with pixel value 0 so
;; that entry 0 of the L2 palette is shown on every scanline (the Copper then
;; repaints entry 0 per scanline to draw the band).
;;--------------------------------------------------------------------
InitLayer2:
	LD BC, $123B
	LD A, 2
	OUT (C), A

	NEXTREG $12, L2_START_16K_BANK
	NEXTREG $70, %00'00'0000   ; 256x192x8

	LD A, L2_START_8K_BANK
.nextBank:
	NEXTREG $56, A
	LD HL, $C000
	LD (HL), 0
	LD HL, .dmaFill
	LD B, .dmaFillLen
	LD C, $6B
	OTIR
	INC A
	CP L2_END_8K_BANK + 1
	JP NZ, .nextBank

	; Set Layer 2 clip window to the full 256x192 screen.
	NEXTREG $18, 0
	NEXTREG $18, 255
	NEXTREG $18, 0
	NEXTREG $18, 191
	NEXTREG $1C, 0
	RET

.dmaFill:
	DB %10000011   ; WR6 - disable DMA
	DB %01111101   ; WR0 - append length + port A address, A->B
	DW $C000
	DW 8*1024-1
	DB %00100100   ; WR1 - A fixed, A=memory
	DB %00010000   ; WR2 - B incrementing, B=memory
	DB %10101101   ; WR4 - continuous, append port B address
	DW $C001
	DB %10000010   ; WR5 - stop on end of block, CE only
	DB %11001111   ; WR6 - load addresses into DMA counters
	DB %10000111   ; WR6 - enable DMA
.dmaFillLen = $ - .dmaFill

;;--------------------------------------------------------------------
;; The Copper repaints palette entry 0 every frame, so the only thing we must
;; guarantee here is that entry 0 starts as the background colour (in case the
;; Copper runs a little late on the very first frame).
;;--------------------------------------------------------------------
InitPalette:
	NEXTREG $43, %10010000   ; L2 first palette, no auto-increment
	NEXTREG $40, 0
	NEXTREG $41, 0           ; entry 0 = background (index 0 in gradient profile)
	RET

;;--------------------------------------------------------------------
;; Upload the generated copper program once, then start it in mode %11
;; (start from index 0, loop, restart at raster 0/0 each frame).
;;--------------------------------------------------------------------
UploadCopper:
	NEXTREG $61, 0
	NEXTREG $62, %00'000'000   ; stop copper, address MSB = 0

	LD HL, CopperList
	LD DE, CopperListEnd - CopperList
	LD B, E
	DEC DE
	INC D
.nextByte:
	LD A, (HL)
	NEXTREG $63, A            ; 16-bit write (auto-increments)
	INC HL
	DJNZ .nextByte
	DEC D
	JP NZ, .nextByte

	NEXTREG $62, %11'000'000  ; start: mode %11, address MSB = 0
	RET

;;--------------------------------------------------------------------
;; A short delay used to pace the animation.  Tuned so the bar advances at a
;; comfortable speed without flicker.
;;--------------------------------------------------------------------
; Pace the animation to one step per output frame.  The active video line
; counter (NextReg $1F, LSB) advances with the raster and wraps once per frame;
; we wait for it to rise past the bottom border and then drop to the top of the
; next frame, which delimits exactly one frame and bounds the bar to one step.
WaitForFrame:
.vbl1:
	LD A, $1F
	CALL ReadNextReg      ; A = current active video line LSB
	CP 200
	JR C, .vbl1           ; wait while line < 200 (still in the active area)
.vbl2:
	LD A, $1F
	CALL ReadNextReg
	CP 40
	JR NC, .vbl2          ; wait until line drops below 40 (new frame begins)
	RET
; Read NextReg N into A.  NextRegs are read by writing the register number to
; port $243B and reading port $253B.
ReadNextReg:
	LD BC, $243B
	OUT (C), A            ; A already holds the register number
	LD BC, $253B
	IN A, (C)
	RET
AdvanceBar:
	LD A, (BarDir)
	AND A
	JR NZ, .down
	LD A, (BarTop)
	SUB BAR_STEPS
	CP BAR_BOUND_LO
	JR C, .bounceDown
	LD (BarTop), A
	RET
.down:
	LD A, (BarTop)
	ADD A, BAR_STEPS
	CP BAR_BOUND_HI
	JR NC, .bounceUp
	LD (BarTop), A
	RET
.bounceDown:
	LD A, BAR_BOUND_LO
	LD (BarTop), A
	LD A, 1
	LD (BarDir), A
	RET
.bounceUp:
	LD A, BAR_BOUND_HI
	LD (BarTop), A
	LD A, 0
	LD (BarDir), A
	RET

; Rewrite the Y byte of every band WAIT instruction so the band appears at the
; current BarTop.  BandTargets[k] is the copper-memory byte offset of the Y
; byte of band line k; value written is BarTop + k (k = 0..BAND).
WriteBarTargets:
	LD A, (BarTop)
	LD D, A                  ; D = base Y (BarTop)
	LD IX, BandTargets
	LD B, BAND + 1
	NEXTREG $62, %11'000'000 ; mode %11, address MSB = 0 (once)
.next:
	LD L, (IX + 0)           ; copper-memory byte offset of this band WAIT Y byte
	INC IX
	LD A, L
	NEXTREG $61, A           ; copper address LSB
	LD A, D                  ; Y value = BarTop + k
	NEXTREG $60, A           ; write the Y byte
	INC D
	DJNZ .next
	RET

;;--------------------------------------------------------------------
;; variables
;;--------------------------------------------------------------------
	.ALIGN 2
BarTop:    DB BAR_TOP0
BarDir:    DB 0        ; 0 = moving up, 1 = moving down

;;--------------------------------------------------------------------
;; data (generated by gen_gradient.py)
;;--------------------------------------------------------------------
	INCLUDE "gradient.inc"
	INCLUDE "copper.inc"
	INCLUDE "targets.inc"

;;--------------------------------------------------------------------
;; NEX file output
;;--------------------------------------------------------------------
	SAVENEX OPEN "build/rasterbar.nex", Start, $FF40
	SAVENEX CORE 3, 0, 0
	SAVENEX CFG 7, 0, 0, 0
	SAVENEX AUTO
