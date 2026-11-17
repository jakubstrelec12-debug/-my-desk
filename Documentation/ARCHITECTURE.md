# Architektura

## Vrstvy

| Vrstva | Soubory | Odpovědnost |
|---|---|---|
| Spuštění | MyDeskApp.swift | SwiftUI App, jediné hlavní okno, menu bar, NSWindow delegate |
| Doménová data | Core/Models.swift | Codable konfigurace, Graph DTO, počasí, zprávy a metriky |
| Persistence a spouštění | Core/Preferences.swift | Atomický lokální JSON, výběry NSOpenPanel, bezpečné rozlišení webu a souboru, NSWorkspace |
| Stav dashboardu | Core/DeskModel.swift | Aktualizace, omezení souběhu, výběr schránky/filtrů, chyby, čas poslední úspěšné aktualizace |
| Microsoft autentizace | Services/MicrosoftAuth.swift | Authorization code + PKCE S256, náhodný state, ASWebAuthenticationSession, Keychain, obnova tokenu |
| Graph | Services/GraphService.swift | Profil, pošta, počty, calendarView a Microsoft To Do, delegované přístupy, Retry-After |
| Síť | Services/Network.swift | Ephemeral URLSession, timeouty, streamovaný limit 6 MB, zákaz přesměrování autorizovaných požadavků |
| Veřejné služby | Services/WeatherNews.swift | Open-Meteo a geokódování, RSS/Atom XML bez externích entit |
| Systém | Services/SystemMetrics.swift | IOKit power sources, Mach memory/CPU, kapacita svazku |
| UI | Views/* | Samostatné panely, dashboard a konfigurační obrazovka |

Všechny publikované změny UI probíhají na hlavním actoru; URLSession používá asynchronní síťové požadavky. Metriky jsou krátké systémové dotazy bez externích procesů. RSS parser běží v úlohách skupiny, nikoli jako neustálý polling. Refresh token má jedinou sdílenou probíhající obnovu. Generace stavu chrání proti zobrazení odpovědi starého účtu po odpojení nebo změně konfigurace.

Pořadí a poměry panelů vycházejí z přiložené reference. UI má minimální šířku obsahu a scrollování; neřeší mobilní zobrazení, protože cíl je Mac. Při menší ploše je část obsahu dostupná posunem. Síťové chyby nejsou nahrazovány vzorovými položkami. Poslední úspěšně načtená veřejná data mohou zůstat zobrazena s označením starších dat.

## Záměrné hranice

- Žádný server, telemetrie, soubor hesel, embedded browser se zachytáváním hesel ani neoficiální Outlook scraping.
- Žádné přímé SQL či administrátorské ERP operace. ESO9 se otevírá v prohlížeči / vzdáleném klientovi.
- Jedna Microsoft identita; přepínání delegovaných schránek uvnitř této identity.
- Žádný automatický import účtů uložených v Outlooku nebo systémových Internetových účtech.
- Vlastní implementace OAuth protokolu místo externího MSAL balíčku. Ověřuje callback scheme/host/state, PKCE váže kód na relaci. Nepoužívá ID token k ověření identity; profil čte autorizovaným Graph požadavkem. Microsoft obecně doporučuje podporovanou autentizační knihovnu; před širší firemní distribucí je vhodné zvážit přechod na MSAL zejména kvůli broker/Conditional Access scénářům.
- SPM projekt se otevírá v Xcode přes Package.swift; app bundle vyrábí balicí skript, nikoli ručně udržovaný pbxproj.
