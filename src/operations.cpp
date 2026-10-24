#include "operations.h"
#include "stream.h"

#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QRandomGenerator>
#include <QSaveFile>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>
#include <QUuid>

// Comms kept per operation; older lines stay in comms.jsonl on disk.
static constexpr int CommsLimit = 400;

QJsonObject Operation::toJson() const {
    return {{"id", id}, {"codename", codename}, {"directory", directory}, {"objective", objective},
            {"model", model}, {"roe", roe}, {"cycles", cycles}, {"cyclesDone", cyclesDone},
            {"status", status}, {"sessionId", sessionId}, {"costUsd", costUsd}, {"sitrep", sitrep},
            {"intel", QJsonArray::fromStringList(intel)}, {"reports", QJsonArray::fromStringList(reports)},
            {"sitreps", QJsonArray::fromStringList(sitreps)}, {"created", created.toString(Qt::ISODate)},
            {"contextTokens", contextTokens}, {"contextWindow", contextWindow}, {"handoffAt", handoffAt},
            {"session", session}, {"handoffBrief", handoffBrief}, {"handoffs", QJsonArray::fromStringList(handoffs)}};
}

Operation Operation::fromJson(const QJsonObject &o) {
    Operation op;
    auto strings = [](const QJsonValue &v) {
        QStringList list;
        for (const auto &item : v.toArray())
            list << item.toString();
        return list;
    };
    op.id = o.value("id").toString();
    op.codename = o.value("codename").toString();
    op.directory = o.value("directory").toString();
    op.objective = o.value("objective").toString();
    op.model = o.value("model").toString();
    op.roe = o.value("roe").toString("restricted");
    op.cycles = o.value("cycles").toInt(1);
    op.cyclesDone = o.value("cyclesDone").toInt();
    op.status = o.value("status").toString("standby");
    op.sessionId = o.value("sessionId").toString();
    op.costUsd = o.value("costUsd").toDouble();
    op.sitrep = o.value("sitrep").toString();
    op.intel = strings(o.value("intel"));
    op.reports = strings(o.value("reports"));
    op.sitreps = strings(o.value("sitreps"));
    op.created = QDateTime::fromString(o.value("created").toString(), Qt::ISODate);
    op.contextTokens = o.value("contextTokens").toInteger();
    op.contextWindow = o.value("contextWindow").toInteger(1000000);
    op.handoffAt = o.value("handoffAt").toInteger(250000);
    op.session = o.value("session").toInt(1);
    op.handoffBrief = o.value("handoffBrief").toString();
    op.handoffs = strings(o.value("handoffs"));
    return op;
}

static QString findClaude() {
    // A launcher-started app may not have the shell's PATH (mise, npm
    // prefixes), so look in the usual install spots too.
    const QString found = QStandardPaths::findExecutable("claude");
    if (!found.isEmpty())
        return found;
    const QString home = QDir::homePath();
    for (const QString &path : {home + "/.local/bin/claude", home + "/.claude/local/claude",
                                home + "/.local/share/mise/command-wrappers/bin/claude",
                                home + "/.local/share/mise/shims/claude", home + "/.npm-global/bin/claude",
                                QString("/usr/local/bin/claude"), QString("/usr/bin/claude")})
        if (QFileInfo(path).isExecutable())
            return path;
    return {};
}

Operations::Operations(const QString &dataDirectory, const QString &claude, QObject *parent)
    : QAbstractListModel(parent),
      m_dataDirectory(dataDirectory.isEmpty()
                          ? QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + "/fireteam"
                          : dataDirectory),
      m_claude(claude.isEmpty() ? findClaude() : claude) {
    QDir().mkpath(m_dataDirectory);
    load();
}

Operations::~Operations() {
    // Closing the app ends its agents (and any git check still running)
    // rather than leaving them working unseen.
    for (QProcess *process : findChildren<QProcess *>()) {
        process->disconnect();
        process->kill();
        process->waitForFinished(2000);
    }
    for (auto &op : m_ops)
        if (op.status == "deployed")
            op.status = "interrupted";
    save();
}

int Operations::rowCount(const QModelIndex &parent) const { return parent.isValid() ? 0 : m_ops.size(); }

