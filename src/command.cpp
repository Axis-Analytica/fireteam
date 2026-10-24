#include "command.h"
#include "operations.h"

#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QSaveFile>
#include <QTimer>

namespace Command {

QString inboxPath(const QString &dataDirectory) { return dataDirectory + "/inbox"; }
QString lockPath(const QString &dataDirectory) { return dataDirectory + "/fireteam.lock"; }

bool needsRunningApp(const QString &command) {
    return QStringList{"deploy", "hold", "abort", "extract", "discard"}.contains(command);
}

static QJsonObject failure(const QString &error) { return {{"ok", false}, {"error", error}}; }

QJsonObject execute(Operations &ops, const QJsonObject &request) {
    const QString command = request.value("command").toString();
    if (command == "plan") {
        const QString directory = request.value("directory").toString();
        const QString objective = request.value("objective").toString();
        const QString problem = ops.validate(directory, objective);
        if (!problem.isEmpty())
            return failure(problem);
        ops.create(request.value("codename").toString(), directory, objective, request.value("cycles").toInt(3),
                   request.value("roe").toString("restricted"), request.value("model").toString(),
                   request.value("handoffAt").toInt(250000), request.value("worktree").toBool(true),
                   request.value("standing").toString(), request.value("overwatch").toString("off"));
        if (request.value("deploy").toBool())
            ops.deploy(0);
        return {{"ok", true}, {"op", ops.toJson().first()}};
    }

    const int row = ops.find(request.value("op").toString());
    if (row < 0)
        return failure(QString("No operation matches \"%1\".").arg(request.value("op").toString()));
    const QString status = ops.at(row).status;
    if (command == "deploy") {
        if (status == "deployed" || status == "staged" || status == "pinned")
            return failure(QString("%1 is already %2.").arg(ops.at(row).codename, status));
        ops.deploy(row);
    } else if (command == "order") {
        const QString text = request.value("text").toString().trimmed();
        if (text.isEmpty())
            return failure("The order is empty.");
        ops.sendOrders(row, text, request.value("deploy").toBool());
    } else if (command == "hold") {
        if (status != "deployed")
            return failure(QString("%1 isn't deployed.").arg(ops.at(row).codename));
        ops.setHold(row, true);
    } else if (command == "abort") {
        if (status != "deployed" && status != "staged" && status != "pinned")
            return failure(QString("%1 isn't deployed or queued.").arg(ops.at(row).codename));
        ops.abort(row);
    } else if (command == "extract") {
        if (!ops.extract(row))
            return failure(ops.at(row).comms.isEmpty() ? QString("Extraction failed.")
                                                       : ops.at(row).comms.last().toMap().value("text").toString());
    } else if (command == "discard") {
        if (!ops.discard(row))
            return failure(QString("%1 has no worktree to discard, or is deployed.").arg(ops.at(row).codename));
    } else {
        return failure(QString("Unknown command \"%1\".").arg(command));
    }
    return {{"ok", true}, {"op", ops.toJson().at(ops.find(request.value("op").toString()))}};
}

}

Inbox::Inbox(Operations &ops, QObject *parent)
    : QObject(parent), m_ops(ops), m_path(Command::inboxPath(ops.dataDirectory())) {
    QDir().mkpath(m_path);
    m_watcher.addPath(m_path);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, [this] { QTimer::singleShot(50, this, &Inbox::scan); });
    // Requests left from before the app started are answered too.
    QTimer::singleShot(0, this, &Inbox::scan);
}

void Inbox::scan() {
    const QStringList requests = QDir(m_path).entryList({"*.json"}, QDir::Files, QDir::Time | QDir::Reversed);
    for (const QString &name : requests) {
        if (name.endsWith(".result.json"))
            continue;
        QFile file(m_path + "/" + name);
        if (!file.open(QIODevice::ReadOnly))
            continue;
        const QJsonDocument request = QJsonDocument::fromJson(file.readAll());
        file.close();
        file.remove();
        const QJsonObject result = request.isObject() ? Command::execute(m_ops, request.object())
                                                      : QJsonObject{{"ok", false}, {"error", "Unreadable request."}};
        QSaveFile out(m_path + "/" + QString(name).replace(".json", ".result.json"));
        if (out.open(QIODevice::WriteOnly)) {
            out.write(QJsonDocument(result).toJson(QJsonDocument::Compact));
            out.commit();
        }
    }
}
