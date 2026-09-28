# Microcontroller research — 9 boards

**Date researched:** 27 September 2026 · All prices INR, single-piece, as listed on that date.
`my-components.csv` in this folder is the importable version of this.

Three independent research passes were run and cross-checked. Where they disagreed, the
resolution and the reasoning are recorded under each item. Nothing was priced from memory.

---

## 1. LOLIN NodeMCU V3 — `NODEMCU-V3-LOLIN` — Rs 219

ESP8266EX @ 80 MHz · 4 MB flash · Wi-Fi b/g/n, no BT · ESP-12E module on 30-pad header ·
3.3 V logic, 5 V Vin · micro-USB + CH340G.

- **Rs 219 incl. GST — Robu.in, SKU 62160 — <https://robu.in/product/nodemcu-esp8266-v3-lua-ch340-wifi-dev-board/> — currently OUT OF STOCK** (verified live 27 Sep 2026 via r.jina.ai proxy)
- Rs 195 incl. GST — Robocraze, SKU TIFC00135 — <https://robocraze.com/products/lolin-nodemcu-esp8266-wifi-module> — **listed sold out**
- Datasheet: <https://documentation.espressif.com/esp8266ex/esp8266ex_datasheet_en.html>

Both Indian retailers show the LOLIN V3 as sold out/out of stock. The Rs 219 figure from Robu is the live price, though unavailable.

**Corrections to your notes:** the vendor site is **wemos.cc**, not "vemos.cc". On baud rate —
9600 is the legacy AT-firmware rate; the ESP8266 **ROM bootloader answers at 74880**, and the
normal serial monitor is **115200**. If 9600 shows nothing, that is expected, not a fault.

**Unresolved:** board dimensions conflict across sources — Robocraze says 49 × 24.5 × 13 mm,
LOLIN's own marketing says 58 × 32 mm. lolinwiki.com did not resolve, so this is not settled.

---

## 2. AI-Thinker NodeMCU V1.2 — `NODEMCU-V1.2-ESP12E` — Rs 259

ESP8266EX @ 80 MHz · 4 MB flash · ESP-12E module · 0.9 in row pitch (V3 is 1.1 in) · 3.3 V logic.

- **Rs 259 incl. GST — Robu.in, SKU 18821, CP2102 "Amica" version, In Stock** — <https://robu.in/product/nodemcu-cp2102-board/> (verified live 27 Sep 2026)
- Rs 199.42 — Electronicscomp EC-1150, **CH340** version — <https://www.electronicscomp.com/nodemcu-esp8266-wifi-development-board>
- Rs 262 incl. GST — Robocraze TIFCC0102, **CP2102** "Amica" — <https://robocraze.com/products/nodemcu-esp8266-amica-cp2102-driver>
- Rs 277.30 — Electronicscomp CP2102 version
- Genuine AI-Thinker-branded: Rs 477–810 depending on seller

**Corrections to your notes:** "8266" in the silkscreen is just **ESP8266**, not a garbled
"ESP8266EX". And **V1.2 is a clone silkscreen, not an official AI-Thinker product** — the real
AI-Thinker board is V1.0 "Amica". That matters for price: the genuine Amica is CP2102 and costs
more, and most V1.2 clones are CH340G, so the cheaper number is the right one to record.

**Your board has the V1.2 silkscreen**, so it's a clone. Check the USB chip on it: if CP2102,
use the Rs 259 figure; if CH340G, the Electronicscomp Rs 199.42 is closer. I've recorded the
Robu CP2102 price since it's live and in stock.

---

## 3. Generic ESP32 DevKit V1, 30-pin — `ESP32-DEVKIT-V1-30PIN` — Rs 417

ESP32-D0WD dual-core Xtensa LX6 @ 240 MHz · 4 MB flash / 520 KB SRAM · Wi-Fi + BT 4.2/BLE ·
ESP32-WROOM-32 module · AMS1117 3.3 V.

