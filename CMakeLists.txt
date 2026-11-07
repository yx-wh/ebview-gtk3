cmake_minimum_required(VERSION 3.16)

project(ebview
    VERSION 0.4.0
    DESCRIPTION "EPWING CD-ROM dictionary viewer (GTK3 port, modernized build)"
    LANGUAGES C)

# Needed to compile the .rc that embeds the application icon into the
# executable.  Unix ports get the icon from the installed desktop files.
if(WIN32)
    enable_language(RC)
endif()

# Export build/compile_commands.json so clangd/IDE can resolve the
# generated config.h and the GTK/GLib include paths.
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

include(GNUInstallDirs)
include(CheckIncludeFile)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_EXTENSIONS ON)
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

# The GTK3 port still calls a few deprecated entry points (gtk_rc_parse and
# friends).  Keep the build warning-clean without hiding real errors.
add_compile_options(-Wall -Wno-deprecated-declarations)

find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK3 REQUIRED IMPORTED_TARGET gtk+-3.0>=3.0)
pkg_check_modules(PANGOCAIRO REQUIRED IMPORTED_TARGET pangocairo)
find_package(Threads REQUIRED)
find_package(ZLIB REQUIRED)

# libeb (EB Library / "eb") has never shipped a .pc file.
find_path(EB_INCLUDE_DIR NAMES eb/eb.h)
find_library(EB_LIBRARY NAMES eb)
if(NOT EB_INCLUDE_DIR OR NOT EB_LIBRARY)
    message(FATAL_ERROR "EB Library development files not found (install libeb16-dev)")
endif()

find_library(INTL_LIBRARY NAMES intl)
find_program(MSGFMT_EXECUTABLE msgfmt)

set(PACKAGE "ebview")
set(PACKAGE_NAME "EBView")
set(PACKAGE_VERSION "${PROJECT_VERSION}")
set(PACKAGE_STRING "EBView ${PROJECT_VERSION}")
# data/about.en.in and data/about.jp.in use @VERSION@.
set(VERSION "${PROJECT_VERSION}")
set(GETTEXT_PACKAGE "ebview")
set(LOCALEDIR "${CMAKE_INSTALL_FULL_LOCALEDIR}")
set(PACKAGEDIR "${CMAKE_INSTALL_FULL_DATADIR}/ebview")

foreach(_hdr unistd.h fcntl.h sys/ioctl.h sys/time.h iconv.h libintl.h dirent.h)
    string(TOUPPER "${_hdr}" _var)
    string(REGEX REPLACE "[/.]" "_" _var "HAVE_${_var}")
    check_include_file("${_hdr}" ${_var})
endforeach()

configure_file(config.h.in "${CMAKE_CURRENT_BINARY_DIR}/config.h" @ONLY)
file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/data")
configure_file(data/about.en.in "${CMAKE_CURRENT_BINARY_DIR}/data/about.en" @ONLY)
configure_file(data/about.jp.in "${CMAKE_CURRENT_BINARY_DIR}/data/about.jp" @ONLY)
configure_file(data/about.zh.in "${CMAKE_CURRENT_BINARY_DIR}/data/about.zh" @ONLY)
configure_file(data/about.zh_TW.in "${CMAKE_CURRENT_BINARY_DIR}/data/about.zh_TW" @ONLY)
# AppStream metadata: the release version tracks PROJECT_VERSION so the
# software centre never shows a stale version.
configure_file(data/ebview.metainfo.xml.in
    "${CMAKE_CURRENT_BINARY_DIR}/data/ebview.metainfo.xml" @ONLY)

