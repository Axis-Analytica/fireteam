QT += network core gui quick quickcontrols2 testlib dbus
CONFIG += c++17 testcase
TARGET = fireteam_tests
TEMPLATE = app

INCLUDEPATH += ../src

HEADERS += ../src/gates.h ../src/fieldlink.h ../src/mcpserver.h ../src/command.h ../src/intel.h ../src/operations.h ../src/stream.h ../src/theme.h ../src/translator.h
SOURCES += fireteam_tests.cpp ../src/gates.cpp ../src/fieldlink.cpp ../src/mcpserver.cpp ../src/command.cpp ../src/intel.cpp ../src/operations.cpp ../src/stream.cpp ../src/theme.cpp ../src/translator.cpp
RESOURCES += fakeclaude.qrc
