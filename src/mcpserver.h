#pragma once

#include <QHash>
#include <QJsonObject>
#include <QLocalSocket>
#include <QObject>

// `fireteam mcp`: the agent's end of the field link, an MCP server on stdin
// and stdout that Claude Code starts for each run. Its tools reach the running
// app over a local socket:
//   sitrep           progress for the board, answered at once
//   mark_objective   claims an acceptance criterion met, with evidence
//   request_orders   a question for the operator; waits for the answer
//   authorise        Claude Code's permission prompt (Supervised ROE); waits
class McpServer : public QObject {
    Q_OBJECT

public:
    McpServer(const QString &opId, const QString &socketName, QObject *parent = nullptr);
    ~McpServer() override;
    // Handles one JSON-RPC line from Claude Code.
    void receive(const QByteArray &line);
    // Reads stdin and writes stdout until stdin closes.
    static int run(const QString &opId, const QString &socketName);

signals:
    // One JSON-RPC line for Claude Code.
    void send(const QByteArray &line);

private:
    void respond(const QJsonValue &id, const QJsonObject &result);
    void fail(const QJsonValue &id, int code, const QString &message);
    void callTool(const QJsonValue &id, const QString &name, const QJsonObject &arguments);
    void answered();
    void linkLost();
    QJsonObject textResult(const QString &text, bool error = false) const;

    QString m_op;
    QLocalSocket m_socket;
    // Tool calls waiting on the operator: request id to {rpc id, tool, input}.
    QHash<QString, QJsonObject> m_waiting;
};