QHash<int, QByteArray> Operations::roleNames() const {
    return {{IdRole, "opId"}, {CodenameRole, "codename"}, {DirectoryRole, "directory"},
            {ObjectiveRole, "objective"}, {ModelRole, "model"}, {RoeRole, "roe"}, {CyclesRole, "cycles"},
            {CyclesDoneRole, "cyclesDone"}, {StatusRole, "status"}, {CostRole, "cost"}, {SitrepRole, "sitrep"},
            {ActivityRole, "activity"}, {IntelRole, "intel"}, {ReportsRole, "reports"}, {CommsRole, "comms"},
            {DossierRole, "dossier"}, {CreatedRole, "created"}, {ContextRole, "context"},
            {ContextWindowRole, "contextWindow"}, {HandoffAtRole, "handoffAt"}, {SessionRole, "session"},
            {HandoffBriefRole, "handoffBrief"}};
}

QVariant Operations::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() >= m_ops.size())
        return {};
    const Operation &op = m_ops.at(index.row());
    switch (role) {
    case IdRole: return op.id;
    case CodenameRole: return op.codename;
    case DirectoryRole: return op.directory;
    case ObjectiveRole: return op.objective;
    case ModelRole: return op.model;
    case RoeRole: return op.roe;
    case CyclesRole: return op.cycles;
    case CyclesDoneRole: return op.cyclesDone;
    case StatusRole: return op.status;
    case CostRole: return op.costUsd;
    case SitrepRole: return op.sitrep;
    case ActivityRole: return op.activity;
    case IntelRole: return op.intel;
    case ReportsRole: return op.reports;
    case CommsRole: return op.comms;
    case DossierRole: return QFileInfo::exists(dossierPath(op)) ? dossierPath(op) : QString();
    case CreatedRole: return op.created;
    case ContextRole: return double(op.contextTokens);
    case ContextWindowRole: return double(op.contextWindow);
    case HandoffAtRole: return double(op.handoffAt);
    case SessionRole: return op.session;
    case HandoffBriefRole: return op.handoffs.isEmpty() ? QString() : op.handoffs.last();
    }
    return {};
}

int Operations::deployedCount() const {
    int count = 0;
    for (const auto &op : m_ops)
        count += op.status == "deployed";
    return count;
}

int Operations::rowOf(const QString &id) const {
    for (int i = 0; i < m_ops.size(); ++i)
        if (m_ops.at(i).id == id)
            return i;
    return -1;
}

void Operations::changed(int row) {
    if (row < 0)
        return;
    emit dataChanged(index(row), index(row));
}

QString Operations::suggestCodename() const {
    QStringList taken;
    for (const auto &op : m_ops)
        taken << op.codename;
    for (int attempt = 0; attempt < 64; ++attempt) {
        const QString name = Stream::codename(QRandomGenerator::global()->generate());
        if (!taken.contains(name))
            return name;
    }
    return Stream::codename(QRandomGenerator::global()->generate());
}

QString Operations::validate(const QString &directory, const QString &objective) const {
    if (m_claude.isEmpty())
        return tr("The claude command isn't installed. Install Claude Code and log in with `claude`.");
    const QFileInfo info(QDir::cleanPath(directory.trimmed()));
    if (directory.trimmed().isEmpty() || !info.isDir())
        return tr("Pick a project directory that exists.");
    if (!info.isWritable())
        return tr("The project directory isn't writable.");
    if (objective.trimmed().isEmpty())
        return tr("Give the fireteam an objective.");
    return {};
}

int Operations::create(const QString &codename, const QString &directory, const QString &objective, int cycles,
                       const QString &roe, const QString &model, int handoffAt) {
    if (!validate(directory, objective).isEmpty())
        return -1;
    Operation op;
    op.id = QUuid::createUuid().toString(QUuid::WithoutBraces).left(8);
    op.codename = codename.trimmed().isEmpty() ? suggestCodename() : codename.trimmed().toUpper();
    op.directory = QDir::cleanPath(directory.trimmed());
    op.objective = objective.trimmed();
    op.cycles = qBound(1, cycles, 20);
    op.roe = roe == "free" ? "free" : "restricted";
    op.model = model.trimmed();
    op.handoffAt = qMax(0, handoffAt);
    op.created = QDateTime::currentDateTime();
    QDir().mkpath(m_dataDirectory + "/ops/" + op.id + "/debriefs");

    beginInsertRows({}, 0, 0);
    m_ops.prepend(op);
    endInsertRows();
    log(m_ops.first(), "sys", tr("Operation planned: %1 cycles, %2, %3.")
                                  .arg(op.cycles).arg(op.roe == "free" ? tr("weapons free") : tr("restricted"))
                                  .arg(op.handoffAt > 0 ? tr("hand off at %1").arg(Stream::tokens(op.handoffAt))
                                                        : tr("no hand-off")));
    save();
    return 0;
}

