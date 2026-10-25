#pragma once

#include <QAbstractListModel>
#include <QDateTime>
#include <QHash>
#include <QSet>
#include <QJsonArray>
#include <QJsonObject>
#include <QPointer>
#include <QProcess>
#include <QTimer>
#include <memory>

class FieldLink;
namespace Engines { class Parser; }
struct StreamEvent;
class Gates;
#include <QVariantList>

// One development effort handed to a Claude Code agent: a project directory,
// an objective, and a number of cycles to work through it. Each cycle is one
// headless `claude -p` run that resumes the previous cycle's session and ends
// with an HTML debrief.
struct Operation {
    QString id;
    QString codename;
    QString directory;
    QString objective;
    QString model;
    // The agent CLI it runs on: "claude", "codex", "gemini" or "opencode".
    QString engine = "claude";
    QString roe = "restricted";
    int cycles = 3;
    int cyclesDone = 0;
    QString status = "standby";
    QString sessionId;
    // Where that session ran: Claude Code keeps sessions per directory.
    QString sessionDir;
    double costUsd = 0;
    // Context of the current session, and the line past which the next cycle
    // goes to a fresh session primed with a handoff brief (0 never hands off).
    qint64 contextTokens = 0;
    qint64 contextWindow = 1000000;
    qint64 handoffAt = 250000;
    int session = 1;
    QString handoffBrief;
    QStringList handoffs;
    // Orders from command waiting for the next cycle, and whether to stand the
    // agent down once its current cycle ends.
    QStringList orders;
    bool hold = false;
    // One entry per cycle run (retries and cut-short runs included), with the
    // snapshots of the project before and after it.
    QVariantList history;
    // Snapshots taken just before each rollback, newest last, so one can be
    // undone.
    QStringList rollbacks;
    // Permission rules the operator approved for this operation, passed to
    // every run, and refused calls waiting for a decision: each {choices
    // (lists of rules granted together), tool, summary, cycle, time}.
    QStringList allowed;
    QVariantList requests;
    // Orders that hold for every cycle.
    QString standing;
    // Overwatch after the final cycle: "off", "review", or "fix" (review, and
    // send it back for one fix cycle if it falls short). Reviews are {cycle,
    // grade, summary, findings, file, time}; fixRounds counts fix cycles
    // since the last deploy.
    QString overwatch = "off";
    QVariantList reviews;
    int fixRounds = 0;
    // Run in a git worktree of its own on branch, made from baseBranch, so
    // operations can share a repository. workdir is where the agent works:
    // the worktree while it's active, otherwise the directory.
    bool worktree = false;
    QString workdir;
    QString branch;
    QString baseBranch;
    QString baseCommit;
    // When a staged operation joined the queue, and when a pinned-down one
    // (stopped by the plan's usage limit) resumes, in seconds since the epoch.
    qint64 stagedAt = 0;
    qint64 resumeAt = 0;
    // Proof. Gates are the project's checks Fireteam runs after each cycle
    // ({name, command, enabled}); criteria are what "done" means ({text,
    // state: open, claimed, met or unmet, evidence, note}); preview is a
    // command and address to screenshot ({command, url}). gateFixes counts
    // the extra cycles given to turn failing gates green since the last
    // deploy.
    QVariantList gates;
    QVariantList criteria;
    QVariantMap preview;
    int gateFixes = 0;
    // Kept, but off the board.
    bool archived = false;
    // The operator's limits and timing: {budgetUsd (0 none), budgetPlan
    // (share of the plan's 5-hour window, 0 none), warned, schedule: {mode:
    // "time" | "reset" | "after", at (seconds since the epoch), after (an
    // operation's id)}}.
    QVariantMap controls;
    // The campaign this operation belongs to, its key in the campaign's plan,
    // and the operations (by id) it waits for.
    QString campaign;
    QString campaignKey;
    QStringList dependsOn;
    // Over the field link, this run: the agent's own progress report (-1 for
    // none), questions waiting for the operator ({id, question, options,
    // time}), and live permission prompts in Supervised ROE ({id, tool,
    // summary, choices, time}). Not saved: they end with the run.
    int progress = -1;
    QString progressNote;
    QVariantList questions;
    QVariantList prompts;
    // Comms lines this session, which the board turns into an activity pulse.
    // Not saved.
    int events = 0;
    QString sitrep;
    QString activity;
    QStringList intel;
    QStringList reports;
    QStringList sitreps;
    QDateTime created;
    QVariantList comms;

