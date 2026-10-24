#include "fieldlink.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QLocalSocket>

FieldLink::FieldLink(const QString &name, QObject *parent) : QObject(parent) {
    // Only this user's processes may connect.
    m_server.setSocketOptions(QLocalServer::UserAccessOption);
    QLocalServer::removeServer(name);
    m_server.listen(name);
    connect(&m_server, &QLocalServer::newConnection, this, &FieldLink::accept);
}

void FieldLink::accept() {
    while (QLocalSocket *socket = m_server.nextPendingConnection()) {
        socket->setParent(this);
        connect(socket, &QLocalSocket::readyRead, this, [this, socket] { read(socket); });
        connect(socket, &QLocalSocket::disconnected, socket, &QObject::deleteLater);
    }
}

void FieldLink::read(QLocalSocket *socket) {
    while (socket->canReadLine()) {
        const QJsonObject message = QJsonDocument::fromJson(socket->readLine()).object();
        const QString type = message.value("type").toString();
        const QString op = message.value("op").toString();
        const QString id = message.value("id").toString();
        if (type == "sitrep") {
            emit sitrep(op, message.value("status").toString(), message.value("progress").toInt(-1));
        } else if (type == "question" && !id.isEmpty()) {
            m_pending.insert(id, socket);
            QStringList options;
            for (const auto &option : message.value("options").toArray())
                options << option.toString();
            emit question(op, id, message.value("question").toString(), options);
        } else if (type == "authorise" && !id.isEmpty()) {
            m_pending.insert(id, socket);
            emit authorise(op, id, message.value("tool").toString(), message.value("input").toObject().toVariantMap());
        }
    }
}

bool FieldLink::reply(const QString &requestId, const QJsonObject &answer) {
    QPointer<QLocalSocket> socket = m_pending.take(requestId);
    if (!socket || socket->state() != QLocalSocket::ConnectedState)
        return false;
    QJsonObject message = answer;
    message.insert("id", requestId);
    socket->write(QJsonDocument(message).toJson(QJsonDocument::Compact) + "\n");
    socket->flush();
    return true;
}
