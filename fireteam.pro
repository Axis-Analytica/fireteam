QT += core gui qml quick quickcontrols2 dbus svg network

CONFIG += c++17 release
TARGET = fireteam
TEMPLATE = app

HEADERS += src/notifier.h \
    src/fieldmanual.h \
    src/graphs.h \
    src/fieldterminal.h \
    src/gates.h \
    src/fieldlink.h \
    src/mcpserver.h \
    src/cli.h \
    src/command.h \
    src/intel.h \
    src/operations.h \
    src/stream.h \
    src/folderpicker.h \
    src/theme.h \
    src/translator.h

SOURCES += src/notifier.cpp \
    src/fieldmanual.cpp \
    src/graphs.cpp \
    src/archive.cpp \
    src/fieldterminal.cpp \
    src/gates.cpp \
    src/fieldlink.cpp \
    src/mcpserver.cpp \
    src/cli.cpp \
    src/command.cpp \
    src/intel.cpp \
    src/main.cpp \
    src/operations.cpp \
    src/stream.cpp \
    src/folderpicker.cpp \
    src/theme.cpp \
    src/translator.cpp

RESOURCES += src/resources.qrc
