#!/usr/bin/env bash
# 把 ebview-gtk3 构建产物收成一个"拷到别的 Windows 机器就能跑"的目录。
# 适配本仓库的 autotools 构建（exe 在 src/ 下，版本来自 configure.ac，GTK3）。
#
#   bash tools/pack_win.sh [输出目录]      # 默认 <repo>/build/dist
#
# 工具链前缀用 PREFIX 覆盖（默认 E:/msys64-mingw64/mingw64）：
#   PREFIX=/e/msys64-mingw64/mingw64 \
#       bash tools/pack_win.sh
#
# 构筑系统标识从 PREFIX 路径推断，写进 zip 文件名与包内 BUILD-INFO.txt。
#
# 产出 <输出目录>/EBView/ 与
#   <输出目录>/EBView-<版本>-win64-<构筑系统>[<SUFFIX>].zip
# 目录布局：
#   EBView/ebview.exe
#   EBView/BUILD-INFO.txt
#   EBView/share/ebview/*          <- shortcut.xml 等运行时资源 (locate_package_dir)
#   EBView/locale/ja/LC_MESSAGES/ebview.mo
#   EBView/lib/gdk-pixbuf-2.0/...  <- 图片加载器
#   EBView/etc/fonts/*             <- fontconfig 配置
set -e

REPO=$(cd "$(dirname "$0")/.." && pwd)
PREFIX=${PREFIX:-/e/msys64-mingw64/mingw64}
SRC=${SRC:-$REPO}
VERSION=$(sed -n 's/^AC_INIT(\[ebview\],\[\([^]]*\)\].*/\1/p' "$SRC/configure.ac" | head -1)
[ -n "$VERSION" ] || { echo "无法从 configure.ac 读出 VERSION" >&2; exit 1; }

BUILD=${BUILD:-$SRC/src}   # autotools 把 exe 放在 src/ 下
OUT=${1:-$SRC/build/dist}
DEST=$OUT/EBView

# 构筑系统标识：从工具链前缀路径推断，可用 SYSNAME 显式覆盖
SYSNAME=${SYSNAME:-}
if [ -z "$SYSNAME" ]; then
	case "$PREFIX" in
		*mingw64*) SYSNAME=mingw64 ;;
		*clang64*) SYSNAME=clang64 ;;
		*ucrt64*)  SYSNAME=ucrt64 ;;
		*mingw32*) SYSNAME=mingw32 ;;
		*clang32*) SYSNAME=clang32 ;;
		*)         SYSNAME=$(basename "$PREFIX") ;;
	esac
fi

if [ ! -f "$BUILD/ebview.exe" ]; then
	echo "找不到 $BUILD/ebview.exe，先编译 (make)" >&2
	exit 1
fi

rm -rf "$DEST"
mkdir -p "$DEST"

cp "$BUILD/ebview.exe" "$DEST/"

# 依赖闭包：优先 ldd 递归解析；ldd 不可用时退回 objdump + 前缀内 BFS。
export PATH="$PREFIX/bin:$PATH"
SYSROOT_W=$(cygpath -w "$PREFIX" 2>/dev/null || true)

collect_via_ldd() {
	local n=0 dll
	for dll in $(ldd "$BUILD/ebview.exe" 2>/dev/null | awk '{print $3}' | sort -u); do
		[ -f "$dll" ] || continue
		if [ -n "$SYSROOT_W" ]; then
			DLL_W=$(cygpath -w "$dll" 2>/dev/null || true)
			[ -z "$DLL_W" ] && continue
			[ "$DLL_W" = "${DLL_W#"$SYSROOT_W"}" ] && continue
		else
			case "$dll" in *"$PREFIX"*) ;; *) continue ;; esac
		fi
		cp "$dll" "$DEST/"
		n=$((n + 1))
	done
	echo "$n"
}

collect_via_objdump() {
	local n=0 seen="" todo="$BUILD/ebview.exe" dll imp w
	while [ -n "$todo" ]; do
		local next=""
		for f in $todo; do
			for imp in $(objdump -p "$f" 2>/dev/null | sed -n 's/.*DLL Name: //p' | sort -u); do
				case "$seen" in *" $imp "*) continue ;; esac
				seen="$seen $imp "
				dll="$PREFIX/bin/$imp"
				[ -f "$dll" ] || continue
				cp "$dll" "$DEST/"
				n=$((n + 1))
				next="$next $dll"
			done
		done
		todo="$next"
	done
	echo "$n"
}

n=$(collect_via_ldd)
if [ "$n" -eq 0 ]; then
	echo "ldd 无结果，改用 objdump 递归收集" >&2
	n=$(collect_via_objdump)
fi
if [ "$n" -eq 0 ]; then
	echo "错误：$PREFIX 下没找到任何依赖 DLL，拒绝打空包" >&2
	exit 1
fi

# 数据文件：data/ 下的运行时资源 -> share/ebview/
mkdir -p "$DEST/share/ebview"
for f in about.en about.jp endinglist.xml endinglist-ja.xml filter.xml searchengines.xml shortcut.xml; do
	[ -f "$SRC/data/$f" ] && cp "$SRC/data/$f" "$DEST/share/ebview/"
done

