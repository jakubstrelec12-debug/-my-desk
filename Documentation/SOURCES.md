# Dokumentace ověřená při implementaci

Ověřeno 17. 11. 2026. Primární zdroje; jejich budoucí změny mohou vyžadovat úpravy.

| Oblast | Zdroj a dopad na implementaci |
|---|---|
| Microsoft OAuth | https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-auth-code-flow — veřejný klient bez tajného klíče, code flow + PKCE |
| Registrace desktopové aplikace | https://learn.microsoft.com/en-us/entra/identity-platform/scenario-desktop-app-configuration |
| Redirect URI | https://learn.microsoft.com/en-us/entra/identity-platform/reply-url — přesná shoda callbacku a public-client platforma |
| Oprávnění Graph | https://learn.microsoft.com/en-us/graph/permissions-reference — rozdělení Mail.Read / Mail.Read.Shared / Calendars.Read / Tasks.ReadWrite |
| Pošta a efektivní filtrování | https://learn.microsoft.com/en-us/graph/api/user-list-messages?view=graph-rest-1.0 — select/top a pořadí vlastností filter/orderby |
| To Do | https://learn.microsoft.com/en-us/graph/api/resources/todo-overview?view=graph-rest-1.0 — úkoly patří do seznamu |
| Exchange on premises | https://learn.microsoft.com/en-us/graph/hybrid-rest-support — hybridní REST přístup ukončen v červenci 2023 |
| Apple web authentication | https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession |
| Automatické spuštění | https://developer.apple.com/documentation/servicemanagement/smappservice |
| ESO9 web a podpora | https://www.eso9.cz/ — oficiální odkaz podpory https://podpora.eso.cz/ |
| ESO9 Wiki | https://wiki.eso9.cz/ |
| Obecný klient | https://wiki.eso9.cz/startdoc/zaciname/zakladni-ovladani/uzivatelske-prostredi-eso9/ — referenční prohlížeče; kompatibilitu všech macOS funkcí nelze garantovat |
| Technologie a Správce | https://wiki.eso9.cz/techdoc/aplikacni-server/obecne/metodika-instalace-as-net/ — správa Windows aplikačního serveru |
| ESO9 JSON API | https://wiki.eso9.cz/api/json-api/instalace-konfigurace/ — IIS, serverová konfigurace a licence; není univerzální automatická integrace |
| Počasí | https://open-meteo.com/en/docs — current + daily, WMO weather codes, timezone |
| Geokódování | https://open-meteo.com/en/docs/geocoding-api |
| Licence počasí | https://open-meteo.com/en/terms — podmínky veřejného API / atribuce |

Výchozí RSS endpointy jsou uvedeny v `Core/Models.swift`; jejich HTTP dostupnost a XML struktura byly ověřeny přímo samostatným síťovým testem, viz `endpoint-checks.json`. Kontrola dostupnosti není licencí k redistribuci plných článků či obrázků. Aplikace poskytuje osobní čtečku titulků s odkazy na zdroj.

Pozadí `Mountains.png` bylo vytvořeno vestavěným generátorem obrázků jako projektový asset. Zadání: alpské jezero za soumraku, hory po stranách, borovice, růžovofialový západ slunce, tmavomodrý klidný střed; žádné UI, text ani panely. Schválená uživatelská reference je samostatně v Design. Logo aplikace je jednoduchá programově kreslená krychle, nikoli cizí ikona.
