#!/usr/bin/env bash
# 用 CMake 同时构建 ucrt64 + mingw64 两套 ebview（GTK3 移植版），
# 并各自收成一个"拷到别的 Windows 机器就能跑"的 zip 包。
#
#   bash tools/pack_win.sh
#
# 仿 E:/git/EBView/tools/pack_win.sh 的写法：每个工具链各打一个独立 zip，
# 包内布局保持一致：
#   EBView/ebview.exe
#   EBView/BUILD-INFO.txt        <- 工具链 / 编译器 / CRT 溯源
#   EBView/share/ebview/*         <- 运行时资源（shortcut.xml 等）
#   EBView/locale/<lang>/LC_MESSAGES/ebview.mo
#   EBView/lib/gdk-pixbuf-2.0/...  <- 插图加载器
#   EBView/etc/fonts/*            <- fontconfig 配置
#
# 环境变量（均可覆盖）：
#   MSYS2_ROOT     MSYS2 安装根（默认 /e/msys64-mingw64）
#   MINGW_PREFIX   mingw64 工具链前缀（默认 $MSYS2_ROOT/mingw64）
#   UCRT_PREFIX    ucrt64 工具链前缀（默认 $MSYS2_ROOT/ucrt64）
#   OUT            输出目录（默认 $SRC/build/dist）
#   SKIP_BUILD=1   跳过 cmake 构建，直接打包已有的 build-<sys> 目录
#
# 产出：
#   $OUT/EBView-<ver>-gtk3-win64-mingw64.zip
#   $OUT/EBView-<ver>-gtk3-win64-ucrt64.zip
set -e

SRC="$(cd "$(dirname "$0")/.." && pwd)"
MSYS2_ROOT=${MSYS2_ROOT:-/e/msys64-mingw64}
MINGW_PREFIX=${MINGW_PREFIX:-$MSYS2_ROOT/mingw64}
UCRT_PREFIX=${UCRT_PREFIX:-$MSYS2_ROOT/ucrt64}
OUT=${OUT:-$SRC/build/dist}

VERSION=$(sed -n 's/^ *VERSION *\([0-9][0-9.]*\).*/\1/p' "$SRC/CMakeLists.txt" | head -1)
[ -n "$VERSION" ] || { echo "无法从 CMakeLists.txt 读出 VERSION" >&2; exit 1; }
[ -x "$MSYS2_ROOT/usr/bin/bash" ] || { echo "找不到 $MSYS2_ROOT/usr/bin/bash" >&2; exit 1; }