- Rs 417 incl. GST — Robocraze TIFCC0162, 30-pin CP2102, **in stock** — <https://robocraze.com/products/nodemcu-32-wifi-bluetooth-esp32-development-board30-pin>
- Rs 400 — KSP Electronics; Rs 375 — Quartzcomponents; Rs 695.80 — iotcart IOT-2592
- 36-pin variants: Rs 449–459 (Robu)

**The FCC ID does not check out — this is the item most worth knowing.**
`2A53N-ESP32` returns **zero filings** in the FCC database, and fccid.io has never had a page for
that grantee code (a Wayback control query confirmed the method itself works). The near-identical
**valid** filing is `2A54N-ESP32` — Shenzhen HiLetgo. For reference, **Espressif's own grantee code
is 2AC7Z**, so a genuine Espressif-certified module would never read 2A53N. So the silkscreen is
third-party or simply fabricated, which is normal for this class of board and not a fault.

`210-1670` is a fragment of the compliance block `210-167000`. Genuine ESP32-WROOM-32 modules are
marked `ESP32-D0WDQ6 V01` plus a lot code, so this is a vendor trace code, not a model.
PCB strings seen on these boards: `GS-S-32D` / `CS-S-32D`, brand mark `ZY-ESPS2`.

**Open question for you:** if your board has a **USB-C** connector rather than micro-USB, it is a
different variant priced at Rs 171–379 and uses CH9102X, so tell me which and I will adjust.

*Method caveat:* fccid.io, fcc.report, device.report and fcc.gov all returned HTTP 403 to this
environment, so the FCC findings come from search-indexed copies plus corroborating forum reports,
not a direct database query.

---

## 4. ESP32-CAM with camera — `ESP32-CAM-OV2640` — Rs 799

ESP32-D0WD dual-core Xtensa LX6 @ 240 MHz · 4 MB flash + 4 MB QSPI PSRAM · Wi-Fi + BT 4.2/BLE ·
40.5 × 27 mm · microSD slot · 5 V or 3.3 V input.

- **Rs 799 incl. GST — Robu.in, kit WITH OV2640** — <https://robu.in/product/esp32-cam-wifi-module-bluetooth-with-ov3660-camera-module-2mp/> — the page title says OV3660 while the URL and body say OV2640; that is a retailer typo, the product is the 2 MP OV2640 kit
- Rs 695.02 — Electronicscomp EC-4974 · Rs 675 — Quartzcomponents
- Rs 687 — Robu ESP32-CAM-MB, includes a micro-USB programmer board
- Not the same product: bare board **without** camera Rs 709; OV3660 **3 MP** version Rs 689

**Identification is solid:** the "ESP32-S" + AI-Thinker logo combination is AI-Thinker's house
name for their WROOM-32-class module. An S3-based board would read "ESP32-S3-WROOM" and carry the
**Espressif** wordmark, not the AI logo. Confirm with `esptool.py chip_id` — an S3 reports
`ESP32-S3 (QFN56)`.

**Practical note recorded in the app:** no onboard USB-serial, so it needs an external USB-TTL
(CH340G ~Rs 101 ex-GST) and GPIO0 pulled low to GPIO15 to enter flash mode. Also needs ≥500 mA;
1 A recommended. Many listings substitute the OV3660 3 MP sensor — worth checking yours.

---

## 5. REES52 Uno R3 — `REES52-RS033` — Rs 215 — **identified**

**"Planting the Seeds of Innovation" is REES52's own tagline**, and the slogan plus the "RES52"
silkscreen is what cracked this one. Both REES52 and **IDUINO** are trademarks of **Robotics
Embedded Education Services Pvt Ltd**, New Delhi. It is not "Impato Zero" or "Imperato".

ATmega328P SMD @ 16 MHz · 32 KB flash / 2 KB SRAM / 1 KB EEPROM · 14 digital (6 PWM) + 6 analog ·
USB Type-B + CH340G · MPN **RS033** (SMD); a DIP variant exists too.

