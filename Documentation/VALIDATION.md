# Stav ověření při předání

Datum: 17. 11. 2026. Prostředí: Linux x86_64, bez Swift kompilátoru, bez macOS SDK a bez Xcode. Nejde o protokol o úspěšném macOS vydání.

## Provedené kontroly

| Kontrola | Výsledek | Co skutečně dokazuje |
|---|---|---|
| Analýza všech Swift souborů parserem tree-sitter-swift | Bez syntaktických ERROR nebo missing nodes | Strukturu syntaxe; **nenahrazuje Swift kompilátor ani kontrolu typů a dostupnosti API** |
| `bash -n` nad sestavovacím skriptem a spouštěcím `.command` | Prošlo | Syntaxi shellu |
| Spuštění sestavovacího skriptu v Linuxu | Správně odmítnuto s informací o macOS/Xcode | Kontrolu cílové platformy; ne nativní build |
| Info.plist | Načten Python plistlib, ověřen identifikátor a callback scheme | Platnost plist struktury |
| Lokální prostředky | Tapeta, schválená reference a vlastní ICNS jsou přítomné a čitelné | Přiložené soubory a formáty |
| Open-Meteo předpověď | HTTP 200, current + šest denních položek | Dostupnost a očekávaný tvar skutečné veřejné odpovědi |
| Open-Meteo geokódování | HTTP 200, výsledky hledání města | Dostupnost vyhledávání |
| RSS ČR / ekonomika / technologie / sport | Vše HTTP 200 a platné XML s položkami | Dostupnost výchozích endpointů; ne spuštění Swift parseru v aplikaci |

Podrobnosti síťových kontrol jsou v `endpoint-checks.json`. Kontroly použily Python a nevyžadovaly přihlášení. Konkrétní nativní integrace nebyly na základě těchto kontrol prohlášeny za otestované.

## Implementované ve zdrojovém kódu, čeká na macOS ověření

| Oblast | Implementace | Zbývající ověření |
|---|---|---|
| Vzhled | SwiftUI tři sloupce, tmavomodré panely, vlastní horská tapeta, oranžové ESO9, světlý/tmavý režim | Screenshot a porovnání s referencí, čitelnost na M2 a při zmenšení okna |
| Rychlé spuštění | NSWorkspace, systémové ikony, picker aplikací, pořadí/odstranění | Spustit každou nainstalovanou aplikaci a ověřit chybějící aplikaci |
| Persistence | Atomický JSON, ochrana původního poškozeného nastavení, lokální úkoly | Změny po restartu, oprávnění souboru, scénář poškozeného JSON |
| Microsoft | PKCE, state, ASWebAuthenticationSession, Keychain, obnova tokenu, Graph | Entra registrace a skutečný účet, MFA/cancel, token refresh, souhlas správce, restart, odpojení |
| Pošta | Doručené/nepřečtené/označené, náhledy, počet, webLink, delegované schránky | Účet se zprávami a delegací, prázdné složky, HTTP 403/429 |
| Kalendář | Dnes / 7 dní, UTC převod, odkazy, kontextové menu pro online meeting | Celodenní i vícedenní události, zimní/letní čas, Teams link |
| Úkoly | Místní CRUD, remote To Do seznam a create/complete | Zápis a následné načtení skutečného To Do; oddělení místního seznamu |
| Počasí | Skutečný zdroj, vyhledávání, lokality, předpověď, atribuce | Swift dekódování a UI, změny místa, offline režim |
| Zprávy | RSS/Atom, kategorie, upravitelné zdroje, originální odkazy | Nativní parser a otevření článku, vadný zdroj a částečný výpadek |
| Metriky | IOKit/Mach/disk, skutečná CPU historie, efektivní intervaly | Hodnoty na M2, odpojená/napájená baterie, spotřeba CPU aplikace |
| ESO9 | Evidence zákazníků, produkce/test/dokumentace, wiki/podpora, soubor vzdáleného připojení | Skutečné zákaznické URL, VPN/certifikáty, soubor .rdp a Windows App |
| Nastavení a systém | Výběr widgetů, intervaly, menu bar, close/reopen, full screen, SMAppService | Instalovaná app v /Applications, restart přihlášení, změna vzhledu a oken |
| Balení | Skript swift test/build, resource bundle, podpis, volitelná notarizace, DMG | Úspěšný macOS build, spustit balenou app, případně Developer ID a notarizace |

## Připravené automatické testy

`Tests/MyDeskTests/MyDeskTests.swift` obsahuje devět XCTest případů: zachování konfigurace, absence vymyšlených zákaznických adres, RSS/Atom a bezpečnost odkazů, limit většího RSS, Graph časové formáty, validace URL, RFC 7636 vektor PKCE, minimální scopes a dekódování počasí.

**XCTest zde nebyl spuštěn.** Proveď `swift test` na macOS. Balicí skript jej spouští povinně. GitHub Actions workflow je přiložen, nebyl nahrán do repozitáře ani spuštěn. Žádný CI výsledek se nepředpokládá.

## Před každodenním používáním

1. Úspěšně sestavit a spustit testy na Macu. Případné chyby kompilátoru nejprve opravit.
2. Otevřít balenou aplikaci a porovnat skutečný screenshot s referencí. Bez tohoto kroku není vizuální shoda potvrzená.
3. Připojit Microsoft a zkontrolovat poštu, schůzky i případný To Do zápis. Zkontrolovat zrušení přihlašování a vymazání tokenu po odpojení.
4. Doplnit zákaznické URL a ověřit reálný přístup. Správce testovat ve Windows přes schválené vzdálené připojení.
5. Vyzkoušet offline stav, chybný RSS zdroj, restart aplikace a skrytí/obnovení okna.
6. Ověřit automatické spuštění po odhlášení/přihlášení a alespoň půlhodinu sledovat zátěž v Monitoru aktivity. Výkonový cíl nebyl na M2 změřen.

## Otevřená omezení

Chybí nativní build/runtime a vizuální ověření v tomto prostředí. Kód používá veřejné API, ale typová kompatibilita konkrétního Xcode ještě není ověřená. Nejsou implementované on-premises Exchange/EWS, více současně přihlášených Microsoft identit, výběr jiného než primárního kalendáře, neomezené stránkování Graph, offline cache cloudových dat, automatické aktualizace aplikace, App Store sandbox ani přímé operace nad ESO9 JSON API. Windows Správce není přepsaný do Swiftu.

Užší okno využívá scrollování, ne přeuspořádání na mobilní layout. Klávesové ovládání a VoiceOver vycházejí z nativních SwiftUI prvků, plný audit přístupnosti neproběhl. Bez odsouhlasení licencí a distribučního podpisu není tento balíček určený k prodeji či široké firemní distribuci.
