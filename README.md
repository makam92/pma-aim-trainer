# PMA Aim Trainer

Aim trainer för CS2, byggd i Godot 4.7. Siktet vrids exakt som i CS2 (0,022° × sensitivity per
musrörelse, raw input, 90° FOV i 4:3) och all rörelse använder CS2:s acceleration, friktion och
maxfart.

## Lägen

Alla lägen körs i 60 sekunder.

- **Gridshot**: tre huvuden åt gången i ett rutnät, varje träff tar fram ett nytt.
- **Flicks**: håll siktet i ringen, flicka till huvudet som dyker upp. Så många träffar som möjligt;
  visar också om du flickar för långt eller för kort.
- **Micro Adjustments**: ett huvud dyker upp 0,5–5° från siktet, var du än siktar. Korrigera och
  skjut; visar också hur rakt du justerar (överkorrigeringar sänker rakheten).
- **Tracking**: följ en gubbe som strafear med riktig CS2-rörelse (ADAD, counter-strafes, upp till
  250 u/s). Mäter tid på huvud och kropp, även direkt efter riktningsbyten.
- **Target Confirmation**: så många huvuden du hinner, en miss och du börjar om från noll.
- **Tracking Confirmation**: döda strafeande CS2-gubbar en i taget, på nya platser och avstånd.
  Bara en kill tar fram nästa gubbe; missar och kroppsträffar (när du siktar på huvudet) sänker
  träffsäkerheten.
- **Aim Punch**: dueller där fienden skjuter först. Varje träff rycker siktet uppåt (aim punch) och
  kulorna går ännu högre tills rycket släppt; hitta tillbaka till huvudet och döda honom innan han
  dödar dig (3 träffar utan kevlar, 4 med). Kevlar ger mycket mindre ryck. Visar hur ofta skotten
  direkt efter en träff dödar jämfört med resten.
- **Strafe Aim**: strafea med A/D och CS2-rörelse och träffa målen medan du rör dig. Skott räknas
  bara när du har minst halva maxfarten, så stillastående skott och vändningarna i ADAD räknas inte.
- **Counter-strafe**: strafea, kontra och skjut. Varje skott får en tidslinje som visar när du blev
  träffsäker (under 34 % av vapnets maxfart) och om skottet kom för tidigt eller sent.

Målen är CS2-huvuden i verklig storlek (eller klot), på avstånd i CS2-units: Blandat 250–1100 u,
Nära, Medel eller Långt. Längre bort ser de mindre ut, precis som i spelet.

Gubbarna i Tracking och Tracking Confirmation croucher ibland, som i CS2: oftast när de stannar och
ibland mitt i ADAD. Crouchade går de i 34 % av maxfarten (85 u/s med kniv) och huvudet sjunker
17 units. Det går att stänga av under Inställningar → Gubbar.

**Dagens pass** kör som standard alla nio lägena tre gånger var (cirka 32 minuter). Med **Ändra**
väljer du själv hur många rundor av varje övning (0–5) och i vilken ordning. Trycker du Esc under
passet visas hela passet bredvid pausmenyn, och du kan hoppa till vilken runda som helst. Efteråt
visas en sammanfattning mot förra passet och hur många dagar i rad du tränat. **Statistik** har en
graf per läge med alla rundor och trenden mot veckan innan, och en kalender över dina pass.

Träffar räknas med CS2:s egna hitboxar (kapslar per ben med CS2:s hit groups: bara huvudet ger
huvudträff, halsen räknas som kropp), och kulan träffar den hitbox den når först, som i CS2.

## Vapen

Under Inställningar → Vapen, allt valbart:

- **AK-47 i handen** som CS2:s viewmodel: CS2:s egna armar och klipp (dra fram, hålla, skjuta), CS2:s
  viewmodel-FOV (54–68) och standardposition. Med AK:n i handen skjuter du högst 600 skott/minut.
- **AK-ljud** från CS2 (fyra inspelningar, som i spelet) i stället för det enkla klicket.
- **Kulhål och spårljus**: missar lämnar kulhål med en dammpuff, och vart tredje skott har spårljus.
  Hålen syns lika stora på alla avstånd, så du ser hur långt du missade.