- **Rs 215 — rees52.com, 1135 in stock** — <https://rees52.com/products/arduino-uno-r3-smd-development-board>
- Rs 200 (was Rs 379) — <https://iduino.co.in/product/smd-uno-r3-ch340-atmega328p-development-board-compatible-with-arduino/>
- DIP variant Rs 390; with USB cable Rs 630 · Indian Uno R3 clone range **Rs 200–400**

**Caveat I would not repeat from your notes:** "Made in India" is seller marketing copied out of
their own listing, not something independently verifiable. These are almost certainly Shenzhen-made
with Indian packaging. I recorded the claim's origin rather than asserting it.

---

## 6. Arduino Nano — `ATMEGA328P-NANO-CH340` — **Rs 255.42** (soldered + cable, in stock)

ATmega328P @ 16 MHz · 32 KB flash / 2 KB SRAM · 45 × 18 mm · Mini-USB Type-B · 5 V logic, no DC jack.

**Robu.in live prices (27 Sep 2026):**

| Variant | Price | SKU | Status | Notes |
|---|---|---|---|---|
| **SOLDERED + USB Mini cable** | **Rs 255.42 incl GST** | 7146 | **In Stock** | CH340G, headers pre-soldered, Mini-USB cable included |
| Unsoldered, no cable | Rs 358.00 incl GST | 4657 | Out of Stock | CH340G, headers not soldered, no cable |
| Genuine Arduino A000005 | Rs 1,755 incl GST | TIFC00120 | 3 left | FT232RL, official blue/white PCB, Arduino branding |

- Robocraze CH340 clone (unspecified solder state): Rs 212 — <https://robocraze.com/products/nano-development-board-compatible-with-arduino>
- REES52 / iduino: Rs 200 (sold by REES52) — <https://iduino.co.in/product/smd-uno-r3-ch340-atmega328p-development-board-compatible-with-arduino/>
- Typical Indian clone range: **Rs 170–350** depending on solder state and cable.

**Port correction:** the Nano has **never** had a square USB-B port. Original A000005 and essentially every clone use **Mini-USB Type-B**. Square USB-B is the **Uno's** port — your memory crossed the two boards.

**Recorded value:** **Rs 255.42** (the soldered + cable variant, SKU 7146, in stock), since you confirmed your board has soldered headers. The unsoldered Rs 358 variant is out of stock. Genuine Arduino is Rs 1,755.

---

## 7. AI-Thinker ESP-12F from the RC plane — `ESP-12F` — Rs 211.22

ESP8266EX @ 80/160 MHz · 4 MB flash · 802.11 b/g/n 2.4 GHz · SMD-22 castellated, 16 × 24 × 3 mm ·
3.0–3.6 V. The AI-Thinker logo is genuine and came from the module itself.

- **Rs 179 ex-GST (MRP Rs 211.22 incl. 18%)** — Electronicscomp EC-4960 — <https://www.electronicscomp.com/ai-thinker-esp-12f-esp8266-serial-wifi-module>
- Rs 152 — Robocraze TIFCC0016
- Recorded cost uses the **GST-inclusive** MRP for consistency with the other rows

**Correction: this is an ESP8266, not an ESP32.** ESP-12F is an ESP8266EX module. Your original
description said ESP32; the module family is unambiguously 8266.

**Recorded as a usability fact, since it bites:** this is a **bare SMD module** — no USB, no
regulator, no EN/BOOT buttons. To program it you need an external 3.3 V USB-TTL adapter
(CH340G ~Rs 101 ex-GST, or FT232RL Rs 172) and GPIO0 pulled low at reset. A ₹16 carrier PCB
exists but is out of stock at Robocraze.

**"Kalam Labs" could not be verified, so I did not record it as a vendor.** `kalamlabs.in`
resolves to a **stratospheric UAV company in Coimbatore** with no store, no catalogue and no
product pages; searching Kalam on ElectronicsComp returns 0 products and on Robocraze returns 5
unrelated items. The pasted report asserts Kalam Labs is a STEM/robotics education company with
this board in its range, but cited no source for it — and nothing corroborates it. Recorded the
module, which is certain, and left the branding as a note.

