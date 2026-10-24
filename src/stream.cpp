#include "stream.h"

#include <QDateTime>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

namespace Stream {

QString describeTool(const QString &name, const QJsonObject &input) {
    // The most telling argument for each tool, so the comms feed reads like
    // "Edit src/main.cpp" rather than a JSON blob.
    for (const char *key : {"file_path", "command", "pattern", "url", "query", "description", "prompt"}) {
        const QString value = input.value(key).toString().simplified();
        if (!value.isEmpty()) {
            const bool path = QLatin1String(key) == QLatin1String("file_path");
            return name + "  " + (path ? QFileInfo(value).fileName() : value.left(140));
        }
    }
    return name;
}

QList<StreamEvent> parseLine(const QByteArray &line) {
    QList<StreamEvent> events;
    const QJsonDocument document = QJsonDocument::fromJson(line.trimmed());
    if (!document.isObject()) {
        const QString text = QString::fromUtf8(line).trimmed();
        if (!text.isEmpty())
            events.append({StreamEvent::Error, text});
        return events;
    }
    const QJsonObject object = document.object();
    const QString type = object.value("type").toString();

    if (type == "system" && object.value("subtype").toString() == "init") {
        StreamEvent event{StreamEvent::Session};
        event.sessionId = object.value("session_id").toString();
        event.text = object.value("model").toString();
        events.append(event);
    } else if (type == "assistant") {
        for (const auto &value : object.value("message").toObject().value("content").toArray()) {
            const QJsonObject block = value.toObject();
            const QString kind = block.value("type").toString();
            if (kind == "text") {
                const QString text = block.value("text").toString().trimmed();
                if (!text.isEmpty())
                    events.append({StreamEvent::Say, text});
            } else if (kind == "tool_use") {
                events.append({StreamEvent::Tool, describeTool(block.value("name").toString(),
                                                               block.value("input").toObject())});
            }
        }
    } else if (type == "result") {
        StreamEvent event{StreamEvent::Result};
        event.text = object.value("result").toString().trimmed();
        event.sessionId = object.value("session_id").toString();
        event.costUsd = object.value("total_cost_usd").toDouble();
        event.turns = object.value("num_turns").toInt();
        event.isError = object.value("is_error").toBool() || object.value("subtype").toString() != "success";
        if (event.text.isEmpty() && event.isError)
            event.text = object.value("subtype").toString();
        events.append(event);
    }
    return events;
}

QString systemBrief() {
    return "You are one agent on a fireteam, working unattended through a series of development cycles. "
           "No one will answer questions mid-cycle, so make sensible decisions, note them, and keep moving. "
           "Each cycle should leave the project working and a little closer to the objective.";
}

QString cyclePrompt(const QString &codename, const QString &objective, int cycle, int cycles,
                    const QString &reportPath) {
    QString orders;
    if (cycle == 1)
        orders = "This is the first cycle. Survey the project, plan the route to the objective, then deliver "
                 "the first meaningful increment.";
    else
        orders = "Continue from the previous cycle. Pick the next most valuable increment toward the objective "
                 "and deliver it.";
    if (cycle == cycles)
        orders += " This is the final cycle: finish, verify, and leave the project in a clean, working state.";

    return QString("OPERATION %1, CYCLE %2 OF %3\n\nOBJECTIVE:\n%4\n\nORDERS:\n%5\n\n"
                   "When this cycle's work is done, write a debrief as one self-contained HTML file to:\n%6\n"
                   "Cover what was done this cycle, the files changed, how it was verified, problems found, and "
                   "the plan for the next cycle. Use inline CSS only with a dark background, and no external "
                   "resources. End with a two-sentence plain-text summary as your final reply.")
        .arg(codename).arg(cycle).arg(cycles).arg(objective, orders, reportPath);
}

static QString page(const QString &title, const QString &body) {
    return QString(R"(<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>%1</title>
<style>
body{margin:0;background:#07090b;color:#e8e6e1;font:15px/1.6 system-ui,sans-serif}
main{max-width:860px;margin:0 auto;padding:40px 20px}
h1{font-size:34px;letter-spacing:.12em;text-transform:uppercase;margin:0}
h2{font-size:13px;letter-spacing:.3em;text-transform:uppercase;color:#f97316;margin:32px 0 8px}
.tag{font:12px ui-monospace,monospace;letter-spacing:.2em;color:#8b8f94;text-transform:uppercase}
.panel{background:#0f1215;border:1px solid #1f2428;border-left:3px solid #f97316;padding:14px 18px;white-space:pre-wrap}
ul{font:13px/1.7 ui-monospace,monospace;color:#c4c2bd;padding-left:18px}
a{color:#f97316}
</style></head><body><main>%2</main></body></html>
)").arg(title.toHtmlEscaped(), body);
}

static QString list(const QStringList &items, const QString &empty) {
    if (items.isEmpty())
        return "<p class=\"tag\">" + empty + "</p>";
    QString html = "<ul>";
    for (const auto &item : items)
        html += "<li>" + item.toHtmlEscaped() + "</li>";
    return html + "</ul>";
}

QString fallbackReport(const QString &codename, int cycle, int cycles, const QString &objective,
                       const QString &sitrep, const QStringList &actions, const QStringList &intel) {
    const QString body =
        QString("<div class=\"tag\">Debrief · cycle %1 of %2 · %3</div><h1>%4</h1>"
                "<h2>Objective</h2><div class=\"panel\">%5</div>"
                "<h2>Sitrep</h2><div class=\"panel\">%6</div>"
                "<h2>Field actions</h2>%7<h2>Changed files</h2>%8"
                "<p class=\"tag\">The agent left no debrief of its own; Fireteam wrote this one from the comms.</p>")
            .arg(cycle).arg(cycles)
            .arg(QDateTime::currentDateTime().toString(Qt::ISODate), codename.toHtmlEscaped(),
                 objective.toHtmlEscaped(), sitrep.isEmpty() ? "No sitrep." : sitrep.toHtmlEscaped(),
                 list(actions, "None recorded."), list(intel, "No git changes detected."));
    return page(codename + " · cycle " + QString::number(cycle), body);
}

QString dossier(const QString &codename, const QString &objective, const QString &directory,
                const QList<DossierEntry> &entries) {
    QString cycles;
    for (const auto &entry : entries)
        cycles += QString("<h2>Cycle %1 · <a href=\"%2\">open debrief</a></h2><div class=\"panel\">%3</div>")
                      .arg(entry.cycle).arg(entry.file.toHtmlEscaped(),
                                            entry.sitrep.isEmpty() ? "No sitrep." : entry.sitrep.toHtmlEscaped());
    const QString body = QString("<div class=\"tag\">Operation dossier · %1</div><h1>%2</h1>"
                                 "<h2>Objective</h2><div class=\"panel\">%3</div>%4")
                             .arg(directory.toHtmlEscaped(), codename.toHtmlEscaped(), objective.toHtmlEscaped(),
                                  cycles.isEmpty() ? "<p class=\"tag\">No cycles completed yet.</p>" : cycles);
    return page(codename + " · dossier", body);
}

QString codename(quint32 seed) {
    static const char *first[] = {"IRON", "SILENT", "BLACK", "COLD", "GHOST", "RED", "STEEL", "NIGHT",
                                  "GRAVE", "AMBER", "BROKEN", "HOLLOW", "WINTER", "COPPER", "ASH", "FERAL"};
    static const char *second[] = {"VIPER", "ANVIL", "TALON", "HARBOR", "LANTERN", "SPIRE", "WOLF", "CINDER",
                                   "RAVEN", "CITADEL", "MERIDIAN", "HAMMER", "TIDE", "SABLE", "KESTREL", "FORGE"};
    return QString("%1 %2").arg(first[seed % 16], second[(seed / 16) % 16]);
}

}
