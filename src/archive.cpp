// Institutional memory for Operations: the after-action review that feeds a
// project's field manual, the archive, search, replays, and exports.

#include "fieldmanual.h"
#include "operations.h"
#include "stream.h"

#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <QTime>
#include <QUrl>
#include <memory>

// Field manual ---------------------------------------------------------------

void Operations::setAfterAction(bool on) {
    if (on == m_afterAction)
        return;
    m_afterAction = on;
    saveSettings();
    emit afterActionChanged();
}

QVariantList Operations::manuals() const { return FieldManual::all(m_dataDirectory); }

QVariantList Operations::lessons(const QString &directory) const {
    return FieldManual(m_dataDirectory, directory).lessons();
}

bool Operations::addLesson(const QString &directory, const QString &text) {
    FieldManual manual(m_dataDirectory, directory);
    if (manual.add({text}, tr("the operator")) == 0 || !manual.save())
        return false;
    emit lessonsChanged(QDir::cleanPath(directory));
    return true;
}

bool Operations::editLesson(const QString &directory, const QString &id, const QString &text) {
    FieldManual manual(m_dataDirectory, directory);
    if (!manual.edit(id, text) || !manual.save())
        return false;
    emit lessonsChanged(QDir::cleanPath(directory));
    return true;
}

bool Operations::removeLesson(const QString &directory, const QString &id) {
    FieldManual manual(m_dataDirectory, directory);
    if (!manual.remove(id) || !manual.save())
        return false;
    emit lessonsChanged(QDir::cleanPath(directory));
    return true;
}

QString Operations::promoteLessons(const QString &directory, const QStringList &ids) {
    return FieldManual(m_dataDirectory, directory).promote(ids);
}

void Operations::reviewAfterAction(const QString &id) {
    const int row = rowOf(id);
    if (row < 0 || m_claude.isEmpty() || !QFileInfo(m_ops.at(row).directory).isDir())
        return;
    const Operation &op = m_ops.at(row);
    const QString folder = m_dataDirectory + "/ops/" + op.id;
    QStringList sources = op.reports;
    sources << op.handoffs;
    for (const QVariant &review : op.reviews)
        sources << review.toMap().value("file").toString();
    const FieldManual manual(m_dataDirectory, op.directory);
    const QString prompt =
        QString("AFTER-ACTION REVIEW, OPERATION %1\n\nThe operation's objective was:\n%2\n\n"
                "Its debriefs, hand-off briefs and reviews are here:\n%3\n\n"
                "Read them, look at the project as much as you need (read-only; change nothing), and write down "
                "what a future agent working in this project should know before starting: lasting, project-specific "
                "facts such as how to build, run and test it, setup it needs, its conventions, and pitfalls with "
                "their fixes. Not what this operation did, and not general advice.\n\n%4"
                "Give 0 to 5 lessons, one sentence each; fewer good ones beat many weak ones. End your reply with "
                "exactly one fenced json block:\n```json\n{\"lessons\": [\"...\"]}\n```")
            .arg(op.codename, op.objective, sources.join('\n'),
                 manual.lessons().isEmpty() ? QString()
                                            : "The project's field manual already says this; don't repeat it:\n"
                                                  + manual.brief(60).section('\n', 1) + "\n\n");
    QStringList arguments{"-p", prompt, "--output-format", "stream-json", "--verbose", "--permission-mode", "plan",
                          "--add-dir", folder, "--model", "haiku"};
    auto *process = new QProcess(this);
    process->setWorkingDirectory(op.directory);
    QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
    environment.remove("CLAUDECODE");
    environment.remove("CLAUDE_CODE_ENTRYPOINT");
    process->setProcessEnvironment(environment);
    process->setStandardInputFile(QProcess::nullDevice());
    auto buffer = std::make_shared<QByteArray>();
    auto reply = std::make_shared<QString>();
    auto cost = std::make_shared<double>(0);
    connect(process, &QProcess::readyReadStandardOutput, this, [process, buffer, reply, cost] {
        *buffer += process->readAllStandardOutput();
        int newline;
        while ((newline = buffer->indexOf('\n')) >= 0) {
            const QByteArray line = buffer->left(newline);
            buffer->remove(0, newline + 1);
            for (const auto &event : Stream::parseLine(line))
                if (event.kind == StreamEvent::Result) {
                    *reply = event.text;
                    *cost += event.costUsd;
                }
        }
    });
    connect(process, &QProcess::finished, this, [this, id, process, reply, cost] {
        process->deleteLater();
        const int r = rowOf(id);
        if (r < 0)
            return;
        Operation &o = m_ops[r];
        o.costUsd += *cost;
        static const QRegularExpression block(R"(```json\s*(\{.*?\})\s*```)", QRegularExpression::DotMatchesEverythingOption);
        QStringList found;
        auto blocks = block.globalMatch(*reply);
        while (blocks.hasNext())
            for (const auto &lesson : QJsonDocument::fromJson(blocks.next().captured(1).toUtf8()).object().value("lessons").toArray())
                found << lesson.toString();
        FieldManual manual(m_dataDirectory, o.directory);
        const int added = manual.add(found.mid(0, 5), o.codename);
        if (added > 0 && manual.save()) {
            log(o, "review", tr("Field manual: %n lesson(s) learned for this project.", "", added));
            emit lessonsChanged(manual.project());
        }
        changed(r);
        save();
    });
    connect(process, &QProcess::errorOccurred, process, [process](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart)
            process->deleteLater();
    });
    process->start(m_claude, arguments);
}

