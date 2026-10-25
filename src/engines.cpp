#include "engines.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSet>
#include <QStandardPaths>
#include <QUuid>

namespace Engines {

QStringList keys() { return {"claude", "codex", "gemini", "opencode"}; }

bool isKnown(const QString &key) { return keys().contains(key); }

QString label(const QString &key) {
    if (key == "codex")
        return "Codex";
    if (key == "gemini")
        return "Gemini CLI";
    if (key == "opencode")
        return "OpenCode";
    return "Claude Code";
}

// A launcher-started app may not have the shell's PATH (mise, npm prefixes),
// so look in the usual install spots too.
// A mise shim exists for every tool a config names, installed or not, so it
// proves nothing; mise's command wrappers are only made for installed tools.
static bool isShim(const QString &path) {
    return path.contains("/mise/shims/") && QFileInfo(path).canonicalFilePath().endsWith("/mise");
}

static QString find(const QString &name, const QStringList &extra = {}) {
    const QString found = QStandardPaths::findExecutable(name);
    if (!found.isEmpty() && !isShim(found))
        return found;
    const QString home = QDir::homePath();
    QStringList paths = extra;
    paths << home + "/.local/bin/" + name << home + "/.local/share/mise/command-wrappers/bin/" + name
          << home + "/.npm-global/bin/" + name << home + "/.bun/bin/" + name << "/usr/local/bin/" + name
          << "/usr/bin/" + name;
    for (const QString &path : paths)
        if (QFileInfo(path).isExecutable() && !isShim(path))
            return path;
    return {};
}

QString executable(const QString &key) {
    if (key == "claude") {
        // Where Claude Code's installers put it.
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
    const char *variable = key == "codex" ? "FIRETEAM_CODEX" : key == "gemini" ? "FIRETEAM_GEMINI"
                         : key == "opencode" ? "FIRETEAM_OPENCODE" : nullptr;
    if (!variable)
        return {};
    if (qEnvironmentVariableIsSet(variable)) {
        const QString path = qEnvironmentVariable(variable);
        return QFileInfo(path).isExecutable() ? path : QString();
    }
    return find(key, key == "opencode" ? QStringList{QDir::homePath() + "/.opencode/bin/opencode"} : QStringList());
}

QVariantMap capabilities(const QString &key) {
    // Supervised needs a permission-prompt tool, which only Claude Code's
    // headless mode has. Codex reports a thread total and Gemini a run total,
    // neither the context now; OpenCode reports each step, with its cost.
    const bool claude = key == "claude";
    return {{"supervised", claude}, {"mcp", true}, {"resume", true},
            {"cost", claude || key == "opencode"}, {"context", claude || key == "opencode"}};
}

QVariantList available() {
    QVariantList engines;
    for (const QString &key : keys()) {
        const QString path = executable(key);
        if (key != "claude" && path.isEmpty())
            continue;
        engines.append(QVariantMap{{"key", key}, {"label", label(key)}, {"path", path},
                                   {"capabilities", capabilities(key)}});
    }
    return engines;
}

QString toolName(const QString &key, const QString &tool) {
    if (key == "gemini")
        return "mcp_fireteam_" + tool;
    if (key == "opencode")
        return "fireteam_" + tool;
    // UNVERIFIED: the name Codex shows its model. Its events give server and
    // tool apart, and Claude Code's form is the usual one for MCP.
    return "mcp__fireteam__" + tool;
}

QString nameTools(const QString &key, const QString &text) {
    if (key == "claude")
        return text;
    QString named = text;
    static const QRegularExpression phrase(R"(\bfireteam (sitrep|request_orders|mark_objective|authorise) tool\b)");
    QRegularExpressionMatchIterator matches = phrase.globalMatch(text);
    QList<QRegularExpressionMatch> found;
    while (matches.hasNext())
        found.prepend(matches.next());
    // From the end, so earlier positions stay put.
    for (const auto &match : found) {
        const QString tool = match.captured(1);
        const QString replacement = key == "codex"
            // UNVERIFIED how Codex names MCP tools to its model, so name the
            // server and tool rather than guess a qualified name.
            ? QString("%1 tool of the fireteam MCP server").arg(tool)
            : QString("fireteam %1 tool (%2)").arg(tool, toolName(key, tool));
        named.replace(match.capturedStart(), match.capturedLength(), replacement);
    }
    return named;
}

bool isRefusal(const QString &key, const QString &text) {
    static const QRegularExpression claude(R"(requires approval|haven't granted|permission to use|was blocked)",
                                           QRegularExpression::CaseInsensitiveOption);
    static const QRegularExpression gemini(R"(denied by policy|Tool execution blocked|requires user confirmation)",
                                           QRegularExpression::CaseInsensitiveOption);
    static const QRegularExpression opencode(R"(rejected permission|prevents you from using|permission to use)",
                                             QRegularExpression::CaseInsensitiveOption);
    static const QRegularExpression codex(R"(approval is not supported)", QRegularExpression::CaseInsensitiveOption);
    if (key == "gemini")
        return text.contains(gemini);
    if (key == "opencode")
        return text.contains(opencode);
    if (key == "codex")
        return text.contains(codex);
    return text.contains(claude);
}

bool isUsageLimit(const QString &key, const QString &text) {
    if (Stream::isUsageLimit(text))
        return true;
    if (key == "claude")
        return false;
    static const QRegularExpression limit(R"(quota|RESOURCE_EXHAUSTED|exhausted your|\b429\b|rate.?limit)",
                                          QRegularExpression::CaseInsensitiveOption);
    return text.contains(limit);
}

// -- Command lines ---------------------------------------------------------

static QString jsonString(const QString &text) {
    // A JSON string is also a TOML basic string.
    const QByteArray array = QJsonDocument(QJsonArray{text}).toJson(QJsonDocument::Compact);
    return QString::fromUtf8(array.mid(1, array.size() - 2));
}

static QString jsonArray(const QStringList &items) {
    return QString::fromUtf8(QJsonDocument(QJsonArray::fromStringList(items)).toJson(QJsonDocument::Compact));
}

// What Claude-style rules allow, for engines with their own allow lists.
struct Allowance {
    bool anyCommand = false;
    QStringList prefixes;
    QStringList exact;
    bool webFetch = false;
};

static Allowance allowance(const QStringList &rules) {
    Allowance allow;
    static const QRegularExpression bash(R"(^Bash\((.*?)(:\*)?\)$)");
    for (const QString &rule : rules) {
        if (rule == "Bash") {
            allow.anyCommand = true;
            continue;
        }
        if (rule == "WebFetch") {
            allow.webFetch = true;
            continue;
        }
        const auto match = bash.match(rule);
        if (!match.hasMatch())
            continue;
        const QString command = match.captured(1).trimmed();
        if (command.isEmpty())
            continue;
        if (match.captured(2).isEmpty()) {
            if (!allow.exact.contains(command))
                allow.exact << command;
        } else if (!allow.prefixes.contains(command)) {
            allow.prefixes << command;
        }
    }
    return allow;
}

static QString withBrief(const RunSpec &spec, const QString &key) {
    // No engine but Claude Code takes extra system instructions on the command
    // line, so the brief leads the prompt.
    const QString prompt = nameTools(key, spec.prompt);
    if (spec.systemBrief.isEmpty())
        return prompt;
    return "STANDING BRIEF:\n" + nameTools(key, spec.systemBrief) + "\n\n" + prompt;
}

static QString tempFile(const RunSpec &spec, const QString &name, const QByteArray &contents) {
    const QString folder = !spec.extraDir.isEmpty() ? spec.extraDir : QDir::tempPath();
    QDir().mkpath(folder);
    const QString path = QString("%1/%2-%3").arg(folder, QUuid::createUuid().toString(QUuid::Id128).left(12), name);
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly))
        return {};
    file.write(contents);
    return path;
}

