# Sunset + Blue Hour — campo dati Garmin

Campo dati Connect IQ per **fēnix 7 Pro** (e famiglia fēnix 7) con interfaccia
in bianco e nero, organizzata su quattro righe:

1. **ora attuale** (la più grande, con secondi in formato 24h oppure AM/PM
   minuscolo in formato 12h);
2. **alba**, con icona (mezzo sole sopra l'orizzonte);
3. **tramonto**, con icona (mezzo sole sotto l'orizzonte);
4. **blue hour**, cioè la finestra in cui il sole è tra 4° e 6° sotto
   l'orizzonte: viene mostrata la prossima finestra (mattina o sera) nel formato
   `BLUE 16:51 - 17:11` (oppure `BLUE 4:51 - 5:11 PM` in formato 12h). Quando ci
   sei dentro, la riga diventa `BLUE HOUR` in negativo.

Il layout si adatta automaticamente allo spazio che il watch assegna al campo,
quindi funziona anche quando il campo non è a schermo intero.

## Come sono calcolati i dati

| Dato | Fonte |
|------|-------|
| Ora | `System.getClockTime()` (ora locale del dispositivo) |
| Alba / tramonto | `Toybox.Weather.getSunrise()/getSunset()` (stessi valori del watch); se non disponibili, calcolo astronomico NOAA locale |
| Blue hour | Calcolo astronomico locale (NOAA solar position): elevazione solare −4° / −6° |

Il calcolo viene rifatto solo quando cambiano giorno, fuso orario o posizione
(ed eventualmente ogni 5 minuti), quindi il costo per secondo è trascurabile.

### Funziona offline?

Sì: non serve né telefono né connessione internet. Tutto viene calcolato sul
watch a partire da ora locale, data e posizione GPS.

- **Ora attuale**: sempre disponibile.
- **Alba / tramonto / blue hour**: richiedono solo la posizione. Il campo salva
  l'ultima posizione GPS e la riusa per un massimo di 7 giorni, così i valori
  restano corretti anche durante attività indoor o senza fix.
- Se non c'è né fix né una posizione salvata, alba/tramonto/blue hour mostrano
  `--:--` (l'ora attuale continua a funzionare).

## Struttura del progetto

```
manifest.xml                 metadati app (UUID, prodotti, permesso Positioning)
monkey.jungle                sorgenti + risorse
source/SunsetApp.mc          entry point (Application.AppBase)
source/SunsetField.mc        DataField: layout e disegno
source/SunTimes.mc           modello astronomico (alba, tramonto, blue hour)
resources/                   stringhe e icona launcher
.vscode/settings.json        configurazione estensione Monkey C
build.sh                     build/export da terminale
```

## Requisiti

- [Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) installato;
- Java 11+;
- una **developer key** (`developer_key.der`): serve per firmare la build e per
  esportare il pacchetto `.iq`.

Se la chiave non esiste, generala una volta sola e conservala:

```bash
openssl genrsa -out developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key.der -nocrypt
```

> Le chiavi sono personali: non finiscono su GitHub (sono in `.gitignore`).
> La stessa chiave va usata sempre, anche per gli aggiornamenti pubblicati
> sullo store.

## Build da terminale

```bash
./build.sh                 # -> bin/SunsetField.prg (fenix7pro)
DEVICE=fenix7xpro ./build.sh
./build.sh --iq            # -> bin/SunsetField.iq (pacchetto firmato, tutti i prodotti)
```

Per provarlo nel simulatore:

```bash
open "$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.3.0-2026-10-20-95888f262/bin/ConnectIQ.app"
"$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.3.0-2026-10-20-95888f262/bin/monkeydo" bin/SunsetField.prg fenix7pro
```

Nel simulatore, senza GPS, alba/tramonto/blue hour mostrano `--:--`.

## VS Code

- estensione **Monkey C** (`garmin.monkey-c`, v1.1.3);
- `.vscode/settings.json` con `monkeyC.developerKeyPath` = `developer_key.der`
  e `monkeyC.jungleFiles` = `monkey.jungle`;
- SDK corrente impostato in `~/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg`.

Apri la cartella in VS Code e usa la Command Palette (`⌘⇧P`):

1. **Monkey C: Verify Installation** — verifica SDK, Java e developer key;
2. **Monkey C: Build for Device** — scegli `fenix7pro`: crea `bin/SunsetField.prg`;
3. **Monkey C: Export Project** — crea il pacchetto firmato `bin/SunsetField.iq`.

Se sposti il progetto o cambi computer, rigenera la chiave con
**Monkey C: Generate a Developer Key** (aggiorna da solo il percorso nelle
impostazioni) oppure correggi `monkeyC.developerKeyPath`.

## Installazione sul watch

1. Collega il fēnix 7 Pro via USB.
2. Copia `bin/SunsetField.prg` nella cartella `GARMIN/APPS` del dispositivo.
3. Sul watch: *Attività → Impostazioni attività → Campi dati* e seleziona
   **Sun + Blue Hour**.