// Archive and search ---------------------------------------------------------

int Operations::archivedCount() const {
    int count = 0;
    for (const auto &op : m_ops)
        count += op.archived;
    return count;
}

void Operations::setArchived(int row, bool archived) {
    if (row < 0 || row >= m_ops.size() || m_ops.at(row).archived == archived)
        return;
    // Only what's finished goes to the archive.
    const QString status = m_ops.at(row).status;
    if (archived && (status == "deployed" || status == "staged" || status == "pinned"))
        return;
    m_ops[row].archived = archived;
    log(m_ops[row], "sys", archived ? tr("Archived.") : tr("Back from the archive."));
    changed(row);
    save();
    emit archivedChanged();
}

static QString plain(const QString &html) {
    QString text = html;
    text.remove(QRegularExpression("<(script|style)[^>]*>.*?</\\1>", QRegularExpression::DotMatchesEverythingOption
                                                                      | QRegularExpression::CaseInsensitiveOption));
    text.replace(QRegularExpression("<[^>]+>"), " ");
    text.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"").replace("&#39;", "'");
    return text.simplified();
}

QVariantList Operations::search(const QString &query) const {
    const QString needle = query.simplified();
    QVariantList results;
    if (needle.size() < 2)
        return results;
    auto snippet = [&needle](const QString &text) {
        const qsizetype at = text.indexOf(needle, 0, Qt::CaseInsensitive);
        if (at < 0)
            return QString();
        const qsizetype from = qMax<qsizetype>(0, at - 60);
        return (from > 0 ? "…" : "") + text.mid(from, needle.size() + 140).simplified() + "…";
    };
    for (int row = 0; row < m_ops.size() && results.size() < 100; ++row) {
        const Operation &op = m_ops.at(row);
        const QString folder = m_dataDirectory + "/ops/" + op.id;
        auto hit = [&](const QString &kind, const QString &text, const QString &path) {
            const QString found = snippet(text);
            if (!found.isEmpty() && results.size() < 100)
                results.append(QVariantMap{{"row", row}, {"opId", op.id}, {"codename", op.codename}, {"kind", kind},
                                           {"snippet", found}, {"path", path}, {"archived", op.archived}});
            return !found.isEmpty();
        };
        hit("objective", op.objective + " " + op.sitrep, QString());
        for (const QString &path : op.reports) {
            QFile file(path);
            if (file.open(QIODevice::ReadOnly))
                hit("debrief", plain(QString::fromUtf8(file.readAll())), path);
        }
        for (const QString &path : op.handoffs) {
            QFile file(path);
            if (file.open(QIODevice::ReadOnly))
                hit("brief", QString::fromUtf8(file.readAll()), path);
        }
        for (const QVariant &review : op.reviews) {
            QFile file(review.toMap().value("file").toString());
            if (file.open(QIODevice::ReadOnly))
                hit("review", plain(QString::fromUtf8(file.readAll())), file.fileName());
        }
        // The whole comms log on disk, not just what the board keeps; the
        // first few hits per operation.
        QFile comms(folder + "/comms.jsonl");
        if (comms.open(QIODevice::ReadOnly)) {
            int hits = 0;
            while (!comms.atEnd() && hits < 5) {
                const QJsonObject entry = QJsonDocument::fromJson(comms.readLine()).object();
                if (hit("comms", entry.value("text").toString(), QString()))
                    ++hits;
            }
        }
    }
    return results;
}