static Command claudeCommand(const RunSpec &spec) {
    Command command;
    command.program = spec.program.isEmpty() ? executable("claude") : spec.program;
    QStringList &arguments = command.arguments;
    arguments << "-p" << spec.prompt << "--output-format" << "stream-json" << "--verbose"
              << "--permission-mode" << (spec.review ? "plan" : spec.roe == "free" ? "bypassPermissions" : "acceptEdits")
              << "--add-dir" << spec.extraDir;
    QStringList allowed = spec.allowed;
    if (!spec.systemBrief.isEmpty())
        arguments << "--append-system-prompt" << spec.systemBrief;
    if (!spec.mcpCommand.isEmpty()) {
        // The field link, whose progress and question tools never need
        // approval.
        const QJsonObject mcp{{"mcpServers", QJsonObject{{"fireteam", QJsonObject{
            {"type", "stdio"}, {"command", spec.mcpCommand}, {"args", QJsonArray::fromStringList(spec.mcpArgs)}}}}}};
        arguments << "--mcp-config" << QString::fromUtf8(QJsonDocument(mcp).toJson(QJsonDocument::Compact));
        allowed << "mcp__fireteam__sitrep" << "mcp__fireteam__request_orders" << "mcp__fireteam__mark_objective";
    }
    allowed << spec.helperRules;
    // Supervised: anything that would need permission is put to the operator,
    // live, while the agent waits.
    if (!spec.mcpCommand.isEmpty() && !spec.review && spec.roe == "supervised")
        arguments << "--permission-prompt-tool" << "mcp__fireteam__authorise";
    // Each approved rule is its own argument, since rules contain spaces.
    if (!allowed.isEmpty())
        arguments << "--allowedTools" << allowed;
    if (!spec.model.isEmpty())
        arguments << "--model" << spec.model;
    if (!spec.resume.isEmpty())
        arguments << "--resume" << spec.resume;
    return command;
}

