# BetterOpel server

BetterOpel does not talk to Opel directly. It talks to
[psa_car_controller](https://github.com/flobz/psa_car_controller), a small
server that signs in to MyOpel on your behalf. This folder puts that server on
an always-on Mac and makes it reachable from your phone, encrypted, wherever
you are.

## Set it up (about ten minutes)

Do these on the Mac that stays on.

1. **Copy this `Server` folder to it** (AirDrop works) and run:

   ```bash
   ./install-mac.sh
   ```

   It installs the server into your user account, starts it, and keeps it
   running. No sudo, no system settings changed.

2. **Install Tailscale and sign in**, on that Mac and on your iPhone, with the
   same account. It is free for personal use: <https://tailscale.com/download>.
   Then run `./install-mac.sh` once more. It prints an address like
   `https://mac-mini.your-tailnet.ts.net`.

   If Tailscale says HTTPS is not enabled for your tailnet, it prints a link;
   open it and switch HTTPS on, then run the script again.

3. **Sign in to MyOpel.** Open the address from step 2 (or
   `http://localhost:5055` on that Mac). Choose Opel, enter your MyOpel e-mail,
   password and country code `DE`, then the SMS code and your four-digit MyOpel
   PIN.

4. **Connect the app.** In BetterOpel: Settings, Connection, enter the address
   from step 2, tap Connect. The VIN is found automatically.

## How it is put together

| Piece | What it does |
| --- | --- |
| psa_car_controller | Listens on `127.0.0.1:5055` only, so nothing on your network can reach it directly. It has no login of its own, which is why it is never exposed. |
| launchd agent `com.example.betteropel.server` | Starts it at login and restarts it if it stops. The Mac has to be logged in. |
| `caffeinate` | Keeps the Mac from idle-sleeping while the server runs. |
| Tailscale Serve | Publishes it over HTTPS, with a real certificate, to devices signed in to your Tailscale account and to nobody else. Traffic is WireGuard-encrypted end to end, at home and away. |

Files live in `~/Library/Application Support/BetterOpelServer`, the log in
`~/Library/Logs/BetterOpelServer/server.log`.

## Things to know

- **Port 5000 is taken on a Mac** by AirPlay Receiver, hence 5055.
- **Your car's model.** The public installer has no personal VIN prefix. If
  the server does not recognize your Grandland Electric, supply your own
  ten-character model prefix locally as `PSACC_VIN_PREFIX` when running it.
  The optional entry assumes a 73 kWh battery; adjust `battery_power` for your
  own vehicle. Do not commit your identifier or server configuration.
- **Trips and charging sessions** are recorded by the server from the moment it
  is signed in. They fill in over the first days.
- **Departure times** cannot be read or set through this server; the app says so
  on the Climate screen when connected.
- **Too many SMS codes** lock the MyOpel remote for a day. If setup fails, wait
  rather than retrying repeatedly.

## Remove it

```bash
./uninstall-mac.sh          # stop the service, keep the data
./uninstall-mac.sh --purge  # remove everything
```

## Developing without a car

`fake_psacc.py` answers the same endpoints with the same JSON as the real
server and keeps a little state:

```bash
python3 fake_psacc.py
```

The fixture binds to loopback only. In the iOS simulator, use
`-server http://127.0.0.1:5055 -vin DEMO0000000000000`.

## Timed starts

`warmup_scheduler.py` is a second, small service that sits next to
psa_car_controller. It keeps the "Ready by" times set in the app and starts the
car's climate ten minutes ahead of each one by calling the car server, the same
way the app's own button does. The programmes stored in the car are not used.

    ./install-warmups.sh

That runs it as its own launchd agent (`com.example.betteropel.warmups`, port
5056, this Mac only) and, when Tailscale Serve already publishes the car
server, adds it under `/scheduler` on the same address. The car server is not
touched or restarted.

- The list lives in `BetterOpelServer/data/warmups.json`, the log in
  `~/Library/Logs/BetterOpelServer/warmups.log`.
- Times are in this Mac's local time.
- A start wakes the car, sends the command, and watches for the car to report
  its climate running, asking once more half way through. The outcome is kept
  per time and shown in the app.
- `POST /scheduler/run` starts the climate now with the same care; the Lock
  Screen widget uses it and follows `GET /scheduler/run` for its notifications.
- It needs only Python's standard library. Restarting it is harmless and does
  not affect the MyOpel sign-in.
