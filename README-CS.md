## Firemní Exchange (od verze 1.1)

V Nastavení → Exchange zadejte EWS adresu serveru, e-mail, přihlašovací jméno přesně jako ve webmailu a heslo. Zvolte Basic přes HTTPS, případně NTLM, a klikněte na Ověřit a připojit. Není potřeba registrace Microsoft Entra ani Application ID. Heslo se uloží do Klíčenky macOS až po úspěšném ověření schránky; není součástí nastavení, instalátoru ani repozitáře.

Dashboard načítá nejvýše 30 zpráv z Doručené pošty, včetně nepřečtených zpráv a vlaječek, počet nepřečtených zpráv a nejvýše 60 událostí na 7 dní. Kalendář používá CalendarView i pro výskyty opakovaných schůzek. V této verzi se vlaječky nehledají v dalších složkách a archivních schránkách. Kliknutí otevře položku ve firemním webmailu. Exchange nepodporuje Microsoft To Do; úkoly v tomto režimu zůstávají místní. Poštu ani kalendář tato integrace nemění.

Odpojení smaže uložené heslo. Přepínačem lze zachovat připojení a přepnout mezi Exchange a původním Microsoft 365. Při změně hesla nebo nastavení se znovu připojte. Připojení vyžaduje platný HTTPS certifikát a odmítá přesměrování. Po odmítnutém přihlášení se automatické pokusy zastaví, aby se neopakovalo nesprávné heslo.

Ověření: automatické testy ověřují SOAP, české znaky, migraci nastavení, filtry, chyby serveru, odmítání přesměrování a zastavení opakovaných požadavků po HTTP 401. Přihlášení ke konkrétní firemní schránce vyžaduje místní zadání hesla uživatelem a není součástí testů na GitHubu.

# MY DESK pro macOS

Nativní osobní dashboard ve SwiftUI pro macOS 13 a novější, včetně Apple Silicon. Zdrojový projekt z 17. listopadu 2026.

**Stav předání:** implementovaný zdrojový projekt. V tomto prostředí je pouze Linux bez Xcode, Swift kompilátoru a macOS SDK. Aplikace zde nebyla sestavena, spuštěna ani vizuálně ověřena v macOS. Součástí tohoto ZIP není ověřená spustitelná `.app` ani `.dmg`. Nelze zatím označit za hotové produkční vydání. Testy pro macOS jsou přiložené, jejich spuštění je součástí sestavovacího skriptu.

## Nejrychlejší cesta na tvém MacBooku

1. Nainstaluj Xcode 15 nebo novější z App Storu. Poprvé jej otevři a dokonči instalaci nástrojů.
2. Rozbal celý ZIP do běžné místní složky, například `Dokumenty/MY-DESK`.
3. Můžeš dvojklikem spustit `Sestavit-MY-DESK.command`. Alternativně v Terminálu přejdi do složky projektu. Můžeš napsat `cd ` a přetáhnout složku MY-DESK z Finderu do Terminálu, potom Enter.
4. Spusť:

```bash
./scripts/build-app.sh
```

Skript nejprve provede `swift test`, poté sestaví aplikaci pro architekturu Macu, vloží zdroje, podepíše ji lokálním podpisem a vytvoří instalační obraz. Na MacBooku Air M2 vznikne arm64 sestavení.

5. Pokud testy a sestavení projdou, otevři `dist/MyDesk.dmg` a přetáhni **MY DESK.app** do **Applications**. Spusť ji z Aplikací.
6. V případě blokování lokálně sestavené aplikace použij standardní postup macOS v Nastavení systému → Soukromí a zabezpečení → Přesto otevřít, pouze pokud znáš původ projektu. Nevypínej Gatekeeper globálně.

Pokud není nastavený aktivní Xcode, vyber jej v Xcode → Settings → Locations → Command Line Tools. Skript při jakémkoli selhání skončí; nepokračuje k balení neúspěšného sestavení. První chybový výstup je potřeba vyřešit před instalací.

## Otevření v Xcode

Otevři `Package.swift` v Xcode. Vyber schéma **MyDesk**, cíl **My Mac**, spusť Product → Test a Product → Build. Nejsou potřeba externí Swift balíčky. Projekt používá Swift 5 jazykový režim a systémové frameworky.

