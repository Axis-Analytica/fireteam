#pragma once

#include <QByteArray>
#include <QJsonObject>
#include <QList>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

// One thing worth showing from a line of `claude -p --output-format
// stream-json`: something the agent said, a tool it used, or the result that
// ends a cycle.
struct StreamEvent {
    // Denied: Claude Code refused a tool call because it needs the operator's
    // approval.
    // RateLimit: the plan's usage, reported on every run.
    enum Kind { Session, Say, Tool, Usage, Result, Error, Denied, RateLimit };
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
    // Tool and Denied: which call it was. Tool also carries the call itself.
    QString toolId;
    QString tool;
    QVariantMap input;
    // Result: every call refused this run, each {tool, input}.
    QVariantList denials;
    // RateLimit: "allowed", "allowed_warning" or "rejected", when the limit
    // resets (seconds since the epoch), and each window's {utilization,
    // resetsAt, status}.
    QString limitStatus;
    qint64 resetsAt = 0;
    QVariantMap windows;
};

namespace Stream {
QList<StreamEvent> parseLine(const QByteArray &line);
QString describeTool(const QString &name, const QJsonObject &input);
// The ways to allow a refused call, broadest sensible first, each a set of
// rules granted together: for `npm test --watch`, {"Bash(npm test:*)"} or
// the exact command; for a chain, one rule per part that needs approval.
QList<QStringList> rulesFor(const QString &tool, const QVariantMap &input);
// The rule a person types: a full rule passes through, a bare command becomes
// a prefix rule for it.
QString ruleFromText(const QString &text);
// "npm test" for Bash(npm test:*), for showing a rule.
QString describeRule(const QString &rule);
// Whether a failed run's text reads as the plan's usage limit.
bool isUsageLimit(const QString &text);

QString cyclePrompt(const QString &codename, const QString &objective, int cycle, int cycles,
                    const QString &reportPath, const QString &handoffBrief = {}, const QString &debriefs = {},
                    const QStringList &commandOrders = {}, const QString &standing = {});
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
// Reviews are {cycle, grade, summary, file}, newest last.
QString dossier(const QString &codename, const QString &objective, const QString &directory,
                const QList<DossierEntry> &entries, const QVariantList &reviews = {});

// Overwatch: an independent, read-only review of an operation's work against
// its objective, ending in a graded JSON verdict.
QString reviewPrompt(const QString &codename, const QString &objective, int cycles, const QString &diffPath,
                     const QString &debriefs, const QVariantList &criteria = {}, const QVariantList &gates = {});
// {grade: pass | needs-work | fail | unknown, summary, findings: [{severity,
// file, issue}], criteria: [{index, met, note}]} from the reviewer's reply.
QVariantMap parseReview(const QString &reply);
QString reviewReport(const QString &codename, const QString &objective, int cycle, const QVariantMap &review,
                     const QString &reply);
// The findings as orders for a fix cycle.
QString reviewOrders(const QVariantMap &review);

// Proof. Acceptance criteria ({text, state}) as a block for the cycle prompt,
// and failed gates ({name, command, passed, output}) as orders to fix them.
QString criteriaBlock(const QVariantList &criteria);
QString gateOrders(const QVariantList &results);

// Campaigns: a read-only planning session breaks a large objective into
// operations with dependencies, as JSON.
// engines: other installed engines (keys) the planner may assign an operation to.
QString campaignPrompt(const QString &name, const QString &objective, const QStringList &engines = {});
// {summary, operations: [{key, codename, objective, cycles, model, depends}]},
// or {error} when the reply has no usable plan. Keys are unique, every
// dependency names another operation, and there are no cycles.
QVariantMap parseCampaignPlan(const QString &reply);
// The operations in an order that respects their dependencies, or empty if
// the dependencies loop.
QStringList dependencyOrder(const QVariantList &operations);
// What dependents are told about work they build on.
QString priorWork(const QList<QVariantMap> &done);
QString campaignDossier(const QString &name, const QString &objective, const QString &summary,
                        const QVariantList &operations);

QString codename(quint32 seed);
}
