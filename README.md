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

- **`Ctrl+M`**：默认绑定到 `Toggle Menu Bar`，可在「偏好设置 → 快捷键」中改绑
  或删除；加速键挂在窗口上，菜单栏隐藏时依然有效。
- **右键 / 中键点击正文区域 → `Display` → `Menu bar`**。
- 先**完全退出程序**，再编辑 `~/.ebview/preference.xml`，把
  `<show_menu_bar>0</show_menu_bar>` 改成 `1`。必须先退出，否则程序退出时
  `save_preference()` 会把当前状态写回去，覆盖你的修改。

## 常用快捷键（默认值）

| 快捷键 | 功能 |
| --- | --- |
| `Ctrl+N` / `Ctrl+P` | 下一条 / 上一条命中 |
| `Ctrl+1..0` | 开关第 1..10 本词典 |
| `Ctrl+反引号` | 当前组词典全部打开 / 全部关闭 |
| `Alt+1..0` | 只查第 N 本 / 除第 N 本外全查 |
| `Ctrl+=` / `Ctrl+-` | 放大 / 缩小字号 |
| `Ctrl+M` | 显示 / 隐藏菜单栏 |
| `Enter`（正文有选区时） | 检索选中的文字 |

所有命令都可在「偏好设置 → 快捷键」中重新绑定。`~/.ebview/shortcut.xml`
只在首次运行时生成，已有配置不会自动获得新的默认键，需要在该页面手动绑定。

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
| 释义区检索 | 需点按钮 | 选中文本后按 Enter（可重绑）直接检索 |
| 菜单项提示 | 不显示快捷键 | 右侧显示已配置的快捷键 |
| 快捷键 | 部分硬编码（Ctrl+M 等） | 全部由 `shortcut.xml` 驱动，可重绑 |
| 词典按钮栏 | 单行 | 自动换行 |
| 词典批量操作 | 无 | `Ctrl+反引号` 全部开关、`Alt+1..0` 单词典隔离 |
| 词典组编辑 | 单选，逐条上下移动 | 多选整块移动、拖放排序、可取消 |
| 搜索方法 | 下拉 / 菜单 / 标签页各自维护 | 独立状态机统一驱动 |
| 偏好设置窗口 | 固定较小尺寸 | 自适应放大并考虑屏幕大小 |
| 偏好设置离开 | 只能确定 | 确定 / 取消，关闭窗口即放弃修改 |

此外还修复了 iconv 越界写与多字节序列被切坏、`remove_space()` 重叠拷贝与
越界读、启动卡死、Ctrl+C 段错误、文件搜索结果展示连锁崩溃等问题。

## 命令行用法

除了 GUI，本版还提供两个命令行工具，便于在终端或管道里使用。

### `ebview --exact-terminal WORD`

对**当前激活辞典组里的所有辞典**做「完全一致」搜索，把每个命中词条的
EB 流式标记原文（`<gaiji>`、`<indent>`、`<keyword>`、`<sup>` 等）打到
标准输出，然后直接退出、不启动 GUI，也**不会**改动「上次使用的搜索模式」
（`last_search_method`）。设计上刻意保留原始 EB 标记（类似 `sdcv`），
方便用户再用管道（`sed` / `grep` / `awk` / `html2text` 之类）进一步处理。

`--method` / `-m` 可指定启动时的搜索模式（automatic、word、endword、
exactword、keyword、multi、internet、grep）；省略时沿用上次退出时的模式。

```sh
ebview --exact-terminal 日本 | less -R
ebview --method exactword
```

### `ebview-format`（包装脚本）

`tools/ebview-format` 把上面 `--exact-terminal` 的原始输出排版成美观的
终端文本：把 EB 标记转成**语义化颜色 / 加粗**而非简单删掉，外字
`<gaiji code=...>` 显示为 `[code]` 占位（整体不被折行切断），并按显示宽度
（中日韩全角算 2 格）软折行。