static Command codexCommand(const RunSpec &spec) {
    Command command;
    command.program = spec.program.isEmpty() ? executable("codex") : spec.program;
    QStringList &arguments = command.arguments;
    // Codex can't allow particular commands from the command line (exec
    // rejects every approval), so the ROE is its sandbox: edits in the project
    // and the op's folder, commands sandboxed with no network.
    const QString sandbox = spec.review ? "read-only" : spec.roe == "free" ? "danger-full-access" : "workspace-write";
    arguments << "exec" << "--json" << "-C" << spec.workdir << "-s" << sandbox;
    if (!spec.extraDir.isEmpty())
        arguments << "--add-dir" << spec.extraDir;
    // Fireteam runs in projects that aren't git repositories too.
    arguments << "--skip-git-repo-check";
    // A review needn't be kept.
    if (spec.review)
        arguments << "--ephemeral";
    if (!spec.mcpCommand.isEmpty()) {
        arguments << "-c" << "mcp_servers.fireteam.command=" + jsonString(spec.mcpCommand)
                  << "-c" << "mcp_servers.fireteam.args=" + jsonArray(spec.mcpArgs)
                  // Otherwise a call that would ask is cancelled in exec.
                  << "-c" << "mcp_servers.fireteam.default_tools_approval_mode=\"approve\"";
        if (spec.mcpTimeoutMs > 0)
            arguments << "-c" << QString("mcp_servers.fireteam.tool_timeout_sec=%1").arg((spec.mcpTimeoutMs + 999) / 1000);
    }
    if (!spec.model.isEmpty())
        arguments << "-m" << spec.model;
    // UNVERIFIED: -c developer_instructions; the brief goes in the prompt.
    // The sandbox, -C, --add-dir and -c all have to come before resume.
    if (!spec.resume.isEmpty())
        arguments << "resume" << spec.resume;
    arguments << withBrief(spec, "codex");
    return command;
}