- **Rekyl och spray** (av som standard): AK:ns rekyl från CS2:s egna värden (rekylseed 223, vinkel
  0 ± 70, styrka 30) genom motorns rekylsystem, plus AK:ns spridning som växer per skott och
  återhämtar sig. Håll inne för att spraya. Rundor med rekyl får eget personbästa.

## CS2-filer (bara för eget bruk)

Spelet innehåller inget från CS2. Under **Inställningar → CS2-filer → Importera från CS2** läser det
in spelarmodeller (SAS, Phoenix) med CS2:s hitboxar, vapen (AK-47, M4A1-S, knivar), CS2:s rörelse-
och crouch-animationer, förstapersonsarmar med AK:ns klipp och AK:ns skottljud ur din egen
CS2-installation (den hittas via Steam). Det tar under en minut. Filerna hamnar i
`%APPDATA%\CS2AimTrainer` (`models`, `viewmodel`, `sounds`), aldrig i projektet eller installern.
Importera igen efter CS2-uppdateringar. Utan CS2-filer används de inbyggda figurerna.

Importen använder Source 2 Viewers kommandoradsverktyg (öppen källkod, MIT), som följer med
installern. Från projektet tas det från `%LOCALAPPDATA%\Programs\Source2Viewer`. Utan fönster:

```
"%LOCALAPPDATA%\Programs\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path . -- --import-cs2
```

## Upplösning

Under Inställningar finns upplösning (t.ex. 1280x1024) och skalning (utsträckt eller svarta kanter).
Spelet och AK:n renderas då i den upplösningen med CS2:s FOV för bildformatet och skalas upp mjukt
till skärmen, som när grafikkortet skalar CS2. Hårkors, HUD och menyer ritas i skärmens egen
upplösning: hårkorset sträcks ut som i CS2 men läggs på hela pixlar, lika på båda sidor.

## Installer

`tools\build_installer.ps1` exporterar spelet till en fristående .exe och bygger
`build\installer\PMA-Aim-Trainer-Setup.exe` med Inno Setup. Den installerar för din användare (inga
adminrättigheter), lägger till Start-menyn och avinstallation, och tar med Source 2 Viewer för
importen. Kräver Godots exportmallar för 4.7.2 och Inno Setup 7 i
`%LOCALAPPDATA%\Programs\Inno Setup 7`.

## Starta från projektet

Dubbelklicka på `Starta.cmd`. Esc pausar, R startar om.

Öppna projektet i Godot-editorn:

```
"%LOCALAPPDATA%\Programs\Godot\Godot_v4.7.2-stable_win64.exe" --editor --path .
```

## Tester

Utan fönster (`test_movement`, `test_targets`, `test_recoil`, och ett självtest av skjutandet):

```
"%LOCALAPPDATA%\Programs\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/test_movement.gd
"%LOCALAPPDATA%\Programs\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path . -- --selftest
```

Kontrollerar rörelsemodellen (counter-strafe ≈ 71 ms till träffsäker, släppa ≈ 199 ms), att
tracking-boten når maxfart och håller sig inom banan, AK:ns spraymönster och skjutandet.

`-- --tour=<mapp>` kör en automatisk rundtur som sparar skärmdumpar av alla vyer (öppnar ett
fönster), och `-- --tour=<mapp> --closeup` närbilder på gubbarna och deras hitboxar.

## Struktur

- `scripts/movement_sim.gd`: CS2-rörelse i 64 tick med sub-tick-input och crouch
- `scripts/bot_brain.gd`: hur gubbarna väljer sina strafes och crouchar
- `scripts/weapon_ak.gd`: AK:ns rekyl, spray och spridning
- `scripts/agents.gd`: laddar CS2-modellerna, hitboxarna och förstapersons-AK:n
- `scripts/cs2_import.gd`: importen från CS2
- `scripts/modes/`: övningarna
- `scripts/ui/`: menyer, HUD och grafer
- `tools/`: installer och verktyg för att granska modeller och animationer
- Inställningar, statistik och CS2-filer sparas i `%APPDATA%\CS2AimTrainer`
