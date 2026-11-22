# Device pop-ups spike S1 (2026-11-23)

Probe: a throwaway signed app bundle (`NSBluetoothAlwaysUsageDescription` set) that registers `IOBluetoothDevice.register(forConnectNotifications:selector:)` and per-device disconnect notifications, and prints `name`, `addressString`, `isConnected()`, `deviceClassMajor/Minor`, `classOfDevice` and the battery selectors. Devices: AirPods 4 (ANC) and Keychron K3, both on this Mac (macOS 26, Apple Silicon).

## Answers

1. **Detection path: IOBluetooth connect notifications work for both devices.** AirPods (classic audio) and the Keychron (HID) each produced a connect notification on real reconnects. The IOKit registry fallback is not viable: `ioreg` shows only placeholder serial `IOBluetoothDevice` nodes, not these devices.
2. **Permission: required.** A command-line binary without `NSBluetoothAlwaysUsageDescription` is killed by TCC at the first IOBluetooth call (SIGABRT, `namespace: TCC`). With the key in a bundle's Info.plist it runs. The Bluetooth prompt appears the first time Shima registers, so at the first launch after the update. The key is mandatory, not conditional.
3. **Registration replays current devices.** Registering the connect notification immediately fires it for every already-connected device (both here, same second as registration). Shima must ignore connect events for the first moments after registering (launch grace, 3 s).
4. **A connect notification can arrive before the device is connected.** AirPods produced two `CONNECT-NOTIFY` with `isConnected() == false`, then one with `true` about 14 s after the disconnect. The client must drop notifications whose `isConnected()` is false; the per-address 5 s limit also absorbs duplicates.
5. **Disconnect notifications fire** (and fire twice in the probe because it registered twice). Not used: no disconnect banners.
6. **Class of device and kind:** AirPods `major=4 minor=6 cod=0x240418` (audio, headphones); Keychron `major=5 minor=16 cod=0x2540` (peripheral; `minor` is the 6-bit field, 16 = keyboard, 32 = pointing device, 48 = combo). AirPods are classed as headphones, so the name ("AirPods") must beat the class to get the earbuds glyph.
7. **Names:** IOBluetooth reports `AirPods 4 (ANC)` and `Keychron K3`, not the user-given "Patrick's AirPods 4" that `system_profiler` shows. Show IOBluetooth's `name`; falling back to the address when nil.
8. **Battery:** the private selectors `batteryPercentLeft` / `batteryPercentRight` (and `Single`, `Combined`, `Case`) answer through key-value coding after `responds(to:)` succeeds. AirPods: left 100, right 100 or 99, readable at connect time. Keychron: all 0. Rule: a value of 0 means unknown; show the lowest non-zero of left/right, else single or combined if non-zero, else no battery. These are undocumented selectors: guard every read with `responds(to:)` and treat anything missing as no battery.

## Decisions for the plan

Path: IOBluetooth (Task 6a). Info.plist key mandatory. Launch grace 3 s in `DevicePeekPolicy`. Client filters `isConnected() == false`. Classification: name keywords decide earbuds before the class does. Battery per rule 8.