QString Operations::reportPath(const Operation &op, int cycle) const {
    return QString("%1/ops/%2/debriefs/cycle-%3.html").arg(m_dataDirectory, op.id).arg(cycle, 2, 10, QChar('0'));
}

QString Operations::dossierPath(const Operation &op) const {
    return QString("%1/ops/%2/dossier.html").arg(m_dataDirectory, op.id);
}

QString Operations::handoffPath(const Operation &op) const {
    return QString("%1/ops/%2/handoffs/session-%3.md").arg(m_dataDirectory, op.id).arg(op.session, 2, 10, QChar('0'));
}

void Operations::deploy(int row) {
    if (row < 0 || row >= m_ops.size())
        return;
    Operation &op = m_ops[row];
    if (op.status == "deployed")
        return;
    if (m_claude.isEmpty()) {
        log(op, "error", tr("The claude command isn't installed, so the fireteam can't deploy."));
        changed(row);
        return;
    }
    if (!QFileInfo(op.directory).isDir()) {
        log(op, "error", tr("The project directory %1 is gone.").arg(op.directory));
        changed(row);
        return;
    }
    // A finished operation redeploys for one more cycle on the same session.
    if (op.cyclesDone >= op.cycles)
        op.cycles = op.cyclesDone + 1;
    op.status = "deployed";
    changed(row);
    emit deployedCountChanged();
    save();
    advance(op.id);
}

void Operations::advance(const QString &id) {
    const Operation &op = m_ops.at(rowOf(id));
    // Hand off between cycles, never mid-cycle, so no work is cut short.
    if (op.handoffAt > 0 && !op.sessionId.isEmpty() && op.contextTokens >= op.handoffAt)
        startHandoff(id);
    else
        startCycle(id);
}

void Operations::startCycle(const QString &id) {
    const int row = rowOf(id);
    Operation &op = m_ops[row];
    const int cycle = op.cyclesDone + 1;
    const QString report = reportPath(op, cycle);
    QDir().mkpath(QFileInfo(report).absolutePath());
    QFile::remove(report);

    // Only the first cycle of a fresh session after a hand-off reads the brief.
    const QString brief = op.sessionId.isEmpty() ? op.handoffBrief : QString();
    op.activity = tr("Cycle %1 inbound").arg(cycle);
    log(op, "sys", tr("Cycle %1 of %2 deployed.").arg(cycle).arg(op.cycles));
    launch(id, Stream::cyclePrompt(op.codename, op.objective, cycle, op.cycles, report, brief,
                                   QFileInfo(report).absolutePath()),
           false);
}

void Operations::startHandoff(const QString &id) {
    const int row = rowOf(id);
    Operation &op = m_ops[row];
    const QString brief = handoffPath(op);
    QDir().mkpath(QFileInfo(brief).absolutePath());
    QFile::remove(brief);
    op.activity = tr("Handing off");
    log(op, "sys", tr("Context at %1, past the %2 line. Session %3 is writing a handoff brief.")
                       .arg(Stream::tokens(op.contextTokens), Stream::tokens(op.handoffAt)).arg(op.session));
    launch(id, Stream::handoffPrompt(op.codename, op.objective, op.contextTokens, op.cycles - op.cyclesDone, brief),
           true);
}

