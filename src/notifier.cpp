#include "notifier.h"

#include <QProcess>
#include <QStandardPaths>

Notifier::Notifier(QObject *parent)
    : QObject(parent), m_notifySend(QStandardPaths::findExecutable("notify-send")) {}

void Notifier::send(const QString &opId, const QString &title, const QString &body) {
    if (m_notifySend.isEmpty())
        return;
    // An action keeps notify-send running until the notification closes and
    // prints the action picked. mako invokes "default" on a click.
    auto *process = new QProcess(this);
    connect(process, &QProcess::finished, this, [this, process, opId] {
        if (process->readAllStandardOutput().trimmed() == "default") {
            QProcess::startDetached("hyprctl", {"dispatch", "focuswindow", "class:fireteam"});
            emit activated(opId);
        }
        process->deleteLater();
    });
    connect(process, &QProcess::errorOccurred, process, &QObject::deleteLater);
    process->start(m_notifySend, {"--app-name=Fireteam", "--icon=fireteam", "--wait", "--action=default=Open",
                                  title, body.left(300)});
}
