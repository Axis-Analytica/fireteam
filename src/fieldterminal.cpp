#include "fieldterminal.h"
#include "operations.h"

#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QNetworkAccessManager>
#include <QNetworkInterface>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcess>
#include <QRandomGenerator>
#include <QSaveFile>
#include <QStandardPaths>
#include <QTcpSocket>
#include <QUrl>
#include <QUrlQuery>

// Requests bigger than this are refused: the API takes a sentence or two.
static constexpr int RequestLimit = 64 * 1024;

FieldTerminal::FieldTerminal(Operations &ops, const QString &dataDirectory, QObject *parent)
    : QObject(parent), m_ops(ops), m_path(dataDirectory + "/terminal.json") {
    load();
    connect(&m_server, &QTcpServer::newConnection, this, &FieldTerminal::accept);
    // Phones are told something changed at most a couple of times a second,
    // and fetch what they need.
    m_notice.setSingleShot(true);
    m_notice.setInterval(400);
    connect(&m_notice, &QTimer::timeout, this, &FieldTerminal::broadcast);
    connect(&ops, &QAbstractItemModel::dataChanged, &m_notice, qOverload<>(&QTimer::start));
    connect(&ops, &QAbstractItemModel::rowsInserted, &m_notice, qOverload<>(&QTimer::start));
    connect(&ops, &QAbstractItemModel::rowsRemoved, &m_notice, qOverload<>(&QTimer::start));
    connect(&ops, &Operations::campaignsChanged, &m_notice, qOverload<>(&QTimer::start));
    // Comment lines keep idle streams open through proxies and sleep.
    m_keepalive.setInterval(20000);
    connect(&m_keepalive, &QTimer::timeout, this, [this] {
        for (const auto &stream : std::as_const(m_streams))
            if (stream)
                stream->write(": keepalive\n\n");
    });
    m_keepalive.start();
    if (m_enabled)
        listen();
}

FieldTerminal::~FieldTerminal() { m_server.close(); }

void FieldTerminal::load() {
    QFile file(m_path);
    QJsonObject settings;
    if (file.open(QIODevice::ReadOnly))
        settings = QJsonDocument::fromJson(file.readAll()).object();
    m_enabled = settings.value("enabled").toBool(false);
    m_lan = settings.value("lan").toBool(false);
    m_port = qBound(1024, settings.value("port").toInt(7788), 65535);
    m_token = settings.value("token").toString();
    m_ntfy = settings.value("ntfy").toString();
    if (m_token.size() < 32)
        newToken();
}

void FieldTerminal::save() const {
    QSaveFile file(m_path);
    if (!file.open(QIODevice::WriteOnly))
        return;
    file.write(QJsonDocument(QJsonObject{{"enabled", m_enabled}, {"lan", m_lan}, {"port", m_port},
                                         {"token", m_token}, {"ntfy", m_ntfy}}).toJson());
    file.commit();
    // The token is a key to the operations: only this user may read it.
    QFile::setPermissions(m_path, QFile::ReadOwner | QFile::WriteOwner);
}

void FieldTerminal::newToken() {
    QByteArray bytes(24, Qt::Uninitialized);
    QRandomGenerator::system()->fillRange(reinterpret_cast<quint32 *>(bytes.data()), bytes.size() / 4);
    m_token = QString::fromLatin1(bytes.toHex());
    // Paired phones lose their streams with the old token.
    for (const auto &stream : std::as_const(m_streams))
        if (stream)
            stream->close();
    m_streams.clear();
    save();
    emit changed();
    emit clientsChanged();
}

void FieldTerminal::setEnabled(bool enabled) {
    if (enabled == m_enabled)
        return;
    m_enabled = enabled;
    save();
    if (enabled) {
        listen();
    } else {
        m_server.close();
        for (const auto &stream : std::as_const(m_streams))
            if (stream)
                stream->close();
        m_streams.clear();
        emit clientsChanged();
    }
    emit changed();
}

void FieldTerminal::setLan(bool lan) {
    if (lan == m_lan)
        return;
    m_lan = lan;
    save();
    if (m_enabled)
        listen();
    emit changed();
}

void FieldTerminal::setPort(int port) {
    port = qBound(1024, port, 65535);
    if (port == m_port)
        return;
    m_port = port;
    save();
    if (m_enabled)
        listen();
    emit changed();
}

