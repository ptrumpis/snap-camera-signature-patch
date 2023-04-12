# 🔓 Snap Camera Signature Patch
Unlocks all Snap Lenses with [Snap Camera Server v3](https://github.com/ptrumpis/snap-camera-server)

TL;DR
- [Web based online Patch Tool](https://ptrumpis.github.io/snap-camera-signature-patch/)

## ℹ️ About
Snap `lens.lns` files come with a *Signature* preventing anyone from distributing or modifying lenses.

This patch will disable all *Signature* checks of your Snap Camera application to use modified Snap Lenses.

Enabling you to
- Access/Download all Snap Lenses from the web https://lens.snapchat.com/
- Use modified Lenses (Remove Watermarks / Change Backgrounds...)

## ⚠ Requirements
- Snap Camera 1.19 - 1.21 (Windows)
- Snap Camera 1.21 (Mac OS)

Now with Windows and Mac OS support 👍

## 🚀 Usage
Use the web based online patch tool
- [Web based online Patch Tool](https://ptrumpis.github.io/snap-camera-signature-patch/)

### 🍏 Additional steps on Mac OS
Mac OS users will also have to run these commands inside the Terminal application after applying the patch.

1. Make the binary executable:
```sh
chmod +x "/Applications/Snap Camera.app/Contents/Mac OS/Snap Camera"
```

2. Remove the Mac OS code signing:
```sh
sudo codesign --remove-signature "/Applications/Snap Camera.app/"
```

#### Error: application can't be opened
Check your Mac OS security settings if the application can't be opened.

![gatekeeper2](https://user-images.githubusercontent.com/116500225/231490273-2c621023-3282-468c-b1b8-411e5df35f81.jpg)

You can also try to fix the error by running the command:
```sh
spctl --add "/Applications/Snap Camera.app"
```

### [📺 Mac OS Video Guide](https://www.youtube.com/watch?v=lJhL7bA7GGA)

[![Patching Snap Camera on Mac OS](https://img.youtube.com/vi/lJhL7bA7GGA/0.jpg)](https://www.youtube.com/watch?v=lJhL7bA7GGA)

## ❤️ Support
If you like my work and want to support me, feel free to invite me for a virtual coffee ☕

- [☕ Ko-fi](https://ko-fi.com/ptrumpis)
- [☕ Buy me a Coffee](https://www.buymeacoffee.com/ptrumpis)
- [☕ Liberapay](https://liberapay.com/ptrumpis/)

You can also become my GitHub Sponsor
