# IPTA-DR3 / EPTA clock overlay (private)

Curated overlay installed **after** the public IPTA snapshot by
`scripts/update_clock_corrections.sh`. Only files listed here are copied into
the image; do not dump the full DR3/EPTA clock tree into this directory.

## Required

- `effix2gps.clk` — EPTA-DR3 Asterix tip (public IPTA ends MJD 59294.5;
  EPTA extends to ~60433). **Build fails without this file.**

## DR3-only site stubs (zero corrections, MJD 55000–65000)

Installed only when the public IPTA snapshot does not already ship the file
(so real upstream corrections are never overwritten):

- `fast2gps.clk`, `lofar2gps.clk`, `nenufar2gps.clk`
- `eflfrhba2gps.clk`, `julfrhba2gps.clk`, `ndlfrhba2gps.clk`,
  `polfrhba2gps.clk`, `tblfrhba2gps.clk`, `uwlfrhba2gps.clk`
- `time_fast.dat`

Build fails if any of these are still missing after the public + overlay merge.

## Optional

- `effedd2gps.clk` — force-replaced into both Tempo2 and PINT trees if present

## Do not add here

These would **regress** the newer public IPTA snapshot already baked from
`github.com/ipta/pulsar-clock-corrections`:

- `gbt2gps.clk`, `ncyobs2obspm.clk`, `tai2tt_bipm20*`
- Redundant copies of `ao2gps.clk`, `pks2gps.clk`, or a stub `gmrt2gps.clk`

Public IPTA GBT/BIPM/Nançay tips stay authoritative; only DR3-only stubs and
the EPTA `effix2gps.clk` tip are overlaid.
