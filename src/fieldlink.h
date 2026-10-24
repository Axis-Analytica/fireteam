#pragma once

#include <QHash>
#include <QJsonObject>
#include <QLocalServer>
#include <QObject>
#include <QPointer>

class QLocalSocket;

// The app's end of the field link: a local socket each agent's `fireteam mcp`
// connects to. Messages are JSON lines. Progress reports are one-way;
// questions and authorisation requests wait for an answer, sent back by id.
class FieldLink : public QObject {
    Q_OBJECT

public:
    explicit FieldLink(const QString &name, QObject *parent = nullptr);
    QString serverName() const { return m_server.fullServerName(); }
    bool listening() const { return m_server.isListening(); }

    // Answers a question or authorisation request; false if its agent has gone.
    bool reply(const QString &requestId, const QJsonObject &answer);

signals:
    void sitrep(const QString &opId, const QString &status, int progress);
    void objective(const QString &opId, int index, bool done, const QString &evidence);
    void question(const QString &opId, const QString &requestId, const QString &text, const QStringList &options);
    void authorise(const QString &opId, const QString &requestId, const QString &tool, const QVariantMap &input);

private:
    void accept();
    void read(QLocalSocket *socket);

    QLocalServer m_server;
    QHash<QString, QPointer<QLocalSocket>> m_pending;
};