Pro kompletní ověření přihlašovacího callbacku a automatického spuštění používej zabalenou aplikaci ze skriptu. Samotné `swift run` ani dočasný executable spuštěný z Xcode nemá všechny vlastnosti nainstalovaného app bundlu.

## První spuštění

- Rozložení odpovídá schválené předloze uložené v `Design/Approved-reference.jpeg`: pozdrav a aplikace vlevo, ESO9 v oranžové, plán a pošta uprostřed, informační widgety vpravo.
- Výchozí vzhled je tmavý. Horské pozadí je samostatně vytvořený lokální obrázek stejného vizuálního směru, nikoli výřez UI. Panelové krytí lze nastavit na 75–98 %.
- Žádné demonstrační e-maily, schůzky, zprávy, úkoly ani systémová procenta. Čas a data jsou skutečná; chybějící integrace mají výzvu k nastavení. Projekty a zákazníci jsou pouze připravené názvy s prázdnými cíli.
- Otevři Nastavení ozubeným kolem nebo `⌘,`. Změny se ukládají průběžně.
- Horní navigace mění pracovní obsah. Vyhledávání prohledává pouze aktuálně načtené e-maily, schůzky, zprávy, názvy aplikací a projekty; není to serverové hledání v celé poště.
- Zavření okna aplikaci neukončí. Otevřeš ji ikonou krychle v menu baru; ukončení je v jejím menu nebo přes `⌘Q`.

## Připojení Microsoft účtu

Potřebuješ firemní účet s poštou v Exchange Online. Lokální Exchange, včetně starého hybridního REST přístupu, není implementovaný: Microsoft tuto cestu v červenci 2023 ukončil. Outlook můžeš spouštět i bez Graph integrace.

1. V Microsoft Entra admin center otevři **App registrations → New registration**. Pro vlastní firemní instalaci zvol účty jen v dané organizaci.
2. V **Authentication → Add a platform → Mobile and desktop applications** přidej vlastní redirect URI přesně:

```text
mydesk://oauth
```

Tato implementace používá přímo OAuth authorization code + PKCE v `ASWebAuthenticationSession`, nikoli MSAL broker. Použij public/native registraci; ne Web/SPA platformu a nezakládej client secret. V případě správy přes manifest musí být URI v `publicClient.redirectUris`. Pokud tvoje firemní konzole custom URI nenabízí, požádej správce o úpravu public-client registrace; nevkládej URI jako SPA.

3. V **API permissions → Microsoft Graph → Delegated permissions** nastav pouze používané funkce:

| Funkce | Oprávnění |
|---|---|
| Profil přihlášeného uživatele | `User.Read` |
| Obnovení přihlášení | `offline_access` |
| Vlastní pošta s náhledem a vlaječkami | `Mail.Read` |
| Vlastní a delegované schránky, pokud zapneš sdílení | `Mail.Read.Shared` místo `Mail.Read` |
| Primární kalendář | `Calendars.Read` |
| Microsoft To Do včetně vytvoření a dokončení | `Tasks.ReadWrite` |

`Mail.ReadBasic` nestačí pro náhled zprávy. Nepřidávej aplikační oprávnění `*.All`, právo posílat e-maily ani zápis do pošty/kalendáře. To Do je výchozím nastavením vypnuté, takže se zápisové oprávnění nežádá bez zapnutí této funkce.

4. Správce může muset udělit souhlas organizace. Conditional Access může tento klient odmítnout, například při požadavku na broker či spravované zařízení. MY DESK tyto zásady neobchází.
5. Zkopíruj **Application (client) ID** a **Directory (tenant) ID** do Nastavení → Microsoft. ID nejsou tajné údaje; nikam nevkládej heslo ani client secret.
6. Zapni požadované moduly a klikni **Připojit / změnit účet**. Přihlášení proběhne na stránce Microsoftu v systémové autentizační relaci. Tokeny se ukládají do macOS Keychain, nikoli do JSON nastavení.
7. Po změně ID, tenantu nebo oprávnění účet odpoj a připoj znovu.

### Sdílené schránky a úkoly

