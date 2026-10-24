#include "operations.h"
#include "fieldlink.h"
#include "intel.h"
#include "stream.h"

#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QCoreApplication>
#include <QCryptographicHash>
#include <QJsonValue>
#include <algorithm>
#include <QRandomGenerator>
#include <QSaveFile>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>
#include <QUuid>

// Comms kept per operation; older lines stay in comms.jsonl on disk.
static constexpr int CommsLimit = 400;
// How long an agent waits on the operator before carrying on: a question gets
// "use your judgement", a permission prompt is refused.
static constexpr int QuestionTimeoutMs = 30 * 60 * 1000;
static constexpr int PromptTimeoutMs = 20 * 60 * 1000;

// claude reports a cycle's closing words twice, as a message and as the
// result, so the result replaces the message instead of repeating it.
static void appendComms(QVariantList &comms, const QVariantMap &entry) {
    if (entry.value("kind") == "result" && !comms.isEmpty()) {
        const QVariantMap last = comms.last().toMap();
        if (last.value("kind") == "say" && last.value("text").toString().trimmed() == entry.value("text").toString().trimmed())
            comms.removeLast();
    }
    comms.append(entry);
}

QJsonObject Operation::toJson() const {
    return {{"id", id}, {"codename", codename}, {"directory", directory}, {"objective", objective},
            {"model", model}, {"roe", roe}, {"cycles", cycles}, {"cyclesDone", cyclesDone},
            {"status", status}, {"sessionId", sessionId}, {"costUsd", costUsd}, {"sitrep", sitrep},
            {"intel", QJsonArray::fromStringList(intel)}, {"reports", QJsonArray::fromStringList(reports)},
            {"sitreps", QJsonArray::fromStringList(sitreps)}, {"created", created.toString(Qt::ISODate)},
            {"contextTokens", contextTokens}, {"contextWindow", contextWindow}, {"handoffAt", handoffAt},
            {"session", session}, {"handoffBrief", handoffBrief}, {"handoffs", QJsonArray::fromStringList(handoffs)},
            {"orders", QJsonArray::fromStringList(orders)}, {"hold", hold},
            {"history", QJsonArray::fromVariantList(history)}, {"rollbacks", QJsonArray::fromStringList(rollbacks)},
            {"allowed", QJsonArray::fromStringList(allowed)}, {"requests", QJsonArray::fromVariantList(requests)},
            {"standing", standing}, {"worktree", worktree}, {"workdir", workdir}, {"branch", branch},
            {"baseBranch", baseBranch}, {"baseCommit", baseCommit}, {"stagedAt", stagedAt}, {"resumeAt", resumeAt},
            {"sessionDir", sessionDir}, {"overwatch", overwatch}, {"reviews", QJsonArray::fromVariantList(reviews)}};
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
    op.orders = strings(o.value("orders"));
    op.hold = o.value("hold").toBool();
    op.history = o.value("history").toArray().toVariantList();
    op.rollbacks = strings(o.value("rollbacks"));
    op.allowed = strings(o.value("allowed"));
    op.requests = o.value("requests").toArray().toVariantList();
    op.standing = o.value("standing").toString();
    op.worktree = o.value("worktree").toBool();
    op.workdir = o.value("workdir").toString();
    op.branch = o.value("branch").toString();
    op.baseBranch = o.value("baseBranch").toString();
    op.baseCommit = o.value("baseCommit").toString();
    op.stagedAt = o.value("stagedAt").toInteger();
    op.resumeAt = o.value("resumeAt").toInteger();
    op.sessionDir = o.value("sessionDir").toString();
    op.overwatch = o.value("overwatch").toString("off");
    op.reviews = o.value("reviews").toArray().toVariantList();
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
      m_dataDirectory(dataDirectory.isEmpty() ? defaultDataDirectory() : dataDirectory),
      m_claude(claude.isEmpty() ? findClaude() : claude) {
    QDir().mkpath(m_dataDirectory);
    loadSettings();
    load();
    m_pinTimer = new QTimer(this);
    m_pinTimer->setSingleShot(true);
    connect(m_pinTimer, &QTimer::timeout, this, &Operations::schedulePinned);
    // One field link per data directory, so tests and a second user don't
    // cross wires.
    m_link = new FieldLink(fieldLinkName(), this);
    connect(m_link, &FieldLink::sitrep, this, &Operations::onSitrep);
    connect(m_link, &FieldLink::question, this, &Operations::onQuestion);
    connect(m_link, &FieldLink::authorise, this, &Operations::onAuthorise);
    // A slot opening up (or a project clearing) lets the queue move.
    connect(this, &Operations::deployedCountChanged, this, &Operations::launchStaged, Qt::QueuedConnection);
    QTimer::singleShot(0, this, &Operations::schedulePinned);
}

QString Operations::defaultDataDirectory() {
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + "/fireteam";
}

void Operations::ensureDataDirectory() { QDir().mkpath(defaultDataDirectory()); }

QString Operations::workdir(const Operation &op) {
    return op.worktree && !op.workdir.isEmpty() ? op.workdir : op.directory;
}

int Operations::stagedCount() const {
    int count = 0;
    for (const auto &op : m_ops)
        count += op.status == "staged";
    return count;
}

void Operations::setMaxDeployed(int max) {
    max = qBound(0, max, 12);
    if (max == m_maxDeployed)
        return;
    m_maxDeployed = max;
    saveSettings();
    emit maxDeployedChanged();
    QTimer::singleShot(0, this, &Operations::launchStaged);
}

static QVariantList defaultLoadouts() {
    return {
        QVariantMap{{"name", "Recon"}, {"model", "haiku"}, {"roe", "restricted"}, {"cycles", 1}, {"handoffAt", 150000},
                    {"worktree", false}, {"standing", "Investigate and report; change as little as possible."}},
        QVariantMap{{"name", "Standard"}, {"model", "sonnet"}, {"roe", "restricted"}, {"cycles", 3},
                    {"handoffAt", 250000}, {"worktree", true}, {"standing", ""}},
        QVariantMap{{"name", "Heavy"}, {"model", "opus"}, {"roe", "restricted"}, {"cycles", 5}, {"handoffAt", 400000},
                    {"worktree", true}, {"standing", "Run the tests at the end of every cycle and fix what fails."}},
    };
}

void Operations::loadSettings() {
    QFile file(m_dataDirectory + "/settings.json");
    QJsonObject settings;
    if (file.open(QIODevice::ReadOnly))
        settings = QJsonDocument::fromJson(file.readAll()).object();
    m_maxDeployed = qBound(0, settings.value("maxDeployed").toInt(3), 12);
    m_loadouts = settings.contains("loadouts") ? settings.value("loadouts").toArray().toVariantList() : defaultLoadouts();
}

void Operations::saveSettings() const {
    QSaveFile file(m_dataDirectory + "/settings.json");
    if (!file.open(QIODevice::WriteOnly))
        return;
    file.write(QJsonDocument(QJsonObject{{"maxDeployed", m_maxDeployed},
                                         {"loadouts", QJsonArray::fromVariantList(m_loadouts)}}).toJson());
    file.commit();
}

void Operations::saveLoadout(const QVariantMap &loadout) {
    const QString name = loadout.value("name").toString().trimmed();
    if (name.isEmpty())
        return;
    QVariantMap entry = loadout;
    entry.insert("name", name);
    for (int i = 0; i < m_loadouts.size(); ++i)
        if (m_loadouts.at(i).toMap().value("name").toString().compare(name, Qt::CaseInsensitive) == 0) {
            m_loadouts[i] = entry;
            saveSettings();
            emit loadoutsChanged();
            return;
        }
    m_loadouts.append(entry);
    saveSettings();
    emit loadoutsChanged();
}

QVariantMap Operations::serviceRecord() const {
    int runs = 0, completed = 0, failed = 0, files = 0, added = 0, removed = 0, handoffs = 0;
    qint64 seconds = 0;
    double cost = 0;
    QHash<QString, QString> gradeKeys;
    QVariantMap grades{{"pass", 0}, {"needs-work", 0}, {"fail", 0}};
    // Weeks start on Monday; the last eight, oldest first.
    const QDate thisWeek = QDate::currentDate().addDays(1 - QDate::currentDate().dayOfWeek());
    QList<double> weekCost(8, 0);
    QList<int> weekCycles(8, 0);
    QHash<QString, QVariantMap> projects;
    for (const auto &op : m_ops) {
        cost += op.costUsd;
        handoffs += op.handoffs.size();
        QVariantMap project = projects.value(op.directory, {{"path", op.directory},
                                                            {"name", QFileInfo(op.directory).fileName()},
                                                            {"runs", 0}, {"cost", 0.0}, {"operations", 0}});
        project["operations"] = project["operations"].toInt() + 1;
        project["cost"] = project["cost"].toDouble() + op.costUsd;
        for (const QVariant &value : op.history) {
            const QVariantMap entry = value.toMap();
            const QString outcome = entry.value("outcome").toString();
            if (outcome == "pinned")
                continue;
            runs += 1;
            completed += outcome == "complete";
            failed += outcome == "failed" || outcome == "aborted";
            files += entry.value("files").toInt();
            added += entry.value("added").toInt();
            removed += entry.value("removed").toInt();
            seconds += entry.value("seconds").toLongLong();
            project["runs"] = project["runs"].toInt() + 1;
            const QDate day = QDateTime::fromString(entry.value("started").toString(), Qt::ISODate).date();
            const qint64 weeksAgo = day.isValid() ? day.addDays(1 - day.dayOfWeek()).daysTo(thisWeek) / 7 : -1;
            if (weeksAgo >= 0 && weeksAgo < 8) {
                weekCost[7 - weeksAgo] += entry.value("cost").toDouble();
                weekCycles[7 - weeksAgo] += outcome == "complete";
            }
        }
        projects.insert(op.directory, project);
        for (const QVariant &review : op.reviews) {
            const QString grade = review.toMap().value("grade").toString();
            if (grades.contains(grade))
                grades[grade] = grades[grade].toInt() + 1;
        }
    }
    QVariantList weeks;
    for (int i = 0; i < 8; ++i)
        weeks.append(QVariantMap{{"start", thisWeek.addDays(-7 * (7 - i)).toString(Qt::ISODate)},
                                 {"cost", weekCost.at(i)}, {"cycles", weekCycles.at(i)}});
    QVariantList busiest;
    for (const QVariantMap &project : std::as_const(projects))
        busiest.append(project);
    std::sort(busiest.begin(), busiest.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap().value("runs").toInt() > b.toMap().value("runs").toInt();
    });
    return {{"operations", m_ops.size()}, {"deployed", deployedCount()}, {"runs", runs}, {"completed", completed},
            {"failed", failed}, {"successRate", completed + failed > 0 ? double(completed) / (completed + failed) : 0.0},
            {"files", files}, {"added", added}, {"removed", removed}, {"seconds", double(seconds)}, {"cost", cost},
            {"handoffs", handoffs}, {"weeks", weeks}, {"projects", busiest.mid(0, 5)}, {"grades", grades}};
}

