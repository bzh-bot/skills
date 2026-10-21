---
name: workflow-flightplan
org: personal
description: Plan a VFR cross-country flight with the user (your home base and rental outfit) — build the nav log (tracks, headings, wind correction, groundspeed, times, fuel), weight & balance, weather/NOTAM briefing via agent-browser, runway performance, destination logistics (fuel/parking prices, accommodation, transport), and the Canadian CFP/ICAO flight plan. Use when the user wants to plan a flight, prepare a nav, fill a nav log, get a weather briefing, or file a flight plan.
---

# Flight Planning (VFR cross-country)

Plan a flight **together with the user**, phase by phase. This is interactive:
the user makes all aeronautical decisions (GO/NO-GO, altitudes, fuel); you do
lookups, math, and transcription. Never present calculated headings/fuel as
authoritative — the user verifies with their whiz wheel/CX-3.

## Context

- Base: **`<HOME_ICAO>`** — your home aerodrome. Rental/school: **`<RENTAL_ORG>`**, with its
  own dispatch hours and out-of-hours authorisation rule (put them here once, then follow
  them); supervisors are usually listed on the weight & balance sheet.
- Rental documents required before flight: Flight Planning Form, Weight &
  Balance, Passenger Manifest, Flight Plan.
- Working folder (`$FLIGHT_DIR`) holding your checklist and the blank forms:
  - a cross-country planning checklist — follow it top-down
  - a nav log form (winds/WCA/TH/MH/GS/time/fuel + DR log + comm plan)
  - the rental outfit's go/no-go form
  - the current weight & balance sheet — the **only** source of empty weight/arm/moment
  - the flight-plan form (CFP/ICAO in Canada)
- Aircraft: read empty weight / arm / moment from the **current** W&B sheet for the tail
  number you are flying — never carry numbers over from memory or an older sheet.
- Fuel reserves: day VFR 30 min, night 45 min; the outfit's recommendation is often 60 min.

## Workflow

Follow the phases in `Cross-Country Planning Checklist.md`. Per flight, create
a dated subfolder (e.g. `trips/2026-09-11 <HOME_ICAO>-XXXX/`) in the working folder
and keep a `plan.md` there that accumulates every value as it's decided —
this file is the single source of truth for filling the PDFs at the end.

1. **Route & chart work** (no weather): destination/alternate, checkpoints,
   true tracks, distances, variation, cruise altitude (hemispheric + airspace),
   frequencies from CFS, airspace/CYR restrictions along the route.
2. **Destination logistics**: fuel price/availability, parking/landing fees,
   accommodation, ground transport, PPR/customs.
3. **Weather & NOTAMs** (day of flight, via agent-browser).
4. **Nav calcs**: WCA → TH → MH, GS, leg times, ETA, fuel required vs on board.
5. **W&B + performance**: takeoff/landing weight & CG, pressure/density
   altitude, takeoff/landing distances vs runway available.
6. **Flight Planning Form** transcription + GO/NO-GO (user decides).
7. **File CFP flight plan** (times in UTC; user files; plan how to close it).
8. **In-flight/after**: revised ETAs, actual fuel burn → log for the spreadsheet.

## Online lookups (use agent-browser skill)

- **Weather + NOTAM briefing**: NAV CANADA CFPS at https://plan.navcanada.ca
  — METAR/TAF, GFA (clouds/wx + icing/turb/frz lvl), upper winds (FDs, use
  CYUL for the region), NOTAMs, AIRMET/SIGMET/PIREPs. No login needed.
- **Flight plan filing**: NAV CANADA online (user account) or 1-866-WXBRIEF.
- **CFS data** (frequencies, runway lengths, fuel, circuit alt): user's CFS
  copy or ForeFlight; web fallback: airport websites / CWAS pages, or
  OurAirports CSVs (https://davidmegginson.github.io/ourairports-data/
  runways.csv + airport-frequencies.csv) — always mark these "verify vs CFS".
- **Official CFS access**: NAV CANADA eCFS is a paid PDF (~$16.50/region,
  56-day cycle; eCFS4 Ontario, eCFS5 Quebec). The **FltPlan Go** app carries
  the full Canadian CFS for free but only inside the app (free FltPlan.com
  login required). TODO/idea: run FltPlan Go in an **Android emulator**
  (e.g. Waydroid/Genymotion) on a machine with an Android runtime so CFS pages can be harvested
  directly during planning instead of relaying via the user's phone. Not set
  up yet — propose setting it up when CFS data is needed; until then ask the
  user to read the relevant CFS entry (arrival routes, PPR/curfew, fuel)
  from their phone.
- **Fuel prices**: airport/FBO websites; ask user to confirm by phone for
  overnight parking + call-out fuel.
- Wind/heading math: compute with the standard formulas
  (WCA = asin(W/TAS × sin(wind − track)), GS = TAS·cos(WCA) − W·cos(wind − track));
  always label results "verify on whiz wheel".

## CFPS mechanics (proven, agent-browser)

- Open https://plan.navcanada.ca/wxrecall/ → "Weather and NOTAM" tab.
- The station box is a combobox: `fill` the combobox ref with one ICAO code,
  press Enter, repeat per station (they become removable chips like
  "<ICAO>✕"). Enter all stations: departure, en-route (e.g. two en-route stations),
  destination, alternate.
- Direct `click` on Search can be blocked by an overlay ("covered by
  div.container-fluid"); click via the `generic "Search"` ref or eval the
  element's onclick instead.
- Wait for "Displaying N/M results", then `get text body > file` and grep —
  the results are plain text (METAR/TAF/NOTAM blocks). Save the dump into the
  trip folder (e.g. `cfps-briefing-HHMMZ.txt`) for the record.
- Upper winds (FDs) come back as FBCN JSON rows:
  `[[alt_ft, dir_true, speed_kt, temp_C, 0], ...]` with validity windows —
  FBCN31 ≈ 14–21Z, FBCN33 ≈ 21–06Z, FBCN35 ≈ 06–18Z. Use the CWAO rows for
  low levels (3000–18000), interpolate for cruise altitude.
- "Display Result Metadata" checkbox shows the search timestamp — keep it on
  and record the briefing time in plan.md.

## Conventions & gotchas

- FDs and printed winds are °TRUE; tower/ATIS winds are °MAGNETIC.
- Variation: **west is best (+), east is least (−)** going true → magnetic.
  Use the variation on the current VNC for your area.
- Average FD winds/temps across altitudes and stations when cruising between them.
- Flight plan times are UTC. Endurance box = usable fuel ÷ planned burn.
- Runway numbers are magnetic; use them + METAR wind for X-wind components.
- Never fill GO/NO-GO, I'M SAFE, or threat-management sections yourself —
  prompt the user and record their answers.
- The nav log's wind-dependent columns (WCA, headings, GS, time, fuel) are
  only filled on the day of flight from the same briefing; pre-weather columns
  (TT, Var, Dist, TAS, freqs) can be done days ahead.