**Unresolved:** I/O count. AI-Thinker spec tables say **9**; the ESP8266EX silicon defines
GPIO0–16 with GPIO6–11 tied to the SPI flash. AI-Thinker's own datasheet is behind a JS bot wall
and could not be read to arbitrate. Worth checking against the physical module.

---

## 8. MATRIX Creator — `MATRIX-CREATOR` — no price

**A Raspberry Pi HAT by MATRIX Labs containing both things you guessed at once:**

| Part | Device |
|---|---|
| FPGA | **Xilinx Spartan-6 XC6SLX4** |
| MCU | **Atmel/Microchip SAM3S2** — 32-bit ARM Cortex-M3 |
| Radio | **Silicon Labs EM3588** — ARM Cortex-M3, Wi-Fi + BT |
| Form factor | Pi HAT, 40-pin header — **not standalone** |
| Supply | 5 V from the Pi supply; docs specify a 5 V / 2.5 A micro-USB PSU |

**"Armel" is a misreading of "Atmel"** — the MCU maker. Confirmed by an official JTAG scan in their
docs that names all four silicon IDs.

Sensors: ST LSM9DS1 accel/gyro/mag · ST HTS221 temp/humidity · NXP PN512 NFC · NXP MPL3115A2
pressure · Vishay VEML6070 UV · Vishay TSOP573 IR receiver · 8× ST MEMS digital microphones ·
SK6812 RGBW "everloop" LED · camera · Zigbee and Z-Wave radios.

**No price, deliberately.** The original company is defunct: `matrix.one` is gone and `matrix.io`
was taken over by an unrelated crypto/"Matrix AI Network" project, so neither is a valid source.
Zero results on ElectronicsComp and Robocraze. A historical ~$99 SparkFun figure could not be
verified, so recording it would have been a guess. Unit cost is 0 rather than a fabricated number.

Two claims in the pasted report I did not carry over: **"MATRIX Labs (Miami)"** — no source
supports a location, and the company trails as a San Francisco startup later acquired as Admobilize,
so I left the city out entirely. And **"36 RGB LEDs"** — the docs describe a single RGBW "everloop"
LED; I could not find 36 anywhere. Also: the silkscreen "will what will you recreate?" appears
nowhere on the web, so I recorded the board as identified by the name and hardware instead.
**Rev 1 vs Rev 2** differ by two expansion pins, and a "…1" on your board may be a revision mark —
unconfirmed.

Docs (GitHub only, not the dead domain): <https://matrix-io.github.io/matrix-documentation/>

---

## 9. Raspberry Pi 4 Model B 8 GB — `SC0195` — Rs 18,497

Market research for the SC0195 used in this inventory. Board revision, serial number,
hostname, network addresses and other machine-specific details are deliberately not
recorded in this repository — that information is private to the machine's owner.

**Price re-verified live on 27 Sep 2026 after the first pass got it wrong.** robu.in is
Cloudflare-walled to direct requests (HTTP 403), but it can be read through the `r.jina.ai`
reader proxy:

- **Rs 18,497.00 incl. GST — Robu.in, SKU 757102, Availability: In Stock** — <https://robu.in/product/raspberry-pi-4-model-b-with-8-gb-ram/> — box contents are the **board only**
- Rs 18,495 incl. GST — Robocraze TIFC00091 — <https://robocraze.com/products/raspberry-pi-4-model-b-8-gb-ram>
- Rs 18,599 — ElectroPi · Rs 18,497 — Robodo · Rs 20,296 — iotcart (backorder)
- Excluded as stale pre-2021-RAM-crisis offers: Engineerstoy Rs 5,649 · IndiaMART Rs 5,720
- Amazon.in unusable as a reference: Rs 11,980 / 19,999 / 34,331 across three dates, all grey sellers

