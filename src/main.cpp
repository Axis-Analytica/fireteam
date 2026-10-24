// fireteam: a base camp for running several Claude Code agents through
// development cycles at once, each ending in an HTML debrief.

#include <QGuiApplication>
#include <QLockFile>
#include <QProcess>
#include <csignal>
#include <QIcon>
#include <QJsonDocument>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QUrl>
#include <cstdio>
#include <cstring>

#include "cli.h"
#include "command.h"
#include "folderpicker.h"
#include "notifier.h"
#include "operations.h"
#include "theme.h"
#include "translator.h"

int main(int argc, char *argv[]) {
    const QByteArray command = argc > 1 ? QByteArray(argv[1]) : QByteArray("open");
    const bool cli = Cli::isCommand(command);
    if (!cli && command != "open" && command != "serve") {
        std::fprintf(stderr, "fireteam: unknown command \"%s\". Try fireteam help.\n", command.constData());
        return 1;
    }
    // Only the board needs a display.
    if (command != "open")
        qputenv("QT_QPA_PLATFORM", "offscreen");

    QGuiApplication app(argc, argv);
    app.setApplicationName("fireteam");
    app.setApplicationVersion("0.2.0");
    if (cli)
        return Cli::run(app.arguments());

    // One Fireteam at a time owns the operations: a second open brings the
    // first to the front instead.
    Operations::ensureDataDirectory();
    QLockFile lock(Command::lockPath(Operations::defaultDataDirectory()));
    lock.setStaleLockTime(0);
    if (!lock.tryLock(0)) {
        std::fprintf(stderr, "Fireteam is already running.\n");
        if (command == "open")
            Notifier::focusFireteam();
        return command == "open" ? 0 : 1;
    }

    if (command == "serve") {
        // Operations with no window: the inbox takes commands, and
        // notifications still go out. Ctrl+C or a stop signal ends it cleanly.
        std::signal(SIGINT, [](int) { QCoreApplication::quit(); });
        std::signal(SIGTERM, [](int) { QCoreApplication::quit(); });
        Operations operations;
        Inbox inbox(operations);
        Notifier notifier;
        QObject::connect(&operations, &Operations::alert, &notifier, &Notifier::send);
        std::fprintf(stderr, "Fireteam serving %s. Stop with Ctrl+C.\n",
                     qPrintable(Operations::defaultDataDirectory()));
        return app.exec();
    }

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
    Inbox inbox(operations);
    FolderPicker folderPicker;
    Notifier notifier;
    operations.checkLink();

    QQmlApplicationEngine engine;
    QObject::connect(&translator, &Translator::changed, &engine, &QQmlEngine::retranslate);
    engine.rootContext()->setContextProperty("translator", &translator);
    engine.rootContext()->setContextProperty("theme", &theme);
    engine.rootContext()->setContextProperty("ops", &operations);
    engine.rootContext()->setContextProperty("folderPicker", &folderPicker);
    engine.rootContext()->setContextProperty("notifier", &notifier);
    engine.load(QUrl("qrc:/Main.qml"));
    if (engine.rootObjects().isEmpty())
        return 1;

    return app.exec();
}