// Gemini CLI has no flag for an MCP server, so Fireteam keeps a home of its
// own for it (GEMINI_CLI_HOME): the operator's ~/.gemini linked in, entry by
// entry, so sign-in and sessions are shared, and a settings.json that is the
// operator's plus the field link. The server's arguments come from the
// environment, so concurrent runs can share the file.
static QString geminiHome(const RunSpec &spec) {
    const QString source = qEnvironmentVariable("GEMINI_CLI_HOME", QDir::homePath()) + "/.gemini";
    const QString home = (spec.stateDir.isEmpty() ? QDir::tempPath() + "/fireteam-engines" : spec.stateDir) + "/gemini-home";
    const QString dot = home + "/.gemini";
    QDir().mkpath(dot);
    const QFileInfoList entries = QDir(source).entryInfoList(QDir::AllEntries | QDir::Hidden | QDir::NoDotAndDotDot);
    for (const QFileInfo &entry : entries) {
        if (entry.fileName() == "settings.json")
            continue;
        const QString link = dot + "/" + entry.fileName();
        if (!QFileInfo(link).exists() && !QFileInfo(link).isSymLink())
            QFile::link(entry.absoluteFilePath(), link);
    }
    QJsonObject settings;
    QFile user(source + "/settings.json");
    if (user.open(QIODevice::ReadOnly))
        settings = QJsonDocument::fromJson(user.readAll()).object();
    QJsonArray args;
    for (int i = 0; i < spec.mcpArgs.size(); ++i)
        args.append(QString("$FIRETEAM_MCP_ARG_%1").arg(i));
    // trust: its tools are allowed, rather than denied in headless mode.
    QJsonObject server{{"command", spec.mcpCommand}, {"args", args}, {"trust", true}};
    if (spec.mcpTimeoutMs > 0)
        server.insert("timeout", spec.mcpTimeoutMs);
    QJsonObject servers = settings.value("mcpServers").toObject();
    servers.insert("fireteam", server);
    settings.insert("mcpServers", servers);
    const QByteArray contents = QJsonDocument(settings).toJson();
    QFile current(dot + "/settings.json");
    if (!current.open(QIODevice::ReadOnly) || current.readAll() != contents) {
        current.close();
        QSaveFile file(dot + "/settings.json");
        if (file.open(QIODevice::WriteOnly)) {
            file.write(contents);
            file.commit();
        }
    }
    return home;
}

static Command geminiCommand(const RunSpec &spec) {
    Command command;
    command.program = spec.program.isEmpty() ? executable("gemini") : spec.program;
    QStringList &arguments = command.arguments;
    // Without --skip-trust, headless exits, and approval modes and MCP are
    // quietly turned off.
    const QString mode = spec.review ? "plan" : spec.roe == "free" ? "yolo" : "auto_edit";
    arguments << "-p" << withBrief(spec, "gemini") << "-o" << "stream-json" << "--skip-trust"
              << "--approval-mode" << mode;
    if (!spec.extraDir.isEmpty())
        arguments << "--include-directories" << spec.extraDir;
    if (spec.roe != "free" || spec.review) {
        // Approved commands as a policy; every other shell call is denied.
        const Allowance allow = allowance(spec.allowed + spec.helperRules);
        QStringList rules;
        auto quoted = [](const QStringList &items) {
            QStringList out;
            for (const QString &item : items)
                out << jsonString(item);
            return out.join(", ");
        };
        if (allow.anyCommand) {
            rules << "[[rule]]\ntoolName = \"run_shell_command\"\ndecision = \"allow\"\npriority = 100\n";
        } else if (!allow.prefixes.isEmpty() || !allow.exact.isEmpty()) {
            // An exact command is allowed as a prefix: the policy's
            // commandRegex form isn't verified.
            rules << QString("[[rule]]\ntoolName = \"run_shell_command\"\ncommandPrefix = [%1]\ndecision = \"allow\"\n"
                             "priority = 100\n").arg(quoted(allow.prefixes + allow.exact));
        }
        if (allow.webFetch)
            rules << "[[rule]]\ntoolName = \"web_fetch\"\ndecision = \"allow\"\npriority = 100\n";
        if (!rules.isEmpty()) {
            const QString path = tempFile(spec, "gemini-policy.toml",
                                          ("# Fireteam: what the operator approved for this run.\n\n" + rules.join('\n')).toUtf8());
            if (!path.isEmpty()) {
                arguments << "--policy" << path;
                command.tempFiles << path;
            }
        }
    }
    if (!spec.model.isEmpty())
        arguments << "-m" << spec.model;
    if (!spec.resume.isEmpty())
        arguments << "--resume" << spec.resume;
    if (!spec.mcpCommand.isEmpty()) {
        command.environment.insert("GEMINI_CLI_HOME", geminiHome(spec));
        for (int i = 0; i < spec.mcpArgs.size(); ++i)
            command.environment.insert(QString("FIRETEAM_MCP_ARG_%1").arg(i), spec.mcpArgs.at(i));
    }
    return command;
}

