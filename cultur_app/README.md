# cult.u.r — Flutter client

Part of the [`cultur`](../) monorepo. The API is in [`../cultur_backend`](../cultur_backend).

## Product direction

`cult.u.r` is being built as a native media tracker with its own backend and
data model.

## Why this setup

The mobile app talks only to the separate Python API, which owns first-party
auth and backend data for `cult.u.r`.

## Boundary rules

- the Flutter app talks only to `yamtrack_api`
- it must not call third-party source integrations directly
- backend-specific data rules belong in the API contract, not in the app

## Flutter app

The app currently includes:

- server API URL setup
- native register and sign-in flow
- authenticated welcome screen for the first-party backend path

## API Contract

The Python API exposes:

- `POST /auth/register`
- `POST /auth/login`
- `POST /auth/refresh`
- `POST /auth/logout`
- `GET /me`
- `GET /backend/health`
- `POST /backend/bootstrap`
- `POST /backend/media`
- `GET /backend/media`
- `PUT /backend/tracking`
- `GET /backend/tracking`

See [`../yamtrack_api/README.md`](../yamtrack_api/README.md) for setup and
deploy notes.

## Local development

### 1. Start the API

```bash
cd ../yamtrack_api
python -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
export YAMTRACK_BASE_URL="https://your-yamtrack-host"
export SERVER_API_SECRET_KEY="change-me"
uvicorn app.main:app --host 0.0.0.0 --port 8787
```

### 2. Run the Flutter app

```bash
PUB_CACHE="$(pwd)/.pub-cache" flutter run
```

When the app opens, enter the API URL, for example
`http://your-server:8787`.

### Android over USB

To run the app on a physical Android phone:

1. Enable Developer Options and USB debugging on the phone.
2. Connect the phone by USB and accept the debugging prompt on the device.
3. Make sure the Android SDK is installed and configured so `flutter devices`
   can see the phone.
4. Run the app on the device:

```bash
PUB_CACHE="$(pwd)/.pub-cache" flutter run -d android
```

If the Python API is running on the same computer as Flutter, forward the port
over USB and use `http://127.0.0.1:8787` inside the app:

```bash
adb reverse tcp:8787 tcp:8787
```

If the API is running on your home server, use the server's LAN URL instead,
for example `http://192.168.1.50:8787`.

### Android wireless debugging

Once the Android SDK is configured, you can pair an Android 11+ phone over Wi-Fi
without keeping the USB cable connected.

The `adb` binary lives at:

```bash
/mnt/GamesSSD/Development/android-sdk/platform-tools/adb
```

Pair the phone:

```bash
/mnt/GamesSSD/Development/android-sdk/platform-tools/adb pair PHONE_IP:PAIR_PORT
```

Then connect it for debugging:

```bash
/mnt/GamesSSD/Development/android-sdk/platform-tools/adb connect PHONE_IP:DEBUG_PORT
flutter devices
PUB_CACHE="$(pwd)/.pub-cache" flutter run -d <device-id>
```

On the phone, open:

- `Developer options`
- `Wireless debugging`
- `Pair device with pairing code`

If the API runs on this same computer, you can still reverse the API port after
connecting wirelessly:

```bash
/mnt/GamesSSD/Development/android-sdk/platform-tools/adb reverse tcp:8787 tcp:8787
```
