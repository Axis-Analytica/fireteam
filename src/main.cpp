// fireteam: a base camp for running several Claude Code agents through
// development cycles at once, each ending in an HTML debrief.

#include <QGuiApplication>
#include <QIcon>
#include <QJsonDocument>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QUrl>
#include <cstdio>
#include <cstring>

#include "folderpicker.h"
#include "operations.h"
#include "theme.h"
#include "translator.h"

static int status(bool json) {
    Operations operations;
    const QJsonArray array = operations.toJson();
    if (json) {
        std::fputs(QJsonDocument(array).toJson().constData(), stdout);
        return 0;
    }
    for (const auto &value : array) {
        const QJsonObject op = value.toObject();
        std::printf("%-20s %-12s %d/%d  %s\n", op.value("codename").toString().toUtf8().constData(),
                    op.value("status").toString().toUtf8().constData(), op.value("cyclesDone").toInt(),
                    op.value("cycles").toInt(), op.value("directory").toString().toUtf8().constData());
    }
    return 0;
}

int main(int argc, char *argv[]) {
    const QByteArray command = argc > 1 ? QByteArray(argv[1]) : QByteArray("open");
    if (command == "status")
        qputenv("QT_QPA_PLATFORM", "offscreen");
    else if (command != "open") {
        std::fprintf(stderr, "Usage: fireteam [open | status [--json]]\n");
        return 1;
    }

    QGuiApplication app(argc, argv);
    app.setApplicationName("fireteam");
    app.setApplicationVersion("0.1.0");
    if (command == "status")
        return status(argc > 2 && std::strcmp(argv[2], "--json") == 0);

    // Matches the window to fireteam.desktop, so the compositor (Wayland
    // app_id) and the launcher pick up the installed icon.
    app.setDesktopFileName("fireteam");
    app.setWindowIcon(QIcon::fromTheme("fireteam"));

    QQuickStyle::setStyle("Material");

    // Installed before anything is translated, and every qsTr() binding is
    // re-evaluated when the Omarchy language changes.
    Translator translator;
    app.installTranslator(&translator);

    Theme theme;
    Operations operations;
    FolderPicker folderPicker;
    operations.checkLink();

    QQmlApplicationEngine engine;
    QObject::connect(&translator, &Translator::changed, &engine, &QQmlEngine::retranslate);
    engine.rootContext()->setContextProperty("translator", &translator);
    engine.rootContext()->setContextProperty("theme", &theme);
    engine.rootContext()->setContextProperty("ops", &operations);
    engine.rootContext()->setContextProperty("folderPicker", &folderPicker);
    engine.load(QUrl("qrc:/Main.qml"));
    if (engine.rootObjects().isEmpty())
        return 1;

    return app.exec();
}