void Operations::removeLoadout(const QString &name) {
    for (int i = 0; i < m_loadouts.size(); ++i)
        if (m_loadouts.at(i).toMap().value("name").toString() == name) {
            m_loadouts.removeAt(i);
            saveSettings();
            emit loadoutsChanged();
            return;
        }
}

Operations::~Operations() {
    // Closing the app ends its agents (and any git check still running)
    // rather than leaving them working unseen.
    for (QProcess *process : findChildren<QProcess *>()) {
        process->disconnect();
        process->kill();
        process->waitForFinished(2000);
    }
    for (auto &op : m_ops) {
        if (op.status == "deployed")
            op.status = "interrupted";
        else if (op.status == "staged")
            op.status = "standby";
    }
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
            {HandoffBriefRole, "handoffBrief"}, {OrdersRole, "orders"}, {HoldRole, "hold"},
            {CeilingRole, "ceiling"}, {HistoryRole, "history"}, {CanUndoRollbackRole, "canUndoRollback"},
            {EventsRole, "events"}, {RequestsRole, "requests"}, {AllowedRole, "allowed"}, {StandingRole, "standing"},
            {WorktreeRole, "worktree"}, {WorkdirRole, "workdir"}, {BranchRole, "branch"},
            {BaseBranchRole, "baseBranch"}, {ResumeAtRole, "resumeAt"}, {QueueRole, "queue"},
            {OverwatchRole, "overwatch"}, {ReviewsRole, "reviews"}, {ProgressRole, "progress"},
            {ProgressNoteRole, "progressNote"}, {QuestionsRole, "questions"}, {PromptsRole, "prompts"}};
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
    case OrdersRole: return op.orders;
    case HoldRole: return op.hold;
    case CeilingRole: return double(ceiling(op));
    case HistoryRole: return op.history;
    case CanUndoRollbackRole: return !op.rollbacks.isEmpty();
    case EventsRole: return op.events;
    case RequestsRole: return op.requests;
    case AllowedRole: return op.allowed;
    case StandingRole: return op.standing;
    case WorktreeRole: return op.worktree;
    case WorkdirRole: return workdir(op);
    case BranchRole: return op.branch;
    case BaseBranchRole: return op.baseBranch;
    case ResumeAtRole: return double(op.resumeAt);
    case OverwatchRole: return op.overwatch;
    case ReviewsRole: return op.reviews;
    case ProgressRole: return op.progress;
    case ProgressNoteRole: return op.progressNote;
    case QuestionsRole: return op.questions;
    case PromptsRole: return op.prompts;
    case QueueRole: {
        // Place in the queue, from 1, for a staged operation.
        if (op.status != "staged")
            return 0;
        int place = 1;
        for (const auto &other : m_ops)
            place += other.status == "staged" && other.stagedAt < op.stagedAt;
        return place;
    }
    }
    return {};
}

int Operations::deployedCount() const {
    int count = 0;
    for (const auto &op : m_ops)
        count += op.status == "deployed";
    return count;
}

int Operations::find(const QString &query) const {
    const QString wanted = query.trimmed().toUpper().replace('-', ' ').replace('_', ' ');
    if (wanted.isEmpty())
        return -1;
    int match = -1;
    for (int i = 0; i < m_ops.size(); ++i) {
        if (m_ops.at(i).id.toUpper() == wanted || m_ops.at(i).codename == wanted)
            return i;
        if (m_ops.at(i).id.toUpper().startsWith(wanted)) {
            if (match >= 0)
                return -1;
            match = i;
        }
    }
    return match;
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
                       const QString &roe, const QString &model, int handoffAt, bool worktree,
                       const QString &standing, const QString &overwatch) {
    if (!validate(directory, objective).isEmpty())
        return -1;
    Operation op;
    op.id = QUuid::createUuid().toString(QUuid::WithoutBraces).left(8);
    op.codename = codename.trimmed().isEmpty() ? suggestCodename() : codename.trimmed().toUpper();
    op.directory = QDir::cleanPath(directory.trimmed());
    op.objective = objective.trimmed();
    op.cycles = qBound(1, cycles, 20);
    op.roe = roe == "free" || roe == "supervised" ? roe : "restricted";
    op.model = model.trimmed();
    op.handoffAt = qMax(0, handoffAt);
    op.standing = standing.trimmed();
    op.overwatch = QStringList{"review", "fix"}.contains(overwatch) ? overwatch : "off";
    // Only a repository with a commit can have a worktree.
    op.worktree = worktree && Intel::repository(op.directory).value("commits").toBool();
    op.created = QDateTime::currentDateTime();
    QDir().mkpath(m_dataDirectory + "/ops/" + op.id + "/debriefs");

    beginInsertRows({}, 0, 0);
    m_ops.prepend(op);
    endInsertRows();
    log(m_ops.first(), "sys", tr("Operation planned: %1 cycles, %2, %3, %4.")
                                  .arg(op.cycles).arg(op.roe == "free" ? tr("weapons free") : op.roe == "supervised" ? tr("supervised") : tr("restricted"))
                                  .arg(op.handoffAt > 0 ? tr("hand off at %1").arg(Stream::tokens(op.handoffAt))
                                                        : tr("no hand-off"))
                                  .arg(op.worktree ? tr("in its own worktree") : tr("in place")));
    save();
    return 0;
}