# 构建并打包单个工具链。
# 整段逻辑都跑在对应 MSYSTEM 的 bash 里，这样 gcc/cmake/ldd/pkg-config
# 全部对齐到该工具链；依赖 DLL 也只从工具链前缀里收，系统 DLL 不收。
pack_one() {
    local SYSNAME="$1" PREFIX="$2"
    local UPPER BUILD
    UPPER=$(echo "$SYSNAME" | tr '[:lower:]' '[:upper:]')   # UCRT64 / MINGW64
    BUILD="$SRC/build-$SYSNAME"

    MSYSTEM=$UPPER "$MSYS2_ROOT/usr/bin/bash" -lc "
        set -e
        export SRC='$SRC' OUT='$OUT' VERSION='$VERSION' SYSNAME='$SYSNAME' PREFIX='$PREFIX' BUILD='$BUILD' SKIP_BUILD='${SKIP_BUILD:-}'
        cd \"\$SRC\"

        if [ -z \"\$SKIP_BUILD\" ]; then
            echo \"===== [\$SYSNAME] cmake configure + build =====\"
            rm -rf \"\$BUILD\"
            cmake -S . -B \"\$BUILD\" -G Ninja -DCMAKE_BUILD_TYPE=Release
            cmake --build \"\$BUILD\"
        fi
        [ -f \"\$BUILD/ebview.exe\" ] || { echo \"找不到 \$BUILD/ebview.exe，先编译\" >&2; exit 1; }

        DEST=\"\$OUT/EBView\"
        rm -rf \"\$DEST\"; mkdir -p \"\$DEST\"
        cp \"\$BUILD/ebview.exe\" \"\$DEST/\"
        [ -f \"\$BUILD/ebdump.exe\" ] && cp \"\$BUILD/ebdump.exe\" \"\$DEST/\" || true
        [ -f \"\$SRC/tools/ebview-format\" ] && cp \"\$SRC/tools/ebview-format\" \"\$DEST/\" || true

        # 依赖闭包：ldd 递归列出，只拷工具链前缀里的 DLL（系统 DLL 不拷）。
        # ldd 打印的可能是 MSYS 挂载别名（/ucrt64/bin/x.dll），也可能是盘符绝对
        # 路径（/e/msys64-mingw64/ucrt64/bin/x.dll）；统一用 cygpath 转 Windows
        # 路径再比前缀，否则前缀匹配不上会静默打出空包。
        export PATH=\"\$PREFIX/bin:\$PATH\"
        SYSROOT_W=\$(cygpath -w \"\$PREFIX\" 2>/dev/null || true)
        n=0
        for dll in \$(ldd \"\$BUILD/ebview.exe\" | awk '{print \$3}' | sort -u); do
            [ -f \"\$dll\" ] || continue
            DLL_W=\$(cygpath -w \"\$dll\" 2>/dev/null || true)
            [ -z \"\$DLL_W\" ] && continue
            case \"\$DLL_W\" in \"\$SYSROOT_W\"*) ;; *) continue ;; esac
            cp \"\$dll\" \"\$DEST/\"
            n=\$((n + 1))
        done
        [ \"\$n\" -gt 0 ] || { echo \"错误：\$PREFIX 下没找到任何依赖 DLL，拒绝打空包\" >&2; exit 1; }

        [ -d \"\$BUILD/share\" ] && cp -r \"\$BUILD/share\" \"\$DEST/\"
        [ -d \"\$BUILD/locale\" ] && cp -r \"\$BUILD/locale\" \"\$DEST/\"

        # gdk-pixbuf 图片加载器。loaders.cache 里是相对路径（lib\\gdk-pixbuf-2.0\\...），
        # gdk-pixbuf 按 DLL 所在目录解析，所以整个目录原样拷过去即可。
        mkdir -p \"\$DEST/lib\"
        [ -d \"\$PREFIX/lib/gdk-pixbuf-2.0\" ] && cp -r \"\$PREFIX/lib/gdk-pixbuf-2.0\" \"\$DEST/lib/\"
        rm -f \"\$DEST\"/lib/gdk-pixbuf-2.0/*/loaders/*.dll.a 2>/dev/null

        # fontconfig 需要 fonts.conf，否则初始化失败、所有文字变豆腐块。
        mkdir -p \"\$DEST/etc\"
        [ -d \"\$PREFIX/etc/fonts\" ] && cp -r \"\$PREFIX/etc/fonts\" \"\$DEST/etc/\"

        # 把工具链 / CRT 等溯源信息写进包内。所有采集都允许失败回落 n/a。
        WINNT_RAW=\$(printf '#include <windows.h>\nEBVIEW_WINNT _WIN32_WINNT\n' \
            | gcc -E -P -x c - 2>/dev/null | awk '/EBVIEW_WINNT/ {print \$2; exit}')
        if [[ \"\$WINNT_RAW\" =~ ^0[xX][0-9a-fA-F]+\$ ]]; then
            WINNT=\$(printf '0x%04X' \$((WINNT_RAW)))
        else
            WINNT=n/a
        fi
        case \"\$WINNT\" in
            0x0A00) TARGET='Windows 10' ;;
            0x0603) TARGET='Windows 8.1' ;;
            0x0602) TARGET='Windows 8' ;;
            0x0601) TARGET='Windows 7' ;;
            0x0600) TARGET='Windows Vista' ;;
            *)      TARGET='unknown' ;;
        esac
        CRT_IMPORTS=\$(objdump -p \"\$BUILD/ebview.exe\" 2>/dev/null | sed -n 's/.*DLL Name: //p')
        if printf '%s\n' \"\$CRT_IMPORTS\" | grep -qi '^msvcrt.dll\$'; then
            CRT=msvcrt.dll
        elif printf '%s\n' \"\$CRT_IMPORTS\" | grep -qi 'ucrtbase.dll'; then
            CRT=ucrtbase.dll
        elif printf '%s\n' \"\$CRT_IMPORTS\" | grep -qi 'api-ms-win-crt'; then
            CRT='UCRT (api-ms-win-crt-*)'
        else
            CRT=n/a
        fi
        GCC_VER=\$(gcc -dumpversion 2>/dev/null || echo n/a)
        GTK_VER=\$(pkg-config --modversion gtk+-3.0 2>/dev/null || echo n/a)
        GLIB_VER=\$(pkg-config --modversion glib-2.0 2>/dev/null || echo n/a)
        EB_LIB=\$(sed -n 's/^EB_LIBRARY:FILEPATH=//p' \"\$BUILD/CMakeCache.txt\" 2>/dev/null | head -1)
        [ -n \"\$EB_LIB\" ] || EB_LIB=n/a
        EXE_SHA=\$(sha256sum \"\$BUILD/ebview.exe\" 2>/dev/null | awk '{print \$1}')
        [ -n \"\$EXE_SHA\" ] || EXE_SHA=n/a

        cat > \"\$DEST/BUILD-INFO.txt\" <<EOF
EBView \${VERSION} (GTK3) - build information
========================================
build-system      : \${SYSNAME}
toolchain-prefix  : \${PREFIX}
target-platform   : _WIN32_WINNT=\${WINNT} (\${TARGET})
compiler          : gcc \${GCC_VER}
gtk3              : \${GTK_VER}
glib2             : \${GLIB_VER}
eb-library        : \${EB_LIB}
exe-crt-import    : \${CRT}
dll-count         : \${n}
exe-sha256        : \${EXE_SHA}
build-tree        : \${BUILD}
packed-at         : \$(date '+%Y-%m-%d %H:%M:%S %z')
EOF

        # 打包（MSYS2 通常没有 zip 命令，退回 python 的 zipfile）
        ZIP=\"\$OUT/EBView-\${VERSION}-gtk3-win64-\${SYSNAME}.zip\"
        rm -f \"\$ZIP\"
        if command -v zip >/dev/null 2>&1; then
            (cd \"\$OUT\" && zip -qr \"\$(basename \"\$ZIP\")\" EBView)
        else
            PYBIN=\$(command -v python || command -v python3 || true)
            [ -n \"\$PYBIN\" ] || { echo \"错误：找不到 python/python3，无法打包\" >&2; exit 1; }
            PYOUT=\$(cygpath -w \"\$OUT\"); PYZIP=\$(cygpath -w \"\$ZIP\")
            \"\$PYBIN\" - \"\$PYOUT\" \"\$PYZIP\" <<'PY'
import os, sys, zipfile
out, zpath = sys.argv[1], sys.argv[2]
root = os.path.join(out, 'EBView')
with zipfile.ZipFile(zpath, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for base, _, files in os.walk(root):
        for f in files:
            full = os.path.join(base, f)
            z.write(full, os.path.relpath(full, out).replace(os.sep, '/'))
PY
        fi
        echo \"[\$SYSNAME] DLL: \$n 个  目录: \$(du -sh \"\$DEST\" | cut -f1)  zip: \$ZIP  (\$(du -h \"\$ZIP\" | cut -f1))\"
    "
}

pack_one mingw64 "$MINGW_PREFIX"
pack_one ucrt64  "$UCRT_PREFIX"
echo "完成：两个 zip 已生成于 $OUT"
