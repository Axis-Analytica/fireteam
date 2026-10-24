#pragma once

#include <QAbstractListModel>
#include <QDateTime>
#include <QHash>
#include <QJsonArray>
#include <QJsonObject>
#include <QPointer>
#include <QProcess>
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
    QString roe = "restricted";
    int cycles = 3;
    int cyclesDone = 0;
    QString status = "standby";
    QString sessionId;
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

public:
    enum Role {
        IdRole = Qt::UserRole + 1, CodenameRole, DirectoryRole, ObjectiveRole, ModelRole, RoeRole,
        CyclesRole, CyclesDoneRole, StatusRole, CostRole, SitrepRole, ActivityRole, IntelRole,
        ReportsRole, CommsRole, DossierRole, CreatedRole, ContextRole, ContextWindowRole, HandoffAtRole,
        SessionRole, HandoffBriefRole, OrdersRole, HoldRole, CeilingRole, HistoryRole, CanUndoRollbackRole
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

    Q_INVOKABLE QString suggestCodename() const;
    Q_INVOKABLE QString validate(const QString &directory, const QString &objective) const;
    Q_INVOKABLE int create(const QString &codename, const QString &directory, const QString &objective,
                           int cycles, const QString &roe, const QString &model, int handoffAt = 250000);
    Q_INVOKABLE bool update(int row, const QString &codename, const QString &objective, int cycles,
                            const QString &roe, const QString &model, int handoffAt);
    Q_INVOKABLE void deploy(int row);
    Q_INVOKABLE void sendOrders(int row, const QString &text, bool deployNow);
    Q_INVOKABLE void clearOrders(int row);
    Q_INVOKABLE void setHold(int row, bool hold);
    Q_INVOKABLE int rowOfId(const QString &id) const { return rowOf(id); }
    Q_INVOKABLE QVariantList cycleChanges(int row, int run) const;
    Q_INVOKABLE QString cycleDiff(int row, int run, const QString &path) const;
    Q_INVOKABLE bool rollback(int row, int run);
    Q_INVOKABLE bool undoRollback(int row);
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
    // Past this much context a cycle is cut short and handed off on the spot.
    static qint64 ceiling(const Operation &op);

signals:
    void deployedCountChanged();
    void accountChanged();
    void cycleFinished(int row, int cycle);
    void operationFinished(int row);
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
        bool pastLine = false;
        bool ceiling = false;
        // Orders this cycle carried, put back if it doesn't finish.
        QStringList orders;
        QString before;
        QDateTime started;
        double costAtStart = 0;
    };

    int rowOf(const QString &id) const;
    void advance(const QString &id);
    void startCycle(const QString &id);
    void startHandoff(const QString &id, bool midCycle = false);
    void stand(const QString &id, const QString &status);
    void launch(const QString &id, const QString &prompt, bool handoff);
    void finishHandoff(const QString &id, const Run &run, int exitCode);
    void readOutput(const QString &id);
    void finishCycle(const QString &id, int exitCode);
    void writeReports(Operation &op, const QStringList &actions);
    void record(Operation &op, const Run &run, int cycle, const QString &outcome);
    QString snapshotRef(const Operation &op, const QString &name) const;
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
};
