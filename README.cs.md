# fancurve

[English](README.md) · **Čeština**

Vlastní teplotní křivka větráků pro MacBook Pro 14" M4 Pro (Mac16,8). Když CPU při zátěži přesáhne 90 °C, převezme větráky a od 100 °C je pustí na plné otáčky, protože výchozí řízení od Applu je roztáčí pozdě a CPU kvůli tomu thermal throttluje.

Není to hotová aplikace, jen shell skript. Do větráků zapisuje přes nástroj `smc`, který je přibalený ve [Stats.app](https://github.com/exelban/stats). Běží jako systémová služba (LaunchDaemon) a ovládá se příkazem `fanctl`.

## Požadavky

- Mac s Apple Silicon (odladěno na M4 Pro, Mac16,8)
- Nainstalovaný Stats.app v `/Applications`, větráky ve Stats nastavené na automatiku
- Žádný jiný nástroj, který řídí větráky (Macs Fan Control, TG Pro)

Na jiném modelu nejdřív zjisti rozsah otáček přes `/Applications/Stats.app/Contents/Resources/smc fans` a nastav `MAX_RPM` ve `fancurve.sh` na maximum. `MIN_RPM` jsou otáčky, kterými křivka začíná, a nesmí být pod hardwarovým minimem.

## Instalace

```sh
git clone https://github.com/otavlna/fancurve.git
cd fancurve
sudo ./fanctl install   # po instalaci je křivka vypnutá
fanctl test             # volitelně: sledování naživo v terminálu, Ctrl+C ukončí
fanctl on
```

## Ovládání

Na běžné zapínání a vypínání stačí `fanctl on` a `fanctl off`. Příkazy, které mění systém, si samy řeknou o heslo pro sudo.

| Příkaz | Co dělá | Heslo |
| --- | --- | --- |
| `fanctl on` | Zapne křivku hned a bude ji zapínat i po restartu | ano |
| `fanctl off` | Vypne křivku a vrátí větráky macOS, vypnutá zůstane i po restartu | ano |
| `fanctl status` | Ukáže, jestli křivka běží, a aktuální otáčky obou větráků | ne |
| `fanctl test` | Spustí křivku v terminálu s výpisem každou sekundu, Ctrl+C ukončí | ano |
| `fanctl install` | Jednorázová instalace, po ní je křivka vypnutá | ano |
| `fanctl uninstall` | Odstraní službu, skript i `fanctl` a vrátí větráky na automatiku | ano |
| `fanctl help` | Vypíše tenhle seznam | ne |

## Jak křivka funguje

Pod 90 °C řídí větráky macOS jako obvykle. Na 90 °C je převezme skript, roztočí je na 4500 rpm a s rostoucí teplotou je lineárně zrychluje, až na 100 °C jedou naplno.

| Teplota CPU | Otáčky (oba větráky) | Proměnná ve skriptu |
| --- | --- | --- |
| pod 90 °C | automatika macOS | — |
| 90 °C | 4500 rpm (`MIN_RPM`) | `T_ON` |
| 95 °C | 6163 rpm | — |
| 100 °C a výš | 7826 rpm (`MAX_RPM`) | `T_FULL` |
| pokles pod 85 °C | zpátky na automatiku | `T_OFF` |

- **Hysteréze:** když skript větráky jednou převezme, vrátí je macOS až pod 85 °C, ne hned pod 90 °C. Mezi 85 a 90 °C zůstanou na 4500 rpm. Větráky tak nepřepínají sem a tam, když se teplota pohybuje kolem prahu.
- **Senzor:** bere se nejvyšší hodnota ze senzorů CPU jader (SMC klíče `Tp*` pro výkonná jádra, `Te*` pro efektivní jádra).
- **Interval:** teplota se měří a otáčky nastavují každou sekundu (`INTERVAL`).
- **Při ukončení:** skript vždy zavolá `smc reset`, takže větráky nikdy nezůstanou zaseknuté v manuálu.

Při běžné práci i střední zátěži (pod 90 °C) skript nic nedělá a větráky jsou stejně tiché jako bez něj.

## Kde co leží

Po `fanctl install` je všechno na těchto místech. Naklonované repo už pak potřeba není.

| Soubor | Cesta |
| --- | --- |
| Ovládací příkaz | `/usr/local/bin/fanctl` |
| Skript s křivkou | `/usr/local/libexec/fancurve.sh` |
| Definice služby | `/Library/LaunchDaemons/io.github.otavlna.fancurve.plist` |
| Chybový log | `/var/log/fancurve.err` |
| SMC nástroj (součást Stats) | `/Applications/Stats.app/Contents/Resources/smc` |

Název služby v launchd je `io.github.otavlna.fancurve`. Křivka závisí na Stats.app: když Stats odinstaluješ, přestane fungovat.

## Úprava prahů

Prahy se mění přímo ve skriptu a projeví se až po restartu služby.

1. Otevři skript: `sudo nano /usr/local/libexec/fancurve.sh`
2. Na začátku uprav hodnoty `T_ON` (kdy skript převezme větráky), `T_FULL` (kdy jedou naplno) a `T_OFF` (kdy je vrátí macOS). `T_OFF` nech vždy o pár stupňů níž než `T_ON`.
3. Restartuj službu: `fanctl off` a pak `fanctl on`.
4. Zkontroluj: `fanctl status`.

Celou křivku si bez změny čehokoli vypíšeš příkazem `fancurve.sh --table`. Dry run, který jen ukazuje, co by skript nastavil, spustíš přes `fancurve.sh --dry-run 60` (číslo je délka běhu v sekundách).

Pokud chceš změnu mít i v repu, uprav `fancurve.sh` tady a spusť znovu `sudo ./fanctl install` a `fanctl on`.

## Když něco nefunguje

Když větráky dělají něco divného, tenhle příkaz je vždy vrátí macOS, i bez `fanctl`:

```sh
sudo /Applications/Stats.app/Contents/Resources/smc reset
```

| Příznak | Co udělat |
| --- | --- |
| Větráky jedou naplno i v klidu | `fanctl off`, pak `fanctl status`. Když pořád jedou v manuálu, spusť `smc reset` výše. |
| `fanctl status` hlásí OFF, i když je zapnutá | Podívej se do `/var/log/fancurve.err`. Nejčastější příčina je chybějící nebo aktualizovaný Stats.app. |
| Otáčky skáčou nebo se nastavují jinak | Zkontroluj, jestli Stats nemá větráky v manuálu. Musí být na automatice. |
| Po instalaci Macs Fan Control nebo TG Pro | Ty mají vlastní řízení větráků a s křivkou by se přetahovaly. Používej jen jedno z toho. |
| `fanctl: command not found` | Není nainstalovaný, nebo chybí `/usr/local/bin` v `PATH`. Spusť rovnou `/usr/local/bin/fanctl`. |