    QJsonObject toJson() const;
    static Operation fromJson(const QJsonObject &object);
};

class Operations : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int deployedCount READ deployedCount NOTIFY deployedCountChanged)
    Q_PROPERTY(QString claudePath READ claudePath CONSTANT)
    Q_PROPERTY(QString account READ account NOTIFY accountChanged)
    Q_PROPERTY(QString linkStatus READ linkStatus NOTIFY accountChanged)
    Q_PROPERTY(QString dataDirectory READ dataDirectory CONSTANT)
    Q_PROPERTY(int stagedCount READ stagedCount NOTIFY deployedCountChanged)
    // How many agents may be deployed at once; 0 is no limit.
    Q_PROPERTY(int maxDeployed READ maxDeployed WRITE setMaxDeployed NOTIFY maxDeployedChanged)
    // The plan's usage from the latest run: {status, resetsAt, windows}.
    Q_PROPERTY(QVariantMap usage READ usage NOTIFY usageChanged)
    Q_PROPERTY(QVariantList loadouts READ loadouts NOTIFY loadoutsChanged)
    // Every campaign with its plan or its operations' live state.
    Q_PROPERTY(QVariantList campaigns READ campaigns NOTIFY campaignsChanged)
    // Whether a Chromium-based browser is installed for preview screenshots.
    Q_PROPERTY(bool browserAvailable READ browserAvailable CONSTANT)
    // Whether finished operations get an after-action review that feeds the
    // project's field manual.
    Q_PROPERTY(bool afterAction READ afterAction WRITE setAfterAction NOTIFY afterActionChanged)
    Q_PROPERTY(int archivedCount READ archivedCount NOTIFY archivedChanged)
    // Knowledge graphs: graphify's path (empty if it isn't installed), whether
    // projects are mapped on their own, and Fireteam installing its own copy
    // ("", "installing", or an error).
    Q_PROPERTY(QString graphify READ graphify NOTIFY graphsChanged)
    Q_PROPERTY(bool graphsAuto READ graphsAuto WRITE setGraphsAuto NOTIFY graphsChanged)
    Q_PROPERTY(QString graphifyInstall READ graphifyInstall NOTIFY graphsChanged)
    // How many questions, permissions and refused commands wait on the
    // operator, across every operation.
    Q_PROPERTY(int inboxCount READ inboxCount NOTIFY inboxChanged)
    // Built-in recipes and the operator's own: [{name, objective, criteria,
    // loadout, builtin}].
    Q_PROPERTY(QVariantList recipes READ recipes NOTIFY recipesChanged)
    // The agent CLIs installed: [{key, label, path, capabilities}] (Claude
    // Code always listed).
    Q_PROPERTY(QVariantList engines READ engines NOTIFY enginesChanged)