# 日语翻译：po/ja.gmo -> locale/ja/LC_MESSAGES/ebview.mo
if [ -f "$SRC/po/ja.gmo" ]; then
	mkdir -p "$DEST/locale/ja/LC_MESSAGES"
	cp "$SRC/po/ja.gmo" "$DEST/locale/ja/LC_MESSAGES/ebview.mo"
fi

# gdk-pixbuf 的图片加载器（连同 loaders.cache 原样拷贝；路径相对 DLL 解析）
mkdir -p "$DEST/lib"
if [ -d "$PREFIX/lib/gdk-pixbuf-2.0" ]; then
	cp -r "$PREFIX/lib/gdk-pixbuf-2.0" "$DEST/lib/"
	rm -f "$DEST"/lib/gdk-pixbuf-2.0/*/loaders/*.dll.a
fi

# fontconfig 需要 fonts.conf，否则初始化失败、所有文字变豆腐块
mkdir -p "$DEST/etc"
if [ -d "$PREFIX/etc/fonts" ]; then
	cp -r "$PREFIX/etc/fonts" "$DEST/etc/"
fi

# BUILD-INFO.txt：构筑系统 / 工具链版本溯源（采集允许失败回落 n/a）
WINNT_RAW=$(printf '#include <windows.h>\nEBVIEW_WINNT _WIN32_WINNT\n' \
	| gcc -E -P -x c - 2>/dev/null | awk '/EBVIEW_WINNT/ {print $2; exit}')
if [[ "$WINNT_RAW" =~ ^0[xX][0-9a-fA-F]+$ ]]; then
	WINNT_NUM=$((WINNT_RAW))
	WINNT=$(printf '0x%04X' "$WINNT_NUM")
else
	WINNT_NUM=-1
	WINNT=n/a
fi
case "$WINNT_NUM" in
	2560) TARGET="Windows 10" ;;
	1539) TARGET="Windows 8.1" ;;
	1538) TARGET="Windows 8" ;;
	1537) TARGET="Windows 7" ;;
	1536) TARGET="Windows Vista" ;;
	*)    TARGET="unknown" ;;
esac
CRT_IMPORTS=$(objdump -p "$BUILD/ebview.exe" 2>/dev/null | sed -n 's/.*DLL Name: //p')
if printf '%s\n' "$CRT_IMPORTS" | grep -qi '^msvcrt.dll$'; then
	CRT=msvcrt.dll
elif printf '%s\n' "$CRT_IMPORTS" | grep -qi 'ucrtbase.dll'; then
	CRT=ucrtbase.dll
elif printf '%s\n' "$CRT_IMPORTS" | grep -qi 'api-ms-win-crt'; then
	CRT='UCRT (api-ms-win-crt-*)'
else
	CRT=n/a
fi
GCC_VER=$(gcc -dumpversion 2>/dev/null || echo n/a)
GTK_VER=$(pkg-config --modversion gtk+-3.0 2>/dev/null || echo n/a)
GLIB_VER=$(pkg-config --modversion glib-2.0 2>/dev/null || echo n/a)
EB_LIB="static libgnurx+libeb (no runtime dll)"
EXE_SHA=$(sha256sum "$BUILD/ebview.exe" 2>/dev/null | awk '{print $1}')
[ -n "$EXE_SHA" ] || EXE_SHA=n/a

cat > "$DEST/BUILD-INFO.txt" <<EOF
ebview ${VERSION} (GTK3) - build information
========================================
build-system      : ${SYSNAME}
toolchain-prefix  : ${PREFIX}
target-platform   : _WIN32_WINNT=${WINNT} (${TARGET})
compiler          : gcc ${GCC_VER}
gtk3              : ${GTK_VER}
glib2             : ${GLIB_VER}
eb-library        : ${EB_LIB}
exe-crt-import    : ${CRT}
dll-count         : ${n}
exe-sha256        : ${EXE_SHA}
build-tree        : ${BUILD}
packed-at         : $(date '+%Y-%m-%d %H:%M:%S %z')
EOF

# 打包（没有 zip 命令则退回 python zipfile）
ZIP=$OUT/EBView-${VERSION}-win64-${SYSNAME}${SUFFIX}.zip
rm -f "$ZIP"
if command -v zip >/dev/null 2>&1; then
	(cd "$OUT" && zip -qr "$(basename "$ZIP")" EBView)
else
	if command -v cygpath >/dev/null 2>&1; then
		PYOUT=$(cygpath -w "$OUT")
		PYZIP=$(cygpath -w "$ZIP")
	else
		PYOUT=$OUT
		PYZIP=$ZIP
	fi
	python - "$PYOUT" "$PYZIP" <<'PY'
import os, sys, zipfile
out, zpath = sys.argv[1], sys.argv[2]
root = os.path.join(out, "EBView")
with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for base, _, files in os.walk(root):
        for f in files:
            full = os.path.join(base, f)
            z.write(full, os.path.relpath(full, out).replace(os.sep, "/"))
PY
fi

echo "构筑系统: $SYSNAME  ($TARGET)"
echo "DLL: $n 个"
echo "目录: $DEST  ($(du -sh "$DEST" | cut -f1))"
echo "zip : $ZIP  ($(du -h "$ZIP" | cut -f1))"
