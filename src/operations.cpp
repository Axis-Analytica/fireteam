#include "operations.h"
#include "engines.h"
#include "fieldlink.h"
#include "fieldmanual.h"
#include "graphs.h"
#include "gates.h"
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
#include <memory>
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
            {"sessionDir", sessionDir}, {"overwatch", overwatch}, {"reviews", QJsonArray::fromVariantList(reviews)},
            {"campaign", campaign}, {"campaignKey", campaignKey}, {"dependsOn", QJsonArray::fromStringList(dependsOn)},
            {"gates", QJsonArray::fromVariantList(gates)}, {"criteria", QJsonArray::fromVariantList(criteria)},
            {"preview", QJsonObject::fromVariantMap(preview)}, {"gateFixes", gateFixes}, {"archived", archived},
            {"controls", QJsonObject::fromVariantMap(controls)}, {"engine", engine}};
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
    op.engine = Engines::isKnown(o.value("engine").toString()) ? o.value("engine").toString() : QString("claude");
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
    op.campaign = o.value("campaign").toString();
    op.campaignKey = o.value("campaignKey").toString();
    op.dependsOn = strings(o.value("dependsOn"));
    op.gates = o.value("gates").toArray().toVariantList();
    op.criteria = o.value("criteria").toArray().toVariantList();
    op.preview = o.value("preview").toObject().toVariantMap();
    op.gateFixes = o.value("gateFixes").toInt();
    op.archived = o.value("archived").toBool();
    op.controls = o.value("controls").toObject().toVariantMap();
    return op;
}

Operations::Operations(const QString &dataDirectory, const QString &claude, QObject *parent)
    : QAbstractListModel(parent),
      m_dataDirectory(dataDirectory.isEmpty() ? defaultDataDirectory() : dataDirectory),
      m_claude(claude.isEmpty() ? Engines::executable("claude") : claude) {
    QDir().mkpath(m_dataDirectory);
    refreshEngines();
    loadSettings();
    load();
    // Scheduled operations are looked at twice a minute, and whenever an
    // operation finishes (one may be waiting for it).
    m_scheduleTimer = new QTimer(this);
    m_scheduleTimer->setInterval(20000);
    connect(m_scheduleTimer, &QTimer::timeout, this, &Operations::checkSchedules);
    m_scheduleTimer->start();
    connect(this, &Operations::operationFinished, this, [this] { QTimer::singleShot(0, this, &Operations::checkSchedules); });
    m_pinTimer = new QTimer(this);
    m_pinTimer->setSingleShot(true);
    connect(m_pinTimer, &QTimer::timeout, this, &Operations::schedulePinned);
    // One field link per data directory, so tests and a second user don't
    // cross wires.
    m_link = new FieldLink(fieldLinkName(), this);
    connect(m_link, &FieldLink::sitrep, this, &Operations::onSitrep);
    connect(m_link, &FieldLink::question, this, &Operations::onQuestion);
    connect(m_link, &FieldLink::authorise, this, &Operations::onAuthorise);
    connect(m_link, &FieldLink::objective, this, &Operations::onObjective);
    loadCampaigns();
    // Campaigns follow their operations: finished ones let the next deploy.
    connect(this, &Operations::operationFinished, this, &Operations::onOperationDone, Qt::QueuedConnection);
    // The board's campaign view refreshes at most a few times a second.
    m_campaignNotice = new QTimer(this);
    m_campaignNotice->setSingleShot(true);
    m_campaignNotice->setInterval(150);
    connect(m_campaignNotice, &QTimer::timeout, this, &Operations::campaignsChanged);
    connect(this, &QAbstractItemModel::dataChanged, this, &Operations::campaignChanged);
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
        QVariantMap{{"name", "Standard"}, {"model", "sonnet"}, {"roe", "supervised"}, {"cycles", 3},
                    {"handoffAt", 250000}, {"worktree", true}, {"standing", ""}},
        QVariantMap{{"name", "Heavy"}, {"model", "opus"}, {"roe", "supervised"}, {"cycles", 5}, {"handoffAt", 400000},
                    {"worktree", true}, {"standing", "Run the tests at the end of every cycle and fix what fails."}},
    };
}

void Operations::loadSettings() {
    QFile file(m_dataDirectory + "/settings.json");
    QJsonObject settings;
    if (file.open(QIODevice::ReadOnly))
        settings = QJsonDocument::fromJson(file.readAll()).object();
    m_maxDeployed = qBound(0, settings.value("maxDeployed").toInt(3), 12);
    m_afterAction = settings.value("afterAction").toBool(true);
    m_graphsAuto = settings.value("graphsAuto").toBool(true);
    m_recipes = settings.value("recipes").toArray().toVariantList();
    m_loadouts = settings.contains("loadouts") ? settings.value("loadouts").toArray().toVariantList() : defaultLoadouts();
}