public:
    enum Role {
        IdRole = Qt::UserRole + 1, CodenameRole, DirectoryRole, ObjectiveRole, ModelRole, RoeRole,
        CyclesRole, CyclesDoneRole, StatusRole, CostRole, SitrepRole, ActivityRole, IntelRole,
        ReportsRole, CommsRole, DossierRole, CreatedRole, ContextRole, ContextWindowRole, HandoffAtRole,
        SessionRole, HandoffBriefRole, OrdersRole, HoldRole, CeilingRole, HistoryRole, CanUndoRollbackRole,
        EventsRole, RequestsRole, AllowedRole, StandingRole, WorktreeRole, WorkdirRole, BranchRole,
        BaseBranchRole, ResumeAtRole, QueueRole, OverwatchRole, ReviewsRole, ProgressRole, ProgressNoteRole,
        QuestionsRole, PromptsRole, CampaignRole, GatesRole, CriteriaRole, PreviewRole, LastGatesRole, ArchivedRole, ControlsRole,
        EngineRole
    };

    // Both arguments exist for tests: a temp data directory and a fake claude.
    explicit Operations(const QString &dataDirectory = {}, const QString &claude = {}, QObject *parent = nullptr);
    ~Operations() override;

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int deployedCount() const;
    QString claudePath() const { return m_claude; }
    QString account() const { return m_account; }
    QString linkStatus() const { return m_linkStatus; }
    QString dataDirectory() const { return m_dataDirectory; }
    int stagedCount() const;
    int maxDeployed() const { return m_maxDeployed; }
    void setMaxDeployed(int max);
    QVariantMap usage() const { return m_usage; }
    QVariantList loadouts() const { return m_loadouts; }
    QVariantList campaigns() const;
    bool browserAvailable() const;
    bool afterAction() const { return m_afterAction; }
    void setAfterAction(bool on);
    int archivedCount() const;
    QVariantList engines() const { return m_engines; }
    // The engine an operation runs on, while it isn't deployed. Sessions
    // don't cross engines, so the next cycle starts a fresh one.
    Q_INVOKABLE void setEngine(int row, const QString &key);
    // Overwatch on another engine and model (empty: the operation's own).
    Q_INVOKABLE void setReviewEngine(int row, const QString &key, const QString &model);

    // Institutional memory: each project's field manual of lessons, the
    // archive, search across everything operations wrote, replays, and
    // exports.
    Q_INVOKABLE QVariantList manuals() const;
    Q_INVOKABLE QVariantList lessons(const QString &directory) const;
    Q_INVOKABLE bool addLesson(const QString &directory, const QString &text);
    Q_INVOKABLE bool editLesson(const QString &directory, const QString &id, const QString &text);
    Q_INVOKABLE bool removeLesson(const QString &directory, const QString &id);
    Q_INVOKABLE QString promoteLessons(const QString &directory, const QStringList &ids);
    Q_INVOKABLE void setArchived(int row, bool archived);
    Q_INVOKABLE QVariantList search(const QString &query) const;
    Q_INVOKABLE QVariantList replay(int row) const;
    Q_INVOKABLE QString exportOperation(int row, const QString &format);
    Q_INVOKABLE QString exportCampaign(const QString &id, const QString &format);
    // Shows an exported file: an HTML report in the browser, anything else
    // in its folder.
    Q_INVOKABLE void reveal(const QString &path);

    // Campaigns: plan with a read-only session, review and edit the plan,
    // approve it into operations, and let them deploy as their dependencies
    // finish.
    Q_INVOKABLE QString planCampaign(const QString &name, const QString &directory, const QString &objective,
                                     const QString &model);
    Q_INVOKABLE void replanCampaign(const QString &id);
    Q_INVOKABLE bool updateCampaignPlan(const QString &id, const QVariantList &operations);
    Q_INVOKABLE bool approveCampaign(const QString &id, const QString &roe, const QString &overwatch);
    Q_INVOKABLE void removeCampaign(const QString &id);
    Q_INVOKABLE bool openCampaignDossier(const QString &id);
    Q_INVOKABLE void resumeCampaign(const QString &id);

    Q_INVOKABLE QString suggestCodename() const;
    Q_INVOKABLE QString validate(const QString &directory, const QString &objective) const;
    Q_INVOKABLE int create(const QString &codename, const QString &directory, const QString &objective,
                           int cycles, const QString &roe, const QString &model, int handoffAt = 250000,
                           bool worktree = false, const QString &standing = {}, const QString &overwatch = "off");
    Q_INVOKABLE bool update(int row, const QString &codename, const QString &objective, int cycles,
                            const QString &roe, const QString &model, int handoffAt, bool worktree = false,
                            const QString &standing = {}, const QString &overwatch = "off");
    // {git, commits, branch} for the briefing, and other operations working
    // in place in the same directory.
    Q_INVOKABLE QVariantMap repository(const QString &directory) const;
    Q_INVOKABLE QStringList sharing(const QString &directory, int exceptRow = -1) const;
    // Proof: the checks a directory's project declares, and setting an
    // operation's gates, acceptance criteria (one per line), and preview.
    Q_INVOKABLE QVariantList detectGates(const QString &directory) const;
    Q_INVOKABLE bool setProof(int row, const QVariantList &gates, const QString &criteria,
                              const QString &previewCommand, const QString &previewUrl);
    // Worktree operations: what the branch holds against where it started,
    // merging it back, and throwing it away.
    Q_INVOKABLE QVariantMap worktreeSummary(int row);
    Q_INVOKABLE bool extract(int row);
    Q_INVOKABLE bool discard(int row);
    Q_INVOKABLE void saveLoadout(const QVariantMap &loadout);
    // Totals across every operation, for the service record: counts, lines,
    // time, API value, the last eight weeks, the busiest projects, and
    // overwatch's verdicts.
    Q_INVOKABLE QVariantMap serviceRecord() const;
    Q_INVOKABLE void removeLoadout(const QString &name);
    // Knowledge graphs.
    QString graphify() const;
    bool graphsAuto() const { return m_graphsAuto; }
    void setGraphsAuto(bool on);
    QString graphifyInstall() const { return m_graphifyInstall; }
    // Builds (or rebuilds) a project's graph in the background.
    Q_INVOKABLE void buildGraph(const QString &directory);
    // A project's graph for the map: Graphs::view plus {state: none, building,
    // ready or failed; error} and activity: {path: [{opId, codename, cycles}]}.
    Q_INVOKABLE QVariantMap graph(const QString &directory);
    Q_INVOKABLE QVariantMap graphFileDetail(const QString &directory, const QString &path) const;
    // One file's symbols and the symbols they're linked to elsewhere, laid out.
    Q_INVOKABLE QVariantMap graphSymbols(const QString &directory, const QString &path) const;
    // Files being edited right now by deployed operations in a project:
    // {path: {opId, codename, at}}, at in ms since the epoch.
    Q_INVOKABLE QVariantMap graphLive(const QString &directory) const;
    // Every project an operation has worked in, or that has a graph:
    // [{directory, state, files}].
    Q_INVOKABLE QVariantList graphProjects() const;
    Q_INVOKABLE void installGraphify();
    // Budgets and scheduling (Phase 14). A budget of 0 is none. A scheduled
    // operation waits (status "scheduled") until its time, until the plan's
    // usage window resets, or until another operation completes.
    Q_INVOKABLE void setBudget(int row, double usd, int planPercent);
    Q_INVOKABLE void setSchedule(int row, const QString &mode, double at, const QString &afterId);
    Q_INVOKABLE void clearSchedule(int row);
    Q_INVOKABLE void setCampaignBudget(const QString &id, double usd);
    // A debrief, review or brief for the in-app reader: {text, format: html
    // or markdown, path}. Only files in Fireteam's data folder are read.
    Q_INVOKABLE QVariantMap readReport(const QString &path) const;
    // Streamlining.
    int inboxCount() const;
    // Everything waiting on the operator, newest first: [{row, opId, codename,
    // kind: question|prompt|request, id, index, text, options, choices, time}].
    Q_INVOKABLE QVariantList inbox() const;
    // A one-line request read as a briefing: {directory, objective, codename,
    // loadout, known}; directory is empty when no project could be found.
    Q_INVOKABLE QVariantMap quickPlan(const QString &text, const QString &fallbackDirectory) const;
    // What Fireteam leans on, for the setup checklist: {claude, git, graphify,
    // chromium, qrencode, python} as paths (empty when missing).
    Q_INVOKABLE QVariantMap environment() const;
    QVariantList recipes() const;
    Q_INVOKABLE void saveRecipe(const QVariantMap &recipe);
    Q_INVOKABLE void removeRecipe(const QString &name);
    Q_INVOKABLE void deploy(int row);
    Q_INVOKABLE void sendOrders(int row, const QString &text, bool deployNow);
    Q_INVOKABLE void clearOrders(int row);
    Q_INVOKABLE void setHold(int row, bool hold);
    Q_INVOKABLE int rowOfId(const QString &id) const { return rowOf(id); }
    // An operation by id, the start of its id, or codename (any case, spaces
    // or dashes); -1 if none or more than one match.
    int find(const QString &query) const;
    Q_INVOKABLE QVariantList cycleChanges(int row, int run) const;
    Q_INVOKABLE QString cycleDiff(int row, int run, const QString &path) const;
    Q_INVOKABLE bool rollback(int row, int run);
    Q_INVOKABLE bool undoRollback(int row);
    // Approves a refused call with one of its suggested rules, for this
    // operation or (projectWide) every Claude session in the project.
    Q_INVOKABLE bool approve(int row, int request, int rule, bool projectWide);
    Q_INVOKABLE void deny(int row, int request);
    // Approves a rule typed by the operator: a command or a full rule.
    Q_INVOKABLE bool allow(int row, const QString &text, bool projectWide);
    Q_INVOKABLE void revoke(int row, const QString &rule);
    Q_INVOKABLE QString describeRule(const QString &rule) const;
    // Answers an agent's question over the field link.
    Q_INVOKABLE bool answer(int row, const QString &requestId, const QString &text);
    // Decides a live permission prompt: "once", "always" (with the suggested
    // rule to remember), or "deny".
    Q_INVOKABLE bool decide(int row, const QString &requestId, const QString &decision, int rule = 0);
    QString fieldLinkName() const;
    Q_INVOKABLE void abort(int row);
    Q_INVOKABLE void remove(int row);
    Q_INVOKABLE void abortAll();
    Q_INVOKABLE bool openDossier(int row);
    Q_INVOKABLE bool openLatestReport(int row);
    Q_INVOKABLE bool openReport(const QString &path);
    Q_INVOKABLE bool openProject(int row);
    Q_INVOKABLE void checkLink();

    QJsonArray toJson() const;
    QString reportPath(const Operation &op, int cycle) const;
    QString dossierPath(const Operation &op) const;
    QString handoffPath(const Operation &op) const;
    const Operation &at(int row) const { return m_ops.at(row); }
    // Where the agent works: its worktree, or the project directory.
    static QString workdir(const Operation &op);
    static QString defaultDataDirectory();
    static void ensureDataDirectory();
    // Past this much context a cycle is cut short and handed off on the spot.
    static qint64 ceiling(const Operation &op);

