# Zapret iOS

Порт [zapret-discord-youtube](https://github.com/Flowseal/zapret-discord-youtube) на iPhone и iPad. Это локальный VPN-туннель (Network Extension) с движком десинхронизации DPI. Трафик никуда не уходит: всё обрабатывается на самом устройстве.

Установка через **AltStore** или SideStore, обновления приходят из источника AltStore.

## Установка

1. Добавьте источник в AltStore:
   ```
   https://raw.githubusercontent.com/absolute2007/zapret-ios/main/altstore/source.json
   ```
   Или скачайте `Zapret.ipa` из [Releases](https://github.com/absolute2007/zapret-ios/releases) и откройте его в AltStore.
2. Запустите приложение и нажмите кнопку питания. iOS попросит разрешить добавление VPN-профиля.
3. На вкладке **«Подбор»** запустите проверку: отдельно на Wi-Fi и отдельно на мобильном интернете.

> ⚠️ Network Extension и App Groups работают **только с платным Apple Developer аккаунтом** в AltStore. На бесплатном Apple ID Apple не выдаёт право `packet-tunnel-provider`, и туннель не запустится. Ограничение со стороны Apple, обойти его нельзя.

## Как это работает

```
Приложения ─► utun (NEPacketTunnelProvider)
                 │
                 ▼
          hev-socks5-tunnel (lwIP, tun → SOCKS5)
                 │ 127.0.0.1
                 ▼
          byedpi (группы правил как в general*.bat)
                 │ обычные сокеты + IP_TTL / MSG_OOB / сегментация
                 ▼
             Интернет
```

Приложение повторяет структуру `general*.bat`: правила разбиты на группы и применяются к первой подходящей.

| zapret (`--new` группы) | iOS |
|---|---|
| `--filter-udp=443` fake QUIC ×6 | UDP/443: фейковый QUIC Initial ×6 (тот же `quic_initial_www_google_com.bin`) или блокировка QUIC |
| `--filter-udp=19294-19344,50000-50100` discord/stun | UDP-фейк `ACTIVE_DISCORD_UDP.bin` ×6 |
| `--hostlist list-google.txt` | `--hosts` + стратегия YouTube |
| `--hostlist list-general.txt` (+user) | `--hosts` + основная стратегия |
| `--hostlist-exclude`, `--ipset-exclude` | группы без десинхронизации |
| `--ipset ipset-all.txt`, Game filter | режим ipset и Game filter |

### Что на iOS невозможно и чем заменено

На iOS без джейлбрейка нет raw-сокетов и WinDivert/NFQUEUE. Всё, что требует **самодельных TCP-пакетов**, повторить нельзя:

- `--dpi-desync=fake` для TCP с fooling `badseq` / `ts` / `md5sig`
- `--dpi-desync-split-seqovl` (перекрытие последовательности)
- `syndata`, `--ip-id=zero`

Поэтому каждая стратегия (general, ALT…ALT13, EXP, FAKE TLS AUTO*, SIMPLE FAKE*) переведена **по смыслу** на приёмы, которые работают через обычные сокеты:

- **split**: разрез ClientHello на сегменты (TCP_NODELAY);
- **disorder**: сегмент уходит с TTL=1 и доставляется ретрансмиссией не по порядку;
- **OOB / disoob**: байт с флагом URG;
- **tlsrec**: разбиение TLS-записи внутри SNI;
- **mod-http**: смена регистра заголовка Host.

UDP-фейки (QUIC, голос Discord, игры) работают **так же, как в оригинале**.

## Мобильные операторы

- **Отдельные профили** для Wi-Fi и сотовой сети. При смене сети движок перезапускается со своей стратегией без разрыва туннеля, кэш стратегий по IP сбрасывается (у оператора другой DPI).
- **Автоподбор при блокировке** (`--auto=torst,ssl_err` + `--tls-timeout`). Если соединение сброшено, повисло или ServerHello не пришёл, пробуются запасные приёмы. Удачный вариант запоминается для IP.
- **Стратегия «Mobile (iOS)»** рассчитана на CGNAT и мобильные DPI.
- **IPv6 через туннель**: многие операторы раздают IPv6, без этого YouTube по v6 шёл бы мимо обхода.
- **Настраиваемый TTL UDP-фейков** на случай, если голос Discord на мобильной сети не соединяется.
- **DNS over HTTPS** защищает от подмены DNS у оператора.
- Встроенный **подбор стратегии** (аналог `test zapret.ps1`) проверяет YouTube и Discord в текущей сети.

## Обновления

- **Приложение.** При пуше тега `vX.Y.Z` GitHub Actions собирает IPA, публикует релиз и дописывает версию в `altstore/source.json`. AltStore видит её и обновляет приложение. Приложение тоже проверяет источник само и предлагает обновиться через `altstore://install?url=…`.
- **Списки.** Раз в сутки скачиваются из репозитория Flowseal (`lists/*`, `.service/ipset-service.txt`): в туннеле, в приложении или вручную. Свои домены и IP добавляются в `*-user.txt` прямо в приложении.

## Сборка

Нужен macOS с Xcode 15+ и [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
git clone --recursive https://github.com/absolute2007/zapret-ios
cd zapret-ios
./Native/build.sh          # byedpi + hev-socks5-tunnel → Native/build/lib
xcodegen generate
open Zapret.xcodeproj
```

Релиз:

```bash
git tag -a v1.0.1 -m "Что нового"
git push origin v1.0.1
```

## Лицензии

- Код приложения: MIT.
- Списки доменов и `.bin`-фейки: [zapret-discord-youtube](https://github.com/Flowseal/zapret-discord-youtube) (MIT, © bol-van, Flowseal).
- Движок десинхронизации: [byedpi](https://github.com/hufrea/byedpi) (MIT, © hufrea).
- tun2socks: [hev-socks5-tunnel](https://github.com/heiher/hev-socks5-tunnel) (MIT, © hev).