QVariantList Operations::replay(int row) const {
    QVariantList timeline;
    if (row < 0 || row >= m_ops.size())
        return timeline;
    QFile file(m_dataDirectory + "/ops/" + m_ops.at(row).id + "/comms.jsonl");
    if (!file.open(QIODevice::ReadOnly))
        return timeline;
    // Lines carry the full moment ("at"); older ones only a clock time, so
    // their days are counted by the clock going backwards.
    qint64 start = -1, last = 0, day = 0, previousClock = -1;
    while (!file.atEnd() && timeline.size() < 20000) {
        const QJsonObject entry = QJsonDocument::fromJson(file.readLine()).object();
        if (entry.isEmpty())
            continue;
        qint64 at = qint64(entry.value("at").toDouble());
        if (at <= 0) {
            const QTime clock = QTime::fromString(entry.value("time").toString(), "HH:mm:ss");
            const qint64 ms = clock.isValid() ? clock.msecsSinceStartOfDay() : previousClock;
            if (previousClock >= 0 && ms < previousClock)
                day += 1;
            previousClock = ms;
            at = day * 86400000LL + ms;
        }
        if (start < 0)
            start = at;
        last = qMax(last, at - start);
        timeline.append(QVariantMap{{"t", double(qMax<qint64>(0, at - start)) / 1000.0}, {"time", entry.value("time").toString()},
                                    {"kind", entry.value("kind").toString()}, {"text", entry.value("text").toString()}});
    }
    return timeline;
}

// Export ---------------------------------------------------------------------

QString Operations::exportDirectory() const {
    if (qEnvironmentVariableIsSet("FIRETEAM_EXPORT_DIR")) {
        QDir().mkpath(qEnvironmentVariable("FIRETEAM_EXPORT_DIR"));
        return qEnvironmentVariable("FIRETEAM_EXPORT_DIR");
    }
    const QString documents = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
    const QString folder = (documents.isEmpty() ? QDir::homePath() : documents) + "/Fireteam";
    QDir().mkpath(folder);
    return folder;
}

static QString escape(const QString &text) { return text.toHtmlEscaped(); }

