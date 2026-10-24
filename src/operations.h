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
        ReportsRole, CommsRole, DossierRole, CreatedRole
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
                           int cycles, const QString &roe, const QString &model);
    Q_INVOKABLE void deploy(int row);
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
    const Operation &at(int row) const { return m_ops.at(row); }

signals:
    void deployedCountChanged();
    void accountChanged();
    void cycleFinished(int row, int cycle);
    void operationFinished(int row);

private:
    struct Run {
        QPointer<QProcess> process;
        QByteArray buffer;
        QStringList actions;
        bool aborting = false;
        bool resultSeen = false;
    };

    int rowOf(const QString &id) const;
    void startCycle(const QString &id);
    void readOutput(const QString &id);
    void finishCycle(const QString &id, int exitCode);
    void writeReports(Operation &op, const QStringList &actions);
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