void FieldTerminal::setNtfyUrl(const QString &url) {
    if (url.trimmed() == m_ntfy)
        return;
    m_ntfy = url.trimmed();
    save();
    emit changed();
}

void FieldTerminal::listen() {
    m_server.close();
    m_error.clear();
    // A port of 0 in the environment picks a free one (tests).
    const int port = qEnvironmentVariableIsSet("FIRETEAM_TERMINAL_PORT") ? qEnvironmentVariableIntValue("FIRETEAM_TERMINAL_PORT") : m_port;
    if (!m_server.listen(m_lan ? QHostAddress::AnyIPv4 : QHostAddress::LocalHost, quint16(port)))
        m_error = tr("Couldn't listen on port %1: %2").arg(port).arg(m_server.errorString());
    emit changed();
}

QStringList FieldTerminal::addresses() const {
    if (!listening())
        return {};
    const QString port = QString::number(m_server.serverPort());
    if (!m_lan)
        return {"http://127.0.0.1:" + port};
    QStringList list;
    for (const QHostAddress &address : QNetworkInterface::allAddresses())
        if (address.protocol() == QAbstractSocket::IPv4Protocol && !address.isLoopback())
            list << "http://" + address.toString() + ":" + port;
    return list.isEmpty() ? QStringList{"http://127.0.0.1:" + port} : list;
}

QString FieldTerminal::pairingUrl() const {
    const QStringList list = addresses();
    // The token rides in the fragment, which browsers never send to servers.
    return list.isEmpty() ? QString() : list.first() + "/#" + m_token;
}

QString FieldTerminal::pairingCode() const {
    const QString url = pairingUrl();
    const QString qrencode = QStandardPaths::findExecutable("qrencode");
    if (url.isEmpty() || qrencode.isEmpty())
        return {};
    QProcess process;
    process.start(qrencode, {"-t", "SVG", "-m", "1", "--foreground=000000", "--background=FFFFFF", "-o", "-", url});
    if (!process.waitForFinished(3000) || process.exitCode() != 0)
        return {};
    return "data:image/svg+xml;base64," + QString::fromLatin1(process.readAllStandardOutput().toBase64());
}

void FieldTerminal::accept() {
    while (QTcpSocket *socket = m_server.nextPendingConnection()) {
        connect(socket, &QTcpSocket::readyRead, this, [this, socket] { read(socket); });
        connect(socket, &QTcpSocket::disconnected, this, [this, socket] {
            m_buffers.remove(socket);
            const qsizetype before = m_streams.size();
            m_streams.removeIf([socket](const QPointer<QTcpSocket> &s) { return !s || s == socket; });
            if (m_streams.size() != before)
                emit clientsChanged();
            socket->deleteLater();
        });
    }
}

void FieldTerminal::read(QTcpSocket *socket) {
    QByteArray &buffer = m_buffers[socket];
    buffer += socket->readAll();
    if (buffer.size() > RequestLimit) {
        reply(socket, 413, "text/plain", "Too large");
        return;
    }
    const qsizetype end = buffer.indexOf("\r\n\r\n");
    if (end < 0)
        return;
    Request request;
    const QList<QByteArray> lines = buffer.left(end).split('\n');
    const QList<QByteArray> first = lines.value(0).trimmed().split(' ');
    request.method = QString::fromLatin1(first.value(0));
    const QUrl url(QString::fromUtf8(first.value(1)));
    request.path = url.path();
    for (const auto &item : QUrlQuery(url).queryItems(QUrl::FullyDecoded))
        request.query.insert(item.first, item.second);
    for (qsizetype i = 1; i < lines.size(); ++i) {
        const qsizetype colon = lines.at(i).indexOf(':');
        if (colon > 0)
            request.headers.insert(QString::fromLatin1(lines.at(i).left(colon)).trimmed().toLower(),
                                   QString::fromUtf8(lines.at(i).mid(colon + 1)).trimmed());
    }
    const int length = request.headers.value("content-length").toInt();
    if (buffer.size() < end + 4 + length)
        return;
    request.body = buffer.mid(end + 4, length);
    m_buffers.remove(socket);
    handle(socket, request);
}