Zapni sdílené schránky, odpoj/připoj účet a přidej jejich e-mailové adresy. Uživatel už musí mít delegovaný přístup. Přepínač schránky je v panelu e-mailů. Nejde o seznam všech firemních schránek ani automatické zjištění delegací. Podporovaný je jeden přihlášený účet a více jemu dostupných schránek, nikoli několik současně přihlášených identit.

V nastavení To Do vyber seznam. Výchozí je standardní seznam účtu, případně první vrácený seznam. Vytváření nového úkolu a dokončení se zapisuje do vybraného seznamu. Nový seznam aplikace sama nezakládá. Při vypnutém To Do se používají oddělené místní úkoly.

### Rozsah načítání

Vše/Nepřečtené: 30 nejnovějších zpráv v Doručené poště. Vlaječky: 30 nejnovějších označených zpráv z celé schránky. Číslo nepřečtených je počet z Doručené pošty, nikoli jen z načtené stránky. Otevření zprávy používá originální Graph `webLink` a systémový prohlížeč. Aplikace nemění přečtenost ani vlaječky. Kalendář: primární kalendář od začátku dne do začátku dne za týden, nejvýše 60 událostí. Výchozí panel ukazuje dnešek; tlačítko 7 dní přepíná na nadcházející události. To Do: nejvýše 100 seznamů a 100 nedokončených úkolů ve vybraném seznamu. Další stránky se v této verzi nenačítají.

## ESO9 – nastavení pro tvoji práci

V Nastavení → ESO9 jsou připraveni **Srnín, PRECITOOL, BATIST a REJFOOD**. U každého doplň skutečnou produkční URL, testovací URL, dokumentaci a poznámku. Žádná adresa zákazníka nebyla odvozena ani vymyšlena. Všechna prostředí zůstávají upravitelná; lze přidávat další.

Odkazy se otevřou ve výchozím prohlížeči. Použij adresu obecného klienta, kterou pro konkrétní instalaci potvrdí správce. Dostupnost z Macu závisí na verzi klienta, prohlížeči, certifikátech, VPN a firemním ověřování. Dokumentace ESO9 uvádí referenční prohlížeče především ve Windows, Androidu a iOS; nelze z toho slíbit bezchybnou kompatibilitu všech funkcí se Safari v macOS. Legacy ActiveX/IE integrace nelze přenést na Mac.

**Správce ESO9:** zůstává ve Windows. Doporučený postup je firemně schválený Windows server/stanice a klient Windows App na Macu přes VPN nebo RD Gateway. Připrav v klientovi připojení, ověř funkčnost a vyber jeho `.rdp` soubor v nastavení MY DESK. Tlačítko otevře soubor v přiřazeném klientovi; samotné připojení, certifikáty a MFA zajišťuje tento klient. Dostupnost RDP hostitele či licencí musí zajistit firma. Nepřipojuj databáze k veřejnému internetu.

Wiki je přednastavena na `https://wiki.eso9.cz`, podpora na oficiální `https://podpora.eso.cz/`. Podporu lze přepsat.

ESO9 nabízí samostatné JSON API provozované v IIS. Jeho zprovoznění vyžaduje serverovou konfiguraci, licenci a oprávnění daného zákazníka. Tato verze API pro ERP data nepoužívá; obsahuje pracovní centrum, nikoli nativní administraci serveru ani přístup přímo do SQL.

## Další funkce

