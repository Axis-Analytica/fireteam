#pragma once

#include <QFileSystemWatcher>
#include <QJsonObject>
#include <QObject>
#include <QString>

class Operations;

// What the command line asks of Fireteam, as JSON: {command, op, ...}. The
// same code runs whether the request arrives through the running app's inbox
// or, with no app running, directly on the saved operations.
namespace Command {
// {ok, error?, op?} for one request.
QJsonObject execute(Operations &ops, const QJsonObject &request);
// The commands that need agents running, so only a running Fireteam can do.
bool needsRunningApp(const QString &command);
QString inboxPath(const QString &dataDirectory);
QString lockPath(const QString &dataDirectory);
}

// The running app's side of the inbox: each request file dropped in is
// carried out and answered with a .result file beside it.
class Inbox : public QObject {
    Q_OBJECT

public:
    Inbox(Operations &ops, QObject *parent = nullptr);

private:
    void scan();

    Operations &m_ops;
    QString m_path;
    QFileSystemWatcher m_watcher;
};