bool FieldTerminal::authorised(const Request &request) const {
    QString offered = request.headers.value("authorization");
    if (offered.startsWith("Bearer "))
        offered = offered.mid(7).trimmed();
    else
        offered = request.query.value("token");
    // Compared in constant time, so timing gives nothing away.
    const QByteArray a = QCryptographicHash::hash(offered.toUtf8(), QCryptographicHash::Sha256);
    const QByteArray b = QCryptographicHash::hash(m_token.toUtf8(), QCryptographicHash::Sha256);
    unsigned char difference = 0;
    for (int i = 0; i < a.size(); ++i)
        difference |= static_cast<unsigned char>(a.at(i) ^ b.at(i));
    return difference == 0 && !m_token.isEmpty();
}

void FieldTerminal::reply(QTcpSocket *socket, int status, const QByteArray &type, const QByteArray &body) {
    static const QHash<int, QByteArray> reasons{{200, "OK"}, {400, "Bad Request"}, {401, "Unauthorized"},
                                                {404, "Not Found"}, {405, "Method Not Allowed"}, {409, "Conflict"},
                                                {413, "Payload Too Large"}};
    QByteArray head = "HTTP/1.1 " + QByteArray::number(status) + " " + reasons.value(status, "Error") + "\r\n";
    head += "Content-Type: " + type + "\r\nContent-Length: " + QByteArray::number(body.size()) + "\r\n";
    // The page is ours alone: no framing, no sniffing, no caching of data.
    head += "X-Frame-Options: DENY\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-store\r\n"
            "Referrer-Policy: no-referrer\r\nConnection: close\r\n\r\n";
    socket->write(head + body);
    socket->disconnectFromHost();
}

void FieldTerminal::replyJson(QTcpSocket *socket, int status, const QJsonObject &body) {
    reply(socket, status, "application/json", QJsonDocument(body).toJson(QJsonDocument::Compact));
}

void FieldTerminal::handle(QTcpSocket *socket, const Request &request) {
    if (request.method == "GET" && (request.path == "/" || request.path == "/index.html")) {
        QFile page(":/web/index.html");
        if (!page.open(QIODevice::ReadOnly)) {
            reply(socket, 404, "text/plain", "The dashboard isn't in this build.");
            return;
        }
        reply(socket, 200, "text/html; charset=utf-8", page.readAll());
        return;
    }
    if (!request.path.startsWith("/api/")) {
        reply(socket, 404, "text/plain", "Not found");
        return;
    }
    if (!authorised(request)) {
        replyJson(socket, 401, {{"error", "Pair this device first: scan the code in Fireteam."}});
        return;
    }
    if (request.method == "GET" && request.path == "/api/state") {
        replyJson(socket, 200, state());
        return;
    }
    if (request.method == "GET" && request.path == "/api/events") {
        // A stream of "something changed" events, kept open.
        socket->write("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-store\r\n"
                      "X-Accel-Buffering: no\r\nConnection: keep-alive\r\n\r\nretry: 3000\n\nevent: update\ndata: {}\n\n");
        m_streams << socket;
        emit clientsChanged();
        return;
    }
    // /api/op/<id> and /api/op/<id>/<action>
    const QStringList parts = request.path.split('/', Qt::SkipEmptyParts);
    if (parts.size() >= 3 && parts.at(1) == "op") {
        const int row = m_ops.rowOfId(parts.at(2));
        if (row < 0) {
            replyJson(socket, 404, {{"error", "No such operation."}});
            return;
        }
        if (parts.size() == 3 && request.method == "GET") {
            replyJson(socket, 200, operation(row));
            return;
        }
        if (parts.size() == 4 && request.method == "POST") {
            const QJsonObject result = act(row, parts.at(3), QJsonDocument::fromJson(request.body).object());
            replyJson(socket, result.contains("error") ? 409 : 200, result);
            return;
        }
        replyJson(socket, 405, {{"error", "Not allowed."}});
        return;
    }
    replyJson(socket, 404, {{"error", "Not found."}});
}

