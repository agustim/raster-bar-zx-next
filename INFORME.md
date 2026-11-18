# Informe de desenvolupament — Raster Bar per a ZX Spectrum Next

Aquest document explica, pas a pas, què s'he fet per crear el raster bar i quins
problemes he anat trobant, amb la causa i la solució de cadascun. L'objectiu és
que quedi clar **per què** s'ha pres cada decisió i quanta part del temps s'ha
perdut en entrebancs d'eines (no de disseny).

---

## 1. Objectiu

Fer un **raster bar** (barra de color horitzontal animada; en anglès "raster bar"
o "copperbar") per a un **ZX Spectrum Next**, pensat per sortir per **HDMI**.
Aquest és el motiu pel qual el resultat és un efecte força diferent del que la
majoria de gent espera d'un "raster bar" d'un Spectrum clàssic.

## 2. Context i punt de partida

El directori de treball era buit. Això volia dir que no hi havia ni codi ni
toolchain. El que sí que hi havia a la màquina (descobert explorant) era:

- **ZEsarUX 13.0** (`/usr/bin/zesarux`), un emulador que suporta el ZX Spectrum
  Next (màquina `TBBlue`).
- Un **dev guide complet** a
  `~/Escriptori/Personal/zxspectrum-next/zx-next-dev-guide/` (i una versió en
  català `zx-next-dev-guide-ca`), que conté exemples i **no el binari de
  sjasmplus** (el directori `Tools/sjasmplus/` només tenia un `.gitignore`,
  perquè els binaris s'ignoren al repositori).

## 3. La decisió clau de disseny: Copper, no CPU

El primer problema conceptual era: **com es fa un raster bar al Next que funcioni
per HDMI?**

A la FAQ oficial de la wiki de SpecNext hi ha aquesta entrada:

> *"I'm using an HDMI display and a game's graphics appear garbled — Some games
> (specifically ones with multicolour or border effects — eg. Nirvana/Bifrost
> engine games, certain demos) require precise timings as with a regular
> Spectrum. Due to the nature of HDMI displays and the lack of internal
> buffering on the Spectrum Next display hardware currently these will not work
> properly and require a VGA or RGB display."*

Traduït: els efectes que depenen de sincronització *exacta* de la CPU per
scanline (els motors de multicolor clàssics, "raster interrupts" a mà) **es
trenquen per HDMI**, perquè el display HDMI no té el buffer que sí que té un
monitor de tub.

**Solució:** el **Copper**. És un coprocessador de maquinari que s'executa
**sincronitzat amb el ràster**, completament independent de la CPU. La wiki ho
descriu així:

> *"The Copper is a simple programmed system which allows certain Next Registers
> to be altered automatically at certain scanline positions."*

Per tant, un raster bar fet amb el Copper és estable tant per VGA com per HDMI.
Aquest és exactament el mateix motiu pel qual el "copperbar" de l'Amiga no
necessitava la CPU. **Aquesta sola decisió és el 90% del valor del treball.**

Ho vaig confirmar executant l'exemple `copper` del dev guide a ZEsarUX: ja
produïa bandes de color vermell/groc. A partir d'aquí vaig construir la versió
pròpia.

## 4. Toolchain: el primer gran entrebanc (temps perdut)

No hi havia assemblador. Opcions:

1. Instal·lar `sjasmplus` des del repositori d'Arch (AUR).
2. Compilar-lo des de la font.
3. Usar un que ja vingués al dev guide (però era un directori buit).

Vaig començar a buscar per `find` a tot el sistema, cosa que **va trigar uns 5
minuts** (la cerca es va executar en segon pla). El resultat va ser que hi havia
el directori `Tools/sjasmplus/` del dev guide, però **buit**.

**Vaig optar per compilar sjasmplus des de la font** (git clone + make). Aquí va
aparèixer el primer error real:

```
sjasm/lua_sjasm.cpp:46:10: fatal error: LuaBridge/LuaBridge.h: No such file or directory
```

**Causa:** el projecte usa submoduls de git (`LuaBridge`, `unittest-cpp`) que no
es descarreguen amb un `clone --depth 1` normal.

**Solució:** `git submodule update --init --recursive` i tornar a `make`. Amb
això va quedar compilat `sjasmplus v1.24.1`.

**Lliçó:** la compilació és ràpida (16 s); el temps es va perdre en la cerca
inicial del binari i en descobrir el problema dels submoduls.

## 5. Entendre els registres del Next

Abans d'escriure codi vaig haver de confirmar els registres exactes. Vaig
descarregar la referència `nextreg.txt` (del projecte `ZXSpectrumNextTests`) i la
referència de ports `ports.txt`. Els rellevants:

| Registre | Funció |
|----------|--------|
| `$12` | Layer 2 — banc de RAM actiu (16K) |
| `$70` | Layer 2 — resolució (bit 5-4) |
| `$43` | Control de paleta (selecció de paleta, auto-increment) |
| `$40` | Índex de paleta |
| `$41` | Valor de paleta (format 8-bit `RRRGGGBB`) |
| `$61` / `$62` | Control del Copper (adreça i mode) |
| `$60` | Dades del Copper (escriptura de 8 bits) |
| `$63` | Dades del Copper (escriptura de 16 bits) |
| `$1E` / `$1F` | Línia de vídeo activa (MSB/LSB) — per sincronitzar amb VBLANK |
| `$18` / `$1C` | Finestra de retall (clip window) de Layer 2 |
| `$123B` | Port per habilitar Layer 2 |

**Format de color 9-bit:** el Next permet 9 bits de color (RGB 3:3:3). Es
converteix en dos bytes:
- `$41` no suporta 9 bits complets (és `RRRGGGBB`, 8 bits).
- `$44` sí: primer byte `RRRGGGBB`, segon byte només el bit LSB del blau.

Aquí vaig prendre una decisió de simplificació: com que jo genero els colors
amb Python i el que vull és un gradient metàl·lic, vaig fer servir el format de
**8 bits via `$41`** (més senzill d'escriure des del Copper amb un sol MOVE,
perquè el Copper escriu 1 byte per instrucció). El gradient no perd res
apreciable perquè el meu perfil ja està limitat a 8 bits.

## 6. L'exemple `copper` del dev guide: la base

L'exemple `copper/main.asm` fa exactament el tipus d'efecte que vull (canvia una
entrada de paleta per scanline mitjançant el Copper). Vaig llegir-lo sencer
(juntament amb els exemples `im2/main.asm` per als vectors d'interrupció). De
l'exemple vaig aprendre:

- La **sintaxi del Copper**: cada instrucció són 2 bytes:
  - `WAIT`: `%1hhhhhhv %vvvvvvvv` (espera a la línia `v` i posició horitzontal `h*8`).
  - `MOVE`: `%0rrrrrrr %vvvvvvvv` (escriu valor `v` al registre `r`).
  - `HALT`: `%11111111 %11111111`.
- El **mode de control** del Copper (`$62` bits 7-6):
  - `%00` aturat, `%01` reinicia i comença, `%10` reprèn, `%11` reinicia a ràster 0/0.
  - El mode `%11` és clau: **reinicia el Copper des de l'inici a cada frame**,
    cosa que permet canviar la posició sense tearing.
- La manera d'**escriure** el programa al Copper: byte a byte pel port `$60`
  (escriptura immediata, cada byte) o `$63` (escriptura parell, que només
  commita quan s'han escrit els 2 bytes d'una instrucció).

## 7. El disseny de la meva versió

Vaig dissenyar un **raster bar metàl·lic** (no un simple bloc sòlid), perquè és
més vistós i demostra millor la tècnica:

1. Omplir tota la pantalla de Layer 2 amb el píxel d'índex 0.
2. El Copper reescriu **l'entrada 0 de la paleta** per cada scanline: fosc fora
   de la banda, i un **gradient metàl·lic** (amb un *specular* brillant al
   centre) dins la banda.
3. Per moure la barra, el codi reescriu el **byte Y de cada instrucció WAIT**.
   Com que el Copper corre en mode `%11`, la nova posició s'aplica al
   principi del frame següent → **sense tearing**.

La generació del gradient la faig amb Python (que no té `sin` a sjasmplus):
una taula de 32 ombres on la brillantor segueix una corba `sin` que culmina al
centre (l'efecte cromat).

## 8. Errors concrets de codi i com els he resolt

Aquí és on es va concentrar la major part del temps de programació (cada un va
donar errors d'assemblatge o de comportament):

### 8.1 `LD (nn), n` — no existeix al Z80
Vaig escriure `LD (BarDir), 1` i el muntador va dir:
`error: Illegal instruction: LD (BarDir), 1`.

**Causa:** al Z80 no hi ha `LD (nn), imm8`; només existeix `LD (nn), A`.
**Solució:** carregar el valor a `A` primer:
```asm
LD A, 1
LD (BarDir), A
```

### 8.2 `NEXTREG $61, L` — el segon operand ha de ser `A` o immediat
Vaig escriure `NEXTREG $61, L` per posar l'adreça baixa del Copper, i va fallar.

**Causa:** la instrucció `NEXTREG` del sjasmplus (opcode Z80N) només accepta com
a segon operand `A` o un valor immediat, perquè l'opcode real és `ED 91, <reg>,
<val>` i només la forma `NEXTREG <reg>, A` fa servir l'acumulador.
**Solució:** separar-ho en dos passos, carregant `A` abans:
```asm
LD A, L
NEXTREG $61, A
```

### 8.3 `WaitForFrame` malformat (restes d'un esborrany)
En una versió vaig deixar dins de la rutina de delay una línia de text solta
(`HALT-aware busy wait: spin on a counter.`) que no era codi, i un `LD C, $10`
que referència un contador que no s'usava bé. El muntador va donar errors
d'instrucció no reconeguda.
**Solució:** reescriure la rutina amb un bucle net de dos nivells (`LD C`, `LD B`,
`DJNZ`, `DEC C`, `JR NZ`).

### 8.4 La barra no es movia / kernel panic "espuri"
El primer intent d'animació feia servir **interrupcions IM2 + `HALT`**. El resultat
va ser que la barra **no es movia** i el ZEsarUX mostrava un missatge
"`kernel panic: Segmentation fault`".

**Causa doble:**
1. El "kernel panic" de ZEsarUX és en realitat un **acudit** que surt en tancar
   l'emulador (un altre era "Insert side B", un altre "she's sucking mud").
   No era un error real; el `PC` que mostrava era només el punt on el bucle
   d'espera estava quan el va matar. Vaig perdre una mica de temps intentant
   "solucionar" un missatge que no era un problema.
2. El problema real era que **les interrupcions IM2 no arribaven de manera
   fiable** a l'emulador, i amb `HALT` (que requereix EI i una interrupció
   activa) el codi es quedava aturat.

**Solució:** **eliminar completament les interrupcions**. En lloc de `HALT + EI`,
vaig escriure un bucle d'animació que **fa una espera activa** i, un cop per
frame, mou la barra i reescriu els WAIT. El Copper ja no depèn de la CPU per
sincronitzar-se, així que la CPU només fa de "director" per moure la posició.
Aquest va ser el canvi que va fer funcionar l'animació.

### 8.5 Sincronització amb VBLANK (el meu propi "trampa")
El següent problema va ser que la barra es movia **massa ràpid** (la CPU va a
3.5 MHz i el bucle d'espera curta feia que s'actualitzés moltes vegades per
frame). A les captures es veia que saltava ~45 línies per frame en lloc d'avançar
de 3 en 3.

**Solució:** sincronitzar amb el **comptador de línia de vídeo activa**
(`NextReg $1F`). El codi espera que la línia baixi per sota d'un llindar
(principi de frame) i després torni a pujar, de manera que **només avança un pas
per frame** independentment de la velocitat de CPU. Això va donar el moviment
suau i oscil·lant que es veu a la verificació.

### 8.6 Escriptura/lectura de NextRegs — port diferent per llegir
Vaig trigar a recordar que **llegir** un NextReg no és com escriure'l. Per
escriure es fa `NEXTREG $NN, val` (que sjasmplus tradueix a `ED 92`/`ED 91`),
però per **llegir** cal:
```asm
LD BC, $243B
OUT (C), A        ; A = número de registre
LD BC, $253B
IN A, (C)         ; A = valor
```
Això va caldre per llegir `$1F` a la sincronització VBLANK. El primer esborrany

### 8.7 La causa arrel: `ReadNextReg` sobreescrivia el registre C (BUG REAL)
Aquest és el problema que l'usuari va veure de veritat: **la barra quedava
congelada al mig** (`zesarux --machine TBBlue --snap src/build/rasterbar.nex`).

**Causa:** la rutina que llegeix un NextReg fa:
```asm
ReadNextReg:
    LD BC, $243B     ; <-- això SOBREESCRIU el registre C
    OUT (C), A
    LD BC, $253B
    IN A, (C)
    RET
```
Però al bucle de sincronització jo guardava el número de registre a llegir
(`$1F`) **dins del registre C**:
```asm
WaitForFrame:
    LD C, $1F        ; C = número de registre
.vbl1:
    LD A, C
    CALL ReadNextReg ; ReadNextReg destrueix C!
    ...
```
Quan `ReadNextReg` fa `LD BC, $243B`, el registre `C` passa a valdre `$3B`
(el byte baix de l'adreça del port). A la segona iteració, `LD A, C` ja no
carrega `$1F` sinó `$3B` (59). Aleshores el codi llegeix el **NextReg 59** en
lloc de la línia de vídeo. El valor d'aquell registre feia que la condició
`CP 40` / `CP 200` **mai es complís**, de manera que el bucle d'espera quedava
atrapat per sempre, `WriteBarTargets` s'executava **una sola vegada** i la barra
es queda fixa.

**Solució:** no confiar en el registre C. Carregar el número de registre
`$1F` **des de l'immediat a cada iteració**:
```asm
WaitForFrame:
.vbl1:
    LD A, $1F
    CALL ReadNextReg
    CP 200
    JR C, .vbl1
.vbl2:
    LD A, $1F
    CALL ReadNextReg
    CP 40
    JR NC, .vbl2
    RET
```
Això va fer que el bucle d'espera funcionés i la barra es mogués.

A més, mentre investigava això vaig intentar sincronitzar amb el **flag
d'interrupció ULA** (`$22` bit 7), però aquell mètode va tornar a congelar la
barra a l'emulador (un altre problema de detecció d'edges), així que em vaig
quedar amb el comptador de línia `$1F`, que és el que funciona de manera fiable.

**Verificació de la fix:** amb la versió corregida, 30 captures seguides
mostren la barra oscil·lant suaument (posicions de la línia *specular*:
462→474→486, rebot, 476→464→...→266, 270→282→...→408), amb 30 posicions
distingibles en 30 captures — un moviment suau i gradual, gens saltat.

## 9. Verificació — i el segon gran entrebanc (captures)

Verificar un efecte de vídeo és la part més frustrant. Vaig provar diverses
maneres de capturar la pantalla:

1. **Captura de la finestra** amb `import` + `xvfb-run`: resultat **inconsistent** —
   de vegades sortia la pantalla, de vegades la interfície grisa de ZEsarUX, de
   vegades tot negre. Depenia de l'enfocament/estat de la finestra, que en un
   entorn sense gestor de finestres canvia.
2. **`--vofile` (sortida de vídeo raw)**: el fitxer quedava sempre a **0 bytes**,
   perquè ZEsarUX el bolca en tancar, i el meu `kill` no ho feia de forma
   ordenada.

**Solució definitiva:** usar el driver de vídeo **`--vo null`** (sense finestra,
per tant sense problemes d'enfocament) juntament amb `--vofile`. Això produeix
un fitxer raw determinista. Vaig descobrir que cada frame és `352×288×3` bytes i
vaig poder **analitzar els frames** amb Python/Numpy: localitzar la fila amb més
color saturat (el *specular* de la barra) i veure com es mouia entre frames.

Aquest mètode em va permetre **provar de manera objectiva** que:
- La barra metàl·lica es renderitza (gradient fosc → brillant → fosc).
- Es mou i **oscil·la** entre els límits de manera suau i periòdica
  (posicions 83→147→211→275, rebot, 0→56→120...).

També vaig renderitzar un frame a PNG per confirmar visualment el resultat.

## 10. Resum del temps invertit

La major part del temps NO es va gastar en el disseny del raster bar (que,
un cop entès el Copper, és relativament directe). Es va gastar en:

| Bloc | Temps aproximat |
|------|-----------------|
| Exploració / buscar toolchain | elevat (la cerca de `find` va trigar ~5 min en segon pla) |
| Compilar sjasmplus (submoduls) | mitjà |
| Errors de sintaxi Z80 (`LD (nn),n`, `NEXTREG`, etc.) | mitjà |
| "Solucionar" el falso kernel panic | baix, però distret |
| Eliminar IM2 i passar a bucle actiu | mitjà |
| Sincronització VBLANK (massa ràpid) | mitjà |
| **Captura/verificació de vídeo** | elevat (mètodes inconsistents) |

**Conclusió:** la dificultat no va ser el concepte (el Copper ho resol), sinó
l'entorn: la manca de toolchain i la dificultat de **capturar i verificar** un
efecte de vídeo en un emulador sense interfície gràfica estable.

## 11. Resultat final

Fitxers al directori `raster-bar/`:
- `src/rasterbar.asm` — codi font (Z80 + `NEXTREG`)
- `src/gen_gradient.py` — genera les taules de colors
- `src/gradient.inc`, `src/copper.inc`, `src/targets.inc` — dades generades
- `src/sjasmplus` — assemblador v1.24.1 (compilat)
- `build.sh` — `./build.sh` → `src/build/rasterbar.nex`
- `README.md`

**Verificat a ZEsarUX** (màquina `TBBlue`): la barra metàl·lica es mou i
oscil·la suaument, sincronitzada a un pas per frame, sense tearing.

**Limitació honesta:** s'ha verificat amb l'emulador ZEsarUX, no amb maquinari
real. El Copper és maquinari i el comportament hauria de ser el mateix en un Next
físic, però convé confirmar-ho. A més, com que el Copper s'ha d'executar molt
ràpid per pintar tantes línies, caldria comprovar que la longitud del llistat i
el temps d'execució no introdueixin artefactes en un dispositiu real.