// An object whose keys keep their order: OpenCode's last matching rule wins.
static QString orderedObject(const QList<QPair<QString, QString>> &members) {
    QStringList parts;
    for (const auto &member : members)
        parts << jsonString(member.first) + ":" + member.second;
    return "{" + parts.join(',') + "}";
}

static Command opencodeCommand(const RunSpec &spec) {
    Command command;
    command.program = spec.program.isEmpty() ? executable("opencode") : spec.program;
    QStringList &arguments = command.arguments;
    const QString allow = "\"allow\"", ask = "\"ask\"", deny = "\"deny\"";
    const bool free = spec.roe == "free" && !spec.review;
    QString permission;
    if (free) {
        permission = orderedObject({{"*", allow}, {"external_directory", allow}, {"doom_loop", allow}});
    } else {
        // Unlisted commands ask, and run rejects every ask: "The user rejected
        // permission to use this specific tool call." (deny gives a wordier
        // refusal).
        const Allowance allowed = allowance(spec.allowed + spec.helperRules);
        QList<QPair<QString, QString>> bash{{"*", allowed.anyCommand ? allow : ask}};
        QStringList prefixes = allowed.prefixes;
        // Overwatch reads the history.
        if (spec.review)
            prefixes << "git diff" << "git log" << "git show" << "git status";
        for (const QString &prefix : prefixes)
            bash << qMakePair(prefix, allow) << qMakePair(prefix + " *", allow);
        for (const QString &exact : allowed.exact)
            bash << qMakePair(exact, allow);
        QList<QPair<QString, QString>> members{{"edit", spec.review ? deny : allow}, {"bash", orderedObject(bash)}};
        if (!spec.extraDir.isEmpty())
            members << qMakePair(QString("external_directory"),
                                 orderedObject({{QDir::cleanPath(spec.extraDir) + "/**", allow}}));
        members << qMakePair(QString("webfetch"), allowed.webFetch ? allow : ask);
        if (!spec.mcpCommand.isEmpty())
            members << qMakePair(QString("fireteam_*"), allow);
        permission = orderedObject(members);
    }
    QList<QPair<QString, QString>> config;
    if (!spec.mcpCommand.isEmpty()) {
        // UNVERIFIED: whether the local server's timeout covers a tool call
        // (it may only cover listing tools), so it's left at its default.
        const QString server = orderedObject({{"type", "\"local\""},
                                              {"command", jsonArray(QStringList{spec.mcpCommand} + spec.mcpArgs)},
                                              {"enabled", "true"}});
        config << qMakePair(QString("mcp"), orderedObject({{"fireteam", server}}));
    }
    config << qMakePair(QString("permission"), permission);
    command.environment.insert("OPENCODE_CONFIG_CONTENT", orderedObject(config));
    command.environment.insert("OPENCODE_DISABLE_AUTOUPDATE", "1");
    arguments << "run" << "--format" << "json" << "--dir" << spec.workdir;
    if (!spec.model.isEmpty())
        arguments << "-m" << spec.model;
    if (free)
        arguments << "--auto";
    if (!spec.resume.isEmpty())
        arguments << "-s" << spec.resume;
    arguments << withBrief(spec, "opencode");
    return command;
}

Command command(const QString &key, const RunSpec &given) {
    RunSpec spec = given;
    // Live prompts are Claude Code's alone; elsewhere supervised is restricted.
    if (key != "claude" && spec.roe == "supervised")
        spec.roe = "restricted";
    if (key == "codex")
        return codexCommand(spec);
    if (key == "gemini")
        return geminiCommand(spec);
    if (key == "opencode")
        return opencodeCommand(spec);
    return claudeCommand(spec);
}