QJsonObject FieldTerminal::operation(int row) const {
    const Operation &op = m_ops.at(row);
    QJsonObject object{{"id", op.id}, {"codename", op.codename}, {"status", op.status}, {"objective", op.objective},
                       {"directory", op.directory}, {"cyclesDone", op.cyclesDone}, {"cycles", op.cycles},
                       {"model", op.model}, {"roe", op.roe}, {"activity", op.activity}, {"progress", op.progress},
                       {"progressNote", op.progressNote}, {"sitrep", op.sitrep}, {"cost", op.costUsd},
                       {"context", double(op.contextTokens)}, {"hold", op.hold},
                       {"questions", QJsonArray::fromVariantList(op.questions)},
                       {"prompts", QJsonArray::fromVariantList(op.prompts)},
                       {"requests", QJsonArray::fromVariantList(op.requests)},
                       {"criteria", QJsonArray::fromVariantList(op.criteria)},
                       {"orders", QJsonArray::fromStringList(op.orders)}};
    for (qsizetype i = op.history.size() - 1; i >= 0; --i)
        if (op.history.at(i).toMap().contains("gates")) {
            object.insert("gates", QJsonArray::fromVariantList(op.history.at(i).toMap().value("gates").toList()));
            break;
        }
    if (!op.reviews.isEmpty())
        object.insert("review", QJsonObject::fromVariantMap(op.reviews.last().toMap()));
    QJsonArray comms;
    for (qsizetype i = qMax<qsizetype>(0, op.comms.size() - 40); i < op.comms.size(); ++i)
        comms.append(QJsonObject::fromVariantMap(op.comms.at(i).toMap()));
    object.insert("comms", comms);
    return object;
}

QJsonObject FieldTerminal::state() const {
    QJsonArray operations;
    for (int row = 0; row < m_ops.rowCount(); ++row) {
        const Operation &op = m_ops.at(row);
        operations.append(QJsonObject{{"id", op.id}, {"codename", op.codename}, {"status", op.status},
                                      {"cyclesDone", op.cyclesDone}, {"cycles", op.cycles}, {"activity", op.activity},
                                      {"progress", op.progress}, {"cost", op.costUsd},
                                      {"waiting", int(op.questions.size() + op.prompts.size())},
                                      {"requests", int(op.requests.size())}});
    }
    return {{"operations", operations}, {"deployed", m_ops.deployedCount()}, {"maxDeployed", m_ops.maxDeployed()},
            {"usage", QJsonObject::fromVariantMap(m_ops.usage())}};
}

QJsonObject FieldTerminal::act(int row, const QString &action, const QJsonObject &body) {
    const QString status = m_ops.at(row).status;
    if (action == "order") {
        const QString text = body.value("text").toString().trimmed();
        if (text.isEmpty())
            return {{"error", "The order is empty."}};
        m_ops.sendOrders(row, text, false);
    } else if (action == "hold") {
        if (status != "deployed")
            return {{"error", "It isn't deployed."}};
        m_ops.setHold(row, !m_ops.at(row).hold);
    } else if (action == "abort") {
        if (status != "deployed" && status != "staged" && status != "pinned")
            return {{"error", "It isn't deployed or queued."}};
        m_ops.abort(row);
    } else if (action == "resume") {
        // Picking up a held operation; new work is planned at the desk.
        if (status != "held")
            return {{"error", "Only a held operation can be resumed from here."}};
        m_ops.deploy(row);
    } else if (action == "answer") {
        if (!m_ops.answer(row, body.value("id").toString(), body.value("text").toString()))
            return {{"error", "That question has gone."}};
    } else if (action == "decide") {
        if (!m_ops.decide(row, body.value("id").toString(), body.value("decision").toString(), body.value("rule").toInt()))
            return {{"error", "That request has gone."}};
    } else if (action == "approve") {
        if (!m_ops.approve(row, body.value("request").toInt(), body.value("rule").toInt(), false))
            return {{"error", "That request has gone."}};
    } else if (action == "deny") {
        m_ops.deny(row, body.value("request").toInt());
    } else {
        return {{"error", "Unknown action."}};
    }
    return {{"ok", true}, {"op", operation(m_ops.rowOfId(m_ops.at(row).id))}};
}

void FieldTerminal::broadcast() {
    for (const auto &stream : std::as_const(m_streams))
        if (stream)
            stream->write("event: update\ndata: {}\n\n");
}

void FieldTerminal::push(const QString &title, const QString &body) {
    const QUrl url(m_ntfy);
    if (m_ntfy.isEmpty() || !url.isValid() || (url.scheme() != "https" && url.scheme() != "http"))
        return;
    if (!m_network)
        m_network = new QNetworkAccessManager(this);
    QNetworkRequest request(url);
    // ntfy headers carry only Latin-1, so the title goes as plain ASCII.
    request.setRawHeader("Title", title.toLatin1());
    request.setRawHeader("Tags", "dart");
    QNetworkReply *reply = m_network->post(request, body.toUtf8());
    connect(reply, &QNetworkReply::finished, reply, &QObject::deleteLater);
}

void FieldTerminal::testPush() {
    push("Fireteam", tr("Field terminal test: alerts will arrive here."));
}
