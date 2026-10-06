# Third-party notices

Idle Miner's original application source is released under **GNU GPL version 3.0**; see [LICENSE](LICENSE). Third-party code and system dependencies retain their own copyright notices and license terms. This notice does not replace their full license texts.

## XMRig 6.26.0

Idle Miner uses the upstream XMRig CPU mining engine. Its source notices license it under **GPL version 3 or later**. The pinned upstream source archive is included at `Linux/vendor/xmrig-6.26.0.tar.gz`; the installer verifies it before compiling. The source archive includes XMRig's license and component notices. The Mac app includes an XMRig license notice, and the release provides the matching upstream engine source.

- [Upstream source at v6.26.0](https://github.com/xmrig/xmrig/tree/v6.26.0)
- [XMRig license](https://github.com/xmrig/xmrig/blob/v6.26.0/LICENSE)

XMRig includes components such as RandomX and other bundled libraries with their own notices. Retain the complete upstream archive and its copyright/license files when redistributing; licensing the Idle Miner application under GPL-3.0 does not erase those terms. The normal configured 1% XMRig developer donation remains enabled. Provider fees are separate.

## Qt 6 and PySide6 / Qt for Python

The Linux interface uses distribution-provided Qt 6 and PySide6 packages. Qt and Qt for Python offer open-source LGPL/GPL licensing and commercial licensing; the applicable terms depend on the installed components and package versions. Additional included components can have other licenses. Idle Miner's installer uses the distribution's system packages rather than relabeling these dependencies as its own code.

- [Qt licensing](https://doc.qt.io/qt-6/licensing.html)
- [Qt for Python license notices](https://doc.qt.io/qtforpython-6/licenses.html)

Keep the license and copyright information supplied with those packages, and consult their full terms if redistributing dependency binaries or a modified build.

## KDE Frameworks 6 KIdleTime

The Linux idle helper uses the distribution-provided KIdleTime library. Its public header carries **LGPL-2.1-or-later** notices, including attribution to Dario Freddi and Harald Sitter. Other files retain their applicable upstream notices.

- [KIdleTime documentation](https://api.kde.org/kidletime-index.html)
- [Upstream source and header notice](https://github.com/KDE/kidletime/blob/master/src/kidletime.h)

## Other dependencies and external services

XMRig builds use libraries including libuv, OpenSSL, and hwloc. Python, compiler/build tools, operating-system frameworks, and distribution packages remain governed by their own terms. Preserve the complete notices supplied with any components you redistribute.

Coinbase and unMineable provide network services, not application code licensed by this project. Their service terms and privacy policies apply independently. Names and trademarks belong to their respective owners; this project is not endorsed by Apple, Qt, KDE, Coinbase, unMineable, or XMRig.
