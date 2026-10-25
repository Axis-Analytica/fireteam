#pragma once

#include "stream.h"

#include <QList>
#include <QMap>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <memory>

// The agent CLIs an operation can run on: Claude Code (the default, and the
// only one with live permission prompts), OpenAI's Codex, Google's Gemini CLI,
// and OpenCode. Each gets its own command line and its own reader for the
// JSON lines it prints, which come out as the same StreamEvents Claude Code's
// stream-json does, so the rest of Fireteam needn't know which ran.
namespace Engines {

// "claude", "codex", "gemini", "opencode".
QStringList keys();
bool isKnown(const QString &key);
// "Claude Code", "Codex", "Gemini CLI", "OpenCode".
QString label(const QString &key);
// The binary on PATH (or in the usual install spots), empty if it isn't
// installed. FIRETEAM_CODEX, FIRETEAM_GEMINI and FIRETEAM_OPENCODE override.
QString executable(const QString &key);
// {supervised (live permission prompts), mcp (the field link), resume, cost
// (reports API cost), context (reports the context per turn)}.
QVariantMap capabilities(const QString &key);
// Every installed engine (Claude Code always): [{key, label, path,
// capabilities}].
QVariantList available();

// One run of an agent.
struct RunSpec {
    QString prompt;
    QString workdir;
    QString model;
    // "restricted", "supervised" or "free". Supervised needs live prompts,
    // which only Claude Code has; elsewhere it runs as restricted.
    QString roe = "restricted";
    // Claude-style permission rules the operator approved ("Bash(npm test:*)").
    QStringList allowed;
    // Rules for Fireteam's own read-only helpers, granted after the field
    // link's tools.
    QStringList helperRules;
    QString resume;
    // A directory outside the project the agent may write to (the op's data).
    QString extraDir;
    // The field link: Fireteam's MCP server for this run, over stdio. None
    // when mcpCommand is empty.
    QString mcpCommand;
    QStringList mcpArgs;
    // How long a field-link call may take (an agent waiting on the operator).
    int mcpTimeoutMs = 0;
    QString systemBrief;
    // Read-only: overwatch.
    bool review = false;
    // Where engines keep Fireteam's own state between runs (Gemini's home).
    QString stateDir;
    // The program to run instead of the one found on PATH.
    QString program;
};

struct Command {
    QString program;
    QStringList arguments;
    // Added to the agent's environment.
    QMap<QString, QString> environment;
    // Written for this run; delete them when it ends.
    QStringList tempFiles;
};

Command command(const QString &key, const RunSpec &spec);

// Reads one engine's output, a line at a time.
class Parser {
public:
    virtual ~Parser() = default;
    virtual QList<StreamEvent> line(const QByteArray &line) = 0;
    // When the process has ended: whatever the engine never said outright
    // (OpenCode has no result event, so one is made here).
    virtual QList<StreamEvent> finish() { return {}; }
};
std::unique_ptr<Parser> parser(const QString &key);

// The field link's tool as the engine's model sees it: "sitrep" is
// mcp__fireteam__sitrep in Claude Code, mcp_fireteam_sitrep in Gemini CLI and
// fireteam_sitrep in OpenCode.
QString toolName(const QString &key, const QString &tool);
// Text that names the field link's tools ("the fireteam sitrep tool"), with
// the names this engine uses. Claude Code's text is left as it is.
QString nameTools(const QString &key, const QString &text);

// Refusals and the plan's usage limit, with each engine's wording.
bool isRefusal(const QString &key, const QString &text);
bool isUsageLimit(const QString &key, const QString &text);

}
