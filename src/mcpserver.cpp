#include "mcpserver.h"

#include <QCoreApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QThread>
#include <QUuid>
#include <cstdio>
#include <iostream>
#include <string>

McpServer::McpServer(const QString &opId, const QString &socketName, QObject *parent)
    : QObject(parent), m_op(opId) {
    connect(&m_socket, &QLocalSocket::readyRead, this, &McpServer::answered);
    connect(&m_socket, &QLocalSocket::disconnected, this, &McpServer::linkLost);
    m_socket.connectToServer(socketName);
    m_socket.waitForConnected(3000);
}

McpServer::~McpServer() {
    // The socket says goodbye as it's destroyed; nothing here should answer.
    m_socket.disconnect(this);
}

QJsonObject McpServer::textResult(const QString &text, bool error) const {
    QJsonObject result{{"content", QJsonArray{QJsonObject{{"type", "text"}, {"text", text}}}}};
    if (error)
        result.insert("isError", true);
    return result;
}

void McpServer::respond(const QJsonValue &id, const QJsonObject &result) {
    emit send(QJsonDocument(QJsonObject{{"jsonrpc", "2.0"}, {"id", id}, {"result", result}}).toJson(QJsonDocument::Compact));
}

void McpServer::fail(const QJsonValue &id, int code, const QString &message) {
    emit send(QJsonDocument(QJsonObject{{"jsonrpc", "2.0"}, {"id", id},
                                        {"error", QJsonObject{{"code", code}, {"message", message}}}})
                  .toJson(QJsonDocument::Compact));
}

static QJsonArray tools() {
    auto schema = [](const QJsonObject &properties, const QJsonArray &required) {
        return QJsonObject{{"type", "object"}, {"properties", properties}, {"required", required}};
    };
    return {
        QJsonObject{{"name", "sitrep"},
                    {"description", "Report progress to the operator's board: what you're doing now and roughly how far "
                                    "through this cycle's work you are. Call it at real milestones, not every step."},
                    {"inputSchema", schema({{"status", QJsonObject{{"type", "string"}, {"description", "One short line: what's done or happening now."}}},
                                            {"progress", QJsonObject{{"type", "integer"}, {"minimum", 0}, {"maximum", 100},
                                                                     {"description", "Percent of this cycle's work done."}}}},
                                           {"status"})}},
        QJsonObject{{"name", "request_orders"},
                    {"description", "Ask the operator a question and wait for the answer. Only for decisions that are "
                                    "genuinely theirs to make (a direction, a trade-off, missing information), not for "
                                    "permission to run commands. Offer options when you can. If no answer comes in time, "
                                    "you'll be told to use your judgement."},
                    {"inputSchema", schema({{"question", QJsonObject{{"type", "string"}}},
                                            {"options", QJsonObject{{"type", "array"}, {"items", QJsonObject{{"type", "string"}}},
                                                                    {"description", "Suggested answers, best first."}}}},
                                           {"question"})}},
        QJsonObject{{"name", "authorise"},
                    {"description", "Used by Claude Code itself to ask the operator for permission. Don't call it."},
                    {"inputSchema", schema({{"tool_name", QJsonObject{{"type", "string"}}},
                                            {"input", QJsonObject{{"type", "object"}}},
                                            {"tool_use_id", QJsonObject{{"type", "string"}}}},
                                           {"tool_name", "input"})}},
    };
}

void McpServer::receive(const QByteArray &line) {
    const QJsonObject message = QJsonDocument::fromJson(line).object();
    const QString method = message.value("method").toString();
    const QJsonValue id = message.value("id");
    const bool request = message.contains("id");
    if (method == "initialize") {
        const QString version = message.value("params").toObject().value("protocolVersion").toString("2025-06-18");
        respond(id, {{"protocolVersion", version},
                     {"capabilities", QJsonObject{{"tools", QJsonObject{}}}},
                     {"serverInfo", QJsonObject{{"name", "fireteam"}, {"version", QCoreApplication::applicationVersion()}}}});
    } else if (method == "tools/list") {
        respond(id, {{"tools", tools()}});
    } else if (method == "tools/call") {
        const QJsonObject params = message.value("params").toObject();
        callTool(id, params.value("name").toString(), params.value("arguments").toObject());
    } else if (method == "ping") {
        respond(id, {});
    } else if (request && !method.isEmpty()) {
        fail(id, -32601, "Method not found: " + method);
    }
    // Notifications (initialized, cancelled) need no answer.
}