void Operations::launch(const QString &id, const QString &prompt, bool handoff) {
    const int row = rowOf(id);
    Operation &op = m_ops[row];
    QStringList arguments{"-p", prompt,
                          "--output-format", "stream-json", "--verbose",
                          "--permission-mode", op.roe == "free" ? "bypassPermissions" : "acceptEdits",
                          "--add-dir", m_dataDirectory + "/ops/" + op.id,
                          "--append-system-prompt", Stream::systemBrief()};
    if (!op.model.isEmpty())
        arguments << "--model" << op.model;
    if (!op.sessionId.isEmpty())
        arguments << "--resume" << op.sessionId;

    auto *process = new QProcess(this);
    process->setWorkingDirectory(op.directory);
    // The agent signs in with the same Claude Code login as the terminal. Only
    // the markers of a parent Claude Code session are dropped, so a Fireteam
    // started from inside one doesn't look nested to its agents.
    QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
    environment.remove("CLAUDECODE");
    environment.remove("CLAUDE_CODE_ENTRYPOINT");
    process->setProcessEnvironment(environment);
    process->setStandardInputFile(QProcess::nullDevice());

    Run run;
    run.process = process;
    run.handoff = handoff;
    m_runs.insert(id, run);
    changed(row);

    connect(process, &QProcess::readyReadStandardOutput, this, [this, id] { readOutput(id); });
    connect(process, &QProcess::readyReadStandardError, this, [this, id, process] {
        const int r = rowOf(id);
        const QString text = QString::fromUtf8(process->readAllStandardError()).trimmed();
        if (r >= 0 && !text.isEmpty()) {
            log(m_ops[r], "error", text.left(600));
            changed(r);
        }
    });
    connect(process, &QProcess::errorOccurred, this, [this, id, process](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart)
            finishCycle(id, -1);
        Q_UNUSED(process);
    });
    connect(process, &QProcess::finished, this, [this, id](int code, QProcess::ExitStatus status) {
        finishCycle(id, status == QProcess::NormalExit ? code : -1);
    });
    process->start(m_claude, arguments);
}

void Operations::readOutput(const QString &id) {
    auto it = m_runs.find(id);
    const int row = rowOf(id);
    if (it == m_runs.end() || row < 0 || !it->process)
        return;
    it->buffer += it->process->readAllStandardOutput();
    Operation &op = m_ops[row];
    int newline;
    while ((newline = it->buffer.indexOf('\n')) >= 0) {
        const QByteArray line = it->buffer.left(newline);
        it->buffer.remove(0, newline + 1);
        for (const auto &event : Stream::parseLine(line)) {
            switch (event.kind) {
            case StreamEvent::Session:
                if (!event.sessionId.isEmpty())
                    op.sessionId = event.sessionId;
                log(op, "sys", tr("Link established%1.").arg(event.text.isEmpty() ? "" : " · " + event.text));
                break;
            case StreamEvent::Say:
                op.activity = event.text.section('\n', 0, 0).left(120);
                log(op, "say", event.text);
                break;
            case StreamEvent::Tool:
                op.activity = event.text;
                it->actions << event.text;
                log(op, "tool", event.text);
                break;
            case StreamEvent::Usage:
                op.contextTokens = event.contextTokens;
                if (!it->handoff && !it->pastLine && op.handoffAt > 0 && op.contextTokens >= op.handoffAt) {
                    it->pastLine = true;
                    log(op, "sys", tr("Context at %1, past the %2 line. Handing off after this cycle.")
                                       .arg(Stream::tokens(op.contextTokens), Stream::tokens(op.handoffAt)));
                }
                break;
            case StreamEvent::Result:
                it->resultSeen = true;
                op.costUsd += event.costUsd;
                if (event.contextWindow > 0)
                    op.contextWindow = event.contextWindow;
                if (!event.sessionId.isEmpty())
                    op.sessionId = event.sessionId;
                if (event.isError) {
                    log(op, "error", tr("Run failed: %1").arg(event.text));
                } else if (it->handoff) {
                    log(op, "result", event.text);
                } else {
                    op.sitrep = event.text;
                    log(op, "result", event.text);
                }
                break;
            case StreamEvent::Error:
                log(op, "error", event.text.left(600));
                break;
            }
        }
    }
    changed(row);
}

void Operations::finishCycle(const QString &id, int exitCode) {
    auto it = m_runs.find(id);
    const int row = rowOf(id);
    if (it == m_runs.end() || row < 0)
        return;
    if (it->process) {
        it->buffer += it->process->readAllStandardOutput();
        it->buffer += '\n';
        readOutput(id);
        it->process->deleteLater();
    }
    const Run run = *it;
    m_runs.erase(it);
    if (run.handoff) {
        finishHandoff(id, run, exitCode);
        return;
    }

    Operation &op = m_ops[row];
    const int cycle = op.cyclesDone + 1;
    op.activity.clear();

    if (run.aborting) {
        op.status = "aborted";
        log(op, "error", tr("Aborted during cycle %1.").arg(cycle));
    } else if (exitCode != 0 || !run.resultSeen) {
        op.status = "failed";
        log(op, "error", exitCode == -1 && !run.resultSeen
                             ? tr("The claude command couldn't run (%1).").arg(m_claude)
                             : tr("Cycle %1 ended without completing (exit %2).").arg(cycle).arg(exitCode));
    } else {
        op.cyclesDone = cycle;
        op.sitreps << op.sitrep;
        writeReports(op, run.actions);
        log(op, "sys", tr("Cycle %1 complete. Debrief filed.").arg(cycle));
        emit cycleFinished(row, cycle);
    }
    collectIntel(id);

    const bool more = op.status == "deployed" && op.cyclesDone < op.cycles;
    if (op.status == "deployed" && !more) {
        op.status = "complete";
        log(op, "sys", tr("Operation complete."));
    }
    changed(row);
    save();
    if (more) {
        advance(id);
    } else {
        emit deployedCountChanged();
        emit operationFinished(row);
    }
}