// -- Parsers -----------------------------------------------------------------

static StreamEvent toolEvent(const QString &tool, const QVariantMap &input, const QString &id) {
    StreamEvent event{StreamEvent::Tool, Stream::describeTool(tool, QJsonObject::fromVariantMap(input))};
    event.tool = tool;
    event.input = input;
    event.toolId = id;
    return event;
}

static bool parseObject(const QByteArray &line, QJsonObject *object, QList<StreamEvent> *events) {
    const QByteArray trimmed = line.trimmed();
    if (trimmed.isEmpty())
        return false;
    const QJsonDocument document = QJsonDocument::fromJson(trimmed);
    if (!document.isObject()) {
        events->append({StreamEvent::Error, QString::fromUtf8(trimmed)});
        return false;
    }
    *object = document.object();
    return true;
}

class ClaudeParser : public Parser {
public:
    QList<StreamEvent> line(const QByteArray &line) override { return Stream::parseLine(line); }
};

// The command inside Codex's `/bin/bash -lc '...'` wrapper.
static QString unwrapShell(const QString &command) {
    static const QRegularExpression wrapper(R"(^(?:\S*/)?(?:ba|z)?sh\s+-l?c\s+(.+)$)",
                                            QRegularExpression::DotMatchesEverythingOption);
    const auto match = wrapper.match(command.trimmed());
    if (!match.hasMatch())
        return command;
    QString inner = match.captured(1).trimmed();
    if (inner.size() >= 2 && inner.startsWith('\'') && inner.endsWith('\''))
        return inner.mid(1, inner.size() - 2).replace("'\\''", "'");
    if (inner.size() >= 2 && inner.startsWith('"') && inner.endsWith('"'))
        return inner.mid(1, inner.size() - 2).replace("\\\"", "\"").replace("\\\\", "\\");
    return inner;
}

class CodexParser : public Parser {
public:
    QList<StreamEvent> line(const QByteArray &line) override {
        QList<StreamEvent> events;
        QJsonObject object;
        if (!parseObject(line, &object, &events))
            return events;
        const QString type = object.value("type").toString();
        if (type == "thread.started") {
            StreamEvent event{StreamEvent::Session};
            event.sessionId = object.value("thread_id").toString();
            events.append(event);
        } else if (type == "item.started" || type == "item.completed") {
            const QJsonObject item = object.value("item").toObject();
            const QString kind = item.value("type").toString();
            const QString id = item.value("id").toString();
            const bool completed = type == "item.completed";
            if (kind == "agent_message" && completed) {
                const QString text = item.value("text").toString().trimmed();
                if (!text.isEmpty()) {
                    m_last = text;
                    events.append({StreamEvent::Say, text});
                }
            } else if (kind == "command_execution" || kind == "mcp_tool_call" || kind == "web_search") {
                if (!m_started.contains(id)) {
                    m_started.insert(id);
                    if (kind == "command_execution")
                        events.append(toolEvent("Bash", {{"command", unwrapShell(item.value("command").toString())}}, id));
                    else if (kind == "mcp_tool_call")
                        events.append(toolEvent(QString("mcp__%1__%2").arg(item.value("server").toString(),
                                                                            item.value("tool").toString()),
                                                item.value("arguments").toObject().toVariantMap(), id));
                    else
                        events.append(toolEvent("WebSearch", {{"query", item.value("query").toString()}}, id));
                }
                // Codex has no refusal of its own: a declined command, or the
                // wording of an approval exec can't ask for.
                const QString status = item.value("status").toString();
                const QString output = item.value("aggregated_output").toString();
                if (completed && kind == "command_execution"
                    && (status == "declined" || (status == "failed" && isRefusal("codex", output)))) {
                    StreamEvent event{StreamEvent::Denied, output.trimmed().left(300)};
                    event.toolId = id;
                    events.append(event);
                }
                if (completed)
                    m_started.remove(id);
            } else if (kind == "file_change" && completed) {
                const QJsonArray changes = item.value("changes").toArray();
                for (int i = 0; i < changes.size(); ++i)
                    events.append(toolEvent("Edit", {{"file_path", changes.at(i).toObject().value("path").toString()}},
                                            changes.size() > 1 ? QString("%1.%2").arg(id).arg(i) : id));
            } else if (kind == "error" && completed) {
                events.append({StreamEvent::Error, item.value("message").toString()});
            }
        } else if (type == "turn.completed") {
            // The usage is the thread's running total, not the context, so it
            // isn't reported as context (it would set off hand-offs early).
            StreamEvent event{StreamEvent::Result, m_last};
            events.append(event);
        } else if (type == "turn.failed") {
            StreamEvent event{StreamEvent::Result, object.value("error").toObject().value("message").toString()};
            event.isError = true;
            if (event.text.isEmpty())
                event.text = "turn failed";
            events.append(event);
        } else if (type == "error") {
            // Often a retry on the way, so not the end of the run.
            events.append({StreamEvent::Error, object.value("message").toString()});
        }
        return events;
    }

private:
    QString m_last;
    QSet<QString> m_started;
};

