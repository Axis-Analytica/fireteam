#pragma once

#include <QByteArray>
#include <QJsonObject>
#include <QList>
#include <QString>
#include <QStringList>

// One thing worth showing from a line of `claude -p --output-format
// stream-json`: something the agent said, a tool it used, or the result that
// ends a cycle.
struct StreamEvent {
    enum Kind { Session, Say, Tool, Usage, Result, Error };
    StreamEvent(Kind k = Say, const QString &t = {}) : kind(k), text(t) {}
    Kind kind = Say;
    QString text;
    QString sessionId;
    double costUsd = 0;
    int turns = 0;
    // Usage: the tokens in context as of this turn. Result: the model's window.
    qint64 contextTokens = 0;
    qint64 contextWindow = 0;
    bool isError = false;
};

namespace Stream {
QList<StreamEvent> parseLine(const QByteArray &line);
QString describeTool(const QString &name, const QJsonObject &input);

QString cyclePrompt(const QString &codename, const QString &objective, int cycle, int cycles,
                    const QString &reportPath, const QString &handoffBrief = {}, const QString &debriefs = {},
                    const QStringList &commandOrders = {});
// midCycle is the cycle the session was stopped in, or 0 between cycles.
QString handoffPrompt(const QString &codename, const QString &objective, qint64 contextTokens, int cyclesLeft,
                      const QString &briefPath, int midCycle = 0);
QString tokens(qint64 count);
QString systemBrief();

// Written when the agent finished a cycle without leaving its own debrief, so
// every cycle still has one.
QString fallbackReport(const QString &codename, int cycle, int cycles, const QString &objective,
                       const QString &sitrep, const QStringList &actions, const QStringList &intel);

struct DossierEntry {
    int cycle;
    QString file;
    QString sitrep;
};
QString dossier(const QString &codename, const QString &objective, const QString &directory,
                const QList<DossierEntry> &entries);

QString codename(quint32 seed);
}