bool Operations::update(int row, const QString &codename, const QString &objective, int cycles,
                        const QString &roe, const QString &model, int handoffAt, bool worktree,
                        const QString &standing, const QString &overwatch) {
    if (row < 0 || row >= m_ops.size() || m_ops.at(row).status == "deployed" || objective.trimmed().isEmpty())
        return false;
    Operation &op = m_ops[row];
    // The directory stays: Claude Code keeps a session with the project it
    // ran in, so moving it would orphan the session.
    if (!codename.trimmed().isEmpty())
        op.codename = codename.trimmed().toUpper();
    op.objective = objective.trimmed();
    op.cycles = qBound(qMax(1, op.cyclesDone), cycles, 20);
    op.roe = roe == "free" || roe == "supervised" ? roe : "restricted";
    op.model = model.trimmed();
    op.handoffAt = qMax(0, handoffAt);
    op.standing = standing.trimmed();
    op.overwatch = QStringList{"review", "fix"}.contains(overwatch) ? overwatch : "off";
    // An active worktree stays until it's extracted or discarded.
    if (op.workdir.isEmpty())
        op.worktree = worktree && Intel::repository(op.directory).value("commits").toBool();
    if (op.status == "complete" && op.cyclesDone < op.cycles)
        op.status = "standby";
    log(op, "sys", tr("Briefing amended: %1 cycles, %2, %3.")
                       .arg(op.cycles).arg(op.roe == "free" ? tr("weapons free") : op.roe == "supervised" ? tr("supervised") : tr("restricted"))
                       .arg(op.handoffAt > 0 ? tr("hand off at %1").arg(Stream::tokens(op.handoffAt))
                                             : tr("no hand-off")));
    changed(row);
    save();
    return true;
}

qint64 Operations::ceiling(const Operation &op) {
    if (op.handoffAt <= 0)
        return 0;
    // Twice the line leaves a cycle room to finish what it started, and the
    // cap keeps clear of the window's end, where Claude Code would compact.
    return qMin(op.handoffAt * 2, op.contextWindow * 9 / 10);
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
    if (op.status == "staged" || op.status == "pinned")
        return;
    // A finished operation redeploys for one more cycle on the same session.
    if (op.cyclesDone >= op.cycles)
        op.cycles = op.cyclesDone + 1;
    op.hold = false;
    op.fixRounds = 0;
    start(op.id);
    if (m_ops.at(rowOf(op.id)).status == "deployed")
        emit deployed(rowOf(op.id));
}

bool Operations::canStart(const Operation &op, QString *reason) const {
    if (m_maxDeployed > 0 && deployedCount() >= m_maxDeployed) {
        *reason = tr("the squad is at its limit of %n agent(s)", "", m_maxDeployed);
        return false;
    }
    // Two agents working in place in one directory would trample each other.
    const QString here = QDir::cleanPath(workdir(op));
    for (const auto &other : m_ops)
        if (other.id != op.id && other.status == "deployed" && QDir::cleanPath(workdir(other)) == here) {
            *reason = tr("%1 is working in the same directory").arg(other.codename);
            return false;
        }
    return true;
}

void Operations::start(const QString &id) {
    const int row = rowOf(id);
    Operation &op = m_ops[row];
    if (!prepareWorktree(op)) {
        op.status = "failed";
        changed(row);
        save();
        emit operationFinished(row);
        return;
    }
    const qint64 now = QDateTime::currentSecsSinceEpoch();
    if (m_limitedUntil > now) {
        pin(op, m_limitedUntil);
        changed(row);
        save();
        emit deployedCountChanged();
        return;
    }
    QString reason;
    if (!canStart(op, &reason)) {
        if (op.status != "staged") {
            op.status = "staged";
            op.stagedAt = QDateTime::currentMSecsSinceEpoch();
            log(op, "sys", tr("Staged: %1. It deploys when that clears.").arg(reason));
        }
        changed(row);
        save();
        emit deployedCountChanged();
        return;
    }
    op.status = "deployed";
    op.stagedAt = 0;
    op.resumeAt = 0;
    changed(row);
    emit deployedCountChanged();
    save();
    advance(op.id);
}

void Operations::launchStaged() {
    QList<Operation *> queue;
    for (auto &op : m_ops)
        if (op.status == "staged")
            queue << &op;
    std::sort(queue.begin(), queue.end(), [](const Operation *a, const Operation *b) { return a->stagedAt < b->stagedAt; });
    for (Operation *op : queue) {
        QString reason;
        if (m_limitedUntil > QDateTime::currentSecsSinceEpoch() || !canStart(*op, &reason))
            continue;
        log(*op, "sys", tr("Out of the queue and deploying."));
        start(op->id);
    }
    // Rows' places in the queue move along.
    if (!queue.isEmpty())
        emit dataChanged(index(0), index(m_ops.size() - 1));
}

void Operations::pin(Operation &op, qint64 until) {
    op.status = "pinned";
    op.resumeAt = until;
    op.activity.clear();
    log(op, "error", tr("Pinned down by the plan's usage limit. Resuming at %1.")
                         .arg(QDateTime::fromSecsSinceEpoch(until).toString("HH:mm")));
    m_pinTimer->stop();
    QTimer::singleShot(0, this, &Operations::schedulePinned);
}

void Operations::schedulePinned() {
    const qint64 now = QDateTime::currentSecsSinceEpoch();
    qint64 next = 0;
    for (auto &op : m_ops) {
        if (op.status != "pinned")
            continue;
        if (op.resumeAt <= now) {
            // Back in the queue, so the squad limit still holds.
            op.status = "staged";
            op.stagedAt = QDateTime::currentMSecsSinceEpoch();
            log(op, "sys", tr("The usage limit has reset. Back in the fight."));
            emit alert(op.id, tr("%1 is moving again").arg(op.codename), tr("The plan's usage limit has reset."));
            changed(rowOf(op.id));
        } else if (next == 0 || op.resumeAt < next) {
            next = op.resumeAt;
        }
    }
    save();
    if (next > 0)
        m_pinTimer->start(int(qMin<qint64>((next - now) * 1000 + 500, 3600 * 1000)));
    launchStaged();
    emit deployedCountChanged();
}

bool Operations::prepareWorktree(Operation &op) {
    if (!op.worktree || (!op.workdir.isEmpty() && QFileInfo(op.workdir).isDir()))
        return true;
    const QVariantMap repo = Intel::repository(op.directory);
    if (!repo.value("commits").toBool()) {
        log(op, "error", tr("A worktree needs a repository with at least one commit. Commit once, or amend the operation to run in place."));
        return false;
    }
    if (op.branch.isEmpty()) {
        QString slug = op.codename.toLower();
        slug.replace(QRegularExpression("[^a-z0-9]+"), "-");
        op.branch = QString("fireteam/%1-%2").arg(slug, op.id.left(4));
        op.baseBranch = repo.value("branch").toString();
    }
    const QString path = m_dataDirectory + "/worktrees/" + op.id;
    QDir(path).removeRecursively();
    QDir().mkpath(QFileInfo(path).absolutePath());
    QString error;
    const QString workdir = Intel::addWorktree(op.directory, path, op.branch, &error);
    if (workdir.isEmpty()) {
        log(op, "error", tr("Couldn't make a worktree: %1").arg(error));
        return false;
    }
    if (op.baseCommit.isEmpty())
        op.baseCommit = Intel::snapshot(workdir, snapshotRef(op, "base"), QString("Fireteam %1, base").arg(op.codename));
    op.workdir = workdir;
    log(op, "sys", tr("Working in its own worktree on branch %1, from %2.")
                       .arg(op.branch, op.baseBranch.isEmpty() ? tr("the current commit") : op.baseBranch));
    return true;
}

void Operations::shelveWorktree(Operation &op) {
    if (op.workdir.isEmpty())
        return;
    // The work is committed to the branch first, so nothing is lost.
    QString error;
    if (QFileInfo(op.workdir).isDir())
        Intel::commitAll(op.workdir, QString("Fireteam %1: work in progress").arg(op.codename), &error);
    Intel::removeWorktree(op.directory, m_dataDirectory + "/worktrees/" + op.id, op.branch, false);
    op.workdir.clear();
}

QVariantMap Operations::repository(const QString &directory) const {
    return Intel::repository(QDir::cleanPath(directory.trimmed()));
}

QStringList Operations::sharing(const QString &directory, int exceptRow) const {
    QStringList names;
    const QString here = QDir::cleanPath(directory.trimmed());
    for (int i = 0; i < m_ops.size(); ++i)
        if (i != exceptRow && !m_ops.at(i).worktree && QDir::cleanPath(m_ops.at(i).directory) == here)
            names << m_ops.at(i).codename;
    return names;
}

