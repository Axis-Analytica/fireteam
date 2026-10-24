QT += core gui qml quick quickcontrols2 dbus svg

CONFIG += c++17 release
TARGET = fireteam
TEMPLATE = app

HEADERS += src/notifier.h \
    src/operations.h \
    src/stream.h \
    src/folderpicker.h \
    src/theme.h \
    src/translator.h

SOURCES += src/notifier.cpp \
    src/main.cpp \
    src/operations.cpp \
    src/stream.cpp \
    src/folderpicker.cpp \
    src/theme.cpp \
    src/translator.cpp

RESOURCES += src/resources.qrc