void McpServer::callTool(const QJsonValue &id, const QString &name, const QJsonObject &arguments) {
    const bool linked = m_socket.state() == QLocalSocket::ConnectedState;
    auto deliver = [this](const QJsonObject &message) {
        m_socket.write(QJsonDocument(message).toJson(QJsonDocument::Compact) + "\n");
        m_socket.flush();
    };
    if (name == "sitrep") {
        if (linked)
            deliver({{"type", "sitrep"}, {"op", m_op}, {"status", arguments.value("status").toString()},
                     {"progress", arguments.value("progress").toInt(-1)}});
        respond(id, textResult(linked ? "Logged on the board." : "The board isn't reachable; carry on."));
        return;
    }
    if (name == "request_orders" || name == "authorise") {
        if (!linked) {
            // No operator to ask: questions get "use your judgement", and
            // permission is refused rather than granted unseen.
            respond(id, name == "authorise"
                            ? textResult(QJsonDocument(QJsonObject{{"behavior", "deny"}, {"message", "The operator isn't reachable."}}).toJson(QJsonDocument::Compact))
                            : textResult("The operator isn't reachable. Use your best judgement and note the decision in your debrief."));
            return;
        }
        const QString request = QUuid::createUuid().toString(QUuid::WithoutBraces);
        m_waiting.insert(request, {{"rpc", id}, {"tool", name}, {"input", arguments.value("input")}});
        if (name == "request_orders")
            deliver({{"type", "question"}, {"op", m_op}, {"id", request},
                     {"question", arguments.value("question").toString()}, {"options", arguments.value("options").toArray()}});
        else
            deliver({{"type", "authorise"}, {"op", m_op}, {"id", request},
                     {"tool", arguments.value("tool_name").toString()}, {"input", arguments.value("input").toObject()}});
        return;
    }
    fail(id, -32602, "Unknown tool: " + name);
}

void McpServer::answered() {
    while (m_socket.canReadLine()) {
        const QJsonObject reply = QJsonDocument::fromJson(m_socket.readLine()).object();
        const QJsonObject waiting = m_waiting.take(reply.value("id").toString());
        if (waiting.isEmpty())
            continue;
        if (waiting.value("tool").toString() == "authorise") {
            // Claude Code reads the decision from the tool's text, as JSON.
            QJsonObject decision;
            if (reply.value("behavior").toString() == "allow")
                decision = {{"behavior", "allow"}, {"updatedInput", waiting.value("input")}};
            else
                decision = {{"behavior", "deny"},
                            {"message", reply.value("message").toString("The operator denied this.")}};
            respond(waiting.value("rpc"), textResult(QJsonDocument(decision).toJson(QJsonDocument::Compact)));
        } else {
            respond(waiting.value("rpc"), textResult(reply.value("answer").toString()));
        }
    }
}

void McpServer::linkLost() {
    // The app went away mid-wait: nobody will answer now.
    const auto waiting = m_waiting;
    m_waiting.clear();
    for (const QJsonObject &call : waiting) {
        if (call.value("tool").toString() == "authorise")
            respond(call.value("rpc"), textResult(QJsonDocument(QJsonObject{{"behavior", "deny"}, {"message", "The operator isn't reachable."}}).toJson(QJsonDocument::Compact)));
        else
            respond(call.value("rpc"), textResult("The operator isn't reachable. Use your best judgement."));
    }
}

namespace {
// stdin is read on a thread of its own, so waiting on the operator never
// blocks reading the next request.
class StdinReader : public QThread {
    Q_OBJECT
public:
    using QThread::QThread;
signals:
    void line(const QByteArray &line);
protected:
    void run() override {
        std::string text;
        while (std::getline(std::cin, text))
            emit line(QByteArray::fromStdString(text));
    }
};
}

int McpServer::run(const QString &opId, const QString &socketName) {
    McpServer server(opId, socketName);
    connect(&server, &McpServer::send, [](const QByteArray &line) {
        std::fwrite(line.constData(), 1, size_t(line.size()), stdout);
        std::fputc('\n', stdout);
        std::fflush(stdout);
    });
    StdinReader reader;
    connect(&reader, &StdinReader::line, &server, &McpServer::receive, Qt::QueuedConnection);
    connect(&reader, &QThread::finished, qApp, &QCoreApplication::quit);
    reader.start();
    const int code = QCoreApplication::exec();
    reader.wait(1000);
    return code;
}

#include "mcpserver.moc"