signals:
    void deployedCountChanged();
    void accountChanged();
    void cycleFinished(int row, int cycle);
    void operationFinished(int row);
    // The operator sent an operation in (not each cycle that follows).
    void deployed(int row);
    void maxDeployedChanged();
    // An agent has stopped to ask the operator something, over the field link.
    void waiting(int row);
    void usageChanged();
    void loadoutsChanged();
    void campaignsChanged();
    void afterActionChanged();
    void archivedChanged();
    void lessonsChanged(const QString &directory);
    void graphChanged(const QString &directory);
    void liveWorkChanged(const QString &directory);
    void inboxChanged();
    void recipesChanged();
    void enginesChanged();
    void graphsChanged();
    // Something worth telling someone who isn't looking at the board.
    void alert(const QString &opId, const QString &title, const QString &body);

private:
    struct Run {
        QPointer<QProcess> process;
        QByteArray buffer;
        QStringList actions;
        bool aborting = false;
        bool resultSeen = false;
        bool handoff = false;
        bool review = false;
        bool pastLine = false;
        bool ceiling = false;
        // Orders this cycle carried, put back if it doesn't finish.
        QStringList orders;
        QString before;
        QDateTime started;
        double costAtStart = 0;
        // Tool calls this run by id, to name the call behind a refusal.
        QHash<QString, QVariantMap> tools;
        // Files this run has edited, from the project's root, with when (ms).
        QHash<QString, qint64> touched;
        // The plan's usage limit stopped this run, until resetsAt.
        bool limited = false;
        qint64 resetsAt = 0;
        // The engine this run is on, its reader (shared, as runs are copied),
        // and files written for it, deleted when it ends.
        QString engine = "claude";
        std::shared_ptr<Engines::Parser> parser;
        QStringList tempFiles;
    };

    int rowOf(const QString &id) const;
    void advance(const QString &id);
    void startCycle(const QString &id);
    void startHandoff(const QString &id, bool midCycle = false);
    void stand(const QString &id, const QString &status);
    // Starts a deployment now, or stages it when the squad is full or the
    // project is busy, or pins it down while the plan is at its limit.
    void start(const QString &id);
    bool canStart(const Operation &op, QString *reason) const;
    void launchStaged();
    void pin(Operation &op, qint64 until);
    void schedulePinned();
    bool prepareWorktree(Operation &op);
    void shelveWorktree(Operation &op);
    void onSitrep(const QString &opId, const QString &status, int progress);
    void onObjective(const QString &opId, int index, bool done, const QString &evidence);
    // After a cycle completes: the gates, the preview, then on to the next
    // cycle, overwatch, or done.
    void proveCycle(const QString &id, int cycle);
    void afterCycle(const QString &id, int cycle);
    void onQuestion(const QString &opId, const QString &requestId, const QString &text, const QStringList &options);
    void onAuthorise(const QString &opId, const QString &requestId, const QString &tool, const QVariantMap &input);
    struct Campaign {
        QString id, name, objective, directory, model;
        // planning, draft (plan ready to review), active, blocked, complete,
        // or failed (the planner couldn't plan).
        QString status = "planning";
        QString summary, error, activity;
        QVariantList plan;
        QDateTime created;
        double costUsd = 0;
        // Holds the campaign's operations once their API value reaches it.
        double budgetUsd = 0;
        QJsonObject toJson() const;
        static Campaign fromJson(const QJsonObject &object);
    };
    int campaignIndex(const QString &id) const;
    void launchPlanner(const QString &id);
    void scheduleCampaign(const QString &id);
    void onOperationDone(int row);
    void writeCampaignDossier(const Campaign &campaign);
    void loadCampaigns();
    void saveCampaigns() const;
    void campaignChanged();
    void reviewAfterAction(const QString &id);
    QString exportDirectory() const;
    void loadSettings();
    void saveSettings() const;
    void launch(const QString &id, const QString &prompt, bool handoff, bool review = false);
    void startReview(const QString &id);
    void finishReview(const QString &id, const Run &run, int exitCode);
    void writeDossier(const Operation &op);
    void finishHandoff(const QString &id, const Run &run, int exitCode);
    void readOutput(const QString &id, bool ended = false);
    void handleEvent(Run &run, Operation &op, const StreamEvent &event);
    void finishCycle(const QString &id, int exitCode);
    void writeReports(Operation &op, const QStringList &actions);
    void record(Operation &op, const Run &run, int cycle, const QString &outcome);
    QString snapshotRef(const Operation &op, const QString &name) const;
    void request(Operation &op, const QString &tool, const QVariantMap &input);
    bool grant(Operation &op, const QStringList &rules, bool projectWide);
    void collectIntel(const QString &id);
    void log(Operation &op, const QString &kind, const QString &text);
    void changed(int row);
    void load();
    void save() const;

    QString m_dataDirectory;
    QString m_claude;
    QString m_account;
    QString m_linkStatus = "checking";
    QList<Operation> m_ops;
    QHash<QString, Run> m_runs;
    int m_maxDeployed = 3;
    QVariantMap m_usage;
    // The plan's limit is shared by every agent: until then, nothing starts.
    qint64 m_limitedUntil = 0;
    QVariantList m_loadouts;
    QTimer *m_pinTimer = nullptr;
    FieldLink *m_link = nullptr;
    QList<Campaign> m_campaigns;
    QHash<QString, QPointer<QProcess>> m_planners;
    QTimer *m_campaignNotice = nullptr;
    QHash<QString, QPointer<Gates>> m_gateRunners;
    bool m_afterAction = true;
    bool m_graphsAuto = true;
    QVariantList m_recipes;
    QVariantList m_engines;
    void refreshEngines();
    QTimer *m_scheduleTimer = nullptr;
    void checkSchedules();
    // True when the operation is at or past a budget, which it then explains.
    bool overBudget(Operation &op);
    QString m_graphifyInstall;
    QHash<QString, QPointer<QProcess>> m_graphBuilds;
    QSet<QString> m_graphPending;
    QHash<QString, QString> m_graphErrors;
    // Views by project, with the graph.json's time they were made from.
    QHash<QString, QPair<QDateTime, QVariantMap>> m_graphViews;
    void refreshGraph(const QString &directory, bool create);
    QVariantMap graphActivity(const QString &directory) const;
    QString graphBrief(const QString &directory);
};
