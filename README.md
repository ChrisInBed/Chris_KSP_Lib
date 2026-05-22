# Chris GNC Suite
Advanced guidance and control research for Kerbal Space Program.

Chris GNC Suite is a powerful autopilot mod containing PEGLand and UEntry programs that enable precise spacecraft landings on the Moon or Earth. It is based on kOS, a scipt language and interpreter for KSP autopilot. This mod is capable of:

- Fuel optimal, precise, realisctic (just like Apollo) and safe powered pin-point landing on the Moon, or any other celectials without atmosphere, with almost any proper lander designs;
- Mild, precise, realistic lifting reentry guidance back to runway on the Earth, or any other celectials with a decent atmosphere, with spaceplanes or reentry capsules;
- High precision maneuver node executor, for both stock and Principia nodes.

Though frontends of Chris GNC Suite is written in kOS, but you don't have to learn kOS script grammar. PEGLand and UEntry applications comes with user-friendly GUIs.

See [Installation](#installation) for installation instructions, and read the [Tutorial](./docs/English/README.md) to learn how to use it.

**KSP Forum Thread:** [Chris GNC Suite](https://forum.kerbalspaceprogram.com/topic/229673-1125chris-gnc-suite-advanced-guidance-and-control-research-for-kerbal-space-program/)

If you have any thouble using it, don't hesitate to open an issue, or contact me via:

- Discord: bilbo_04_71051
- [Discord KSP-RO server](https://discord.gg/cxxHuGywV): @Chris in RP-1 general
- Email: gchrispan@gmail.com

![](./docs/pictures/coverpage.png)

## Videos

> [!NOTE]
> These are brief introductions for this mod. I still recommend you to read text tutorials as they are more comprehensive.

### YouTube

- [[KSP]PEGLand: Graceful and Precise Powered Landing Autopilot](https://www.youtube.com/watch?v=zdxEXBxVh9Y)
- [[KSP]UEntry: General Purpose Lifting Reentry Autopilot](https://www.youtube.com/watch?v=50bq9pkTl-I)
- [[KSP]UEntry: Apollo Precision Skip-reentry from the Moon](https://www.youtube.com/watch?v=iLDDLfczL_4)

### Bilibili

- [[KSP/RSS/RO]PEGLand: 你也许能找到的最方便的定点着陆脚本](https://www.bilibili.com/video/BV1wDd2YDEf1)
- [[KSP/RSS/RO]PEGLand v0.3: 早期探测器一键自动定点落月](https://www.bilibili.com/video/BV1ZJdZY6EwE)
- [[KSP/RSS/RO]PEGLand v0.3阿波罗登月特别版：厘米级优雅着陆](https://www.bilibili.com/video/BV1wGdZYjEgm)
- [[KSP/RSS/RO]PEGLand 0.7: 通用定点着陆制导，支持目视修正](https://www.bilibili.com/video/BV1yUT6z4ExF)
- [UEntry: 如何专业且优雅地把航天飞机飞回跑道(Part 1)](https://www.bilibili.com/video/BV1dAcFz5ECu)
- [UEntry: 如何驾驶梦舟飞船从月球飞回文昌(Part2)](https://www.bilibili.com/video/BV1QncPzEEKC)

## MOD List

- KSP 1.12.5
- kOS: Scriptable Autopilot System 1.4.0.0
- KSPBurst Compiler 1.5.5.2 (Required by UEntry)
- Ferram Aerospace Research Continued 0.16.1.2 (Required by UEntry)
- WaypointManager (Recommended for PEGLand and UEntry)

## Installation

### Via CKAN

Search for `Chris GNC Suite` and install. All scripts and DLLs will be automatically put into the right places.

### Manual Installation

First install all mod dependencies, then download the installation package from:

- [SpaceDock](https://spacedock.info/mod/4126/Chris%20GNC%20Suite)
- [Github Releases](https://github.com/ChrisInBed/Chris_KSP_Lib/releases/latest) (`Chris_GNC_Suite-v<VERSION>.zip`)

After extraction, you will see two folders:

- `Ships`: Move it to the `<KSP Root Directory>\` folder. When complete, the path `<KSP Root Directory>\Ships\Script\pegland.ks` should exist.
- `GameData`: Move it to the `<KSP Root Directory>\` folder. When complete, the path `<KSP Root Directory>\GameData\kOS-Addons\AFS\kOS-AFS.dll` should exist.

## Tutorial

[Tutorial](./docs/English/README.md)
