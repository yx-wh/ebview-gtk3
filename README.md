# EBView — GTK3 移植版

EBView 是須藤賢一（Kenichi Suto）编写的 EPWING CD-ROM 词典阅读器，基于
[EB Library](http://www.sra.co.jp/people/m-kasahr/eb/)（`libeb`）。本仓库是
社区 GTK 3 移植分支，构建系统已从 Autotools 切换为 CMake，并在原版 0.3.6
基础上做了一批稳定性与体验修复。

> 原始日文 README 保留为 [`README.ja`](README.ja)（EUC-JP 编码）。

## 背景

- 上游自 0.3.6 起基本停止维护。
- 本仓库源自社区 GTK 3 移植，使用的是 CMake 构建。
- 另一条 GTK 2 分支在移植后修复了大量 bug、增加了若干功能，这些改动正逐步
  回移到本仓库（配置编码、iconv、弹窗、搜索状态机等，详见下文）。

## 依赖

Debian / Ubuntu：

```sh
sudo apt install build-essential cmake pkg-config \
                 libgtk-3-dev libeb16-dev zlib1g-dev gettext
```

- `libgtk-3-dev` 提供 `gtk+-3.0` 与 `pangocairo`；
- `libeb16-dev` 提供 EB Library 头文件与 `libeb`（该库没有 `.pc` 文件，
  CMake 用 `find_path` / `find_library` 查找）；
- `gettext`（`msgfmt`）用于可选的 ja / zh_CN / zh_TW 翻译，缺失时构建自动跳过；
- 非 Windows 平台会显式链接 `libX11`（程序仍使用少量 X11 入口）。

## 构建与运行

```sh
./build.sh
```

等价于：

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel "$(nproc)"
```

直接运行即可，程序会自动探测可执行文件旁的 `share/ebview`，无需安装：

```sh
./build/ebview
```

如需手动指定数据目录（例如移动过构建产物），可用 `EBVIEW_DATADIR` 覆盖：

```sh
EBVIEW_DATADIR="$PWD/build/share/ebview" ./build/ebview
```

用隔离的 HOME 做测试：

```sh
HOME=/tmp/ebview-home ./build/ebview
```

安装到系统：

```sh
sudo cmake --install build       # 默认 prefix /usr/local
ebview
```

自定义安装前缀：

```sh
cmake -S . -B build -DCMAKE_INSTALL_PREFIX=/opt/ebview
cmake --build build
sudo cmake --install build
```

## 数据目录探测顺序

运行时会按以下顺序寻找包含 `shortcut.xml` 的数据目录：

1. `$EBVIEW_DATADIR`
2. `<可执行文件目录>/share/ebview`（CMake 构建树）
3. `<可执行文件目录>/../share/ebview`（重定位后的安装前缀）
4. 编译期 `PACKAGEDIR`（默认 `/usr/local/share/ebview`）

Linux 下用 `/proc/self/exe` 定位可执行文件，因此从任意工作目录启动都有效。

## 加载 EPWING 词典

在「偏好设置 → 词典组（Dictionary Group）」中添加包含 `CATALOGS` 文件的
词典目录即可，也可直接编辑 `~/.ebview/dictgroup.xml`。支持同时挂载多本词典
进行串刺搜索。本仓库不含任何词典数据，需自行准备。

首次运行会在 `~/.ebview/` 生成 `preference.xml`、`dictgroup.xml`、
`shortcut.xml`、`searchengines.xml`、`filter.xml` 等配置文件。

## 菜单栏隐藏后怎么恢复

- **`Ctrl+M`**：硬编码的切换快捷键，不依赖快捷键配置，任何状态下都可用。
- **右键 / 中键点击正文区域 → `Display` → `Menu bar`**。
- 先**完全退出程序**，再编辑 `~/.ebview/preference.xml`，把
  `<show_menu_bar>0</show_menu_bar>` 改成 `1`。必须先退出，否则程序退出时
  `save_preference()` 会把当前状态写回去，覆盖你的修改。

## 本版相对原版的改进

| 项目 | 原版 | 本版 |
| --- | --- | --- |
| GUI | GTK 2 | GTK 3 |
| 构建系统 | Autotools | CMake + `pkg-config` + `find_library` |
| 数据目录 | 编译期写死 | 自动探测 + `EBVIEW_DATADIR` 覆盖 |
| 用户配置编码 | EUC-JP | UTF-8（读取端仍兼容旧配置） |
| Windows 文件系统编码 | Shift_JIS | UTF-8 |
| 错误弹窗 | 模态 `gtk_dialog_run()` | 非模态、按位置去重、总数上限、启动/搜索期间不弹 |
| 外字 / 图片读取失败 | CRITICAL 刷屏，缺失时可能把 NULL 交给 GTK | 降级为 INFO，缺失时安全跳过 |
| 释义区检索 | 需点按钮 | 选中文本后按 Enter 直接检索 |
| 菜单项提示 | 不显示快捷键 | 右侧显示已配置的快捷键 |
| 词典按钮栏 | 单行 | 自动换行 |
| 搜索方法 | 下拉 / 菜单 / 标签页各自维护 | 独立状态机统一驱动 |
| 偏好设置窗口 | 固定较小尺寸 | 自适应放大并考虑屏幕大小 |

此外还修复了 iconv 越界写与多字节序列被切坏、`remove_space()` 重叠拷贝与
越界读、启动卡死、Ctrl+C 段错误、文件搜索结果展示连锁崩溃等问题。

## 目录结构

```
CMakeLists.txt        构建定义
config.h.in           由 CMake 生成的配置头模板
build.sh              一键构建
src/                  源码
data/                 运行时数据（默认配置、ending list 等）
pixmaps/              图标
doc/                  帮助文档（en / ja / zh_CN / zh_TW）
po/                   翻译（ja / zh_CN / zh_TW）
desktop/              桌面入口
tools/pack_win.sh     Windows 打包脚本（MSYS2 UCRT64）
util/ebdump.c         命令行词典导出工具
build/                构建产物（生成）
```

## Windows 构建

`CMakeLists.txt` 已包含 Windows 分支（`WIN32` 子系统、图标与 VERSIONINFO、
`winmm` / `ws2_32` / `iconv` / `gnurx`）。推荐在 MSYS2 UCRT64 环境下用
MinGW-w64 构建，`tools/pack_win.sh` 可收集依赖 DLL 与运行时配置。

## 许可证

GPL-2.0-or-later，见 `COPYING`。原作者須藤賢一，上游版权声明均保留在源码中。