void Operations::finishHandoff(const QString &id, const Run &run, int exitCode) {
    const int row = rowOf(id);
    Operation &op = m_ops[row];
    op.activity.clear();
    if (run.aborting) {
        op.status = "aborted";
        log(op, "error", tr("Aborted during the hand-off."));
        changed(row);
        save();
        emit deployedCountChanged();
        emit operationFinished(row);
        return;
    }

    const QString brief = handoffPath(op);
    if (exitCode == 0 && run.resultSeen && QFileInfo::exists(brief)) {
        op.handoffBrief = brief;
        op.handoffs << brief;
        log(op, "sys", tr("Handoff brief filed. Session %1 takes over.").arg(op.session + 1));
    } else {
        // The old session couldn't write a brief, but its context still has to
        // go; the fresh session starts from the last debrief instead.
        op.handoffBrief = op.reports.isEmpty() ? QString() : op.reports.last();
        log(op, "error", tr("No handoff brief was written. Session %1 starts from the last debrief.")
                             .arg(op.session + 1));
    }
    op.sessionId.clear();
    op.session += 1;
    op.contextTokens = 0;
    changed(row);
    save();
    startCycle(id);
}

void Operations::writeReports(Operation &op, const QStringList &actions) {
    const QString report = reportPath(op, op.cyclesDone);
    if (!QFileInfo::exists(report)) {
        QSaveFile file(report);
        if (file.open(QIODevice::WriteOnly)) {
            file.write(Stream::fallbackReport(op.codename, op.cyclesDone, op.cycles, op.objective, op.sitrep,
                                              actions, op.intel).toUtf8());
            file.commit();
        }
    }
    if (!op.reports.contains(report))
        op.reports << report;

    QList<Stream::DossierEntry> entries;
    for (int i = 0; i < op.reports.size(); ++i)
        entries.append({i + 1, QFileInfo(op.reports.at(i)).fileName().prepend("debriefs/"), op.sitreps.value(i)});
    QSaveFile dossier(dossierPath(op));
    if (dossier.open(QIODevice::WriteOnly)) {
        dossier.write(Stream::dossier(op.codename, op.objective, op.directory, entries).toUtf8());
        dossier.commit();
    }
}

void Operations::collectIntel(const QString &id) {
    const int row = rowOf(id);
    if (row < 0)
        return;
    // Changed files, from git when the project is a repository. Anything else
    // just leaves the intel empty.
    auto *git = new QProcess(this);
    git->setWorkingDirectory(m_ops.at(row).directory);
    connect(git, &QProcess::finished, this, [this, id, git](int code) {
        const int r = rowOf(id);
        if (r >= 0 && code == 0) {
            QStringList files;
            for (const auto &line : QString::fromUtf8(git->readAllStandardOutput()).split('\n', Qt::SkipEmptyParts))
                files << line.trimmed();
            m_ops[r].intel = files.mid(0, 200);
            changed(r);
            save();
        }
        git->deleteLater();
    });
    connect(git, &QProcess::errorOccurred, git, &QObject::deleteLater);
    git->start("git", {"status", "--porcelain", "--untracked-files=all"});
}

void Operations::abort(int row) {
    if (row < 0 || row >= m_ops.size())
        return;
    auto it = m_runs.find(m_ops.at(row).id);
    if (it == m_runs.end() || !it->process)
        return;
    it->aborting = true;
    QPointer<QProcess> process = it->process;
    process->terminate();
    QTimer::singleShot(3000, this, [process] {
        if (process && process->state() != QProcess::NotRunning)
            process->kill();
    });
}

void Operations::abortAll() {
    for (int row = 0; row < m_ops.size(); ++row)
        abort(row);
}