QVariantMap Operations::worktreeSummary(int row) {
    if (row < 0 || row >= m_ops.size() || m_ops.at(row).workdir.isEmpty())
        return {};
    Operation &op = m_ops[row];
    const QString now = Intel::snapshot(op.workdir, snapshotRef(op, "extract"), QString("Fireteam %1, to extract").arg(op.codename));
    int added = 0, removed = 0;
    const QVariantList files = Intel::changes(op.workdir, op.baseCommit, now);
    for (const QVariant &file : files) {
        added += file.toMap().value("added").toInt();
        removed += file.toMap().value("removed").toInt();
    }
    return {{"files", files.size()}, {"added", added}, {"removed", removed}, {"branch", op.branch},
            {"target", Intel::repository(op.directory).value("branch").toString()}};
}

bool Operations::extract(int row) {
    if (row < 0 || row >= m_ops.size() || m_ops.at(row).workdir.isEmpty() || m_ops.at(row).status == "deployed")
        return false;
    Operation &op = m_ops[row];
    QString error;
    if (!Intel::commitAll(op.workdir, QString("%1: %2").arg(op.codename, op.objective.section('\n', 0, 0).left(72)), &error)) {
        log(op, "error", tr("Couldn't commit the worktree: %1").arg(error));
        changed(row);
        return false;
    }
    QStringList conflicts;
    const QString result = Intel::merge(op.directory, op.branch, tr("Extract %1 (Fireteam)").arg(op.codename), &conflicts);
    if (result == "conflicts") {
        log(op, "error", tr("Extraction stopped: %1 conflicts with your branch in %2. Nothing was changed; merge %3 by hand, or amend the work and try again.")
                             .arg(op.branch, conflicts.join(", "), op.branch));
        emit alert(op.id, tr("%1 couldn't be extracted").arg(op.codename), tr("Conflicts in %1").arg(conflicts.join(", ")));
        changed(row);
        return false;
    }
    if (!result.isEmpty()) {
        log(op, "error", tr("Extraction stopped; nothing was changed: %1").arg(result.left(400)));
        changed(row);
        return false;
    }
    Intel::removeWorktree(op.directory, m_dataDirectory + "/worktrees/" + op.id, op.branch, true);
    log(op, "sys", tr("Extracted: %1 merged into %2. The worktree is gone; the next deploy starts a fresh one.")
                       .arg(op.branch, Intel::repository(op.directory).value("branch").toString()));
    op.workdir.clear();
    op.branch.clear();
    op.baseCommit.clear();
    changed(row);
    save();
    collectIntel(op.id);
    return true;
}

bool Operations::discard(int row) {
    if (row < 0 || row >= m_ops.size() || m_ops.at(row).branch.isEmpty() || m_ops.at(row).status == "deployed")
        return false;
    Operation &op = m_ops[row];
    Intel::removeWorktree(op.directory, m_dataDirectory + "/worktrees/" + op.id, op.branch, true);
    log(op, "sys", tr("Worktree and branch %1 discarded. The project wasn't touched.").arg(op.branch));
    op.workdir.clear();
    op.branch.clear();
    op.baseCommit.clear();
    changed(row);
    save();
    return true;
}

void Operations::sendOrders(int row, const QString &text, bool deployNow) {
    if (row < 0 || row >= m_ops.size() || text.trimmed().isEmpty())
        return;
    Operation &op = m_ops[row];
    op.orders << text.trimmed();
    log(op, "cmd", text.trimmed());
    if (op.status == "deployed")
        log(op, "sys", tr("Orders received. They go out at the start of the next cycle."));
    changed(row);
    save();
    if (deployNow && op.status != "deployed")
        deploy(row);
}

void Operations::clearOrders(int row) {
    if (row < 0 || row >= m_ops.size() || m_ops.at(row).orders.isEmpty())
        return;
    Operation &op = m_ops[row];
    op.orders.clear();
    log(op, "sys", tr("Queued orders withdrawn."));
    changed(row);
    save();
}

void Operations::setHold(int row, bool hold) {
    if (row < 0 || row >= m_ops.size() || m_ops.at(row).status != "deployed" || m_ops.at(row).hold == hold)
        return;
    Operation &op = m_ops[row];
    op.hold = hold;
    log(op, "sys", hold ? tr("Holding after this cycle.") : tr("Hold lifted. The operation carries on."));
    changed(row);
    save();
}

void Operations::stand(const QString &id, const QString &status) {
    const int row = rowOf(id);
    Operation &op = m_ops[row];
    op.status = status;
    op.hold = false;
    op.activity.clear();
    changed(row);
    save();
    emit deployedCountChanged();
    emit operationFinished(row);
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
    op.progress = -1;
    op.progressNote.clear();
    const QString report = reportPath(op, cycle);
    QDir().mkpath(QFileInfo(report).absolutePath());
    QFile::remove(report);

    // Claude Code keeps sessions per directory, so an operation that has moved
    // (into a worktree, or back out) starts a fresh session from its notes.
    if (!op.sessionId.isEmpty() && !op.sessionDir.isEmpty()
        && QDir::cleanPath(op.sessionDir) != QDir::cleanPath(workdir(op))) {
        op.sessionId.clear();
        op.session += 1;
        op.contextTokens = 0;
        op.handoffBrief = !op.handoffs.isEmpty() ? op.handoffs.last() : op.reports.isEmpty() ? QString() : op.reports.last();
        log(op, "sys", tr("Moved to %1, so session %2 starts fresh from the last brief.").arg(workdir(op)).arg(op.session));
    }

    // Only the first cycle of a fresh session after a hand-off reads the brief.
    const QString brief = op.sessionId.isEmpty() ? op.handoffBrief : QString();
    const QStringList orders = op.orders;
    op.orders.clear();
    op.activity = tr("Cycle %1 inbound").arg(cycle);
    log(op, "sys", orders.isEmpty() ? tr("Cycle %1 of %2 deployed.").arg(cycle).arg(op.cycles)
                                    : tr("Cycle %1 of %2 deployed with %n order(s) from command.", "", orders.size())
                                          .arg(cycle).arg(op.cycles));
    save();
    // The project as the agent finds it, to diff against when the cycle ends.
    const QString before = Intel::snapshot(workdir(op), snapshotRef(op, QString("run-%1-before").arg(op.history.size() + 1)),
                                           QString("Fireteam %1, before cycle %2").arg(op.codename).arg(cycle));
    const double costAtStart = op.costUsd;
    launch(id, Stream::cyclePrompt(op.codename, op.objective, cycle, op.cycles, report, brief,
                                   QFileInfo(report).absolutePath(), orders, op.standing),
           false);
    Run &run = m_runs[id];
    run.orders = orders;
    run.before = before;
    run.started = QDateTime::currentDateTime();
    run.costAtStart = costAtStart;
}

void Operations::startHandoff(const QString &id, bool midCycle) {
    const int row = rowOf(id);
    Operation &op = m_ops[row];
    const QString brief = handoffPath(op);
    QDir().mkpath(QFileInfo(brief).absolutePath());
    QFile::remove(brief);
    op.activity = tr("Handing off");
    log(op, "sys", tr("Context at %1, past the %2 line. Session %3 is writing a handoff brief.")
                       .arg(Stream::tokens(op.contextTokens), Stream::tokens(op.handoffAt)).arg(op.session));
    launch(id, Stream::handoffPrompt(op.codename, op.objective, op.contextTokens, op.cycles - op.cyclesDone, brief,
                                     midCycle ? op.cyclesDone + 1 : 0),
           true);
}