**Two prices that looked real and are not:**

| Figure | What it actually was |
|---|---|
| **Rs 9,029** | A **"Raspberry Pi Weekend Sale"** promo captured in a Wayback snapshot from 3 Jan 2026. It has since reverted. The snapshot is 9 months stale. |
| **Rs 15,600** (QuartzComponents) | Could not be corroborated, and is below what two authorized resellers agree on. Almost certainly a misread or a stale listing. **Not used.** |

Robocraze at Rs 18,495 and Robu at Rs 18,497 agreeing within **Rs 2** across two independent
authorized Pi resellers is strong evidence that ~Rs 18,500 is the standing market price. My first
pass picked the Rs 15,600 outlier on the strength of a single unverified listing, which was the
wrong call — corrected.

**Correction to the pasted report: the Pi 4B is NOT discontinued.** The official product brief
says production continues to at least **January 2034** and part SC0195 is "Active". It is
superseded by the Pi 5, not end-of-life. The wild Amazon prices are grey sellers, not scarcity.

Board only — a PSU is **not** included (Rs 700–1,200 separately), and the 8 GB variant wants
5.1 V / 3 A. The Robu listing quotes the 1.5 GHz base clock; on some boards
`arm_boost=1` in `/boot/firmware/config.txt` raises it to 1.8 GHz.

---

## Cross-check summary

Every board was researched by more than one pass. The three places the sources genuinely diverged,
and how each was settled:

| Item | Disagreement | Resolution |
|---|---|---|
| REES52 / Uno | "Made in India" stated as fact | Recorded as seller marketing with its origin; not asserted. Brand **REES52** confirmed via its own tagline. |
| ESP32 FCC ID | One pass called `2A53N-ESP32` "a known" FCC ID; the other found **zero** filings | Went with **unverified**. Do not enter as an MPN. The real neighbouring filing is `2A54N`. |
| ESP-12F branding | One pass asserted a Kalam Labs product; the other found no such product anywhere | Went with **unverified**. Recorded the module, which is certain, and kept the branding in notes. |
| Pi 4B 8 GB | Rs 15,600 (QuartzComponents) vs Rs 18,495 (Robocraze) vs Rs 9,029 (stale Wayback promo) | Went with **Rs 18,497**, verified live at Robu. Two authorized resellers agree within Rs 2; the outlier was dropped and the Rs 9,029 promo identified as a reverted January sale. |

**Price policy applied: higher-end / recent price for each board.**

| Board | Lower option | Higher (recorded) | Rationale |
|---|---|---|---|
| NodeMCU V3 | Rs 195 (Robocraze, sold out) | **Rs 219** (Robu, out of stock) | Higher of two verified but unavailable prices |
| NodeMCU V1.2 | Rs 199.42 (Electronicscomp CH340) | **Rs 259** (Robu CP2102, in stock) | Higher verified price, in stock |
| Arduino Nano | Rs 200 (REES52) / Rs 255.42 (Robu soldered, in stock) | **Rs 255.42** (Robu soldered + cable, in stock) | User confirmed soldered headers; in-stock variant |
| ESP-12F | Rs 152 (Robocraze) | **Rs 211.22** (Electronicscomp MRP incl GST) | Higher MRP figure |
| Pi 4B 8GB | Rs 18,495 (Robocraze) | **Rs 18,497** (Robu, in stock) | Higher of two live verified prices |

I did not average conflicting prices. Where two sources agreed on a number I used it; where a
board was listed sold out I recorded the price anyway but said so in the notes.

**One correction to my own first pass:** the Pi price originally went in at Rs 15,600 on the
strength of a single uncorroborated listing. When Robu turned out to be readable via the `r.jina.ai`
proxy, the live figure was Rs 18,497 — Rs 2,897 higher, and consistent with Robocraze. Picking
the cheapest single listing was wrong when authorized resellers converge on a different number.