static QString exportPage(const QString &title, const QString &body) {
    return QString(R"(<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>%1</title>
<style>
:root{--bg:#0f100e;--panel:#161714;--line:#2a2b27;--line2:#3b3d37;--text:#ecebe6;--text2:#c9c8c1;--dim:#93948d;--accent:#ffd60a;--good:#7ccf8a;--bad:#f0605a;--mono:"Martian Mono",ui-monospace,monospace}
body{margin:0;background:var(--bg);color:var(--text);font:15px/1.6 "Red Hat Text",system-ui,sans-serif}
main{max-width:920px;margin:0 auto;padding:48px 20px}
h1{font:500 38px/1.1 var(--mono);letter-spacing:-.02em;margin:0}
h2{font:500 14px "Red Hat Text",system-ui,sans-serif;color:var(--text2);margin:36px 0 12px;padding-bottom:6px;border-bottom:1px solid var(--line)}
h2::before{content:"";display:inline-block;width:5px;height:5px;background:var(--accent);margin-right:10px;vertical-align:middle}
.tag{font:12px var(--mono);color:var(--dim)}
.panel{background:var(--panel);border:1px solid var(--line);border-left:2px solid var(--accent);padding:14px 18px;white-space:pre-wrap;margin-bottom:10px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:0;border:1px solid var(--line)}.stat{padding:14px 16px;border-right:1px solid var(--line)}
.stat b{display:block;font:300 26px var(--mono);letter-spacing:-.01em}.stat span{color:var(--dim);font:11px var(--mono)}.stat span::before{content:"# "}
details{background:var(--panel);border:1px solid var(--line);margin-bottom:10px}summary{cursor:pointer;padding:12px 16px;font-weight:500}
iframe{width:100%;height:640px;border:0;background:#fff}img{max-width:100%;border:1px solid var(--line)}
.met{color:var(--good)}.unmet{color:var(--bad)}code{font-family:var(--mono)}
</style></head><body><main>%2<p class="tag" style="margin-top:40px">Exported from Fireteam</p></main></body></html>
)").arg(escape(title), body);
}

static QString operationHtml(const Operation &op, bool embedDebriefs) {
    int files = 0, added = 0, removed = 0;
    for (const QVariant &value : op.history) {
        files += value.toMap().value("files").toInt();
        added += value.toMap().value("added").toInt();
        removed += value.toMap().value("removed").toInt();
    }
    QString body = QString("<div class=\"tag\">Operation · %1</div><h1>%2</h1>"
                           "<div class=\"grid\" style=\"margin-top:18px\">"
                           "<div class=\"stat\"><b>%3/%4</b><span>Cycles</span></div>"
                           "<div class=\"stat\"><b>+%5 −%6</b><span>Lines</span></div>"
                           "<div class=\"stat\"><b>%10</b><span>File changes</span></div>"
                           "<div class=\"stat\"><b>%7</b><span>Status</span></div>"
                           "<div class=\"stat\"><b>$%8</b><span>API value</span></div></div>"
                           "<h2>Objective</h2><div class=\"panel\">%9</div>")
                       .arg(escape(op.directory), escape(op.codename)).arg(op.cyclesDone).arg(op.cycles)
                       .arg(added).arg(removed).arg(escape(op.status)).arg(op.costUsd, 0, 'f', 2).arg(escape(op.objective))
                       .arg(files);
    if (!op.sitrep.isEmpty())
        body += "<h2>Result</h2><div class=\"panel\">" + escape(op.sitrep) + "</div>";
    if (!op.criteria.isEmpty()) {
        body += "<h2>Acceptance criteria</h2><div class=\"panel\">";
        for (const QVariant &value : op.criteria) {
            const QVariantMap c = value.toMap();
            const QString state = c.value("state").toString();
            body += QString("<div class=\"%1\">%2 %3</div>").arg(state == "met" ? "met" : state == "unmet" ? "unmet" : "",
                                                                 state == "met" ? "●" : state == "unmet" ? "✕" : state == "claimed" ? "◐" : "○",
                                                                 escape(c.value("text").toString()));
        }
        body += "</div>";
    }
    if (!op.reviews.isEmpty()) {
        const QVariantMap review = op.reviews.last().toMap();
        body += QString("<h2>Overwatch</h2><div class=\"panel\">%1 · %2</div>")
                    .arg(escape(review.value("grade").toString().toUpper()), escape(review.value("summary").toString()));
    }
    body += "<h2>Cycles</h2>";
    for (int i = 0; i < op.history.size(); ++i) {
        const QVariantMap entry = op.history.at(i).toMap();
        QString gates;
        for (const QVariant &gate : entry.value("gates").toList())
            gates += QString(" <span class=\"%1\">%2 %3</span>").arg(gate.toMap().value("passed").toBool() ? "met" : "unmet",
                                                                     gate.toMap().value("passed").toBool() ? "✓" : "✕",
                                                                     escape(gate.toMap().value("name").toString()));
        const int cycle = entry.value("cycle").toInt();
        QString inner = escape(entry.value("sitrep").toString().isEmpty() ? QString("No sitrep.") : entry.value("sitrep").toString());
        // The debrief itself, sandboxed in a frame so its styles stay its own.
        const QString report = cycle >= 1 && cycle <= op.reports.size() ? op.reports.at(cycle - 1) : QString();
        QFile file(report);
        if (embedDebriefs && entry.value("outcome") == "complete" && file.open(QIODevice::ReadOnly))
            inner += "<iframe sandbox srcdoc=\"" + QString::fromUtf8(file.readAll()).toHtmlEscaped() + "\"></iframe>";
        QFile shot(entry.value("screenshot").toString());
        if (shot.open(QIODevice::ReadOnly) && shot.size() < 4 * 1024 * 1024)
            inner += "<p><img alt=\"Preview\" src=\"data:image/png;base64," + QString::fromLatin1(shot.readAll().toBase64()) + "\"></p>";
        body += QString("<details%1><summary>Cycle %2 · %3 · %4 files · +%5 −%6%7</summary><div style=\"padding:0 16px 16px\">%8</div></details>")
                    .arg(i == op.history.size() - 1 ? " open" : "").arg(cycle).arg(escape(entry.value("outcome").toString()))
                    .arg(entry.value("files").toInt()).arg(entry.value("added").toInt()).arg(entry.value("removed").toInt())
                    .arg(gates, inner);
    }
    return body;
}

static QString operationMarkdown(const Operation &op) {
    int files = 0, added = 0, removed = 0;
    for (const QVariant &value : op.history) {
        files += value.toMap().value("files").toInt();
        added += value.toMap().value("added").toInt();
        removed += value.toMap().value("removed").toInt();
    }
    QStringList md{QString("## %1").arg(op.codename), "", op.objective, ""};
    if (!op.sitrep.isEmpty())
        md << "**Result:** " + op.sitrep << "";
    md << QString("%1 cycle(s) · %2 file change(s) · +%3 −%4 lines").arg(op.cyclesDone).arg(files).arg(added).arg(removed) << "";
    if (!op.criteria.isEmpty()) {
        md << "### Acceptance criteria" << "";
        for (const QVariant &value : op.criteria) {
            const QString state = value.toMap().value("state").toString();
            md << QString("- [%1] %2%3").arg(state == "met" ? "x" : " ", value.toMap().value("text").toString(),
                                            state == "unmet" ? " (not met)" : state == "claimed" ? " (claimed, not verified)" : "");
        }
        md << "";
    }
    QVariantList gates;
    for (qsizetype i = op.history.size() - 1; i >= 0 && gates.isEmpty(); --i)
        gates = op.history.at(i).toMap().value("gates").toList();
    if (!gates.isEmpty()) {
        md << "### Checks" << "";
        for (const QVariant &gate : gates)
            md << QString("- %1 `%2`").arg(gate.toMap().value("passed").toBool() ? "✅" : "❌", gate.toMap().value("command").toString());
        md << "";
    }
    if (!op.reviews.isEmpty())
        md << "### Review" << "" << QString("**%1.** %2").arg(op.reviews.last().toMap().value("grade").toString(),
                                                            op.reviews.last().toMap().value("summary").toString()) << "";
    md << "### Cycles" << "";
    for (const QVariant &value : op.history) {
        const QVariantMap entry = value.toMap();
        md << QString("%1. **%2** · %3 files, +%4 −%5. %6").arg(entry.value("cycle").toInt()).arg(entry.value("outcome").toString())
                  .arg(entry.value("files").toInt()).arg(entry.value("added").toInt()).arg(entry.value("removed").toInt())
                  .arg(entry.value("sitrep").toString());
    }
    md << "";
    return md.join('\n');
}

static QString fileName(const QString &name, const QString &format) {
    QString slug = name.toLower();
    slug.replace(QRegularExpression("[^a-z0-9]+"), "-");
    return slug + "-" + QDate::currentDate().toString(Qt::ISODate) + (format == "md" ? ".md" : ".html");
}

QString Operations::exportOperation(int row, const QString &format) {
    if (row < 0 || row >= m_ops.size())
        return {};
    const Operation &op = m_ops.at(row);
    const QString path = exportDirectory() + "/" + fileName(op.codename, format);
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly))
        return {};
    file.write((format == "md" ? QString("# Fireteam report\n\n") + operationMarkdown(op)
                               : exportPage(op.codename, operationHtml(op, true))).toUtf8());
    return file.commit() ? path : QString();
}