void Operations::launch(const QString &id, const QString &prompt, bool handoff, bool review) {
    const int row = rowOf(id);
    Operation &op = m_ops[row];
    // Overwatch reads but never writes, in a session of its own.
    QStringList arguments{"-p", prompt,
                          "--output-format", "stream-json", "--verbose",
                          "--permission-mode", review ? "plan" : op.roe == "free" ? "bypassPermissions" : "acceptEdits",
                          "--add-dir", m_dataDirectory + "/ops/" + op.id};
    QStringList allowed = op.allowed;
    if (!review) {
        arguments << "--append-system-prompt" << Stream::systemBrief();
        // The field link: Fireteam's own MCP server for this operation, whose
        // progress and question tools never need approval.
        const QJsonObject mcp{{"mcpServers", QJsonObject{{"fireteam", QJsonObject{
            {"type", "stdio"}, {"command", qEnvironmentVariable("FIRETEAM_BIN", QCoreApplication::applicationFilePath())},
            {"args", QJsonArray{"mcp", "--op", op.id, "--socket", m_link->serverName()}}}}}}};
        arguments << "--mcp-config" << QString::fromUtf8(QJsonDocument(mcp).toJson(QJsonDocument::Compact));
        allowed << "mcp__fireteam__sitrep" << "mcp__fireteam__request_orders";
        // Supervised: anything that would need permission is put to the
        // operator, live, while the agent waits.
        if (op.roe == "supervised")
            arguments << "--permission-prompt-tool" << "mcp__fireteam__authorise";
    }
    // Each approved rule is its own argument, since rules contain spaces.
    if (!allowed.isEmpty())
        arguments << "--allowedTools" << allowed;
    if (!op.model.isEmpty())
        arguments << "--model" << op.model;
    if (!op.sessionId.isEmpty() && !review)
        arguments << "--resume" << op.sessionId;

    auto *process = new QProcess(this);
    process->setWorkingDirectory(workdir(op));
    // The agent signs in with the same Claude Code login as the terminal. Only
    // the markers of a parent Claude Code session are dropped, so a Fireteam
    // started from inside one doesn't look nested to its agents.
    QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
    environment.remove("CLAUDECODE");
    environment.remove("CLAUDE_CODE_ENTRYPOINT");
    // An agent may wait on the operator for a while.
    environment.insert("MCP_TOOL_TIMEOUT", QString::number(QuestionTimeoutMs + 60000));
    process->setProcessEnvironment(environment);
    process->setStandardInputFile(QProcess::nullDevice());

    Run run;
    run.process = process;
    run.handoff = handoff;
    run.review = review;
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
                if (it->review) {
                    log(op, "sys", tr("Overwatch on station%1.").arg(event.text.isEmpty() ? "" : " · " + event.text));
                    break;
                }
                if (!event.sessionId.isEmpty()) {
                    op.sessionId = event.sessionId;
                    op.sessionDir = workdir(op);
                }
                log(op, "sys", tr("Link established%1.").arg(event.text.isEmpty() ? "" : " · " + event.text));
                break;
            case StreamEvent::Say:
                op.activity = event.text.section('\n', 0, 0).left(120);
                log(op, "say", event.text);
                break;
            case StreamEvent::Tool:
                if (!event.toolId.isEmpty())
                    it->tools.insert(event.toolId, {{"tool", event.tool}, {"input", event.input}});
                // The field link's own tools show up as their reports and
                // questions, and tool lookups are housekeeping.
                if (event.tool.startsWith("mcp__fireteam__") || event.tool == "ToolSearch")
                    break;
                op.activity = event.text;
                it->actions << event.text;
                log(op, "tool", event.text);
                break;
            case StreamEvent::RateLimit: {
                m_usage = QVariantMap{{"status", event.limitStatus}, {"resetsAt", double(event.resetsAt)},
                                      {"type", event.text}, {"windows", event.windows},
                                      {"updated", double(QDateTime::currentSecsSinceEpoch())}};
                emit usageChanged();
                if (event.limitStatus == "rejected") {
                    it->limited = true;
                    it->resetsAt = event.resetsAt;
                }
                break;
            }
            case StreamEvent::Denied: {
                const QVariantMap call = it->tools.value(event.toolId);
                if (!call.isEmpty() && !it->review)
                    request(op, call.value("tool").toString(), call.value("input").toMap());
                break;
            }
            case StreamEvent::Usage:
                if (it->review)
                    break;
                op.contextTokens = event.contextTokens;
                if (!it->handoff && !it->pastLine && op.handoffAt > 0 && op.contextTokens >= op.handoffAt) {
                    it->pastLine = true;
                    log(op, "sys", tr("Context at %1, past the %2 line. Handing off after this cycle.")
                                       .arg(Stream::tokens(op.contextTokens), Stream::tokens(op.handoffAt)));
                }
                // A cycle that keeps going far past the line is cut short
                // rather than left to grow toward the end of the window.
                if (!it->handoff && !it->ceiling && !it->aborting && ceiling(op) > 0
                    && op.contextTokens >= ceiling(op)) {
                    it->ceiling = true;
                    log(op, "error", tr("Context at %1, past the %2 ceiling. Stopping the agent mid-cycle to hand off.")
                                         .arg(Stream::tokens(op.contextTokens), Stream::tokens(ceiling(op))));
                    emit alert(op.id, tr("%1 hit the context ceiling").arg(op.codename),
                               tr("Cycle %1 was stopped at %2 and is handing off to a fresh session.")
                                   .arg(op.cyclesDone + 1).arg(Stream::tokens(op.contextTokens)));
                    it->process->terminate();
                }
                break;
            case StreamEvent::Result:
                it->resultSeen = true;
                op.costUsd += event.costUsd;
                // The full list, in case a refusal wasn't recognised as it
                // happened.
                for (const QVariant &denial : it->review ? QVariantList() : event.denials)
                    request(op, denial.toMap().value("tool").toString(), denial.toMap().value("input").toMap());
                if (event.contextWindow > 0)
                    op.contextWindow = event.contextWindow;
                if (!event.sessionId.isEmpty() && !it->review)
                    op.sessionId = event.sessionId;
                if (it->review && !event.isError) {
                    it->actions << event.text;
                    break;
                }
                if (event.isError && Stream::isUsageLimit(event.text)) {
                    it->limited = true;
                    log(op, "error", tr("Run stopped by the plan's usage limit: %1").arg(event.text));
                } else if (event.isError) {
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
    // Whatever the agent was waiting on went with it.
    m_ops[row].questions.clear();
    m_ops[row].prompts.clear();
    if (run.handoff) {
        finishHandoff(id, run, exitCode);
        return;
    }
    if (run.review) {
        finishReview(id, run, exitCode);
        return;
    }

    Operation &op = m_ops[row];
    const int cycle = op.cyclesDone + 1;
    op.activity.clear();
    // A cycle that didn't finish didn't carry out its orders either.
    if (!run.orders.isEmpty() && (run.aborting || run.ceiling || run.limited || exitCode != 0 || !run.resultSeen))
        op.orders = run.orders + op.orders;

    // Stopped by the plan's usage limit: every agent waits for the reset, and
    // this one picks the same cycle up then.
    if (run.limited && !run.aborting) {
        const qint64 now = QDateTime::currentSecsSinceEpoch();
        const qint64 resets = run.resetsAt > now ? run.resetsAt
                            : m_usage.value("resetsAt").toLongLong() > now ? m_usage.value("resetsAt").toLongLong()
                            : now + 30 * 60;
        // A minute's margin past the reset; tests shorten it.
        m_limitedUntil = resets + qEnvironmentVariableIntValue("FIRETEAM_PIN_MARGIN", nullptr)
                         + (qEnvironmentVariableIsSet("FIRETEAM_PIN_MARGIN") ? 0 : 60);
        record(op, run, cycle, "pinned");
        pin(op, m_limitedUntil);
        emit alert(op.id, tr("%1 is pinned down").arg(op.codename),
                   tr("The plan's usage limit was reached. It resumes at %1.")
                       .arg(QDateTime::fromSecsSinceEpoch(m_limitedUntil).toString("HH:mm")));
        collectIntel(id);
        changed(row);
        save();
        emit deployedCountChanged();
        emit operationFinished(row);
        return;
    }

    // Stopped at the ceiling before the cycle could finish: the old session
    // writes a brief and a fresh one picks the same cycle up.
    if (run.ceiling && !run.resultSeen && !run.aborting) {
        record(op, run, cycle, "cut");
        changed(row);
        save();
        startHandoff(id, true);
        return;
    }

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
    }
    record(op, run, cycle, op.status == "deployed" ? "complete" : op.status);
    if (op.status == "deployed")
        emit cycleFinished(row, cycle);
    collectIntel(id);

    const bool more = op.status == "deployed" && op.cyclesDone < op.cycles;
    // The last cycle is done: overwatch looks the work over before it counts.
    if (op.status == "deployed" && !more && op.overwatch != "off") {
        changed(row);
        save();
        startReview(id);
        return;
    }
    if (op.status == "deployed" && !more) {
        op.status = "complete";
        log(op, "sys", tr("Operation complete."));
        emit alert(op.id, tr("%1 complete").arg(op.codename), op.sitrep);
    } else if (op.status == "failed") {
        emit alert(op.id, tr("%1 failed in cycle %2").arg(op.codename).arg(cycle),
                   tr("Check the comms, then retry the cycle."));
    } else if (more && !op.requests.isEmpty()) {
        // Another cycle would only run into the same refusals.
        log(op, "sys", tr("Holding at cycle %1 of %2 for authorisation.").arg(op.cyclesDone).arg(op.cycles));
        emit alert(op.id, tr("%1 is waiting for authorisation").arg(op.codename),
                   tr("%n request(s) to approve or deny before cycle %1.", "", op.requests.size()).arg(op.cyclesDone + 1));
        stand(id, "held");
        return;
    } else if (more && op.hold) {
        log(op, "sys", tr("Holding at cycle %1 of %2, as ordered.").arg(op.cyclesDone).arg(op.cycles));
        emit alert(op.id, tr("%1 is holding").arg(op.codename),
                   tr("Cycle %1 of %2 done. Resume when ready.").arg(op.cyclesDone).arg(op.cycles));
        stand(id, "held");
        return;
    } else if (more) {
        emit alert(op.id, tr("%1: cycle %2 of %3 done").arg(op.codename).arg(op.cyclesDone).arg(op.cycles), op.sitrep);
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
        log(op, "error", tr("Aborted during the hand-off."));
        stand(id, "aborted");
        return;
    }

    const QString brief = handoffPath(op);
    if (exitCode == 0 && run.resultSeen && QFileInfo::exists(brief)) {
        op.handoffBrief = brief;
        op.handoffs << brief;
        log(op, "sys", tr("Handoff brief filed. Session %1 takes over.").arg(op.session + 1));
        emit alert(op.id, tr("%1 handed off").arg(op.codename),
                   tr("Session %1 takes over from a fresh context.").arg(op.session + 1));
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
    if (op.hold) {
        log(op, "sys", tr("Holding before cycle %1, as ordered.").arg(op.cyclesDone + 1));
        stand(id, "held");
        return;
    }
    changed(row);
    save();
    startCycle(id);
}

QString Operations::snapshotRef(const Operation &op, const QString &name) const {
    return QString("refs/fireteam/%1/%2").arg(op.id, name);
}

void Operations::record(Operation &op, const Run &run, int cycle, const QString &outcome) {
    const int index = op.history.size() + 1;
    const QString after = run.before.isEmpty()
        ? QString()
        : Intel::snapshot(workdir(op), snapshotRef(op, QString("run-%1-after").arg(index)),
                          QString("Fireteam %1, after cycle %2").arg(op.codename).arg(cycle));
    int added = 0, removed = 0;
    const QVariantList files = Intel::changes(workdir(op), run.before, after);
    for (const QVariant &file : files) {
        added += file.toMap().value("added").toInt();
        removed += file.toMap().value("removed").toInt();
    }
    const QDateTime now = QDateTime::currentDateTime();
    op.history.append(QVariantMap{
        {"cycle", cycle}, {"session", op.session},
        {"started", run.started.toString(Qt::ISODate)}, {"seconds", run.started.isValid() ? run.started.secsTo(now) : 0},
        {"cost", op.costUsd - run.costAtStart}, {"context", double(op.contextTokens)}, {"before", run.before},
        {"after", after}, {"files", files.size()}, {"added", added}, {"removed", removed}, {"outcome", outcome},
        {"sitrep", outcome == "complete" ? op.sitrep : QString()}});
}

QVariantList Operations::cycleChanges(int row, int run) const {
    if (row < 0 || row >= m_ops.size() || run < 0 || run >= m_ops.at(row).history.size())
        return {};
    const QVariantMap entry = m_ops.at(row).history.at(run).toMap();
    return Intel::changes(workdir(m_ops.at(row)), entry.value("before").toString(), entry.value("after").toString());
}

QString Operations::cycleDiff(int row, int run, const QString &path) const {
    if (row < 0 || row >= m_ops.size() || run < 0 || run >= m_ops.at(row).history.size())
        return {};
    const QVariantMap entry = m_ops.at(row).history.at(run).toMap();
    return Intel::diff(workdir(m_ops.at(row)), entry.value("before").toString(), entry.value("after").toString(), path);
}

bool Operations::rollback(int row, int run) {
    if (row < 0 || row >= m_ops.size() || run < 0 || run >= m_ops.at(row).history.size()
        || m_ops.at(row).status == "deployed")
        return false;
    Operation &op = m_ops[row];
    const QVariantMap entry = op.history.at(run).toMap();
    const QString target = entry.value("before").toString();
    // The tree as it is now is kept first, so the rollback can be undone.
    const QString current = Intel::snapshot(workdir(op), snapshotRef(op, QString("rollback-%1").arg(op.rollbacks.size() + 1)),
                                            QString("Fireteam %1, before a rollback").arg(op.codename));
    if (target.isEmpty() || current.isEmpty() || !Intel::restore(workdir(op), target, current)) {
        log(op, "error", tr("The rollback failed; the project wasn't changed."));
        changed(row);
        return false;
    }
    op.rollbacks << current;
    log(op, "sys", tr("Project rolled back to before cycle %1. Undo puts it back as it was.")
                       .arg(entry.value("cycle").toInt()));
    changed(row);
    save();
    collectIntel(op.id);
    return true;
}

bool Operations::undoRollback(int row) {
    if (row < 0 || row >= m_ops.size() || m_ops.at(row).rollbacks.isEmpty() || m_ops.at(row).status == "deployed")
        return false;
    Operation &op = m_ops[row];
    const QString current = Intel::snapshot(workdir(op), snapshotRef(op, "undo"),
                                            QString("Fireteam %1, before undoing a rollback").arg(op.codename));
    if (current.isEmpty() || !Intel::restore(workdir(op), op.rollbacks.last(), current)) {
        log(op, "error", tr("Undoing the rollback failed; the project wasn't changed."));
        changed(row);
        return false;
    }
    op.rollbacks.removeLast();
    log(op, "sys", tr("Rollback undone."));
    changed(row);
    save();
    collectIntel(op.id);
    return true;
}

void Operations::request(Operation &op, const QString &tool, const QVariantMap &input) {
    const QList<QStringList> choices = Stream::rulesFor(tool, input);
    const QString summary = Stream::describeTool(tool, QJsonObject::fromVariantMap(input));
    QVariantList options;
    for (const QStringList &rules : choices) {
        bool covered = true;
        for (const QString &rule : rules)
            covered = covered && op.allowed.contains(rule);
        // Refused although approved: say so rather than ask again for what
        // was already given.
        if (covered) {
            log(op, "error", tr("Claude Code refused this although %1 is approved: %2").arg(rules.join(", "), summary));
            return;
        }
        options.append(rules);
    }
    for (const QVariant &pending : op.requests)
        if (pending.toMap().value("choices").toList() == options)
            return;
    op.requests.append(QVariantMap{{"choices", options}, {"tool", tool}, {"summary", summary},
                                   {"cycle", op.cyclesDone + 1}, {"time", QDateTime::currentDateTime().toString("HH:mm")}});
    log(op, "denied", tr("Needs authorisation: %1").arg(summary));
    emit alert(op.id, tr("%1 needs authorisation").arg(op.codename), summary);
    save();
}

bool Operations::grant(Operation &op, const QStringList &rules, bool projectWide) {
    if (rules.isEmpty() || rules.first().isEmpty())
        return false;
    QStringList described;
    for (const QString &rule : rules) {
        if (!op.allowed.contains(rule))
            op.allowed << rule;
        described << "`" + Stream::describeRule(rule) + "`";
    }
    // The agent gets told, so it uses the command where it needed it.
    op.orders << tr("The operator has now authorised %1. Use it where it was refused before, as a separate "
                    "command rather than part of a chain.").arg(described.join(", "));
    log(op, "cmd", tr("Authorised: %1").arg(rules.join(", ")));
    if (projectWide) {
        // Claude Code's personal settings for the project, read by every
        // session there (Fireteam's or the user's own).
        // A worktree has its own copy of the file, so it gets the rule too.
        if (!op.workdir.isEmpty() && QFileInfo(op.workdir).isDir()) {
            const QString copy = op.workdir + "/.claude/settings.local.json";
            QFile existing(copy);
            QJsonObject local;
            if (existing.open(QIODevice::ReadOnly))
                local = QJsonDocument::fromJson(existing.readAll()).object();
            existing.close();
            QJsonObject localPermissions = local.value("permissions").toObject();
            QJsonArray localAllow = localPermissions.value("allow").toArray();
            for (const QString &rule : rules)
                if (!localAllow.contains(QJsonValue(rule)))
                    localAllow.append(rule);
            localPermissions.insert("allow", localAllow);
            local.insert("permissions", localPermissions);
            QDir().mkpath(op.workdir + "/.claude");
            QSaveFile out(copy);
            if (out.open(QIODevice::WriteOnly)) {
                out.write(QJsonDocument(local).toJson());
                out.commit();
            }
        }
        const QString path = op.directory + "/.claude/settings.local.json";
        QFile file(path);
        QJsonObject settings;
        if (file.open(QIODevice::ReadOnly)) {
            const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
            file.close();
            if (!document.isObject() && file.size() > 0) {
                log(op, "error", tr("%1 isn't valid JSON, so the rule was only approved for this operation.").arg(path));
                return true;
            }
            settings = document.object();
        }
        QJsonObject permissions = settings.value("permissions").toObject();
        QJsonArray allow = permissions.value("allow").toArray();
        for (const QString &rule : rules)
            if (!allow.contains(QJsonValue(rule)))
                allow.append(rule);
        permissions.insert("allow", allow);
        settings.insert("permissions", permissions);
        QDir().mkpath(QFileInfo(path).absolutePath());
        QSaveFile out(path);
        if (out.open(QIODevice::WriteOnly)) {
            out.write(QJsonDocument(settings).toJson());
            out.commit();
            log(op, "sys", tr("Also allowed for every Claude session in this project, in %1.").arg(path));
        }
    }
    return true;
}

bool Operations::approve(int row, int request, int rule, bool projectWide) {
    if (row < 0 || row >= m_ops.size() || request < 0 || request >= m_ops.at(row).requests.size())
        return false;
    Operation &op = m_ops[row];
    const QVariantList choices = op.requests.at(request).toMap().value("choices").toList();
    if (rule < 0 || rule >= choices.size())
        return false;
    op.requests.removeAt(request);
    grant(op, choices.at(rule).toStringList(), projectWide);
    changed(row);
    save();
    return true;
}

void Operations::deny(int row, int request) {
    if (row < 0 || row >= m_ops.size() || request < 0 || request >= m_ops.at(row).requests.size())
        return;
    Operation &op = m_ops[row];
    const QString summary = op.requests.at(request).toMap().value("summary").toString();
    op.requests.removeAt(request);
    op.orders << tr("The operator denied this, so don't use it; work without it: %1").arg(summary);
    log(op, "cmd", tr("Denied: %1").arg(summary));
    changed(row);
    save();
}

bool Operations::allow(int row, const QString &text, bool projectWide) {
    if (row < 0 || row >= m_ops.size())
        return false;
    Operation &op = m_ops[row];
    if (!grant(op, {Stream::ruleFromText(text)}, projectWide))
        return false;
    changed(row);
    save();
    return true;
}

void Operations::revoke(int row, const QString &rule) {
    if (row < 0 || row >= m_ops.size() || !m_ops.at(row).allowed.contains(rule))
        return;
    Operation &op = m_ops[row];
    op.allowed.removeAll(rule);
    log(op, "cmd", tr("Authorisation withdrawn: %1").arg(rule));
    changed(row);
    save();
}

QString Operations::describeRule(const QString &rule) const { return Stream::describeRule(rule); }

QString Operations::fieldLinkName() const {
    return "fireteam-" + QCryptographicHash::hash(m_dataDirectory.toUtf8(), QCryptographicHash::Sha1).toHex().left(12);
}

void Operations::onSitrep(const QString &opId, const QString &status, int progress) {
    const int row = rowOf(opId);
    if (row < 0)
        return;
    Operation &op = m_ops[row];
    op.progress = progress < 0 ? op.progress : qBound(0, progress, 100);
    op.progressNote = status.left(200);
    log(op, "report", progress >= 0 ? QString("%1% · %2").arg(qBound(0, progress, 100)).arg(op.progressNote) : op.progressNote);
    changed(row);
}

void Operations::onQuestion(const QString &opId, const QString &requestId, const QString &text, const QStringList &options) {
    const int row = rowOf(opId);
    if (row < 0) {
        m_link->reply(requestId, {{"answer", "No operation is listening. Use your best judgement."}});
        return;
    }
    Operation &op = m_ops[row];
    op.questions.append(QVariantMap{{"id", requestId}, {"question", text}, {"options", options},
                                    {"time", QDateTime::currentDateTime().toString("HH:mm")}});
    op.activity = tr("Awaiting orders");
    log(op, "ask", text);
    emit alert(op.id, tr("%1 is asking for orders").arg(op.codename), text);
    changed(row);
    QTimer::singleShot(QuestionTimeoutMs, this, [this, opId, requestId] {
        const int r = rowOf(opId);
        if (r < 0)
            return;
        for (const QVariant &q : m_ops.at(r).questions)
            if (q.toMap().value("id") == requestId) {
                answer(r, requestId, QString());
                return;
            }
    });
}

void Operations::onAuthorise(const QString &opId, const QString &requestId, const QString &tool, const QVariantMap &input) {
    const int row = rowOf(opId);
    if (row < 0) {
        m_link->reply(requestId, {{"behavior", "deny"}, {"message", "No operation is listening."}});
        return;
    }
    Operation &op = m_ops[row];
    const QList<QStringList> choices = Stream::rulesFor(tool, input);
    const QString summary = Stream::describeTool(tool, QJsonObject::fromVariantMap(input));
    // Already approved for this operation ("always"): let it through.
    for (const QStringList &rules : choices) {
        bool covered = !rules.isEmpty();
        for (const QString &rule : rules)
            covered = covered && op.allowed.contains(rule);
        if (covered) {
            m_link->reply(requestId, {{"behavior", "allow"}});
            log(op, "tool", tr("Cleared by standing approval: %1").arg(summary));
            changed(row);
            return;
        }
    }
    QVariantList options;
    for (const QStringList &rules : choices)
        options.append(rules);
    op.prompts.append(QVariantMap{{"id", requestId}, {"tool", tool}, {"summary", summary}, {"choices", options},
                                  {"time", QDateTime::currentDateTime().toString("HH:mm")}});
    op.activity = tr("Requesting permission: %1").arg(summary);
    log(op, "denied", tr("Requesting permission, waiting: %1").arg(summary));
    emit alert(op.id, tr("%1 requests permission").arg(op.codename), summary);
    changed(row);
    QTimer::singleShot(PromptTimeoutMs, this, [this, opId, requestId] {
        const int r = rowOf(opId);
        if (r < 0)
            return;
        for (const QVariant &p : m_ops.at(r).prompts)
            if (p.toMap().value("id") == requestId) {
                decide(r, requestId, "timeout");
                return;
            }
    });
}

bool Operations::answer(int row, const QString &requestId, const QString &text) {
    if (row < 0 || row >= m_ops.size())
        return false;
    Operation &op = m_ops[row];
    for (int i = 0; i < op.questions.size(); ++i) {
        if (op.questions.at(i).toMap().value("id") != requestId)
            continue;
        op.questions.removeAt(i);
        const bool timedOut = text.trimmed().isEmpty();
        const QString reply = timedOut ? QString("No answer from the operator. Use your best judgement and note the decision in your debrief.")
                                       : text.trimmed();
        const bool delivered = m_link->reply(requestId, {{"answer", reply}});
        log(op, timedOut ? "sys" : "cmd", timedOut ? tr("No answer in time; the agent carries on with its own judgement.")
                                                    : tr("Answered: %1").arg(text.trimmed()));
        if (!delivered)
            log(op, "error", tr("The agent that asked has gone, so the answer wasn't delivered."));
        op.activity = op.questions.isEmpty() && op.prompts.isEmpty() ? QString() : op.activity;
        changed(row);
        return delivered;
    }
    return false;
}

bool Operations::decide(int row, const QString &requestId, const QString &decision, int rule) {
    if (row < 0 || row >= m_ops.size())
        return false;
    Operation &op = m_ops[row];
    for (int i = 0; i < op.prompts.size(); ++i) {
        const QVariantMap prompt = op.prompts.at(i).toMap();
        if (prompt.value("id") != requestId)
            continue;
        op.prompts.removeAt(i);
        const bool allow = decision == "once" || decision == "always";
        if (decision == "always") {
            const QVariantList choices = prompt.value("choices").toList();
            for (const QString &r : choices.value(qBound(0, rule, int(choices.size()) - 1)).toStringList())
                if (!op.allowed.contains(r))
                    op.allowed << r;
            save();
        }
        const bool delivered = m_link->reply(requestId, allow ? QJsonObject{{"behavior", "allow"}}
                                                              : QJsonObject{{"behavior", "deny"},
                                                                            {"message", decision == "timeout"
                                                                                 ? "The operator didn't answer in time. Carry on without it."
                                                                                 : "The operator denied this. Carry on without it."}});
        log(op, "cmd", decision == "always" ? tr("Approved, and always for this operation: %1").arg(prompt.value("summary").toString())
                     : decision == "once" ? tr("Approved once: %1").arg(prompt.value("summary").toString())
                     : decision == "timeout" ? tr("No answer in time, so refused: %1").arg(prompt.value("summary").toString())
                     : tr("Denied: %1").arg(prompt.value("summary").toString()));
        if (!delivered)
            log(op, "error", tr("The agent that asked has gone, so the decision wasn't delivered."));
        op.activity = op.questions.isEmpty() && op.prompts.isEmpty() ? QString() : op.activity;
        changed(row);
        return delivered;
    }
    return false;
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

    writeDossier(op);
}

void Operations::writeDossier(const Operation &op) {
    QList<Stream::DossierEntry> entries;
    for (int i = 0; i < op.reports.size(); ++i)
        entries.append({i + 1, QFileInfo(op.reports.at(i)).fileName().prepend("debriefs/"), op.sitreps.value(i)});
    QSaveFile dossier(dossierPath(op));
    if (dossier.open(QIODevice::WriteOnly)) {
        dossier.write(Stream::dossier(op.codename, op.objective, op.directory, entries, op.reviews).toUtf8());
        dossier.commit();
    }
}

void Operations::startReview(const QString &id) {
    const int row = rowOf(id);
    Operation &op = m_ops[row];
    const QString folder = QString("%1/ops/%2/reviews").arg(m_dataDirectory, op.id);
    QDir().mkpath(folder);
    // The whole operation's work: from where it started (its worktree's base,
    // or before its first recorded cycle) to now.
    QString from = op.baseCommit;
    for (const QVariant &entry : op.history)
        if (from.isEmpty())
            from = entry.toMap().value("before").toString();
    const QString now = Intel::snapshot(workdir(op), snapshotRef(op, QString("review-%1").arg(op.reviews.size() + 1)),
                                        QString("Fireteam %1, for overwatch").arg(op.codename));
    QString diffPath;
    const QString diff = Intel::diffAll(workdir(op), from, now);
    if (!diff.trimmed().isEmpty()) {
        diffPath = QString("%1/review-%2.diff").arg(folder).arg(op.reviews.size() + 1, 2, 10, QChar('0'));
        QSaveFile file(diffPath);
        if (file.open(QIODevice::WriteOnly)) {
            file.write(diff.toUtf8());
            file.commit();
        }
    }
    op.activity = tr("Overwatch reviewing");
    log(op, "sys", tr("Cycle %1 was the last. Overwatch is reviewing the work against the objective.").arg(op.cyclesDone));
    launch(id, Stream::reviewPrompt(op.codename, op.objective, op.cyclesDone, diffPath,
                                    m_dataDirectory + "/ops/" + op.id + "/debriefs"),
           false, true);
}

void Operations::finishReview(const QString &id, const Run &run, int exitCode) {
    const int row = rowOf(id);
    Operation &op = m_ops[row];
    op.activity.clear();
    if (run.aborting) {
        log(op, "error", tr("Aborted during the overwatch review."));
        stand(id, "aborted");
        return;
    }
    if (run.limited) {
        // The work is done; only the review waits, and isn't retried.
        log(op, "error", tr("The usage limit stopped the overwatch review; the operation stands as complete without one."));
    }
    const QString reply = run.actions.isEmpty() ? QString() : run.actions.last();
    QVariantMap review = Stream::parseReview(reply);
    if (exitCode != 0 || reply.isEmpty())
        review.insert("summary", tr("Overwatch couldn't finish its review."));
    const QString file = QString("%1/ops/%2/reviews/review-%3.html").arg(m_dataDirectory, op.id)
                             .arg(op.reviews.size() + 1, 2, 10, QChar('0'));
    QSaveFile report(file);
    if (report.open(QIODevice::WriteOnly)) {
        report.write(Stream::reviewReport(op.codename, op.objective, op.cyclesDone, review, reply).toUtf8());
        report.commit();
    }
    review.insert("cycle", op.cyclesDone);
    review.insert("file", file);
    review.insert("time", QDateTime::currentDateTime().toString(Qt::ISODate));
    op.reviews.append(review);
    writeDossier(op);

    const QString grade = review.value("grade").toString();
    const int findings = review.value("findings").toList().size();
    log(op, "review", tr("Overwatch: %1. %2").arg(grade.toUpper(), review.value("summary").toString()));
    // Falls short: one fix cycle with the findings, then overwatch again.
    if ((grade == "needs-work" || grade == "fail") && op.overwatch == "fix" && op.fixRounds < 1 && !run.limited) {
        op.fixRounds += 1;
        op.cycles += 1;
        op.orders << Stream::reviewOrders(review);
        log(op, "sys", tr("Sent back for a fix cycle with %n finding(s).", "", findings));
        emit alert(op.id, tr("%1 sent back by overwatch").arg(op.codename), review.value("summary").toString());
        changed(row);
        save();
        advance(id);
        return;
    }
    op.status = "complete";
    log(op, "sys", tr("Operation complete."));
    emit alert(op.id, tr("%1 complete · overwatch: %2").arg(op.codename, grade), review.value("summary").toString());
    changed(row);
    save();
    emit deployedCountChanged();
    emit operationFinished(row);
}

void Operations::collectIntel(const QString &id) {
    const int row = rowOf(id);
    if (row < 0)
        return;
    // Changed files, from git when the project is a repository. Anything else
    // just leaves the intel empty.
    auto *git = new QProcess(this);
    git->setWorkingDirectory(workdir(m_ops.at(row)));
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
    // Waiting operations just leave the queue.
    if (m_ops.at(row).status == "staged" || m_ops.at(row).status == "pinned") {
        Operation &op = m_ops[row];
        op.status = "standby";
        op.stagedAt = 0;
        op.resumeAt = 0;
        log(op, "sys", tr("Stood down from the queue."));
        changed(row);
        save();
        emit deployedCountChanged();
        return;
    }
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
    // A worktree's work is committed to its branch, which stays.
    shelveWorktree(m_ops[row]);
    // Only Fireteam's own records go: its data and its hidden snapshot refs.
    // The project's files, branches, and index are never touched.
    QDir(m_dataDirectory + "/ops/" + m_ops.at(row).id).removeRecursively();
    if (QFileInfo(m_ops.at(row).directory).isDir())
        Intel::forget(m_ops.at(row).directory, QString("refs/fireteam/%1/").arg(m_ops.at(row).id));
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
    return row >= 0 && row < m_ops.size() && QDesktopServices::openUrl(QUrl::fromLocalFile(workdir(m_ops.at(row))));
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
    appendComms(op.comms, entry);
    op.events += 1;
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
        // The queue is per run of the app; pinned operations keep waiting.
        else if (op.status == "staged")
            op.status = "standby";
        op.hold = false;
        QFile comms(m_dataDirectory + "/ops/" + op.id + "/comms.jsonl");
        if (comms.open(QIODevice::ReadOnly)) {
            const QList<QByteArray> lines = comms.readAll().split('\n');
            for (qsizetype i = qMax<qsizetype>(0, lines.size() - CommsLimit); i < lines.size(); ++i) {
                const QJsonObject entry = QJsonDocument::fromJson(lines.at(i)).object();
                if (!entry.isEmpty())
                    appendComms(op.comms, entry.toVariantMap());
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