void Operations::remove(int row) {
    if (row < 0 || row >= m_ops.size() || m_ops.at(row).status == "deployed")
        return;
    // Only Fireteam's own records go; the project directory is never touched.
    QDir(m_dataDirectory + "/ops/" + m_ops.at(row).id).removeRecursively();
    beginRemoveRows({}, row, row);
    m_ops.removeAt(row);
    endRemoveRows();
    save();
}

bool Operations::openReport(const QString &path) {
    return QFileInfo::exists(path) && QDesktopServices::openUrl(QUrl::fromLocalFile(path));
}

bool Operations::openDossier(int row) {
    return row >= 0 && row < m_ops.size() && openReport(dossierPath(m_ops.at(row)));
}

bool Operations::openLatestReport(int row) {
    return row >= 0 && row < m_ops.size() && !m_ops.at(row).reports.isEmpty()
           && openReport(m_ops.at(row).reports.last());
}

bool Operations::openProject(int row) {
    return row >= 0 && row < m_ops.size() && QDesktopServices::openUrl(QUrl::fromLocalFile(m_ops.at(row).directory));
}

void Operations::checkLink() {
    if (m_claude.isEmpty()) {
        m_linkStatus = "missing";
        m_account.clear();
        emit accountChanged();
        return;
    }
    auto *process = new QProcess(this);
    connect(process, &QProcess::finished, this, [this, process](int code) {
        const QJsonObject status = QJsonDocument::fromJson(process->readAllStandardOutput()).object();
        if (code == 0 && status.value("loggedIn").toBool()) {
            m_linkStatus = "online";
            const QString plan = status.value("subscriptionType").toString();
            m_account = status.value("email").toString();
            if (!plan.isEmpty())
                m_account += " · " + plan.toUpper();
        } else {
            m_linkStatus = "offline";
            m_account.clear();
        }
        emit accountChanged();
        process->deleteLater();
    });
    connect(process, &QProcess::errorOccurred, this, [this, process] {
        m_linkStatus = "offline";
        emit accountChanged();
        process->deleteLater();
    });
    process->start(m_claude, {"auth", "status"});
}

void Operations::log(Operation &op, const QString &kind, const QString &text) {
    const QVariantMap entry{{"time", QDateTime::currentDateTime().toString("HH:mm:ss")}, {"kind", kind},
                            {"text", text}};
    op.comms.append(entry);
    if (op.comms.size() > CommsLimit)
        op.comms.erase(op.comms.begin(), op.comms.begin() + (op.comms.size() - CommsLimit));
    QFile file(m_dataDirectory + "/ops/" + op.id + "/comms.jsonl");
    QDir().mkpath(QFileInfo(file).absolutePath());
    if (file.open(QIODevice::Append))
        file.write(QJsonDocument(QJsonObject::fromVariantMap(entry)).toJson(QJsonDocument::Compact) + "\n");
}

QJsonArray Operations::toJson() const {
    QJsonArray array;
    for (const auto &op : m_ops) {
        QJsonObject object = op.toJson();
        object.insert("dossier", dossierPath(op));
        array.append(object);
    }
    return array;
}

void Operations::load() {
    QFile file(m_dataDirectory + "/operations.json");
    if (!file.open(QIODevice::ReadOnly))
        return;
    for (const auto &value : QJsonDocument::fromJson(file.readAll()).array()) {
        Operation op = Operation::fromJson(value.toObject());
        if (op.id.isEmpty())
            continue;
        // An operation that was deployed when the app last closed lost its
        // agent; it can be redeployed from the cycle it reached.
        if (op.status == "deployed")
            op.status = "interrupted";
        QFile comms(m_dataDirectory + "/ops/" + op.id + "/comms.jsonl");
        if (comms.open(QIODevice::ReadOnly)) {
            const QList<QByteArray> lines = comms.readAll().split('\n');
            for (qsizetype i = qMax<qsizetype>(0, lines.size() - CommsLimit); i < lines.size(); ++i) {
                const QJsonObject entry = QJsonDocument::fromJson(lines.at(i)).object();
                if (!entry.isEmpty())
                    op.comms.append(entry.toVariantMap());
            }
        }
        m_ops.append(op);
    }
}

void Operations::save() const {
    QSaveFile file(m_dataDirectory + "/operations.json");
    if (!file.open(QIODevice::WriteOnly))
        return;
    QJsonArray array;
    for (const auto &op : m_ops)
        array.append(op.toJson());
    file.write(QJsonDocument(array).toJson());
    file.commit();
}