| EB 标记 | 终端渲染 |
| --- | --- |
| `<keyword>` | 加粗 + 黄（词头 / 关键词） |
| `<gaiji code=...>` | 品红 `[code]` 占位 |
| `<sup>` / `<sub>` | 青色 + 上标 / 下标字符 |
| `<em>` | 下划线 |
| `<reference>` | 蓝色（交叉引用） |
| `<indent position=N>` | 前导缩进 + 续行对齐 |
| `=== 标题 ===` | 加粗青色 |

用法：

```sh
ebview --exact-terminal 日本 | ebview-format          # 作为过滤器
ebview-format 日本                                      # 直接查词（内部调用 ebview）
ebview-format -w 60 日本                                # 指定折行宽度
ebview-format --no-color 日本 | sed ...                 # 关颜色便于再管道
EBVIEW_BIN=/path/to/ebview ebview-format 日本           # 指定 ebview 路径
```

配套还有 `ebdump`：一个从上游搬来的纯命令行 EB 文本区块底层 dump 工具
（`ebdump <book-path> <subbook-index> <block-number(hex)>`），用于查 EB 光盘
原始字节，不做任何词条解析。

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
`winmm` / `ws2_32` / `iconv` / `gnurx`）。推荐在 MSYS2 环境下用 MinGW-w64 构建。

Windows 免安装包用 `tools/pack_win.sh` 生成，会收集依赖 DLL、gdk-pixbuf 加载器
与 fontconfig 配置。默认按 UCRT64 工具链打包（Windows 10/11）：

```sh
bash tools/pack_win.sh
# -> build/dist/EBView-<version>-gtk3-win64-ucrt64.zip
```

要生成 **Windows 7 可用**的包，需要换 MINGW64 工具链单独编译，并用环境变量
覆盖工具链前缀与构建目录：

```sh
UCRT=/mingw64 BUILD=/e/git/EBView/build-mingw64 \
    bash tools/pack_win.sh E:/git/EBView/build-mingw64/dist
# -> ...-gtk3-win64-mingw64.zip
```

UCRT64 包依赖 `ucrtbase.dll`，只能在 Windows 10 及以上运行；MINGW64 包使用
msvcrt，Windows 7 也能运行。

Windows 上 libeb 4.4.3 还有两个路径问题：`E:\...` 会被当成相对路径，非 ASCII
词典目录会按 ANSI 代码页打开。使用自建 libeb 时需按 `patches/README.md` 应用
两个补丁；MSYS2 预编译包若未包含修复，也会表现为词典组扫描失败。

### 发版清单

版本号只在 `CMakeLists.txt` 的 `VERSION` 一处改，它同时驱动 `PACKAGE_VERSION`、
AppStream 元数据和 Windows 的 VERSIONINFO。

```sh
./build.sh
git commit -am "chore(release): bump version to 0.4.1"
git tag -a v0.4.1 -m "EBView 0.4.1"
git push origin main v0.4.1

bash tools/make_deb.sh
git archive --format=tar --prefix=ebview-0.4.1/ v0.4.1 \
    | xz -9e > build/dist/ebview-0.4.1.tar.xz
```

几个容易踩的点：

- 标签要先打再 `git archive`，否则 `v0.4.1` 解析不到；
- `data/` 下的文件由 `file(COPY ...)` 在 **configure** 阶段拷进
  `build/share/ebview/`，改了 `data/shortcut.xml` 之类必须重跑 `./build.sh`，
  只执行 `cmake --build` 不会刷新；
- 用户配置 `~/.ebview/*.xml` 只在文件缺失时才从安装目录复制，**新增的默认快捷键
  对老用户不生效**，需删文件重新生成或在设置里手动绑定；
- 发布前清掉 `build/dist/` 里的旧版本产物，避免和校验和文件对不上。

## 许可证

GPL-2.0-or-later，见 `COPYING`。原作者須藤賢一，上游版权声明均保留在源码中。