// Gemini CLI's own tool names, as Claude Code's, so rules, edits on the map
// and the field link read the same.
static StreamEvent geminiTool(const QString &name, QVariantMap input, const QString &id) {
    static const QRegularExpression mcp(R"(^mcp_([^_]+)_(.+)$)");
    QString tool = name;
    if (name == "run_shell_command")
        tool = "Bash";
    else if (name == "write_file")
        tool = "Write";
    else if (name == "replace")
        tool = "Edit";
    else if (name == "read_file")
        tool = "Read";
    else if (name == "web_fetch")
        tool = "WebFetch";
    else if (name == "google_web_search")
        tool = "WebSearch";
    else if (const auto match = mcp.match(name); match.hasMatch())
        tool = QString("mcp__%1__%2").arg(match.captured(1), match.captured(2));
    return toolEvent(tool, input, id);
}

class GeminiParser : public Parser {
public:
    QList<StreamEvent> line(const QByteArray &line) override {
        QList<StreamEvent> events;
        QJsonObject object;
        if (!parseObject(line, &object, &events))
            return events;
        const QString type = object.value("type").toString();
        if (type == "init") {
            StreamEvent event{StreamEvent::Session, object.value("model").toString()};
            event.sessionId = object.value("session_id").toString();
            events.append(event);
        } else if (type == "message") {
            // Streamed in pieces: one Say per message, when it's done.
            if (object.value("role").toString() == "assistant")
                m_pending += object.value("content").toString();
        } else if (type == "tool_use") {
            flush(events);
            events.append(geminiTool(object.value("tool_name").toString(),
                                     object.value("parameters").toObject().toVariantMap(),
                                     object.value("tool_id").toString()));
        } else if (type == "tool_result") {
            flush(events);
            if (object.value("status").toString() == "error") {
                const QJsonObject error = object.value("error").toObject();
                const QString text = error.value("message").toString(object.value("output").toString());
                if (error.value("type").toString() == "policy_violation" || isRefusal("gemini", text)) {
                    StreamEvent event{StreamEvent::Denied, text.trimmed().left(300)};
                    event.toolId = object.value("tool_id").toString();
                    events.append(event);
                }
            }
        } else if (type == "error") {
            flush(events);
            events.append({StreamEvent::Error, object.value("message").toString()});
        } else if (type == "result") {
            flush(events);
            // The stats are this process's totals, not the context, so they
            // aren't reported as context.
            StreamEvent event{StreamEvent::Result, m_last};
            event.isError = object.value("status").toString() != "success";
            if (event.isError) {
                const QJsonObject error = object.value("error").toObject();
                event.text = error.value("message").toString(error.value("type").toString("error"));
            }
            event.turns = object.value("stats").toObject().value("tool_calls").toInt();
            events.append(event);
        }
        return events;
    }
    QList<StreamEvent> finish() override {
        QList<StreamEvent> events;
        flush(events);
        return events;
    }

private:
    void flush(QList<StreamEvent> &events) {
        const QString text = m_pending.trimmed();
        m_pending.clear();
        if (text.isEmpty())
            return;
        m_last = text;
        events.append({StreamEvent::Say, text});
    }
    QString m_pending;
    QString m_last;
};