- **Aplikace:** přidávání přes systémový výběr `.app`, odstranění, přejmenování a změna pořadí šipkami. Ikony se čtou ze skutečných aplikací přes NSWorkspace. Nenainstalovaná aplikace má neutrální ikonu a srozumitelnou chybu.
- **Projekty:** Nuviro, ZakázkaAI, Fluento a ESO9 projekty. Doplň URL, soubor nebo složku. Otevření obstará příslušná aplikace/Finder; žádné shellové příkazy.
- **Počasí:** výchozí Jindřichův Hradec, aktuální stav a dalších pět dní. Vyhledání města přes geokódování nebo ruční souřadnice. Open-Meteo je modelová předpověď, nikoli zaručené měření z místní stanice. Atribuce je v panelu. Veřejné API je určeno pro osobní nekomerční použití; placená distribuce vyžaduje komerční podmínky a úpravu endpointu.
- **RSS:** ČR a ekonomika iDNES.cz, technologie Root.cz, sport iDNES.cz. Zdroje jsou upravitelné, čtou se jen titulky/odkazy/data. Záměrně se nestahují celé články ani cizí náhledové fotografie. Kategorie a původní články se otevírají přímo.
- **Metriky:** baterie přes IOKit, RAM a CPU přes Mach, obsazenost domovského svazku přes systémové kapacity. Graf CPU obsahuje pouze skutečné vzorky. První CPU vzorek je prázdný, protože je potřeba rozdíl dvou měření. RAM = aktivní + zapojená + komprimovaná; disk zohledňuje místo uvolnitelné pro důležité operace. Hodnoty nemusí přesně kopírovat Monitor aktivity.
- **Aktualizace:** výchozí Microsoft 5 min, počasí/RSS 30 min, systém 10 s. Systémový plánovač se probouzí po 5 s. Síť se nenačítá pro vypnuté widgety a při skrytém okně se automatické aktualizace zastaví.

## Soukromí a umístění dat

Nastavení, místní úkoly, názvy zákazníků, URL a poznámky jsou v:

```text
~/Library/Application Support/MY DESK/settings-v1.json
```

Zápis je atomický, soubor má práva pouze pro vlastníka. **Není šifrovaný.** Hesla a tajné údaje nepatří do poznámek ani URL. OAuth tokeny jsou v položce Keychain se službou `cz.mydesk.microsoft`, účet `primary`, přístupné při odemčené Klíčence a nepřenosné na jiné zařízení. Lokálně podepsaná vývojová aplikace může při změně podpisu vyžádat nový souhlas Klíčenky; stabilní distribuční podpis je vhodný pro každodenní používání.

Pošta, profil, schůzky, RSS a počasí jsou pouze v paměti procesu. Po odpojení účtu se Microsoft data smažou z paměti a tokeny z Klíčenky. Odpojení nenahrazuje odvolání souhlasu aplikace v účtu Microsoft. Není přítomná analytika ani vlastní server. Síťový provoz směřuje přímo k Microsoftu, meteorologickému zdroji a zvoleným RSS. Prohlížeč a vzdálený klient obsluhují své vlastní přihlašování.

Poškozené nastavení aplikace nepřepíše. Ukonči ji, zkopíruj soubor pro obnovu a případně jej přejmenuj; při dalším spuštění vznikne nové nastavení. Token můžeš odstranit odpojením nebo v aplikaci Klíčenka.

## Podpis, distribuce a instalační balíček

Lokální build používá ad hoc podpis a je určen pro vlastní Mac. Pro distribuci ostatním potřebuješ Apple Developer ID a notarizaci. Skript podporuje volitelné proměnné:

```bash
MYDESK_SIGN_IDENTITY='Developer ID Application: TVOJE IDENTITA (TEAMID)' \
MYDESK_NOTARY_PROFILE='MYDESK-NOTARY' ./scripts/build-app.sh
```

Notarizační profil nejprve bezpečně vytvoř pomocí `xcrun notarytool store-credentials` podle dokumentace Apple. Přístupové údaje nepatří do repozitáře. Není přiložen distribuční certifikát, instalační PKG, automatický updater ani App Store sandbox. Aplikace používá běžný macOS proces a uživatelem vybrané soubory. Nevyžaduje Full Disk Access, kontakty ani záznam obrazovky.

## Ověření a omezení

Přesný stav je v `Documentation/VALIDATION.md`, architektura v `Documentation/ARCHITECTURE.md`, zdroje v `Documentation/SOURCES.md` a kontrola endpointů v `Documentation/endpoint-checks.json`.

Zásadní zbývající krok je první sestavení a funkční/obrazové ověření v macOS. Nelze tvrdit, že prošel build, automatické testy, přihlášení k tvému účtu, spuštění po přihlášení či přístup k zákazníkům, dokud tyto kroky skutečně neproběhnou. Projekt je připraven k jejich provedení, nikoli označen jako bezchybně otestovaná aplikace.
