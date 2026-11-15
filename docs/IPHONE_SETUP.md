# Run coy on your iPhone

coy is a native SwiftUI app for identifying campus wildlife, naming sightings, commenting, and browsing Home, Species, Ranked, and Map. Its 34-class BioCLIP-v4 classifier runs on your Mac. The iPhone sends a photo to the Mac and displays the actual prediction and confidence.

The app requires **iOS 18 or later**. The recorded walkthrough uses an iOS 18.3 simulator; physical-device installation is a separate step and is not claimed as tested by that recording. Use an Xcode version compatible with your Mac and your phone's installed iOS version; check Apple's [Xcode device-support table](https://developer.apple.com/xcode/system-requirements/).

## 1. Prepare the Mac

You need Xcode, Python 3.10 or later, the trained model artifacts, and internet access for the first dependency/base-model download. Apple Silicon is recommended for local inference.

If you already have the working `/Users/harshranjan/DEVFEST` folder, use it:

```bash
cd /Users/harshranjan/DEVFEST
```

For a fresh checkout, use a new directory and a GitHub account with repository access:

```bash
git clone git@github.com:hranjan004/devfest_model_training.git
cd devfest_model_training
```

The trained files under `runs/` are intentionally excluded from Git. Before starting a fresh checkout, copy these files from the real completed training run into `runs/ucsc34_bioclip_v4/`:

```text
model_adapter.pt
model_checksum.json
classes.json
ucsc_bioclip.json
```

The existing DEVFEST folder already contains that run. There is no published download link for this project-specific adapter in the repository. Do not substitute the older synthetic smoke-test checkpoint. The loader fetches the BioCLIP 2 base model from Hugging Face at the revision recorded inside the adapter; this is separate from the trained 34-class adapter.

Create the environment if needed and start the two services:

```bash
python3 -m venv .venv
.venv/bin/python -m pip install --upgrade pip
.venv/bin/python -m pip install -e '.[app]'
bash scripts/run_coy.sh
```

Leave that terminal running. Port `8080` serves the trained classifier; port `8081` adapts its response for coy. The app must use **8081**. Initial model loading can take longer than later predictions.

In a second terminal, check the app-facing service:

```bash
curl --fail http://127.0.0.1:8081/healthz
```

The response should identify the BioCLIP model and `num_classes: 34`. A successful health check establishes service availability; it is not by itself proof that a photo has been classified. The first real photo upload is the inference check.

## 2. Connect your iPhone with USB-C

1. Connect your unlocked iPhone to the Mac with a USB-C cable that supports data. For an older Lightning iPhone, use the appropriate data cable instead.
2. Accept **Trust This Computer** on the iPhone and enter its passcode. If Finder asks you to trust the iPhone, accept that as well. Apple's [trust instructions](https://support.apple.com/en-us/109054) explain these pairing prompts.
3. Open the project:

   ```bash
   open ios/ucscdevfestapp/ucscdevfestapp.xcodeproj
   ```

4. In Xcode, open **Window → Devices and Simulators** and select the connected iPhone. Newer Xcode releases may present device management in **Device Hub**. Allow device preparation to finish.
5. On the iPhone, open **Settings → Privacy & Security → Developer Mode**, enable it, restart when prompted, then confirm the choice after the restart. If the switch is missing, initiate pairing with Xcode first. Follow Apple's [Developer Mode instructions](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).

USB-C is used to install and debug the app. It does **not** make `localhost` on your iPhone refer to your Mac, and it does not place the classifier on the phone.

## 3. Sign and install from Xcode

1. In **Xcode → Settings → Accounts** (called **Apple Accounts** in newer Xcode versions), sign in with your Apple Account.
2. Select the project, then the **ucscdevfestapp** app target and **Signing & Capabilities**.
3. Enable **Automatically manage signing** and select your team. A personal team can be used for development on your own device, subject to Apple's account and provisioning limits.
4. If Xcode reports that the existing bundle identifier is unavailable, replace it with your own unique identifier, for example `com.yourname.coy`. Keep this identifier stable between installs if you want to keep using the same installed app and its saved sightings.
5. Choose the **ucscdevfestapp** scheme and your physical iPhone as the run destination. Under **Product → Scheme → Edit Scheme → Run**, use the **Debug** build configuration for this local HTTP setup. Click **Run** (or press **Command-R**). Complete any signing, device registration, or developer trust prompt Xcode/iOS presents.

The Debug configuration includes local-network usage text and permits the local HTTP service. The Release configuration does not broadly permit arbitrary HTTP; use a properly configured HTTPS service before distributing a production build. Keep personal signing changes local, and never commit signing certificates, provisioning profiles, private keys, passwords, or API credentials.

Apple documents [signing and running on a physical device](https://developer.apple.com/documentation/xcode/building-and-running-an-app). If your phone's iOS version is newer than your Xcode supports, install a compatible Xcode version and its required macOS version; do not erase or downgrade the phone to work around this.

## 4. Point coy at the Mac

1. Put the Mac and iPhone on the same Wi-Fi network with device-to-device communication allowed. Guest/campus networks sometimes isolate devices; use a trusted network where they can reach each other.
2. Find the Mac's active Wi-Fi IP address in **System Settings → Wi-Fi → Details → TCP/IP**. Use its local address, for example `192.168.1.20`, not a public IP address.
3. On the iPhone, open Safari and visit `http://192.168.1.20:8081/healthz`, replacing the example address with your Mac's address. You should see JSON. Keep the Mac awake and the services running.
4. In coy, open the gear icon on **Home**, then set **Model server** to `http://192.168.1.20:8081` using your actual address. Tap **Check again** and confirm **Live**, then **Done**.
5. Allow coy's **Local Network** request. If previously denied, enable coy under **Settings → Privacy & Security → Local Network**. Apple explains these [local-network controls](https://support.apple.com/en-us/102229).

The simulator can use `http://localhost:8081` because it runs on the Mac. A physical iPhone needs the Mac's reachable address. A changed Wi-Fi network or DHCP address may require updating coy's setting.

If macOS asks whether the Python service may accept incoming connections, allow it for this local test. If a firewall rule already blocks it, allow the service rather than disabling the firewall. This is a local development service without a production authentication layer; do not forward its ports to the public internet.

## 5. Verify the full flow

1. Save a photo you own or are licensed to reuse into iPhone Photos. For the included demo imagery, preserve the attribution in `coy_product_demo_credits.md`.
2. In coy, start a sighting and choose the photo. Wait for the live BioCLIP result, then review the predicted class and confidence. The model classifies the whole photo across its 34 trained classes; it does not run an animal detector.
3. Add a name, caption, and location, and publish the sighting.
4. Find it in **Home**, open its detail, and add a comment. Check its species, **Ranked**, and its map location. A post may appear below higher-rated entries in Ranked.
5. Close and reopen the app. Confirm that your sighting, name, comment, and location remain.

In this coy build, sightings, names, comments, and coordinates are stored locally on that installation. Seeded community entries are demo data. They are not evidence of multi-user synchronization, and installing on another phone does not copy your posts. Avoid deleting the app or changing its bundle identifier when checking persistence.

## Troubleshooting

| Symptom | What to check |
|---|---|
| Model service exits or reports missing weights | Confirm the real `runs/ucsc34_bioclip_v4` files are present. Check the terminal for a checksum mismatch, dependency error, or failed initial base-model download. |
| Mac health check fails | Keep `scripts/run_coy.sh` running. Check whether ports 8080/8081 are already occupied; do not terminate unrelated services blindly. |
| Mac works, iPhone Safari does not | Use the Mac's current LAN address and port 8081. Check same Wi-Fi, network isolation, Mac sleep, and incoming-connection permissions. USB-C alone does not establish this route. |
| Safari works, coy cannot connect | Recheck coy's Model server address and Local Network permission, then tap Check again. |
| Health responds, prediction fails | Read the service error and retry a normal JPEG/PNG photo. A healthy endpoint does not guarantee that model loading or a particular image upload succeeded. |
| iPhone only charges or is absent from Xcode | Unlock it, reconnect, try a known data cable/port, and complete Trust prompts. See Apple's [device-recognition guide](https://support.apple.com/en-us/108643). |
| Developer Mode switch is absent | Start pairing in Xcode first, then return to Privacy & Security. |
| Signing or provisioning fails | Check the selected team, unique bundle identifier, internet connection, and Xcode's exact signing message. Renew/rebuild through Xcode when your development provisioning requires it. |
| App works in simulator but cannot run on phone | Check iOS 18 minimum, Xcode device support, Developer Mode, and signing. Simulator builds do not validate physical-device signing. |

After the first successful cable pairing, Xcode can also debug a paired device over a reachable network; see Apple's [wireless-device instructions](https://help.apple.com/xcode/mac/current/en.lproj/dev3e2f4ee6d.html). The Mac classifier still needs to be running and reachable separately.

## Demo files

The repository root contains `coy_product_demo.mp4` and `coy_product_demo_credits.md`. The video demonstrates the native iOS simulator app; feature cards and annotations are added in editing. Refer to the credits for image sources and recording details.