# ebview-client.c is an unfinished standalone remote-client experiment from
# upstream; it was never part of the original Makefile.am target either.
file(GLOB EBVIEW_SOURCES CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/src/*.c")
list(REMOVE_ITEM EBVIEW_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/src/ebview-client.c")

# WIN32 => link as a GUI-subsystem executable (-mwindows on MinGW).  EBView is
# a GUI app, not a console tool; a GUI-subsystem build has no console window.
add_executable(ebview WIN32 ${EBVIEW_SOURCES})
target_include_directories(ebview PRIVATE
    "${CMAKE_CURRENT_BINARY_DIR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
    "${EB_INCLUDE_DIR}")

# libeb is configured with autoconf's AC_SYS_LARGEFILE, which puts
# _FILE_OFFSET_BITS=64 into its config.h.  That macro widens off_t to 64 bits,
# and EB_Text_Context stores an off_t, so it changes the *binary layout* of
# every EB_Book the library touches.  eb/defs.h is compiled into the client,
# so a client built without the same macro allocates a short EB_Book and
# eb_initialize_book() then writes past the end of it.  Keep this in sync with
# whatever libeb itself was built with.
target_compile_definitions(ebview PRIVATE _FILE_OFFSET_BITS=64)

target_link_libraries(ebview PRIVATE
    PkgConfig::GTK3
    PkgConfig::PANGOCAIRO
    ${EB_LIBRARY}
    ZLIB::ZLIB
    Threads::Threads
    m)
if(INTL_LIBRARY)
    target_link_libraries(ebview PRIVATE ${INTL_LIBRARY})
endif()

# This GTK3 port still calls a handful of raw X11 entry points
# (XIconifyWindow / DefaultScreen in shortcutfunc.c, plus gdk_x11_* helpers).
# gtk+-3.0 does not pull libX11 in transitively, so link it explicitly on X11
# platforms; Windows takes the __WIN32__ branches and needs no X11 at all.
if(NOT WIN32)
    find_package(X11 REQUIRED)
    target_link_libraries(ebview PRIVATE X11::X11)
endif()

# util/ebdump is a small command-line companion shipped by this port.  Unlike
# the GUI binary it must stay a console application, so no WIN32 flag here.
add_executable(ebdump "${CMAKE_CURRENT_SOURCE_DIR}/util/ebdump.c")
target_include_directories(ebdump PRIVATE
    "${CMAKE_CURRENT_BINARY_DIR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
    "${EB_INCLUDE_DIR}")
target_compile_definitions(ebdump PRIVATE _FILE_OFFSET_BITS=64)
target_link_libraries(ebdump PRIVATE
    PkgConfig::GTK3
    ${EB_LIBRARY}
    ZLIB::ZLIB
    Threads::Threads
    m)
if(INTL_LIBRARY)
    target_link_libraries(ebdump PRIVATE ${INTL_LIBRARY})
endif()

# Embed the application icon and a VERSIONINFO block in the executable.
# windres runs with the build directory as its working directory, so the
# autotools-era relative path "../pixmaps/ebview.ico" would not resolve.
if(WIN32)
    set(EBVIEW_ICON_FILE "${CMAKE_CURRENT_SOURCE_DIR}/pixmaps/ebview.ico")

    # VERSIONINFO wants four comma separated 16-bit numbers; the tweak
    # component is empty for a three-component PROJECT_VERSION.
    set(EBVIEW_VERSION_TWEAK "${PROJECT_VERSION_TWEAK}")
    if(EBVIEW_VERSION_TWEAK STREQUAL "")
        set(EBVIEW_VERSION_TWEAK 0)
    endif()
    set(EBVIEW_VERSION_COMMA
        "${PROJECT_VERSION_MAJOR},${PROJECT_VERSION_MINOR},${PROJECT_VERSION_PATCH},${EBVIEW_VERSION_TWEAK}")

    configure_file("${CMAKE_CURRENT_SOURCE_DIR}/src/ebview.rc.in"
        "${CMAKE_CURRENT_BINARY_DIR}/ebview.rc" @ONLY)
    target_sources(ebview PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/ebview.rc")
endif()

# Windows-specific system/compatibility libraries:
#   winmm   - MCI multimedia (external.c: mciSendCommand)
#   ws2_32  - Winsock, needed by libeb built with EBNET support
#   iconv   - GNU libiconv (jcode.c)
#   gnurx   - POSIX regex (reg.c: regcomp / regexec / regfree)
# On Linux none of these exist: glibc provides iconv/regex and the shared
# libeb already records its own dependencies.
if(WIN32)
    target_link_libraries(ebview PRIVATE winmm ws2_32 iconv gnurx)
    target_link_libraries(ebdump PRIVATE ws2_32 iconv gnurx)
endif()

# Stage a runtime data tree in the build dir so the app can be launched
# straight after compiling; locate_package_dir() finds it automatically.
set(EBVIEW_RUN_DATADIR "${CMAKE_CURRENT_BINARY_DIR}/share/ebview")
file(MAKE_DIRECTORY "${EBVIEW_RUN_DATADIR}/help")
file(COPY
    "${CMAKE_CURRENT_SOURCE_DIR}/data/endinglist.xml"
    "${CMAKE_CURRENT_SOURCE_DIR}/data/endinglist-ja.xml"
    "${CMAKE_CURRENT_SOURCE_DIR}/data/filter.xml"
    "${CMAKE_CURRENT_SOURCE_DIR}/data/searchengines.xml"
    "${CMAKE_CURRENT_SOURCE_DIR}/data/shortcut.xml"
    "${CMAKE_CURRENT_SOURCE_DIR}/data/gtkrc"
    DESTINATION "${EBVIEW_RUN_DATADIR}")
file(COPY
    "${CMAKE_CURRENT_BINARY_DIR}/data/about.en"
    "${CMAKE_CURRENT_BINARY_DIR}/data/about.jp"
    "${CMAKE_CURRENT_BINARY_DIR}/data/about.zh"
    "${CMAKE_CURRENT_BINARY_DIR}/data/about.zh_TW"
    DESTINATION "${EBVIEW_RUN_DATADIR}")
file(COPY "${CMAKE_CURRENT_SOURCE_DIR}/pixmaps/" DESTINATION "${EBVIEW_RUN_DATADIR}/pixmaps")
foreach(_doc_lang en ja zh_CN zh_TW)
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/doc/${_doc_lang}")
        file(COPY "${CMAKE_CURRENT_SOURCE_DIR}/doc/${_doc_lang}" DESTINATION "${EBVIEW_RUN_DATADIR}/help")
    endif()
endforeach()

# Translations
if(MSGFMT_EXECUTABLE)
    set(EBVIEW_LINGUAS ja zh_CN zh_TW)
    set(_mos "")
    foreach(_lang ${EBVIEW_LINGUAS})
        if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/po/${_lang}.po")
            set(_mo "${CMAKE_CURRENT_BINARY_DIR}/locale/${_lang}/LC_MESSAGES/${GETTEXT_PACKAGE}.mo")
            add_custom_command(OUTPUT "${_mo}"
                COMMAND ${CMAKE_COMMAND} -E make_directory
                    "${CMAKE_CURRENT_BINARY_DIR}/locale/${_lang}/LC_MESSAGES"
                COMMAND ${MSGFMT_EXECUTABLE} -o "${_mo}"
                    "${CMAKE_CURRENT_SOURCE_DIR}/po/${_lang}.po"
                DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/po/${_lang}.po"
                COMMENT "Compiling ${_lang} translation")
            list(APPEND _mos "${_mo}")
            install(FILES "${_mo}"
                DESTINATION "${CMAKE_INSTALL_LOCALEDIR}/${_lang}/LC_MESSAGES")
        endif()
    endforeach()
    if(_mos)
        add_custom_target(translations ALL DEPENDS ${_mos})
    endif()
endif()

install(TARGETS ebview ebdump RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})

# ebview-format — a Python wrapper that pretty-prints the raw EB streaming
# output of `ebview --exact-terminal` (ANSI colors / bold, gaiji placeholders,
# wrap by display width).  It is interpreted, so we just install it executable.
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/tools/ebview-format"
    DESTINATION "${CMAKE_INSTALL_BINDIR}"
    PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE
                GROUP_READ GROUP_EXECUTE
                WORLD_READ WORLD_EXECUTE)

install(FILES
    "${CMAKE_CURRENT_BINARY_DIR}/data/about.en"
    "${CMAKE_CURRENT_BINARY_DIR}/data/about.jp"
    "${CMAKE_CURRENT_BINARY_DIR}/data/about.zh"
    "${CMAKE_CURRENT_BINARY_DIR}/data/about.zh_TW"
    "${CMAKE_CURRENT_SOURCE_DIR}/data/endinglist.xml"
    "${CMAKE_CURRENT_SOURCE_DIR}/data/endinglist-ja.xml"
    "${CMAKE_CURRENT_SOURCE_DIR}/data/filter.xml"
    "${CMAKE_CURRENT_SOURCE_DIR}/data/searchengines.xml"
    "${CMAKE_CURRENT_SOURCE_DIR}/data/shortcut.xml"
    "${CMAKE_CURRENT_SOURCE_DIR}/data/gtkrc"
    DESTINATION "${CMAKE_INSTALL_DATADIR}/ebview")
install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/pixmaps/"
    DESTINATION "${CMAKE_INSTALL_DATADIR}/ebview/pixmaps")
foreach(_doc_lang en ja zh_CN zh_TW)
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/doc/${_doc_lang}")
        install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/doc/${_doc_lang}"
            DESTINATION "${CMAKE_INSTALL_DATADIR}/ebview/help")
    endif()
endforeach()

# The hicolor theme is where desktop shells look up Icon=ebview.
install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/pixmaps/hicolor/"
    DESTINATION "${CMAKE_INSTALL_DATADIR}/icons/hicolor")
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/pixmaps/ebview.svg"
    DESTINATION "${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps")
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/desktop/ebview.desktop"
    DESTINATION "${CMAKE_INSTALL_DATADIR}/applications")
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/data/ebview.metainfo.xml"
    DESTINATION "${CMAKE_INSTALL_DATADIR}/metainfo")
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/pixmaps/ebview.xpm"
    DESTINATION "${CMAKE_INSTALL_DATADIR}/pixmaps")
install(FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/README.md"
    "${CMAKE_CURRENT_SOURCE_DIR}/README.ja"
    DESTINATION "${CMAKE_INSTALL_DOCDIR}" OPTIONAL)

message(STATUS "EBView ${PROJECT_VERSION} (GTK3)")
message(STATUS "  GTK         : ${GTK3_VERSION}")
message(STATUS "  EB library  : ${EB_LIBRARY}")
message(STATUS "  Data dir    : ${PACKAGEDIR}")
message(STATUS "  Run datadir : ${EBVIEW_RUN_DATADIR}")

# clangd looks for compile_commands.json in the source tree itself, not in
# build/. Mirror the generated database at the project root so IDE
# diagnostics resolve config.h and the GTK/GLib headers out of the box.
set(_db_link "${CMAKE_SOURCE_DIR}/compile_commands.json")
if(IS_SYMLINK "${_db_link}" OR EXISTS "${_db_link}")
    file(REMOVE "${_db_link}")
endif()
file(CREATE_LINK "${CMAKE_BINARY_DIR}/compile_commands.json" "${_db_link}"
     SYMBOLIC RESULT _db_link_result)