static StreamEvent opencodeTool(const QString &name, QVariantMap input, const QString &id) {
    QString tool = name;
    if (input.contains("filePath") && !input.contains("file_path"))
        input.insert("file_path", input.value("filePath"));
    if (name == "bash")
        tool = "Bash";
    else if (name == "edit")
        tool = "Edit";
    else if (name == "write")
        tool = "Write";
    else if (name == "read")
        tool = "Read";
    else if (name == "webfetch")
        tool = "WebFetch";
    else if (name == "websearch")
        tool = "WebSearch";
    else if (name.startsWith("fireteam_"))
        tool = "mcp__fireteam__" + name.mid(QString("fireteam_").size());
    return toolEvent(tool, input, id);
}

class OpencodeParser : public Parser {
public:
    QList<StreamEvent> line(const QByteArray &line) override {
        QList<StreamEvent> events;
        QJsonObject object;
        if (!parseObject(line, &object, &events))
            return events;
        const QString session = object.value("sessionID").toString();
        if (m_session.isEmpty() && !session.isEmpty()) {
            m_session = session;
            StreamEvent event{StreamEvent::Session};
            event.sessionId = session;
            events.append(event);
        }
        const QString type = object.value("type").toString();
        const QJsonObject part = object.value("part").toObject();
        if (type == "text") {
            const QString text = part.value("text").toString().trimmed();
            if (!text.isEmpty()) {
                m_last = text;
                events.append({StreamEvent::Say, text});
            }
        } else if (type == "tool_use") {
            // Only sent once the call is done, its result with it.
            const QJsonObject state = part.value("state").toObject();
            const QString id = part.value("callID").toString(part.value("id").toString());
            events.append(opencodeTool(part.value("tool").toString(), state.value("input").toObject().toVariantMap(), id));
            const QString error = state.value("error").toString();
            if (state.value("status").toString() == "error" && isRefusal("opencode", error)) {
                StreamEvent event{StreamEvent::Denied, error.trimmed().left(300)};
                event.toolId = id;
                events.append(event);
            }
        } else if (type == "step_finish") {
            m_steps += 1;
            m_cost += part.value("cost").toDouble();
            const QJsonObject tokens = part.value("tokens").toObject();
            const QJsonObject cache = tokens.value("cache").toObject();
            StreamEvent event{StreamEvent::Usage};
            event.contextTokens = tokens.value("input").toInteger() + tokens.value("output").toInteger()
                                + cache.value("read").toInteger() + cache.value("write").toInteger();
            if (event.contextTokens > 0)
                events.append(event);
        } else if (type == "error") {
            const QJsonObject error = object.value("error").toObject();
            const QString text = error.value("data").toObject().value("message").toString(error.value("name").toString("error"));
            m_error = text;
            events.append({StreamEvent::Error, text});
        }
        return events;
    }
    QList<StreamEvent> finish() override {
        // No result event: the run ends when the session goes idle.
        if (m_session.isEmpty() || m_finished)
            return {};
        m_finished = true;
        StreamEvent event{StreamEvent::Result, m_error.isEmpty() ? m_last : m_error};
        event.isError = !m_error.isEmpty();
        event.sessionId = m_session;
        event.costUsd = m_cost;
        event.turns = m_steps;
        return {event};
    }

private:
    QString m_session;
    QString m_last;
    QString m_error;
    double m_cost = 0;
    int m_steps = 0;
    bool m_finished = false;
};

std::unique_ptr<Parser> parser(const QString &key) {
    if (key == "codex")
        return std::make_unique<CodexParser>();
    if (key == "gemini")
        return std::make_unique<GeminiParser>();
    if (key == "opencode")
        return std::make_unique<OpencodeParser>();
    return std::make_unique<ClaudeParser>();
}

}