QString Operations::exportCampaign(const QString &id, const QString &format) {
    const int c = campaignIndex(id);
    if (c < 0)
        return {};
    const Campaign &campaign = m_campaigns.at(c);
    QList<const Operation *> members;
    for (const QString &key : Stream::dependencyOrder(campaign.plan))
        for (const auto &op : m_ops)
            if (op.campaign == id && op.campaignKey == key)
                members << &op;
    QString text;
    if (format == "md") {
        QStringList md{QString("# Campaign %1").arg(campaign.name), "", campaign.objective, ""};
        if (!campaign.summary.isEmpty())
            md << "**Plan:** " + campaign.summary << "";
        for (const Operation *op : members)
            md << operationMarkdown(*op);
        text = md.join('\n');
    } else {
        QString body = QString("<div class=\"tag\">Campaign</div><h1>%1</h1><h2>Objective</h2><div class=\"panel\">%2</div>")
                           .arg(escape(campaign.name), escape(campaign.objective));
        if (!campaign.summary.isEmpty())
            body += "<h2>Plan</h2><div class=\"panel\">" + escape(campaign.summary) + "</div>";
        for (const Operation *op : members)
            body += "<hr style=\"border:0;border-top:1px solid var(--line);margin:40px 0\">" + operationHtml(*op, false);
        text = exportPage(campaign.name, body);
    }
    const QString path = exportDirectory() + "/" + fileName("campaign-" + campaign.name, format);
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly))
        return {};
    file.write(text.toUtf8());
    return file.commit() ? path : QString();
}

void Operations::reveal(const QString &path) {
    if (path.isEmpty())
        return;
    QDesktopServices::openUrl(QUrl::fromLocalFile(path.endsWith(".html") ? path : QFileInfo(path).absolutePath()));
}
