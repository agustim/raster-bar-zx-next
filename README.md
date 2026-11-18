# Raster Bar (Copperbar) per al ZX Spectrum Next

Un **raster bar** (barra metàl·lica horitzontal) per a ZX Spectrum Next, dibuixat
amb el coprocessor **Copper**.
  `src/build/rasterbar.nex` (el script fa `cd src` i compila des d'allà).
## Per què Copper i no la CPU

A la wiki oficial de SpecNext, la FAQ diu que els efectes de multicolor/border
que depenen del *timing* de la CPU (per exemple els motors Nirvana/Bifrost) **no
funcionen bé per HDMI**, perquè els displays HDMI no tenen el buffer intern que
té un monitor de tub i el Next no el compensa. Aquests requereixen VGA/RGB.

El **Copper** és un coprocessador de maquinari que s'executa **sincronitzat amb
el ràster** (independentment de la CPU). Per tant, un raster bar fet amb el
Copper **és estable per HDMI** — és exactament el mateix motiu pel qual el
"copperbar" original de l'Amiga no necessitava la CPU.

## Com funciona

1. Omplim tota la pantalla de **Layer 2** amb el color d'índex 0 de la paleta.
2. El **Copper** reescriu l'entrada 0 de la paleta a cada scanline: fosc a fora
   de la banda, i un gradient metàl·lic dins la banda. Com que cada scanline
   mostra el píxel 0, això pinta la banda horitzontal.
3. Per moure la barra, un manejador reescriu el **byte Y de cada instrucció
   WAIT** del llistat de Copper. El Copper s'executa en mode `%11`, que reinicia
   des de l'índex 0 a cada ràster 0/0, així que la nova posició s'aplica al
   principi del següent frame sense tearing.

## Fitxers

- `src/rasterbar.asm` — codi font (Z80 + instruccions Z80N `NEXTREG`).
- `src/gen_gradient.py` — genera les taules `gradient.inc`, `copper.inc` i
  `targets.inc` (NOVA: podeu ajustar l'alçada/colors de la banda aquí).
- `src/gradient.inc`, `src/copper.inc`, `src/targets.inc` — dades generades.
- `src/sjasmplus` — assemblador (v1.24.1, precompilat).
- `build.sh` — compila tot i genera `src/build/rasterbar.nex`.

## Compilar

```sh
./build.sh
```

Requereix `python3` i `sjasmplus` (ja inclòs a `src/`). El resultat és
`src/build/rasterbar.nex`.

## Executar

Carregueu `build/rasterbar.nex` en un emulador que suporti ZX Spectrum Next
(per exemple ZEsarUX amb `--machine TBBlue`) o en maquinari real.

```sh
zesarux --machine TBBlue --snap src/build/rasterbar.nex
```

## Ajustos

A `src/rasterbar.asm`:

- `BAR_STEPS` — velocitat vertical (scanlines per frame).
- `BAR_BOUND_LO` / `BAR_BOUND_HI` — límits del recorregut de la barra.

A `src/gen_gradient.py`:

- `BAND` — alçada de la barra en scanlines.
- `FLOOR` / `PEAK` — colors (r,g,b 0-7) de la base i del centre (specular) de la
  banda metàl·lica.