void Operations::saveSettings() const {
    QSaveFile file(m_dataDirectory + "/settings.json");
    if (!file.open(QIODevice::WriteOnly))
        return;
    file.write(QJsonDocument(QJsonObject{{"maxDeployed", m_maxDeployed}, {"afterAction", m_afterAction}, {"graphsAuto", m_graphsAuto}, {"recipes", QJsonArray::fromVariantList(m_recipes)},
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
    // Per engine: operations, cycles run and cost.
    QHash<QString, QVariantMap> engineTotals;
    for (const auto &op : m_ops) {
        cost += op.costUsd;
        QVariantMap engineTotal = engineTotals.value(op.engine, {{"key", op.engine}, {"label", Engines::label(op.engine)},
                                                                 {"operations", 0}, {"cycles", 0}, {"cost", 0.0}});
        engineTotal["operations"] = engineTotal["operations"].toInt() + 1;
        engineTotal["cost"] = engineTotal["cost"].toDouble() + op.costUsd;
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
            engineTotal["cycles"] = engineTotal["cycles"].toInt() + 1;
            const QDate day = QDateTime::fromString(entry.value("started").toString(), Qt::ISODate).date();
            const qint64 weeksAgo = day.isValid() ? day.addDays(1 - day.dayOfWeek()).daysTo(thisWeek) / 7 : -1;
            if (weeksAgo >= 0 && weeksAgo < 8) {
                weekCost[7 - weeksAgo] += entry.value("cost").toDouble();
                weekCycles[7 - weeksAgo] += outcome == "complete";
            }
        }
        projects.insert(op.directory, project);
        engineTotals.insert(op.engine, engineTotal);
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
    // In the engines' own order: Claude Code first.
    QVariantList engines;
    for (const QString &key : Engines::keys())
        if (engineTotals.contains(key))
            engines.append(engineTotals.value(key));
    return {{"operations", m_ops.size()}, {"deployed", deployedCount()}, {"runs", runs}, {"completed", completed},
            {"failed", failed}, {"successRate", completed + failed > 0 ? double(completed) / (completed + failed) : 0.0},
            {"files", files}, {"added", added}, {"removed", removed}, {"seconds", double(seconds)}, {"cost", cost},
            {"handoffs", handoffs}, {"weeks", weeks}, {"projects", busiest.mid(0, 5)}, {"grades", grades},
            {"engines", engines}};
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
            {ProgressNoteRole, "progressNote"}, {QuestionsRole, "questions"}, {PromptsRole, "prompts"},
            {CampaignRole, "campaign"}, {GatesRole, "gates"}, {CriteriaRole, "criteria"}, {PreviewRole, "preview"},
            {LastGatesRole, "lastGates"}, {ArchivedRole, "archived"},
            {ControlsRole, "controls"}, {EngineRole, "engine"}};
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
    case ArchivedRole: return op.archived;
    case ControlsRole: return op.controls;
    case EngineRole: return op.engine;
    case GatesRole: return op.gates;
    case CriteriaRole: return op.criteria;
    case PreviewRole: return op.preview;
    case LastGatesRole: {
        // The latest run's gate results, for the board's proof chip.
        for (qsizetype i = op.history.size() - 1; i >= 0; --i)
            if (op.history.at(i).toMap().contains("gates"))
                return op.history.at(i).toMap().value("gates");
        return QVariantList();
    }
    case CampaignRole: {
        const int c = campaignIndex(op.campaign);
        return c < 0 ? QString() : m_campaigns.at(c).name;
    }
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
    emit inboxChanged();
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
    // The project's own checks, found now and editable in the briefing.
    for (const QVariant &gate : Gates::detect(op.directory)) {
        QVariantMap entry = gate.toMap();
        entry.insert("enabled", true);
        op.gates.append(entry);
    }
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

void Operations::refreshEngines() {
    QVariantList engines = Engines::available();
    // Claude Code is whichever claude this Fireteam was given.
    for (QVariant &value : engines) {
        QVariantMap engine = value.toMap();
        if (engine.value("key") == "claude") {
            engine.insert("path", QFileInfo(m_claude).isExecutable() ? m_claude : QString());
            value = engine;
        }
    }
    if (engines == m_engines)
        return;
    m_engines = engines;
    emit enginesChanged();
}

void Operations::setEngine(int row, const QString &key) {
    if (row < 0 || row >= m_ops.size() || !Engines::isKnown(key))
        return;
    Operation &op = m_ops[row];
    if (op.status == "deployed" || op.engine == key)
        return;
    op.engine = key;
    QString note;
    // A session belongs to the engine that made it, so the next cycle starts
    // a fresh one from the last brief.
    if (!op.sessionId.isEmpty()) {
        op.sessionId.clear();
        op.sessionDir.clear();
        op.session += 1;
        op.contextTokens = 0;
        op.handoffBrief = !op.handoffs.isEmpty() ? op.handoffs.last() : op.reports.isEmpty() ? QString() : op.reports.last();
        note = " " + tr("Session %1 starts fresh from the last brief.").arg(op.session);
    }
    if (op.roe == "supervised" && !Engines::capabilities(key).value("supervised").toBool())
        note += " " + tr("It can't put permissions to you live, so supervised runs as restricted.");
    log(op, "sys", tr("Engine set to %1.").arg(Engines::label(key)) + note);
    changed(row);
    save();
}

void Operations::setReviewEngine(int row, const QString &key, const QString &model) {
    if (row < 0 || row >= m_ops.size() || (!key.isEmpty() && !Engines::isKnown(key)))
        return;
    Operation &op = m_ops[row];
    const QString engine = key == op.engine ? QString() : key;
    if (op.controls.value("reviewEngine").toString() == engine
        && op.controls.value("reviewModel").toString() == model.trimmed())
        return;
    if (engine.isEmpty())
        op.controls.remove("reviewEngine");
    else
        op.controls.insert("reviewEngine", engine);
    if (model.trimmed().isEmpty())
        op.controls.remove("reviewModel");
    else
        op.controls.insert("reviewModel", model.trimmed());
    log(op, "sys", tr("Overwatch will review on %1%2.")
                       .arg(Engines::label(engine.isEmpty() ? op.engine : engine),
                            model.trimmed().isEmpty() ? QString() : " · " + model.trimmed()));
    changed(row);
    save();
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
    if (op.engine == "claude" && m_claude.isEmpty()) {
        log(op, "error", tr("The claude command isn't installed, so the fireteam can't deploy."));
        changed(row);
        return;
    }
    if (op.engine != "claude" && Engines::executable(op.engine).isEmpty()) {
        log(op, "error", tr("%1 isn't installed, so the fireteam can't deploy.").arg(Engines::label(op.engine)));
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
    op.gateFixes = 0;
    // A project's first operation maps it, for this and every later session.
    refreshGraph(op.directory, true);
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
    op.workdir.clear();
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
    refreshGraph(op.directory, false);
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
                                   QFileInfo(report).absolutePath(), orders,
                                   QStringList{op.standing, Stream::criteriaBlock(op.criteria),
                                               brief.isEmpty() && !op.sessionId.isEmpty() ? QString()
                                                   : FieldManual(m_dataDirectory, op.directory).brief(),
                                               brief.isEmpty() && !op.sessionId.isEmpty() ? QString()
                                                   : graphBrief(op.directory)}
                                       .join("\n\n").trimmed()),
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
    // A working directory that's gone is said plainly, not as a failed agent.
    if (!QFileInfo(workdir(op)).isDir()) {
        log(op, "error", tr("The working directory %1 doesn't exist.").arg(workdir(op)));
        QTimer::singleShot(0, this, [this, id] { finishCycle(id, -2); });
        m_runs.insert(id, Run{});
        changed(row);
        return;
    }
    // Overwatch reads but never writes, in a session of its own, and may be on
    // another engine and model.
    QString engine = op.engine;
    QString model = op.model;
    if (review) {
        const QString reviewEngine = op.controls.value("reviewEngine").toString();
        const QString reviewModel = op.controls.value("reviewModel").toString();
        if (Engines::isKnown(reviewEngine) && reviewEngine != engine) {
            engine = reviewEngine;
            model = reviewModel;
        } else if (!reviewModel.isEmpty()) {
            model = reviewModel;
        }
    }
    Engines::RunSpec spec;
    spec.prompt = prompt;
    spec.workdir = workdir(op);
    spec.model = model;
    spec.roe = op.roe;
    spec.allowed = op.allowed;
    spec.extraDir = m_dataDirectory + "/ops/" + op.id;
    spec.review = review;
    spec.stateDir = m_dataDirectory + "/engines";
    if (engine == "claude")
        spec.program = m_claude;
    if (!review) {
        spec.systemBrief = Stream::systemBrief();
        // The field link: Fireteam's own MCP server for this operation.
        spec.mcpCommand = qEnvironmentVariable("FIRETEAM_BIN", QCoreApplication::applicationFilePath());
        spec.mcpArgs = QStringList{"mcp", "--op", op.id, "--socket", m_link->serverName()};
        // An agent may wait on the operator for a while.
        spec.mcpTimeoutMs = QuestionTimeoutMs + 60000;
        // Asking the project's knowledge graph only reads it.
        if (QFileInfo::exists(Graphs::graphFile(m_dataDirectory, op.directory)))
            spec.helperRules = Graphs::allowedRules(graphify());
        spec.resume = op.sessionId;
    }
    const Engines::Command command = Engines::command(engine, spec);

    auto *process = new QProcess(this);
    process->setWorkingDirectory(workdir(op));
    // The agent signs in with the same login as the terminal. Only the markers
    // of a parent Claude Code session are dropped, so a Fireteam started from
    // inside one doesn't look nested to its agents.
    QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
    environment.remove("CLAUDECODE");
    environment.remove("CLAUDE_CODE_ENTRYPOINT");
    environment.insert("MCP_TOOL_TIMEOUT", QString::number(QuestionTimeoutMs + 60000));
    for (auto it = command.environment.begin(); it != command.environment.end(); ++it)
        environment.insert(it.key(), it.value());
    process->setProcessEnvironment(environment);
    // Codex and OpenCode read stdin to its end before starting.
    process->setStandardInputFile(QProcess::nullDevice());

    Run run;
    run.process = process;
    run.handoff = handoff;
    run.review = review;
    run.engine = engine;
    run.parser = std::shared_ptr<Engines::Parser>(Engines::parser(engine).release());
    run.tempFiles = command.tempFiles;
    m_runs.insert(id, run);
    if (engine != op.engine)
        log(op, "sys", tr("Overwatch runs on %1.").arg(Engines::label(engine)));
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
    process->start(command.program, command.arguments);
}

void Operations::readOutput(const QString &id, bool ended) {
    auto it = m_runs.find(id);
    const int row = rowOf(id);
    if (it == m_runs.end() || row < 0 || !it->process)
        return;
    it->buffer += it->process->readAllStandardOutput();
    Operation &op = m_ops[row];
    if (!it->parser)
        it->parser = std::shared_ptr<Engines::Parser>(Engines::parser(it->engine).release());
    int newline;
    while ((newline = it->buffer.indexOf('\n')) >= 0) {
        const QByteArray line = it->buffer.left(newline);
        it->buffer.remove(0, newline + 1);
        for (const auto &event : it->parser->line(line))
            handleEvent(*it, op, event);
    }
    // What the engine leaves unsaid until it's gone.
    if (ended)
        for (const auto &event : it->parser->finish())
            handleEvent(*it, op, event);
    changed(row);
}

void Operations::handleEvent(Run &run, Operation &op, const StreamEvent &event) {
    Run *it = &run;
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
    {
        // Codex and OpenCode don't name their model, so name the engine.
        const QString detail = event.text.isEmpty() && it->engine != "claude" ? Engines::label(it->engine) : event.text;
        log(op, "sys", tr("Link established%1.").arg(detail.isEmpty() ? "" : " · " + detail));
    }
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
        // An edit lights its file on the knowledge graph while the cycle runs.
        if (QStringList{"Edit", "Write", "MultiEdit", "NotebookEdit"}.contains(event.tool)) {
            const QString path = event.input.value("file_path", event.input.value("notebook_path")).toString();
            if (!path.isEmpty()) {
                const QString relative = QDir::cleanPath(QFileInfo(path).isAbsolute()
                    ? QDir(workdir(op)).relativeFilePath(path) : path);
                if (!relative.startsWith("..")) {
                    it->touched.insert(relative, QDateTime::currentMSecsSinceEpoch());
                    emit liveWorkChanged(QDir::cleanPath(op.directory));
                }
            }
        }
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
        if (event.isError && Engines::isUsageLimit(it->engine, event.text)) {
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

void Operations::finishCycle(const QString &id, int exitCode) {
    auto it = m_runs.find(id);
    const int row = rowOf(id);
    if (it == m_runs.end() || row < 0)
        return;
    if (it->process) {
        it->buffer += it->process->readAllStandardOutput();
        it->buffer += '\n';
        readOutput(id, true);
        it->process->deleteLater();
    }
    const Run run = *it;
    m_runs.erase(it);
    for (const QString &file : run.tempFiles)
        QFile::remove(file);
    if (!run.touched.isEmpty())
        emit liveWorkChanged(QDir::cleanPath(m_ops.at(row).directory));
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
                             ? (run.engine == "claude" ? tr("The claude command couldn't run (%1).").arg(m_claude)
                                : tr("%1 couldn't run (%2).").arg(Engines::label(run.engine), Engines::executable(run.engine)))
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
    // A finished cycle is proved before anything follows it.
    if (op.status == "deployed") {
        changed(row);
        save();
        proveCycle(id, cycle);
        return;
    }
    afterCycle(id, cycle);
}

void Operations::afterCycle(const QString &id, int cycle) {
    const int row = rowOf(id);
    if (row < 0)
        return;
    Operation &op = m_ops[row];
    op.activity.clear();
    // Gates still red after the last cycle: up to two more cycles to fix
    // them, then it fails rather than calling red done.
    const QVariantList gates = op.history.isEmpty() ? QVariantList() : op.history.last().toMap().value("gates").toList();
    bool red = false;
    for (const QVariant &gate : gates)
        red = red || !gate.toMap().value("passed").toBool();
    if (op.status == "deployed" && red) {
        op.orders << Stream::gateOrders(gates);
        if (op.cyclesDone >= op.cycles) {
            if (op.gateFixes < 2) {
                op.gateFixes += 1;
                op.cycles += 1;
                log(op, "sys", tr("Gates are red after the last cycle; one more cycle to fix them."));
            } else {
                op.status = "failed";
                log(op, "error", tr("Gates are still red after two fix cycles. The operation isn't done."));
            }
        }
    }
    // A budget reached holds the operation once this cycle is done.
    if (op.status == "deployed" && op.cyclesDone < op.cycles && overBudget(op))
        op.hold = true;
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
        {"sitrep", outcome == "complete" ? op.sitrep : QString()}, {"paths", [&files] {
            // Which files, for the knowledge graph's activity overlay.
            QStringList paths;
            for (int i = 0; i < files.size() && i < 300; ++i)
                paths << files.at(i).toMap().value("path").toString();
            return paths;
        }()}});
    // The map follows the code: a cycle in the project itself redraws it (a
    // worktree's cycles reach the project when they're extracted).
    if (files.size() > 0 && QDir::cleanPath(workdir(op)) == QDir::cleanPath(op.directory))
        refreshGraph(op.directory, false);
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
    emit waiting(row);
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
    emit waiting(row);
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
    const QVariantList gates = op.history.isEmpty() ? QVariantList() : op.history.last().toMap().value("gates").toList();
    launch(id, Stream::reviewPrompt(op.codename, op.objective, op.cyclesDone, diffPath,
                                    m_dataDirectory + "/ops/" + op.id + "/debriefs", op.criteria, gates),
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
    // Overwatch's word on each criterion, over the agent's own.
    for (const QVariant &value : review.value("criteria").toList()) {
        const QVariantMap verdict = value.toMap();
        const int index = verdict.value("index").toInt();
        if (index < 1 || index > op.criteria.size())
            continue;
        QVariantMap criterion = op.criteria.at(index - 1).toMap();
        criterion.insert("state", verdict.value("met").toBool() ? "met" : "unmet");
        criterion.insert("note", verdict.value("note").toString().left(500));
        op.criteria[index - 1] = criterion;
    }
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
    // No optional locks: this read mustn't block a merge happening meanwhile.
    git->start("git", {"--no-optional-locks", "status", "--porcelain", "--untracked-files=all"});
}

void Operations::abort(int row) {
    if (row < 0 || row >= m_ops.size())
        return;
    // Proving a finished cycle: stop the gates and stand it down.
    if (QPointer<Gates> gates = m_gateRunners.take(m_ops.at(row).id)) {
        gates->stop();
        gates->deleteLater();
        log(m_ops[row], "error", tr("Aborted while running gates."));
        stand(m_ops.at(row).id, "aborted");
        return;
    }
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
    refreshEngines();
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
    // "at" is the full moment, for replays; "time" is what the board shows.
    const QDateTime now = QDateTime::currentDateTime();
    const QVariantMap entry{{"time", now.toString("HH:mm:ss")}, {"at", double(now.toMSecsSinceEpoch())},
                            {"kind", kind}, {"text", text}};
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

// Campaigns ------------------------------------------------------------------

QJsonObject Operations::Campaign::toJson() const {
    return {{"budgetUsd", budgetUsd}, {"id", id}, {"name", name}, {"objective", objective}, {"directory", directory}, {"model", model},
            {"status", status}, {"summary", summary}, {"error", error}, {"plan", QJsonArray::fromVariantList(plan)},
            {"created", created.toString(Qt::ISODate)}, {"costUsd", costUsd}};
}

Operations::Campaign Operations::Campaign::fromJson(const QJsonObject &o) {
    Campaign campaign;
    campaign.id = o.value("id").toString();
    campaign.budgetUsd = o.value("budgetUsd").toDouble();
    campaign.name = o.value("name").toString();
    campaign.objective = o.value("objective").toString();
    campaign.directory = o.value("directory").toString();
    campaign.model = o.value("model").toString();
    campaign.status = o.value("status").toString("draft");
    campaign.summary = o.value("summary").toString();
    campaign.error = o.value("error").toString();
    campaign.plan = o.value("plan").toArray().toVariantList();
    campaign.created = QDateTime::fromString(o.value("created").toString(), Qt::ISODate);
    campaign.costUsd = o.value("costUsd").toDouble();
    // A planner that was running when the app closed is gone.
    if (campaign.status == "planning") {
        campaign.status = "failed";
        campaign.error = QObject::tr("Planning was interrupted. Plan it again.");
    }
    return campaign;
}

int Operations::campaignIndex(const QString &id) const {
    for (int i = 0; i < m_campaigns.size(); ++i)
        if (m_campaigns.at(i).id == id)
            return i;
    return -1;
}

void Operations::campaignChanged() {
    if (m_campaignNotice && !m_campaigns.isEmpty())
        m_campaignNotice->start();
}

QVariantList Operations::campaigns() const {
    QVariantList list;
    for (const Campaign &campaign : m_campaigns) {
        QVariantList operations;
        // Before approval the plan; after, the operations it became.
        QHash<QString, int> rows;
        for (int i = 0; i < m_ops.size(); ++i)
            if (m_ops.at(i).campaign == campaign.id)
                rows.insert(m_ops.at(i).campaignKey, i);
        for (const QVariant &value : campaign.plan) {
            QVariantMap entry = value.toMap();
            const int row = rows.value(entry.value("key").toString(), -1);
            if (row >= 0) {
                const Operation &op = m_ops.at(row);
                entry.insert("row", row);
                entry.insert("opId", op.id);
                entry.insert("codename", op.codename);
                entry.insert("status", op.status);
                entry.insert("cyclesDone", op.cyclesDone);
                entry.insert("cycles", op.cycles);
                entry.insert("activity", op.activity);
                entry.insert("branch", op.branch);
                entry.insert("waiting", op.questions.size() + op.prompts.size() + op.requests.size());
            } else {
                entry.insert("row", -1);
                entry.insert("status", campaign.status == "draft" ? "planned" : "missing");
            }
            operations.append(entry);
        }
        list.append(QVariantMap{{"id", campaign.id}, {"name", campaign.name}, {"objective", campaign.objective},
                                {"directory", campaign.directory}, {"status", campaign.status},
                                {"summary", campaign.summary}, {"error", campaign.error}, {"activity", campaign.activity},
                                {"cost", campaign.costUsd}, {"budget", campaign.budgetUsd}, {"operations", operations},
                                {"dossier", QFileInfo::exists(m_dataDirectory + "/campaigns/" + campaign.id + "/dossier.html")}});
    }
    return list;
}

QString Operations::planCampaign(const QString &name, const QString &directory, const QString &objective,
                                 const QString &model) {
    if (!validate(directory, objective).isEmpty())
        return {};
    Campaign campaign;
    campaign.id = QUuid::createUuid().toString(QUuid::WithoutBraces).left(8);
    campaign.name = name.trimmed().isEmpty() ? suggestCodename() : name.trimmed().toUpper();
    campaign.directory = QDir::cleanPath(directory.trimmed());
    campaign.objective = objective.trimmed();
    campaign.model = model.trimmed();
    campaign.created = QDateTime::currentDateTime();
    m_campaigns.prepend(campaign);
    saveCampaigns();
    launchPlanner(campaign.id);
    return campaign.id;
}

void Operations::replanCampaign(const QString &id) {
    const int c = campaignIndex(id);
    if (c < 0 || m_campaigns.at(c).status == "active" || m_planners.contains(id))
        return;
    launchPlanner(id);
}

void Operations::launchPlanner(const QString &id) {
    Campaign &campaign = m_campaigns[campaignIndex(id)];
    campaign.status = "planning";
    campaign.error.clear();
    campaign.activity = tr("Surveying the project");
    // Read-only: the planner looks around but can't change anything.
    const QString map = graphBrief(campaign.directory);
    QStringList others;
    for (const QVariant &engine : m_engines)
        if (engine.toMap().value("key").toString() != "claude")
            others << engine.toMap().value("key").toString();
    QStringList arguments{"-p", Stream::campaignPrompt(campaign.name, campaign.objective, others)
                                    + (map.isEmpty() ? QString() : "\n\n" + map),
                          "--output-format", "stream-json", "--verbose", "--permission-mode", "plan"};
    if (!campaign.model.isEmpty())
        arguments << "--model" << campaign.model;
    auto *process = new QProcess(this);
    process->setWorkingDirectory(campaign.directory);
    QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
    environment.remove("CLAUDECODE");
    environment.remove("CLAUDE_CODE_ENTRYPOINT");
    process->setProcessEnvironment(environment);
    process->setStandardInputFile(QProcess::nullDevice());
    m_planners.insert(id, process);
    auto buffer = std::make_shared<QByteArray>();
    auto reply = std::make_shared<QString>();
    connect(process, &QProcess::readyReadStandardOutput, this, [this, id, process, buffer, reply] {
        *buffer += process->readAllStandardOutput();
        const int c = campaignIndex(id);
        int newline;
        while ((newline = buffer->indexOf('\n')) >= 0) {
            const QByteArray line = buffer->left(newline);
            buffer->remove(0, newline + 1);
            for (const auto &event : Stream::parseLine(line)) {
                if (c < 0)
                    continue;
                if (event.kind == StreamEvent::Tool)
                    m_campaigns[c].activity = event.text;
                else if (event.kind == StreamEvent::Result) {
                    *reply = event.text;
                    m_campaigns[c].costUsd += event.costUsd;
                }
            }
        }
        campaignChanged();
    });
    connect(process, &QProcess::finished, this, [this, id, process, reply](int code) {
        m_planners.remove(id);
        process->deleteLater();
        const int c = campaignIndex(id);
        if (c < 0)
            return;
        Campaign &campaign = m_campaigns[c];
        campaign.activity.clear();
        const QVariantMap plan = Stream::parseCampaignPlan(*reply);
        if (code != 0 || plan.contains("error")) {
            campaign.status = "failed";
            campaign.error = plan.value("error", tr("The planner stopped without a plan.")).toString();
        } else {
            campaign.status = "draft";
            campaign.summary = plan.value("summary").toString();
            campaign.plan = plan.value("operations").toList();
            emit alert(QString(), tr("Campaign %1 is planned").arg(campaign.name),
                       tr("%n operation(s) ready for your review.", "", campaign.plan.size()));
        }
        saveCampaigns();
        emit campaignsChanged();
    });
    connect(process, &QProcess::errorOccurred, this, [this, id, process](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart)
            return;
        m_planners.remove(id);
        process->deleteLater();
        const int c = campaignIndex(id);
        if (c >= 0) {
            m_campaigns[c].status = "failed";
            m_campaigns[c].error = tr("The claude command couldn't run.");
            saveCampaigns();
            emit campaignsChanged();
        }
    });
    process->start(m_claude, arguments);
    emit campaignsChanged();
}

bool Operations::updateCampaignPlan(const QString &id, const QVariantList &operations) {
    const int c = campaignIndex(id);
    if (c < 0 || m_campaigns.at(c).status != "draft")
        return false;
    QVariantList cleaned;
    QSet<QString> keys;
    for (const QVariant &value : operations) {
        const QVariantMap op = value.toMap();
        if (!op.value("objective").toString().trimmed().isEmpty())
            keys.insert(op.value("key").toString());
    }
    for (const QVariant &value : operations) {
        QVariantMap op = value.toMap();
        if (op.value("objective").toString().trimmed().isEmpty())
            continue;
        QStringList depends;
        for (const QString &dependency : op.value("depends").toStringList())
            if (keys.contains(dependency) && dependency != op.value("key").toString())
                depends << dependency;
        op.insert("depends", depends);
        op.insert("cycles", qBound(1, op.value("cycles").toInt(), 20));
        cleaned.append(op);
    }
    // A plan that loops can't be run; the edit is refused.
    if (cleaned.isEmpty() || Stream::dependencyOrder(cleaned).isEmpty())
        return false;
    m_campaigns[c].plan = cleaned;
    saveCampaigns();
    emit campaignsChanged();
    return true;
}

bool Operations::approveCampaign(const QString &id, const QString &roe, const QString &overwatch) {
    const int c = campaignIndex(id);
    if (c < 0 || m_campaigns.at(c).status != "draft")
        return false;
    Campaign &campaign = m_campaigns[c];
    const QStringList order = Stream::dependencyOrder(campaign.plan);
    if (order.isEmpty() || !validate(campaign.directory, campaign.objective).isEmpty())
        return false;
    QHash<QString, QVariantMap> byKey;
    for (const QVariant &value : campaign.plan)
        byKey.insert(value.toMap().value("key").toString(), value.toMap());
    QHash<QString, QString> ids;
    // Created in dependency order, so each knows its dependencies' ids.
    for (const QString &key : order) {
        const QVariantMap planned = byKey.value(key);
        create(planned.value("codename").toString(), campaign.directory, planned.value("objective").toString(),
               planned.value("cycles").toInt(), roe, planned.value("model").toString(), 250000, true, QString(),
               overwatch);
        Operation &op = m_ops.first();
        op.campaign = campaign.id;
        op.campaignKey = key;
        // The planner may route an operation to another installed engine.
        const QString engine = planned.value("engine").toString();
        if (!engine.isEmpty() && Engines::isKnown(engine) && !Engines::executable(engine).isEmpty())
            op.engine = engine;
        for (const QString &dependency : planned.value("depends").toStringList())
            op.dependsOn << ids.value(dependency);
        ids.insert(key, op.id);
        for (const QString &criterion : planned.value("criteria").toStringList())
            op.criteria.append(QVariantMap{{"text", criterion}, {"state", "open"}});
        log(op, "sys", tr("Part of campaign %1.").arg(campaign.name));
    }
    campaign.status = "active";
    save();
    saveCampaigns();
    writeCampaignDossier(campaign);
    emit dataChanged(index(0), index(m_ops.size() - 1));
    emit campaignsChanged();
    scheduleCampaign(id);
    return true;
}

void Operations::resumeCampaign(const QString &id) {
    const int c = campaignIndex(id);
    if (c < 0 || (m_campaigns.at(c).status != "blocked" && m_campaigns.at(c).status != "active"))
        return;
    m_campaigns[c].status = "active";
    m_campaigns[c].error.clear();
    saveCampaigns();
    scheduleCampaign(id);
    emit campaignsChanged();
}

void Operations::scheduleCampaign(const QString &id) {
    const int c = campaignIndex(id);
    if (c < 0 || m_campaigns.at(c).status != "active")
        return;
    // Done means complete and, for a worktree operation, merged back in.
    auto done = [this](const QString &opId) {
        const int row = rowOf(opId);
        return row >= 0 && m_ops.at(row).status == "complete" && m_ops.at(row).branch.isEmpty();
    };
    bool all = true, any = false;
    for (int row = 0; row < m_ops.size(); ++row) {
        Operation &op = m_ops[row];
        if (op.campaign != id)
            continue;
        any = true;
        all = all && done(op.id);
        if (op.status != "standby")
            continue;
        bool ready = true;
        for (const QString &dependency : op.dependsOn)
            ready = ready && done(dependency);
        if (!ready)
            continue;
        // What it builds on goes out with its first cycle.
        QList<QVariantMap> prior;
        for (const QString &dependency : op.dependsOn) {
            const Operation &before = m_ops.at(rowOf(dependency));
            prior.append({{"codename", before.codename}, {"objective", before.objective}, {"sitrep", before.sitrep},
                          {"brief", !before.handoffs.isEmpty() ? before.handoffs.last()
                                    : before.reports.isEmpty() ? QString() : before.reports.last()}});
        }
        const QString orders = Stream::priorWork(prior);
        if (!orders.isEmpty() && op.cyclesDone == 0)
            op.orders.prepend(orders);
        log(op, "sys", tr("Campaign %1: dependencies clear, deploying.").arg(m_campaigns.at(c).name));
        deploy(row);
    }
    if (any && all) {
        m_campaigns[c].status = "complete";
        emit alert(QString(), tr("Campaign %1 complete").arg(m_campaigns.at(c).name), m_campaigns.at(c).objective);
    }
    writeCampaignDossier(m_campaigns.at(c));
    saveCampaigns();
    emit campaignsChanged();
}

void Operations::onOperationDone(int row) {
    if (row < 0 || row >= m_ops.size())
        return;
    if (m_ops.at(row).status == "complete" && m_afterAction)
        reviewAfterAction(m_ops.at(row).id);
    if (m_ops.at(row).campaign.isEmpty())
        return;
    Operation &op = m_ops[row];
    const int c = campaignIndex(op.campaign);
    if (c < 0 || m_campaigns.at(c).status != "active")
        return;
    Campaign &campaign = m_campaigns[c];
    if (op.status == "complete") {
        // Its work joins the project, so the operations after it build on it.
        if (!op.branch.isEmpty() && !extract(row)) {
            campaign.status = "blocked";
            campaign.error = tr("%1 couldn't be merged in; see its comms. Resolve it, then resume the campaign.").arg(op.codename);
            emit alert(QString(), tr("Campaign %1 is blocked").arg(campaign.name), campaign.error);
            saveCampaigns();
            emit campaignsChanged();
            return;
        }
    } else if (op.status == "failed" || op.status == "aborted") {
        campaign.status = "blocked";
        campaign.error = op.status == "failed" ? tr("%1 failed. Retry it, then resume the campaign.").arg(op.codename)
                                               : tr("%1 was aborted. Retry it, then resume the campaign.").arg(op.codename);
        emit alert(QString(), tr("Campaign %1 is blocked").arg(campaign.name), campaign.error);
        saveCampaigns();
        emit campaignsChanged();
        return;
    }
    scheduleCampaign(campaign.id);
}

void Operations::removeCampaign(const QString &id) {
    const int c = campaignIndex(id);
    if (c < 0)
        return;
    if (m_planners.contains(id) && m_planners.value(id))
        m_planners.value(id)->kill();
    // Its operations stay, on their own.
    for (auto &op : m_ops)
        if (op.campaign == id) {
            op.campaign.clear();
            op.dependsOn.clear();
        }
    m_campaigns.removeAt(c);
    QDir(m_dataDirectory + "/campaigns/" + id).removeRecursively();
    save();
    saveCampaigns();
    emit dataChanged(index(0), index(qMax(0, int(m_ops.size()) - 1)));
    emit campaignsChanged();
}

void Operations::writeCampaignDossier(const Campaign &campaign) {
    QVariantList operations;
    for (const QVariant &entry : campaigns().value(campaignIndex(campaign.id)).toMap().value("operations").toList()) {
        QVariantMap op = entry.toMap();
        const int row = op.value("row").toInt();
        if (row >= 0) {
            op.insert("sitrep", m_ops.at(row).sitrep);
            op.insert("dossier", QFileInfo::exists(dossierPath(m_ops.at(row))) ? dossierPath(m_ops.at(row)) : QString());
        }
        operations.append(op);
    }
    const QString folder = m_dataDirectory + "/campaigns/" + campaign.id;
    QDir().mkpath(folder);
    QSaveFile file(folder + "/dossier.html");
    if (file.open(QIODevice::WriteOnly)) {
        file.write(Stream::campaignDossier(campaign.name, campaign.objective, campaign.summary, operations).toUtf8());
        file.commit();
    }
}

bool Operations::openCampaignDossier(const QString &id) {
    const int c = campaignIndex(id);
    if (c < 0)
        return false;
    writeCampaignDossier(m_campaigns.at(c));
    return openReport(m_dataDirectory + "/campaigns/" + id + "/dossier.html");
}

void Operations::loadCampaigns() {
    QFile file(m_dataDirectory + "/campaigns.json");
    if (!file.open(QIODevice::ReadOnly))
        return;
    for (const auto &value : QJsonDocument::fromJson(file.readAll()).array()) {
        const Campaign campaign = Campaign::fromJson(value.toObject());
        if (!campaign.id.isEmpty())
            m_campaigns.append(campaign);
    }
}

void Operations::saveCampaigns() const {
    QSaveFile file(m_dataDirectory + "/campaigns.json");
    if (!file.open(QIODevice::WriteOnly))
        return;
    QJsonArray array;
    for (const Campaign &campaign : m_campaigns)
        array.append(campaign.toJson());
    file.write(QJsonDocument(array).toJson());
    file.commit();
}

// Proof ----------------------------------------------------------------------

bool Operations::browserAvailable() const { return !Gates::browser().isEmpty(); }

QVariantList Operations::detectGates(const QString &directory) const {
    QVariantList gates;
    for (const QVariant &gate : Gates::detect(QDir::cleanPath(directory.trimmed()))) {
        QVariantMap entry = gate.toMap();
        entry.insert("enabled", true);
        gates.append(entry);
    }
    return gates;
}

bool Operations::setProof(int row, const QVariantList &gates, const QString &criteria, const QString &previewCommand,
                          const QString &previewUrl) {
    if (row < 0 || row >= m_ops.size())
        return false;
    Operation &op = m_ops[row];
    // A copy first: the caller may be handing back this operation's own list.
    const QVariantList incoming = gates;
    op.gates.clear();
    for (const QVariant &value : incoming) {
        const QVariantMap gate = value.toMap();
        if (gate.value("command").toString().trimmed().isEmpty())
            continue;
        op.gates.append(QVariantMap{{"name", gate.value("name").toString().trimmed().isEmpty() ? gate.value("command").toString().section(' ', 0, 1)
                                                                                              : gate.value("name").toString().trimmed()},
                                    {"command", gate.value("command").toString().trimmed()},
                                    {"enabled", gate.value("enabled", true).toBool()}});
    }
    // Criteria keep their state when their wording doesn't change.
    QHash<QString, QVariantMap> previous;
    for (const QVariant &value : op.criteria)
        previous.insert(value.toMap().value("text").toString(), value.toMap());
    op.criteria.clear();
    for (const QString &line : criteria.split('\n', Qt::SkipEmptyParts)) {
        const QString text = line.trimmed().remove(QRegularExpression("^([-*•]|\\d+[.)])\\s*"));
        if (!text.isEmpty())
            op.criteria.append(previous.value(text, {{"text", text}, {"state", "open"}}));
    }
    op.preview = previewUrl.trimmed().isEmpty() ? QVariantMap()
                                                : QVariantMap{{"command", previewCommand.trimmed()}, {"url", previewUrl.trimmed()}};
    changed(row);
    save();
    return true;
}

void Operations::onObjective(const QString &opId, int index, bool done, const QString &evidence) {
    const int row = rowOf(opId);
    if (row < 0 || index < 1 || index > m_ops.at(row).criteria.size())
        return;
    Operation &op = m_ops[row];
    QVariantMap criterion = op.criteria.at(index - 1).toMap();
    criterion.insert("state", done ? "claimed" : "open");
    criterion.insert("evidence", evidence.left(500));
    op.criteria[index - 1] = criterion;
    log(op, "report", tr("Criterion %1 %2: %3").arg(index).arg(done ? tr("claimed met") : tr("not met yet"),
                                                               criterion.value("text").toString()));
    changed(row);
    save();
}

void Operations::proveCycle(const QString &id, int cycle) {
    const int row = rowOf(id);
    Operation &op = m_ops[row];
    // A project built from nothing gets its checks partway through: look for
    // them while there are none.
    if (op.gates.isEmpty()) {
        for (const QVariant &gate : Gates::detect(workdir(op))) {
            QVariantMap entry = gate.toMap();
            entry.insert("enabled", true);
            op.gates.append(entry);
        }
        if (!op.gates.isEmpty()) {
            QStringList commands;
            for (const QVariant &gate : op.gates)
                commands << gate.toMap().value("command").toString();
            log(op, "sys", tr("The project has checks now; gates from here on: %1").arg(commands.join(", ")));
        }
    }
    QVariantList enabled;
    for (const QVariant &gate : op.gates)
        if (gate.toMap().value("enabled", true).toBool())
            enabled.append(gate);
    const bool preview = !op.preview.value("url").toString().isEmpty();
    if (enabled.isEmpty() && !preview) {
        afterCycle(id, cycle);
        return;
    }
    auto *gates = new Gates(this);
    m_gateRunners.insert(id, gates);
    auto finish = [this, id, cycle, gates] {
        m_gateRunners.remove(id);
        gates->deleteLater();
        const int r = rowOf(id);
        if (r < 0)
            return;
        // Aborted while proving: the abort already settled it.
        if (m_ops.at(r).status != "deployed")
            return;
        changed(r);
        save();
        afterCycle(id, cycle);
    };
    auto shoot = [this, id, cycle, gates, finish] {
        const int r = rowOf(id);
        if (r < 0)
            return;
        Operation &o = m_ops[r];
        if (o.preview.value("url").toString().isEmpty()) {
            finish();
            return;
        }
        o.activity = tr("Taking the preview screenshot");
        changed(r);
        const QString path = QString("%1/ops/%2/proof/cycle-%3.png").arg(m_dataDirectory, o.id).arg(cycle, 2, 10, QChar('0'));
        QDir().mkpath(QFileInfo(path).absolutePath());
        connect(gates, &Gates::previewed, this, [this, id, path, finish](const QString &shot, const QString &problem) {
            const int r = rowOf(id);
            if (r >= 0 && !m_ops.at(r).history.isEmpty()) {
                Operation &o = m_ops[r];
                QVariantMap entry = o.history.last().toMap();
                if (!shot.isEmpty()) {
                    entry.insert("screenshot", shot);
                    log(o, "report", tr("Preview screenshot taken."));
                } else {
                    log(o, "error", tr("No preview screenshot: %1").arg(problem));
                }
                o.history.last() = entry;
            }
            finish();
        });
        gates->preview(workdir(o), o.preview.value("command").toString(), o.preview.value("url").toString(), path);
    };
    if (enabled.isEmpty()) {
        shoot();
        return;
    }
    op.activity = tr("Running gates");
    log(op, "sys", tr("Running %n gate(s).", "", enabled.size()));
    changed(row);
    connect(gates, &Gates::started, this, [this, id](const QString &name) {
        const int r = rowOf(id);
        if (r >= 0) {
            m_ops[r].activity = tr("Gate: %1").arg(name);
            changed(r);
        }
    });
    connect(gates, &Gates::finished, this, [this, id, shoot](const QVariantList &results) {
        const int r = rowOf(id);
        if (r < 0)
            return;
        Operation &o = m_ops[r];
        if (!o.history.isEmpty()) {
            QVariantMap entry = o.history.last().toMap();
            entry.insert("gates", results);
            o.history.last() = entry;
        }
        int passed = 0;
        for (const QVariant &value : results) {
            const QVariantMap gate = value.toMap();
            passed += gate.value("passed").toBool();
            log(o, gate.value("passed").toBool() ? "report" : "error",
                tr("Gate %1 %2 in %3s: %4").arg(gate.value("name").toString(),
                                                 gate.value("passed").toBool() ? tr("passed") : tr("FAILED"))
                    .arg(gate.value("seconds").toInt()).arg(gate.value("command").toString()));
        }
        if (passed < results.size())
            emit alert(o.id, tr("%1: %2 of %3 gates failed").arg(o.codename).arg(results.size() - passed).arg(results.size()),
                       tr("The next cycle is told to fix them."));
        shoot();
    });
    gates->run(workdir(op), enabled);
}

// Knowledge graphs ------------------------------------------------------------

QString Operations::graphify() const { return Graphs::executable(m_dataDirectory); }

void Operations::setGraphsAuto(bool on) {
    if (on == m_graphsAuto)
        return;
    m_graphsAuto = on;
    saveSettings();
    emit graphsChanged();
}

// Builds a project's graph when it's due: create for a project's first
// operation, otherwise only when there's a graph to keep current.
void Operations::refreshGraph(const QString &directory, bool create) {
    if (!m_graphsAuto || graphify().isEmpty() || !QFileInfo(directory).isDir())
        return;
    const bool exists = QFileInfo::exists(Graphs::graphFile(m_dataDirectory, QDir::cleanPath(directory)));
    if (exists == create)
        return;
    buildGraph(directory);
}

void Operations::buildGraph(const QString &directory) {
    const QString project = QDir::cleanPath(directory);
    const QString executable = graphify();
    if (executable.isEmpty() || project.isEmpty())
        return;
    // One build per project at a time; a change during one builds again after.
    if (m_graphBuilds.value(project)) {
        m_graphPending.insert(project);
        return;
    }
    QDir().mkpath(Graphs::outputDirectory(m_dataDirectory, project));
    auto *process = new QProcess(this);
    process->setWorkingDirectory(project);
    QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
    // No model: the code-only build is local and needs no key.
    environment.insert("GRAPHIFY_BACKEND", "none");
    process->setProcessEnvironment(environment);
    process->setStandardInputFile(QProcess::nullDevice());
    process->setProcessChannelMode(QProcess::MergedChannels);
    m_graphBuilds.insert(project, process);
    m_graphErrors.remove(project);
    connect(process, &QProcess::finished, this, [this, process, project](int code, QProcess::ExitStatus status) {
        const QString output = QString::fromUtf8(process->readAll());
        process->deleteLater();
        m_graphBuilds.remove(project);
        if (code != 0 || status != QProcess::NormalExit || !QFileInfo::exists(Graphs::graphFile(m_dataDirectory, project))) {
            const QStringList lines = output.trimmed().split('\n');
            m_graphErrors.insert(project, output.trimmed().isEmpty() ? tr("graphify stopped.") : lines.last().left(300));
        }
        m_graphViews.remove(project);
        emit graphChanged(project);
        if (m_graphPending.remove(project))
            buildGraph(project);
    });
    connect(process, &QProcess::errorOccurred, this, [this, process, project](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart)
            return;
        process->deleteLater();
        m_graphBuilds.remove(project);
        m_graphErrors.insert(project, tr("graphify couldn't start."));
        emit graphChanged(project);
    });
    process->start(executable, Graphs::buildArguments(m_dataDirectory, project));
    emit graphChanged(project);
}

QVariantMap Operations::graph(const QString &directory) {
    const QString project = QDir::cleanPath(directory);
    const QString file = Graphs::graphFile(m_dataDirectory, project);
    QVariantMap result;
    const QFileInfo info(file);
    if (info.exists()) {
        auto cached = m_graphViews.value(project);
        if (cached.first != info.lastModified() || cached.second.isEmpty()) {
            cached = qMakePair(info.lastModified(), Graphs::view(file));
            m_graphViews.insert(project, cached);
        }
        result = cached.second;
        result.insert("activity", graphActivity(project));
    }
    result.insert("state", m_graphBuilds.value(project) ? "building"
                         : m_graphErrors.contains(project) ? "failed"
                         : info.exists() ? "ready" : "none");
    result.insert("error", m_graphErrors.value(project));
    result.insert("directory", project);
    result.insert("graphFile", file);
    return result;
}

QVariantMap Operations::graphFileDetail(const QString &directory, const QString &path) const {
    return Graphs::fileDetail(Graphs::graphFile(m_dataDirectory, QDir::cleanPath(directory)), path);
}

QVariantMap Operations::graphActivity(const QString &directory) const {
    // Paths from git are from the top of the repository; the graph's are from
    // the project, which may be a folder inside it.
    const QString top = Intel::repository(directory).value("top").toString();
    const QString prefix = top.isEmpty() ? QString()
        : QDir(QFileInfo(top).canonicalFilePath()).relativeFilePath(QFileInfo(directory).canonicalFilePath());
    const QString strip = prefix.isEmpty() || prefix == "." ? QString() : prefix + "/";
    QVariantMap activity;
    for (const Operation &op : m_ops) {
        if (QDir::cleanPath(op.directory) != directory)
            continue;
        QHash<QString, int> cycles;
        for (const QVariant &value : op.history) {
            const QVariantMap entry = value.toMap();
            QStringList paths = entry.value("paths").toStringList();
            // Cycles from before paths were kept: read them back from the snapshots.
            if (!entry.contains("paths"))
                for (const QVariant &file : Intel::changes(op.directory, entry.value("before").toString(),
                                                           entry.value("after").toString()))
                    paths << file.toMap().value("path").toString();
            for (QString path : paths) {
                if (!strip.isEmpty()) {
                    if (!path.startsWith(strip))
                        continue;
                    path = path.mid(strip.size());
                }
                cycles[path] += 1;
            }
        }
        for (auto it = cycles.cbegin(); it != cycles.cend(); ++it) {
            QVariantList list = activity.value(it.key()).toList();
            list << QVariantMap{{"opId", op.id}, {"codename", op.codename}, {"cycles", it.value()}};
            activity.insert(it.key(), list);
        }
    }
    return activity;
}

QVariantList Operations::graphProjects() const {
    QStringList directories;
    for (const Operation &op : m_ops)
        if (!directories.contains(QDir::cleanPath(op.directory)))
            directories << QDir::cleanPath(op.directory);
    for (const Campaign &campaign : m_campaigns)
        if (!directories.contains(QDir::cleanPath(campaign.directory)))
            directories << QDir::cleanPath(campaign.directory);
    QVariantList list;
    for (const QString &directory : directories) {
        if (!QFileInfo(directory).isDir())
            continue;
        const bool ready = QFileInfo::exists(Graphs::graphFile(m_dataDirectory, directory));
        list << QVariantMap{{"directory", directory},
                            {"state", m_graphBuilds.value(directory) ? "building" : m_graphErrors.contains(directory) ? "failed"
                                    : ready ? "ready" : "none"}};
    }
    return list;
}

QString Operations::graphBrief(const QString &directory) {
    const QString project = QDir::cleanPath(directory);
    const QString file = Graphs::graphFile(m_dataDirectory, project);
    if (!QFileInfo::exists(file))
        return {};
    return Graphs::brief(graph(project), file, graphify());
}

void Operations::installGraphify() {
    if (m_graphifyInstall == "installing")
        return;
    const QString python = QStandardPaths::findExecutable("python3");
    if (python.isEmpty()) {
        m_graphifyInstall = tr("Python 3 isn't installed, so graphify can't be.");
        emit graphsChanged();
        return;
    }
    // A virtual environment of its own in Fireteam's data directory: nothing
    // system-wide, and removing the folder removes it.
    const QString target = Graphs::installDirectory(m_dataDirectory);
    auto *process = new QProcess(this);
    process->setProcessChannelMode(QProcess::MergedChannels);
    process->setStandardInputFile(QProcess::nullDevice());
    m_graphifyInstall = "installing";
    emit graphsChanged();
    connect(process, &QProcess::finished, this, [this, process, target](int code, QProcess::ExitStatus status) {
        const QStringList lines = QString::fromUtf8(process->readAll()).trimmed().split('\n');
        process->deleteLater();
        m_graphifyInstall = code == 0 && status == QProcess::NormalExit && QFileInfo(target + "/bin/graphify").isExecutable()
            ? QString() : tr("graphify didn't install: %1").arg(lines.last().left(240));
        emit graphsChanged();
    });
    process->start("/bin/sh", {"-c", "\"$0\" -m venv \"$1\" && \"$1/bin/pip\" install --quiet --disable-pip-version-check graphifyy",
                               python, target});
}

QVariantMap Operations::graphSymbols(const QString &directory, const QString &path) const {
    return Graphs::symbolView(Graphs::graphFile(m_dataDirectory, QDir::cleanPath(directory)), path);
}

QVariantMap Operations::graphLive(const QString &directory) const {
    QVariantMap live;
    for (auto it = m_runs.cbegin(); it != m_runs.cend(); ++it) {
        const int row = rowOf(it.key());
        if (row < 0 || QDir::cleanPath(m_ops.at(row).directory) != QDir::cleanPath(directory))
            continue;
        for (auto file = it->touched.cbegin(); file != it->touched.cend(); ++file)
            live.insert(file.key(), QVariantMap{{"opId", m_ops.at(row).id}, {"codename", m_ops.at(row).codename},
                                                {"at", double(file.value())}});
    }
    return live;
}

// Streamlining -----------------------------------------------------------------

int Operations::inboxCount() const {
    int count = 0;
    for (const Operation &op : m_ops)
        count += op.questions.size() + op.prompts.size() + op.requests.size();
    return count;
}

QVariantList Operations::inbox() const {
    QVariantList items;
    for (int row = 0; row < m_ops.size(); ++row) {
        const Operation &op = m_ops.at(row);
        auto add = [&](const QString &kind, const QVariantMap &entry, int index) {
            items << QVariantMap{{"row", row}, {"opId", op.id}, {"codename", op.codename}, {"kind", kind},
                                 {"id", entry.value("id")}, {"index", index},
                                 {"text", entry.value(kind == "question" ? "question" : "summary")},
                                 {"tool", entry.value("tool")}, {"options", entry.value("options")},
                                 {"choices", entry.value("choices")}, {"time", entry.value("time")}};
        };
        // The agent is stopped on questions and live permissions; refused
        // commands can wait for the next cycle, so they come after.
        for (int i = 0; i < op.questions.size(); ++i)
            add("question", op.questions.at(i).toMap(), i);
        for (int i = 0; i < op.prompts.size(); ++i)
            add("prompt", op.prompts.at(i).toMap(), i);
        for (int i = 0; i < op.requests.size(); ++i)
            add("request", op.requests.at(i).toMap(), i);
    }
    std::stable_sort(items.begin(), items.end(), [](const QVariant &a, const QVariant &b) {
        auto rank = [](const QString &kind) { return kind == "request" ? 1 : 0; };
        const int ra = rank(a.toMap().value("kind").toString()), rb = rank(b.toMap().value("kind").toString());
        if (ra != rb)
            return ra < rb;
        return a.toMap().value("time").toString() > b.toMap().value("time").toString();
    });
    return items;
}

QVariantMap Operations::quickPlan(const QString &text, const QString &fallbackDirectory) const {
    QString objective = text.trimmed();
    QString directory;
    // A path in the text: ~/..., /..., or ./... (quoted or not).
    static const QRegularExpression path(R"((?:^|\s)(?:in\s+|at\s+|for\s+)?("[^"]+"|'[^']+'|(?:~|/|\./)[^\s,;]+))");
    const auto match = path.match(objective);
    if (match.hasMatch()) {
        QString candidate = match.captured(1);
        if (candidate.size() > 1 && (candidate.startsWith('"') || candidate.startsWith('\'')))
            candidate = candidate.mid(1, candidate.size() - 2);
        if (candidate.startsWith("~"))
            candidate = QDir::homePath() + candidate.mid(1);
        if (QFileInfo(candidate).isDir()) {
            directory = QDir::cleanPath(QFileInfo(candidate).absoluteFilePath());
            objective.remove(match.capturedStart(0), match.capturedLength(0));
        }
    }
    // A known project named in the text ("logbook", "test app").
    if (directory.isEmpty()) {
        QStringList known;
        for (const Operation &op : m_ops)
            if (!known.contains(QDir::cleanPath(op.directory)))
                known << QDir::cleanPath(op.directory);
        // The longest name first, so "test app" wins over "app".
        std::sort(known.begin(), known.end(), [](const QString &a, const QString &b) {
            return QFileInfo(a).fileName().size() > QFileInfo(b).fileName().size();
        });
        for (const QString &candidate : known) {
            const QString name = QFileInfo(candidate).fileName();
            const QRegularExpression word("(?:\\b(?:in|to|for|on)\\s+)?\\b" + QRegularExpression::escape(name) + "\\b",
                                          QRegularExpression::CaseInsensitiveOption);
            const auto found = word.match(objective);
            if (name.size() >= 3 && found.hasMatch() && QFileInfo(candidate).isDir()) {
                directory = candidate;
                objective.remove(found.capturedStart(0), found.capturedLength(0));
                break;
            }
        }
    }
    const bool known = !directory.isEmpty();
    if (directory.isEmpty() && QFileInfo(fallbackDirectory).isDir())
        directory = QDir::cleanPath(fallbackDirectory);
    objective = objective.simplified();
    static const QRegularExpression trailing(R"(^[,;:\-\s]+|[,;:\-\s]+$)");
    objective.remove(trailing);
    if (!objective.isEmpty())
        objective[0] = objective.at(0).toUpper();
    return {{"directory", directory}, {"objective", objective}, {"codename", suggestCodename()}, {"known", known}};
}

QVariantMap Operations::environment() const {
    auto find = [](const char *name) { return QStandardPaths::findExecutable(QLatin1String(name)); };
    QString chromium;
    for (const char *name : {"chromium", "chromium-browser", "google-chrome-stable", "google-chrome", "brave"})
        if (chromium.isEmpty())
            chromium = find(name);
    return {{"claude", QFileInfo(m_claude).isExecutable() ? m_claude : QString()}, {"git", find("git")}, {"graphify", graphify()}, {"chromium", chromium},
            {"qrencode", find("qrencode")}, {"python", find("python3")}};
}

static QVariantList builtinRecipes() {
    auto recipe = [](const QString &name, const QString &objective, const QString &criteria, const QString &loadout) {
        return QVariantMap{{"name", name}, {"objective", objective}, {"criteria", criteria}, {"loadout", loadout}, {"builtin", true}};
    };
    return {
        recipe(QObject::tr("Upgrade dependencies"),
               QObject::tr("Upgrade the project's dependencies to their latest compatible versions, one group at a time, "
                           "fixing whatever breaks. Note anything held back and why."),
               QObject::tr("Every dependency is current or noted as held back\nThe build and tests pass"), "Standard"),
        recipe(QObject::tr("Add tests"),
               QObject::tr("Find the most important untested code and add focused tests for it, starting with the riskiest "
                           "logic. Don't change behaviour; report bugs the tests reveal."),
               QObject::tr("New tests cover the riskiest untested code\nThe tests pass"), "Standard"),
        recipe(QObject::tr("Fix the build"),
               QObject::tr("Get the build and the test suite passing again. Find the root cause of each failure and fix it "
                           "rather than skipping or loosening tests."),
               QObject::tr("The build passes\nThe tests pass\nNo test was skipped or weakened"), "Standard"),
        recipe(QObject::tr("Refresh the README"),
               QObject::tr("Bring the README up to date with the code: what the project does, how to install, build, run and "
                           "test it, and its configuration. Check every command works."),
               QObject::tr("Every command in the README works\nThe README matches the code"), "Recon"),
        recipe(QObject::tr("Security pass"),
               QObject::tr("Review the project for security problems (injection, secrets in the repo, unsafe deserialisation, "
                           "missing authorisation, vulnerable dependencies) and fix what's clearly safe to fix. List the rest."),
               QObject::tr("Each finding is fixed or listed with its risk"), "Heavy"),
        recipe(QObject::tr("Tidy up"),
               QObject::tr("Remove dead code, unused dependencies and stale files, and simplify what's needlessly complicated, "
                           "without changing behaviour."),
               QObject::tr("Behaviour is unchanged\nThe tests pass"), "Standard"),
    };
}

QVariantList Operations::recipes() const { return builtinRecipes() + m_recipes; }

void Operations::saveRecipe(const QVariantMap &recipe) {
    const QString name = recipe.value("name").toString().trimmed();
    if (name.isEmpty() || recipe.value("objective").toString().trimmed().isEmpty())
        return;
    QVariantMap entry{{"name", name}, {"objective", recipe.value("objective")}, {"criteria", recipe.value("criteria")},
                      {"loadout", recipe.value("loadout")}};
    for (int i = 0; i < m_recipes.size(); ++i)
        if (m_recipes.at(i).toMap().value("name").toString().compare(name, Qt::CaseInsensitive) == 0) {
            m_recipes[i] = entry;
            saveSettings();
            emit recipesChanged();
            return;
        }
    m_recipes << entry;
    saveSettings();
    emit recipesChanged();
}

void Operations::removeRecipe(const QString &name) {
    for (int i = 0; i < m_recipes.size(); ++i)
        if (m_recipes.at(i).toMap().value("name").toString() == name) {
            m_recipes.removeAt(i);
            saveSettings();
            emit recipesChanged();
            return;
        }
}

// Budgets and scheduling ---------------------------------------------------------

void Operations::setBudget(int row, double usd, int planPercent) {
    if (row < 0 || row >= m_ops.size())
        return;
    Operation &op = m_ops[row];
    op.controls.insert("budgetUsd", std::max(0.0, usd));
    op.controls.insert("budgetPlan", qBound(0, planPercent, 100));
    op.controls.remove("warned");
    if (usd > 0 || planPercent > 0)
        log(op, "cmd", usd > 0 && planPercent > 0
                           ? tr("Budget set: ≈$%1 of API value, or %2% of the plan's 5-hour window.").arg(usd, 0, 'f', 2).arg(planPercent)
                       : usd > 0 ? tr("Budget set: ≈$%1 of API value.").arg(usd, 0, 'f', 2)
                                 : tr("Budget set: %1% of the plan's 5-hour window.").arg(planPercent));
    else
        log(op, "cmd", tr("Budget removed."));
    changed(row);
    save();
}

void Operations::setCampaignBudget(const QString &id, double usd) {
    const int c = campaignIndex(id);
    if (c < 0)
        return;
    m_campaigns[c].budgetUsd = std::max(0.0, usd);
    saveCampaigns();
    emit campaignsChanged();
}

bool Operations::overBudget(Operation &op) {
    const double budget = op.controls.value("budgetUsd").toDouble();
    if (budget > 0 && op.costUsd >= budget) {
        log(op, "sys", tr("Budget reached: ≈$%1 of ≈$%2. Holding; raise the budget to go on.")
                           .arg(op.costUsd, 0, 'f', 2).arg(budget, 0, 'f', 2));
        emit alert(op.id, tr("%1 reached its budget").arg(op.codename), tr("≈$%1 of API value spent.").arg(op.costUsd, 0, 'f', 2));
        return true;
    }
    if (budget > 0 && op.costUsd >= budget * 0.8 && !op.controls.value("warned").toBool()) {
        op.controls.insert("warned", true);
        log(op, "sys", tr("80% of the budget spent: ≈$%1 of ≈$%2.").arg(op.costUsd, 0, 'f', 2).arg(budget, 0, 'f', 2));
        emit alert(op.id, tr("%1 is near its budget").arg(op.codename), tr("≈$%1 of ≈$%2.").arg(op.costUsd, 0, 'f', 2).arg(budget, 0, 'f', 2));
    }
    const int plan = op.controls.value("budgetPlan").toInt();
    const double used = m_usage.value("windows").toMap().value("five_hour").toMap().value("utilization").toDouble() * 100;
    if (plan > 0 && used >= plan) {
        log(op, "sys", tr("The plan's 5-hour window is %1% used, past this operation's %2%. Holding.").arg(qRound(used)).arg(plan));
        emit alert(op.id, tr("%1 reached its share of the plan").arg(op.codename), tr("%1% of the 5-hour window used.").arg(qRound(used)));
        return true;
    }
    if (!op.campaign.isEmpty()) {
        const int c = campaignIndex(op.campaign);
        if (c >= 0 && m_campaigns.at(c).budgetUsd > 0) {
            double total = m_campaigns.at(c).costUsd;
            for (const Operation &other : m_ops)
                if (other.campaign == op.campaign)
                    total += other.costUsd;
            if (total >= m_campaigns.at(c).budgetUsd) {
                log(op, "sys", tr("Campaign %1 reached its budget: ≈$%2. Holding.").arg(m_campaigns.at(c).name).arg(total, 0, 'f', 2));
                emit alert(op.id, tr("Campaign %1 reached its budget").arg(m_campaigns.at(c).name), tr("≈$%1 of API value spent.").arg(total, 0, 'f', 2));
                return true;
            }
        }
    }
    return false;
}

void Operations::setSchedule(int row, const QString &mode, double at, const QString &afterId) {
    if (row < 0 || row >= m_ops.size())
        return;
    Operation &op = m_ops[row];
    if (op.status == "deployed" || op.status == "staged" || op.status == "pinned")
        return;
    if (mode == "after" && (afterId == op.id || rowOf(afterId) < 0))
        return;
    op.controls.insert("schedule", QVariantMap{{"mode", mode}, {"at", at}, {"after", afterId}});
    op.status = "scheduled";
    if (mode == "time")
        log(op, "cmd", tr("Scheduled: deploys at %1.").arg(QDateTime::fromSecsSinceEpoch(qint64(at)).toString("ddd HH:mm")));
    else if (mode == "reset")
        log(op, "cmd", tr("Scheduled: deploys when the plan's usage window resets."));
    else
        log(op, "cmd", tr("Scheduled: deploys when %1 completes.").arg(m_ops.at(rowOf(afterId)).codename));
    changed(row);
    save();
    checkSchedules();
}

void Operations::clearSchedule(int row) {
    if (row < 0 || row >= m_ops.size() || !m_ops.at(row).controls.contains("schedule"))
        return;
    Operation &op = m_ops[row];
    op.controls.remove("schedule");
    if (op.status == "scheduled")
        op.status = "standby";
    log(op, "cmd", tr("Schedule cleared."));
    changed(row);
    save();
}

void Operations::checkSchedules() {
    const double now = QDateTime::currentSecsSinceEpoch();
    QStringList due;
    for (const Operation &op : m_ops) {
        if (op.status != "scheduled")
            continue;
        const QVariantMap schedule = op.controls.value("schedule").toMap();
        const QString mode = schedule.value("mode").toString();
        bool ready = false;
        if (mode == "time")
            ready = now >= schedule.value("at").toDouble();
        else if (mode == "reset")
            // When the window resets, or at once if the plan hasn't said when.
            ready = now >= m_usage.value("resetsAt").toDouble() && now >= m_limitedUntil;
        else if (mode == "after") {
            const int target = rowOf(schedule.value("after").toString());
            ready = target < 0 || m_ops.at(target).status == "complete";
        }
        if (ready)
            due << op.id;
    }
    for (const QString &id : due) {
        const int row = rowOf(id);
        if (row < 0)
            continue;
        Operation &op = m_ops[row];
        op.controls.remove("schedule");
        op.status = "standby";
        log(op, "sys", tr("Scheduled time reached; deploying."));
        deploy(row);
        changed(row);
    }
    if (!due.isEmpty())
        save();
}

QVariantMap Operations::readReport(const QString &path) const {
    const QString real = QFileInfo(path).canonicalFilePath();
    const QString root = QFileInfo(m_dataDirectory).canonicalFilePath();
    if (real.isEmpty() || root.isEmpty() || !real.startsWith(root + "/"))
        return {};
    QFile file(real);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    const QString text = QString::fromUtf8(file.read(2 * 1024 * 1024));
    const QString suffix = QFileInfo(real).suffix().toLower();
    return {{"text", text}, {"format", suffix == "md" || suffix == "markdown" ? "markdown" : suffix == "html" || suffix == "htm" ? "html" : "text"},
            {"path", real}};
}
